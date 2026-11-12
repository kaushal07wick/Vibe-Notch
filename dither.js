// Ordered (Bayer) dithering of a colour ramp onto a <canvas>, drawn small and scaled up with crisp pixels.
// <canvas data-dither data-stops="#1b2d47,#2d6a6f,#e2a23c" data-dir="down|up|radial" data-scale="3" data-sun="0.5,0.62,0.22">
(() => {
  const bayer = (n) => { let m = [[0]]; while (m.length < n) { const k = m.length; const b = Array.from({ length: k * 2 }, () => Array(k * 2).fill(0));
    for (let y = 0; y < k; y++) for (let x = 0; x < k; x++) { const v = m[y][x] * 4; b[y][x] = v; b[y][x + k] = v + 2; b[y + k][x] = v + 3; b[y + k][x + k] = v + 1; } m = b; } return m; };
  const M = bayer(8), N = 64;
  const rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  function draw(c) {
    const scale = +c.dataset.scale || 3, stops = c.dataset.stops.split(',').map(rgb), dir = c.dataset.dir || 'down';
    const sun = (c.dataset.sun || '').split(',').map(Number);
    const w = Math.max(2, Math.ceil(c.clientWidth / scale)), h = Math.max(2, Math.ceil(c.clientHeight / scale));
    c.width = w; c.height = h;
    const ctx = c.getContext('2d'), img = ctx.createImageData(w, h), n = stops.length - 1;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      let t = dir === 'up' ? 1 - y / h : y / h;
      if (dir === 'radial') t = Math.min(1, Math.hypot((x / w - 0.5) * (w / h), y / h - 0.5) * 1.4);
      if (sun.length === 3) { const d = Math.hypot((x / w - sun[0]) * (w / h), y / h - sun[1]); t = Math.max(0, t - Math.max(0, 1 - d / sun[2]) * 0.55); }
      const f = Math.min(0.9999, Math.max(0, t)) * n, i = Math.floor(f), fr = f - i;
      const pick = fr > (M[y % 8][x % 8] + 0.5) / N ? stops[i + 1] : stops[i];
      const o = (y * w + x) * 4; img.data[o] = pick[0]; img.data[o + 1] = pick[1]; img.data[o + 2] = pick[2]; img.data[o + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
  }
  // living dither: a slow flowing field, quantised through the same Bayer matrix, nudged toward the pointer
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const mouse = { x: 0.5, y: 0.3, tx: 0.5, ty: 0.3 };
  addEventListener('pointermove', (e) => { mouse.tx = e.clientX / innerWidth; mouse.ty = e.clientY / innerHeight; }, { passive: true });
  const live = [];
  function frame(c, t) {
    const scale = +c.dataset.scale || 4, stops = c.__stops, n = stops.length - 1, w = c.width, h = c.height;
    const ctx = c.__ctx, img = c.__img, d = img.data, base = c.dataset.dir || 'radial';
    const r = c.getBoundingClientRect(), mx = (mouse.x * innerWidth - r.left) / r.width, my = (mouse.y * innerHeight - r.top) / r.height;
    for (let y = 0; y < h; y++) { const fy = y / h; for (let x = 0; x < w; x++) {
      const fx = x / w, ar = w / h;
      let b = base === 'up' ? 1 - fy : Math.min(1, Math.hypot((fx - 0.5) * ar * 0.9, fy * 1.15));
      const wave = Math.sin(fx * 9 + t * 0.55 + Math.sin(fy * 7 - t * 0.35) * 1.6) * 0.5 + Math.sin(fy * 11 + fx * 4 - t * 0.4) * 0.5;
      const glow = Math.max(0, 1 - Math.hypot((fx - mx) * ar, fy - my) / 0.32);
      let v = 1 - b * 1.15 + wave * 0.09 + glow * glow * 0.42;       // brightness 0..1
      v = Math.min(0.9999, Math.max(0, v));
      const f = v * n, i = Math.floor(f), fr = f - i;
      const pick = fr > (M[y % 8][x % 8] + 0.5) / N ? stops[i + 1] : stops[i];
      const o = (y * w + x) * 4; d[o] = pick[0]; d[o + 1] = pick[1]; d[o + 2] = pick[2]; d[o + 3] = 255;
    } }
    ctx.putImageData(img, 0, 0);
  }
  function setupLive(c) {
    const scale = +c.dataset.scale || 4;
    c.width = Math.max(2, Math.ceil(c.clientWidth / scale)); c.height = Math.max(2, Math.ceil(c.clientHeight / scale));
    c.__stops = c.dataset.stops.split(',').map(rgb); c.__ctx = c.getContext('2d'); c.__img = c.__ctx.createImageData(c.width, c.height);
    if (!live.includes(c)) live.push(c);
  }
  let last = 0, running = false;
  function loop(ts) {
    requestAnimationFrame(loop);
    if (ts - last < 50 || document.hidden) return; last = ts;
    mouse.x += (mouse.tx - mouse.x) * 0.08; mouse.y += (mouse.ty - mouse.y) * 0.08;
    for (const c of live) { const r = c.getBoundingClientRect(); if (r.bottom > 0 && r.top < innerHeight) frame(c, ts / 1000); }
  }
  const all = () => document.querySelectorAll('canvas[data-dither]').forEach((c) => {
    if (c.dataset.animate && !still) { setupLive(c); if (!running) { running = true; requestAnimationFrame(loop); } } else draw(c);
  });
  addEventListener('DOMContentLoaded', all); addEventListener('load', all);
  let t; addEventListener('resize', () => { clearTimeout(t); t = setTimeout(all, 120); });
})();
