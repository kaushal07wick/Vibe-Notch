// Motion layer: scroll progress, reveals, cursor spotlight, magnetic buttons, terminal typing,
// the notch that hangs from the top of the page, and a ghost whose eyes follow you.
(() => {
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];

  // ---- the ghost sprite (same pixels as the app) ----
  const rows = ["...oooooo...", "..oblbbbbbo.", ".oblbbbbbbbo", ".obbbbbbbbbo", ".obbEEbbEEbo", ".obbeebbeebo", ".obpbbbbbpbo", ".obbbbbbbbdo", ".obbbbbbbddo", ".obbbbbbbddo"];
  const hem = [[".obbobbobbo.", "..oo.oo.oo.."], [".obobbobbob.", "..o.oo.oo.o."]];
  const blue = { b: '#7aa7ff', l: '#b9d2ff', d: '#4f78d8', o: '#2a3f7a', p: '#ff9fc0', w: '#fff', k: '#101830' };
  const amber = { ...blue, b: '#ffbf3c', l: '#ffe08a', d: '#d89a10', o: '#6b4a05' };
  function ghost(ctx, t, { wait = false, look = 0, blink = false, bob = 0 } = {}) {
    const pal = wait ? amber : blue, grid = rows.concat(hem[Math.floor(t / 400) % 2]);
    ctx.clearRect(0, 0, 12, 12);
    grid.forEach((r, y) => [...r].forEach((c, x) => {
      if (c === '.') return; let col;
      if (c === 'E' || c === 'e') { const second = r[x - 1] === c;
        if (blink) col = c === 'E' ? pal.b : pal.o; else if (wait) col = (c === 'E' && !second) ? pal.w : pal.k; else col = c === 'E' ? pal.w : ((second ? 1 : 0) === look ? pal.k : pal.w);
      } else col = pal[c];
      ctx.fillStyle = col; ctx.fillRect(x, y + bob, 1, 1);
    }));
  }
  const pointer = { x: innerWidth / 2, y: innerHeight / 2 };
  addEventListener('pointermove', (e) => { pointer.x = e.clientX; pointer.y = e.clientY; }, { passive: true });

  // ---- scroll progress ----
  const bar = Object.assign(document.createElement('div'), { className: 'progress' }); document.body.append(bar);
  const onScroll = () => { const h = document.documentElement; bar.style.transform = `scaleX(${h.scrollTop / Math.max(1, h.scrollHeight - innerHeight)})`; };
  addEventListener('scroll', onScroll, { passive: true }); onScroll();

  // ---- reveals ----
  const targets = $$('.label, h2, .sec-lead, .cell, .step, details, .marquee, .shell, .stage, .facts, .cta, .finale .in > *');
  targets.forEach((el) => {
    if (el.closest('.hero') && !el.matches('.stage')) return;
    const sibs = [...el.parentElement.children].filter((c) => targets.includes(c));
    el.style.setProperty('--d', Math.min(5, sibs.indexOf(el)));
    el.classList.add('reveal');
  });
  const io = new IntersectionObserver((es) => es.forEach((e) => { if (e.isIntersecting) { e.target.classList.add('shown'); io.unobserve(e.target); } }), { threshold: 0.12, rootMargin: '0px 0px -6% 0px' });
  $$('.reveal').forEach((el) => (still ? el.classList.add('shown') : io.observe(el)));

  // ---- MacBook lid opens when it scrolls into view ----
  const mb = $('#macbook');
  if (mb && !still) { mb.classList.add('closed'); new IntersectionObserver(([e], o) => { if (e.isIntersecting) { setTimeout(() => mb.classList.remove('closed'), 150); o.disconnect(); } }, { threshold: 0.25 }).observe(mb); }

  // ---- cursor spotlight on cards ----
  $$('.cell').forEach((c) => c.addEventListener('pointermove', (e) => { const r = c.getBoundingClientRect(); c.style.setProperty('--mx', e.clientX - r.left + 'px'); c.style.setProperty('--my', e.clientY - r.top + 'px'); }));

  // ---- magnetic buttons ----
  if (!still) $$('.btn.primary').forEach((b) => {
    b.addEventListener('pointermove', (e) => { const r = b.getBoundingClientRect(); b.style.transform = `translate(${(e.clientX - r.left - r.width / 2) * 0.12}px, ${(e.clientY - r.top - r.height / 2) * 0.2}px)`; });
    b.addEventListener('pointerleave', () => (b.style.transform = ''));
  });

  // ---- terminal typing ----
  const pre = $('#cmds');
  if (pre) {
    pre.innerHTML = pre.innerHTML.split('\n').map((l, i) => `<span class="ln" style="--i:${i}">${l || ' '}</span>`).join('');
    const shell = pre.closest('.shell');
    new IntersectionObserver(([e], o) => { if (e.isIntersecting) { shell.classList.add('on'); o.disconnect(); } }, { threshold: 0.5 }).observe(shell);
  }

  // ---- the notch that hangs from the top of the page ----
  const sn = Object.assign(document.createElement('div'), { className: 'sn', innerHTML:
    '<div class="top"><canvas width="12" height="12"></canvas><span class="dot"></span><b class="bn">Vibe Notch</b><span class="cnt">0%</span></div><div class="msg"></div><i class="prog"></i>' });
  sn.tabIndex = 0; sn.setAttribute('role', 'navigation'); sn.setAttribute('aria-label', 'Site menu');
  document.body.append(sn);
  const snCtx = $('canvas', sn).getContext('2d'), msg = $('.msg', sn);
    const scenes = {
    hero: { w: 150, h: 32, html: '' },
    demo: { w: 330, h: 70, html: '<b>2 agents live</b><br><span class="m">1 running · 1 waiting on you</span>' },
    features: { w: 400, h: 96, wait: true, html: '<b>Edit</b> <span class="m">NotchView.swift</span> <span class="ok">+2</span> <span class="del">−3</span><div class="pillrow"><span>Deny</span><span>Allow once</span><span class="go">Bypass</span></div>' },
    agents: { w: 400, h: 70, html: ['claude', 'codex', 'gemini', 'opencode', 'cursor'].map((a) => `<img src="./assets/agents/${a}.png" alt="">`).join('') + '<span class="m">all in one notch</span>' },
    install: { w: 390, h: 70, html: '<span class="m">$</span> ./scripts/bundle.sh release <span class="ok">✓ built</span>' },
    faq: { w: 340, h: 70, html: '<b>Local by default.</b> <span class="m">no account · no telemetry</span>' },
    finale: { w: 330, h: 70, wait: true, html: '<b>Download ready</b> <span class="m">macOS 14+ · unsigned beta</span>' },
  };
  scenes.nav = { w: 500, h: 92, hpx: 104, html: '<div class="navrow"><div class="lk"><a href="#features"><em>01</em>Features</a><a href="#agents"><em>02</em>Agents</a><a href="#install"><em>03</em>Install</a><a href="#faq"><em>04</em>FAQ</a><a href="https://github.com/kaushal07wick/Vibe-Notch"><em>↗</em>GitHub</a></div><a class="dl" href="./downloads/VibeNotch-0.4.0-beta.1-UNSIGNED-BETA.dmg">Download</a></div>' };
  const spots = { hero: '.hero', demo: '.stage', features: '#features', agents: '#agents', install: '#install', faq: '#faq', finale: '.finale' };
  let current = '', closeTimer;
  function show(name) {
    const s = scenes[name]; if (!s) return;
    if (name !== 'nav' && sn.classList.contains('isnav') && sn.classList.contains('open')) return; // keep an open menu
    clearTimeout(closeTimer);
    msg.innerHTML = s.html ? '<div class="fit">' + s.html + '</div>' : ''; sn.classList.toggle('wait', !!s.wait); sn.classList.toggle('isnav', name === 'nav');
    // size the notch to what it shows: header row + content + padding
    const fit = $('.fit', msg), w = fit ? Math.max(220, fit.offsetWidth + 40) : 220, h = fit ? 44 + fit.offsetHeight + 16 : 44;
    sn.style.setProperty('--w', w + 'px'); sn.style.setProperty('--h', h + 'px');
    sn.classList.toggle('open', !!s.html);
    if (s.html && name !== 'nav') closeTimer = setTimeout(rest, 3400);
  }
  function close() { clearTimeout(closeTimer); sn.classList.remove('open', 'isnav'); sn.style.setProperty('--w', '220px'); sn.style.setProperty('--h', '44px'); }
  function rest() { if (sn.matches(':hover, :focus-within')) { closeTimer = setTimeout(rest, 1200); return; } close(); }
  sn.addEventListener('pointerenter', () => show('nav'));
  sn.addEventListener('click', (e) => { if (e.target.closest('a')) return; sn.classList.remove('pop'); void sn.offsetWidth; sn.classList.add('pop'); show('nav'); });
  sn.addEventListener('focusin', () => { if (!sn.classList.contains('isnav')) show('nav'); });
  sn.addEventListener('focusout', (e) => { if (!sn.contains(e.relatedTarget)) { clearTimeout(closeTimer); closeTimer = setTimeout(rest, 300); } });
  sn.addEventListener('keydown', (e) => { if (e.key === 'Escape') { document.activeElement.blur(); close(); } });
  sn.addEventListener('pointerleave', () => { clearTimeout(closeTimer); closeTimer = setTimeout(rest, 700); });
  const names = Object.keys(spots).filter((k) => $(spots[k]));
  function pick() { const st = $('.stage'); if (st) { const r = st.getBoundingClientRect(); }
     let best = 'hero', bd = 1e9; names.forEach((n) => { const r = $(spots[n]).getBoundingClientRect(); const mid = r.top + Math.min(r.height, innerHeight) * 0.35; const d = r.top <= innerHeight * 0.45 && r.bottom > innerHeight * 0.25 ? Math.abs(mid - innerHeight * 0.4) : 1e9; if (d < bd) { bd = d; best = n; } }); if (best !== current) { current = best; show(best); } }
  const cnt = $('.cnt', sn), prog = $('.prog', sn);
  function progress() { const p = Math.min(1, scrollY / Math.max(1, document.documentElement.scrollHeight - innerHeight)); cnt.textContent = Math.round(p * 100) + '%'; prog.style.setProperty('--p', p); }
  addEventListener('scroll', progress, { passive: true }); progress();
  addEventListener('scroll', pick, { passive: true }); setTimeout(pick, 600);
  setTimeout(() => { if (!still) show('demo'); }, 1400); setTimeout(() => { if (current === 'hero' || current === '') rest(); }, 5200);

  // ---- ghosts: the little one in the notch, the big one that follows your eyes ----
  const big = $('#bigghost'), bigCtx = big && big.getContext('2d');
  function tick(ts) {
    requestAnimationFrame(tick);
    const wait = sn.classList.contains('wait'), look = Math.floor(ts / 900) % 2, blink = ts % 3300 < 140;
    ghost(snCtx, ts, { wait, look, blink, bob: wait ? 0 : (ts % 900 < 220 ? -1 : 0) });
    if (big && !still) {
      const r = big.getBoundingClientRect(); const cx = r.left + r.width / 2, cy = r.top + r.height / 2, dx = pointer.x - cx, dy = pointer.y - cy, dist = Math.hypot(dx, dy) || 1;
      ghost(bigCtx, ts, { look: dx < 0 ? 0 : 1, blink, bob: Math.sin(ts / 500) > 0.4 ? -1 : 0 });
      big.style.transform = `translate(${(dx / dist) * Math.min(10, dist / 40)}px, ${(dy / dist) * Math.min(8, dist / 50)}px)`;
    } else if (big) ghost(bigCtx, 0, {});
  }
  requestAnimationFrame(tick);
})();
