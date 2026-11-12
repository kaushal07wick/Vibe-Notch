(() => {

const $ = s => document.querySelector(s), mac = $('#mac'), notch = $('#notch');
const SIZE = { closed:[190,32], sessions:[430,192], approval:[450,246], question:[450,232], tray:[430,150] };
let state = 'closed', locked = false, timer;
function setState(s) {
  state = s;
  const open = s !== 'closed';
  notch.className = 'notch in s-' + s + (open ? ' open' : '') + (s === 'approval' || s === 'question' ? ' wait' : '');
  mac.style.setProperty('--w', SIZE[s][0] + 'px'); mac.style.setProperty('--h', SIZE[s][1] + 'px');
  [...$('#controls').children].forEach(b => b.setAttribute('aria-pressed', b.dataset.s === s));
}
[['closed','Closed'],['sessions','Hover'],['approval','Approval'],['question','Question'],['tray','Tray']].forEach(([s, label]) => {
  const b = document.createElement('button'); b.textContent = label; b.dataset.s = s;
  b.onclick = () => { locked = true; clearTimeout(timer); setState(s); };
  $('#controls').append(b);
});
notch.addEventListener('mouseenter', () => { if (state === 'closed') { locked = true; setState('sessions'); } });
notch.addEventListener('mouseleave', () => { if (state === 'sessions') setTimeout(() => state === 'sessions' && setState('closed'), 600); });
notch.addEventListener('click', e => { if (e.target.closest('.opt,.btns button')) setState('closed'); });

// the tour starts only once the MacBook is on screen and its lid has opened
const tour = ['closed','sessions','approval','question','tray'];
let i = 0, started = false;
mac.style.setProperty('--w', '190px'); mac.style.setProperty('--h', '32px');
function next() { if (locked) return; i = (i + 1) % tour.length; setState(tour[i]); timer = setTimeout(next, tour[i] === 'closed' ? 1700 : 3800); }
function begin() { if (started) return; started = true; setState('closed'); timer = setTimeout(next, 1600); }
new IntersectionObserver(([e], o) => { if (e.isIntersecting) { o.disconnect(); setTimeout(begin, matchMedia('(prefers-reduced-motion:reduce)').matches ? 0 : 1900); } }, { threshold: 0.3 }).observe($('#macbook'));
// first touch takes over from the tour
$('#controls').addEventListener('pointerdown', () => { started = true; });

// pixel ghost, same sprite as the app
const rows = ["...oooooo...","..oblbbbbbo.",".oblbbbbbbbo",".obbbbbbbbbo",".obbEEbbEEbo",".obbeebbeebo",".obpbbbbbpbo",".obbbbbbbbdo",".obbbbbbbddo",".obbbbbbbddo"];
const hem = [[".obbobbobbo.","..oo.oo.oo.."],[".obobbobbob.","..o.oo.oo.o."]];
const blue = {b:'#7aa7ff',l:'#b9d2ff',d:'#4f78d8',o:'#2a3f7a',p:'#ff9fc0',w:'#fff',k:'#101830'};
const amber = {...blue,b:'#ffbf3c',l:'#ffe08a',d:'#d89a10',o:'#6b4a05'};
const ctx = $('#ghost').getContext('2d'), still = matchMedia('(prefers-reduced-motion:reduce)').matches;
function ghost(t) {
  const wait = state === 'approval' || state === 'question', pal = wait ? amber : blue, beat = Math.floor(t / 400), look = (beat >> 1) % 2;
  const blink = !wait && (t % 3200) < 150, grid = rows.concat(hem[still ? 0 : beat % 2]);
  ctx.clearRect(0, 0, 12, 12);
  const dx = wait && !still ? (Math.floor(t / 70) % 2 ? 1 : 0) : 0, dy = !wait && !still && (t % 800) < 200 ? -1 : 0;
  grid.forEach((r, y) => [...r].forEach((c, x) => {
    if (c === '.') return; let col;
    if (c === 'E' || c === 'e') { const second = r[x - 1] === c;
      if (blink) col = c === 'E' ? pal.b : pal.o; else if (wait) col = (c === 'E' && !second) ? pal.w : pal.k; else col = c === 'E' ? pal.w : ((second ? 1 : 0) === look ? pal.k : pal.w);
    } else col = pal[c];
    ctx.fillStyle = col; ctx.fillRect(x + dx, y + dy, 1, 1);
  }));
  requestAnimationFrame(ghost);
}
requestAnimationFrame(ghost);

})();
