/* ============================================
   ZIGGO — Main JavaScript
   ============================================ */

document.addEventListener('DOMContentLoaded', () => {
  initNav();
  initDropdowns();
  initFAQ();
  initAuthTabs();
  initScrollReveal();
  initSmoothScroll();
  setActiveNav();
  initThemeToggle();
  initCounters();
  initBackToTop();
  initCookieBanner();
  initScrollProgress();
  initMagneticButtons();
  // initHeroSpotlight();
  initWordMorph();
  initLiveActivity();
  initFareEstimator();
  initBookingFlow();
  initEarningsCalc();
  initHeroParallax();
});

/* ---------- Mobile Nav Toggle ---------- */
function initNav() {
  const toggle = document.querySelector('.nav-toggle');
  const menu = document.querySelector('.nav-menu');
  if (!toggle || !menu) return;

  toggle.addEventListener('click', () => {
    menu.classList.toggle('open');
    const isOpen = menu.classList.contains('open');
    toggle.innerHTML = isOpen
      ? '<i class="fa-solid fa-xmark"></i>'
      : '<i class="fa-solid fa-bars"></i>';
    toggle.setAttribute('aria-expanded', isOpen);
  });

  document.addEventListener('click', (e) => {
    if (!menu.contains(e.target) && !toggle.contains(e.target)) {
      menu.classList.remove('open');
      toggle.innerHTML = '<i class="fa-solid fa-bars"></i>';
    }
  });
}

/* ---------- Mobile dropdown toggle ---------- */
function initDropdowns() {
  const items = document.querySelectorAll('.nav-item.has-dropdown');
  items.forEach(item => {
    const link = item.querySelector('.nav-link');
    link.addEventListener('click', (e) => {
      if (window.innerWidth <= 768) {
        e.preventDefault();
        item.classList.toggle('open');
      }
    });
  });
}

/* ---------- FAQ accordion ---------- */
function initFAQ() {
  document.querySelectorAll('.faq-item').forEach(item => {
    const q = item.querySelector('.faq-question');
    if (!q) return;
    q.addEventListener('click', () => {
      const wasOpen = item.classList.contains('open');
      document.querySelectorAll('.faq-item').forEach(i => i.classList.remove('open'));
      if (!wasOpen) item.classList.add('open');
    });
  });
}

/* ---------- Auth tabs (login / signup) ---------- */
function initAuthTabs() {
  const tabs = document.querySelectorAll('.auth-tab');
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      tabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      const target = tab.dataset.target;
      document.querySelectorAll('.auth-form').forEach(f => {
        f.style.display = (f.dataset.form === target) ? 'block' : 'none';
      });
    });
  });
}

/* ---------- Scroll reveal (no library) ---------- */
function initScrollReveal() {
  const els = document.querySelectorAll('[data-reveal]');
  if (!('IntersectionObserver' in window)) {
    els.forEach(el => el.classList.add('reveal-in'));
    return;
  }
  const io = new IntersectionObserver((entries) => {
    entries.forEach(en => {
      if (en.isIntersecting) {
        en.target.classList.add('reveal-in');
        io.unobserve(en.target);
      }
    });
  }, { threshold: 0.12 });
  els.forEach(el => io.observe(el));
}

/* ---------- Smooth scroll to anchors ---------- */
function initSmoothScroll() {
  document.querySelectorAll('a[href^="#"]').forEach(link => {
    link.addEventListener('click', (e) => {
      const href = link.getAttribute('href');
      if (href.length <= 1) return;
      const target = document.querySelector(href);
      if (!target) return;
      e.preventDefault();
      const offset = 80;
      const top = target.getBoundingClientRect().top + window.pageYOffset - offset;
      window.scrollTo({ top, behavior: 'smooth' });
    });
  });
}

/* ---------- Highlight active nav link by URL ---------- */
function setActiveNav() {
  const path = window.location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.nav-link').forEach(link => {
    const href = link.getAttribute('href');
    if (!href) return;
    const linkPage = href.split('/').pop();
    if (linkPage === path) link.classList.add('active');
  });
}

/* ---------- Theme toggle (dark mode) ---------- */
function initThemeToggle() {
  const saved = localStorage.getItem('ziggo-theme');
  if (saved === 'dark') document.body.classList.add('dark');

  document.querySelectorAll('.theme-toggle').forEach(t => {
    t.style.cursor = 'pointer';
    t.addEventListener('click', () => {
      document.body.classList.toggle('dark');
      const isDark = document.body.classList.contains('dark');
      localStorage.setItem('ziggo-theme', isDark ? 'dark' : 'light');
    });
  });
}

/* ---------- Animated number counter ---------- */
function initCounters() {
  const counters = document.querySelectorAll('[data-counter]');
  if (!counters.length || !('IntersectionObserver' in window)) {
    counters.forEach(c => { c.textContent = c.dataset.counter + (c.dataset.suffix || ''); });
    return;
  }
  const io = new IntersectionObserver((entries) => {
    entries.forEach(en => {
      if (en.isIntersecting) {
        animateCount(en.target);
        io.unobserve(en.target);
      }
    });
  }, { threshold: 0.4 });
  counters.forEach(c => io.observe(c));
}

function animateCount(el) {
  const target = parseFloat(el.dataset.counter);
  const suffix = el.dataset.suffix || '';
  const duration = 1800;
  const start = performance.now();
  function tick(now) {
    const t = Math.min((now - start) / duration, 1);
    const eased = 1 - Math.pow(1 - t, 3);
    const val = target * eased;
    el.textContent = formatNum(val, target) + suffix;
    if (t < 1) requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
}
function formatNum(val, target) {
  if (target >= 1000000) return (val / 1000000).toFixed(1) + 'M';
  if (target >= 1000) return Math.round(val / 100) / 10 + 'K';
  return Math.round(val).toString();
}

/* ---------- Back-to-top button ---------- */
function initBackToTop() {
  const btn = document.querySelector('.fab-back-to-top');
  if (!btn) return;
  window.addEventListener('scroll', () => {
    if (window.scrollY > 600) btn.classList.add('visible');
    else btn.classList.remove('visible');
  });
  btn.addEventListener('click', (e) => {
    e.preventDefault();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });
}

/* ---------- Cookie consent banner ---------- */
function initCookieBanner() {
  const banner = document.querySelector('.cookie-banner');
  if (!banner) return;
  if (localStorage.getItem('ziggo-cookies') === 'accepted') return;
  setTimeout(() => banner.classList.add('show'), 1200);
  banner.querySelectorAll('button').forEach(b => {
    b.addEventListener('click', () => {
      localStorage.setItem('ziggo-cookies', b.dataset.action || 'accepted');
      banner.classList.remove('show');
    });
  });
}

/* ---------- Scroll progress bar (auto-injected) ---------- */
function initScrollProgress() {
  let bar = document.querySelector('.scroll-progress');
  if (!bar) {
    bar = document.createElement('div');
    bar.className = 'scroll-progress';
    document.body.appendChild(bar);
  }
  function update() {
    const h = document.documentElement;
    const max = h.scrollHeight - h.clientHeight;
    const pct = max > 0 ? (h.scrollTop / max) * 100 : 0;
    bar.style.width = pct + '%';
  }
  update();
  window.addEventListener('scroll', update, { passive: true });
}

/* ---------- Magnetic / micro-tilt buttons ---------- */
function initMagneticButtons() {
  const targets = document.querySelectorAll('.btn-primary, .btn-glow, .btn-3d, .btn-shine, .fab, .app-badge');
  targets.forEach(el => {
    el.addEventListener('mousemove', (e) => {
      const r = el.getBoundingClientRect();
      const x = e.clientX - r.left - r.width / 2;
      const y = e.clientY - r.top - r.height / 2;
      el.style.setProperty('--mx', (x * 0.15) + 'px');
      el.style.setProperty('--my', (y * 0.15) + 'px');
      el.style.transform = `translate(${x * 0.12}px, ${y * 0.18}px)`;
    });
    el.addEventListener('mouseleave', () => {
      el.style.transform = '';
    });
  });
}

/* ---------- Hero cursor spotlight ---------- */
function initHeroSpotlight() {
  const hero = document.querySelector('.hero-carousel');
  if (!hero) return;
  const sp = document.createElement('div');
  sp.className = 'hero-spotlight';
  hero.appendChild(sp);
  hero.addEventListener('mousemove', (e) => {
    const r = hero.getBoundingClientRect();
    const x = ((e.clientX - r.left) / r.width) * 100;
    const y = ((e.clientY - r.top) / r.height) * 100;
    sp.style.setProperty('--mx', x + '%');
    sp.style.setProperty('--my', y + '%');
  });
}

/* ---------- Hero word morph (cycles through words) ---------- */
function initWordMorph() {
  const morph = document.querySelector('.word-morph');
  if (!morph) return;
  const words = morph.querySelectorAll('.word');
  let i = 0;
  words[0].classList.add('active');
  setInterval(() => {
    const cur = words[i];
    cur.classList.remove('active');
    cur.classList.add('exit');
    i = (i + 1) % words.length;
    const next = words[i];
    next.classList.remove('exit');
    next.classList.add('active');
    setTimeout(() => cur.classList.remove('exit'), 600);
  }, 2400);
}

/* ---------- Live activity feed (random ticker increments) ---------- */
function initLiveActivity() {
  const els = document.querySelectorAll('[data-live]');
  if (!els.length) return;
  function tick() {
    els.forEach(el => {
      const base = parseInt(el.dataset.live, 10) || 0;
      const drift = Math.floor(Math.random() * 200) - 80;
      el.textContent = (base + drift).toLocaleString('en-US');
    });
  }
  tick();
  setInterval(tick, 3500);
}

/* ---------- Fare Estimator widget ---------- */
function initFareEstimator() {
  const card = document.querySelector('.fare-card');
  if (!card) return;

  // Pricing per service type (LKR per km + base + min)
  const pricing = {
    ride: [
      { name: 'Tuk', icon: 'fa-taxi', base: 80, perKm: 50, eta: 3 },
      { name: 'Mini', icon: 'fa-car-side', base: 200, perKm: 95, eta: 4, recommended: true },
      { name: 'City', icon: 'fa-car', base: 280, perKm: 120, eta: 5 },
      { name: 'Flex', icon: 'fa-van-shuttle', base: 450, perKm: 150, eta: 6 },
      { name: 'Lux', icon: 'fa-car-burst', base: 750, perKm: 220, eta: 8 }
    ],
    food: [
      { name: 'Express', icon: 'fa-bolt', base: 150, perKm: 60, eta: 25, recommended: true },
      { name: 'Standard', icon: 'fa-utensils', base: 100, perKm: 40, eta: 35 }
    ],
    flash: [
      { name: 'Document', icon: 'fa-envelope', base: 250, perKm: 50, eta: 30 },
      { name: 'Small', icon: 'fa-box', base: 350, perKm: 60, eta: 45, recommended: true },
      { name: 'Medium', icon: 'fa-boxes-stacked', base: 550, perKm: 80, eta: 60 },
      { name: 'Large', icon: 'fa-pallet', base: 950, perKm: 100, eta: 90 }
    ],
    truck: [
      { name: 'Pickup', icon: 'fa-truck-pickup', base: 1500, perKm: 180, eta: 30 },
      { name: 'Mini Lorry', icon: 'fa-van-shuttle', base: 2500, perKm: 220, eta: 45, recommended: true },
      { name: 'Lorry', icon: 'fa-truck', base: 4500, perKm: 320, eta: 60 },
      { name: 'Mover', icon: 'fa-truck-moving', base: 7500, perKm: 450, eta: 90 }
    ]
  };

  // Approx distances between cities (km)
  const cityDist = {
    Colombo: { Kandy: 115, Galle: 119, Negombo: 38, Jaffna: 398, Anuradhapura: 205, Matara: 159, Kurunegala: 94, Polonnaruwa: 216 },
    Kandy: { Galle: 226, Negombo: 137, Jaffna: 326, Anuradhapura: 135, Matara: 263, Kurunegala: 42, Polonnaruwa: 140 },
    Galle: { Negombo: 156, Jaffna: 517, Anuradhapura: 324, Matara: 45, Kurunegala: 213, Polonnaruwa: 335 },
    Negombo: { Jaffna: 360, Anuradhapura: 170, Matara: 196, Kurunegala: 60, Polonnaruwa: 195 },
    Jaffna: { Anuradhapura: 196, Matara: 553, Kurunegala: 305, Polonnaruwa: 235 },
    Anuradhapura: { Matara: 360, Kurunegala: 110, Polonnaruwa: 100 },
    Matara: { Kurunegala: 250, Polonnaruwa: 372 },
    Kurunegala: { Polonnaruwa: 145 }
  };
  function distance(a, b) {
    if (a === b) return 5;
    return (cityDist[a] && cityDist[a][b]) || (cityDist[b] && cityDist[b][a]) || 50;
  }

  let activeService = 'ride';
  const tabs = card.querySelectorAll('.fare-tab');
  const fromSel = card.querySelector('.fare-from');
  const toSel = card.querySelector('.fare-to');
  const btn = card.querySelector('.fare-estimate-btn');
  const results = card.querySelector('.fare-results');

  tabs.forEach(t => {
    t.addEventListener('click', () => {
      tabs.forEach(x => x.classList.remove('active'));
      t.classList.add('active');
      activeService = t.dataset.service;
      if (results.classList.contains('show')) estimate();
    });
  });

  function estimate() {
    const km = distance(fromSel.value, toSel.value);
    const opts = pricing[activeService];
    results.innerHTML = opts.map(o => {
      const fare = Math.round(o.base + o.perKm * km);
      const etaText = activeService === 'ride' ? `${o.eta} min away` :
                      activeService === 'food' ? `${o.eta} min delivery` :
                      `${o.eta} min ETA`;
      return `
        <div class="fare-option${o.recommended ? ' recommended' : ''}">
          <div class="icon"><i class="fa-solid ${o.icon}"></i></div>
          <div class="info">
            <span class="name">${o.name}</span>
            <span class="eta">${etaText} &middot; ~${km}km</span>
          </div>
          <span class="price">LKR ${fare.toLocaleString()}</span>
        </div>`;
    }).join('');
    results.classList.add('show');
  }

  btn.addEventListener('click', (e) => { e.preventDefault(); estimate(); });
  fromSel.addEventListener('change', () => results.classList.contains('show') && estimate());
  toSel.addEventListener('change', () => results.classList.contains('show') && estimate());
}

/* ---------- Animated Booking Flow demo ---------- */
function initBookingFlow() {
  const wrap = document.querySelector('.flow-phone-wrap');
  if (!wrap) return;
  const states = wrap.querySelectorAll('.flow-state');
  const steps = document.querySelectorAll('.flow-step');
  let i = 0;

  function go(n) {
    states.forEach((s, idx) => {
      s.classList.toggle('active', idx === n);
      s.classList.toggle('exit', idx === (n - 1 + states.length) % states.length);
    });
    steps.forEach((s, idx) => s.classList.toggle('active', idx === n));
    i = n;
  }
  go(0);

  steps.forEach((s, idx) => {
    s.addEventListener('click', () => go(idx));
  });

  let timer = setInterval(() => go((i + 1) % states.length), 3500);
  wrap.addEventListener('mouseenter', () => clearInterval(timer));
  wrap.addEventListener('mouseleave', () => {
    timer = setInterval(() => go((i + 1) % states.length), 3500);
  });
}

/* ---------- Driver Earnings Calculator ---------- */
function initEarningsCalc() {
  const calc = document.querySelector('.earnings-calc');
  if (!calc) return;
  const hoursSlider = calc.querySelector('.calc-hours');
  const hoursLabel = calc.querySelector('.calc-hours-val');
  const vehicles = calc.querySelectorAll('.calc-vehicle');
  const weekly = calc.querySelector('.calc-weekly');
  const monthly = calc.querySelector('.calc-monthly');

  // LKR per hour by vehicle type
  const rates = { tuk: 600, mini: 800, city: 1000, lux: 1500 };
  let veh = 'mini';

  vehicles.forEach(v => {
    v.addEventListener('click', () => {
      vehicles.forEach(x => x.classList.remove('active'));
      v.classList.add('active');
      veh = v.dataset.vehicle;
      update();
    });
  });

  hoursSlider.addEventListener('input', update);

  function update() {
    const hrs = parseInt(hoursSlider.value, 10);
    hoursLabel.textContent = hrs + ' hrs/wk';
    const week = Math.round(hrs * rates[veh]);
    const month = week * 4;
    weekly.textContent = 'LKR ' + week.toLocaleString();
    monthly.textContent = '~ LKR ' + month.toLocaleString() + ' / month';
  }
  update();
}

/* ---------- Hero parallax (content drifts up on scroll) ---------- */
function initHeroParallax() {
  const hero = document.querySelector('.hero-carousel');
  const content = document.querySelectorAll('.hero-slide-content');
  const sideLabel = document.querySelector('.hero-side-label');
  const counter = document.querySelector('.hero-counter');
  if (!hero || !content.length) return;
  function update() {
    const y = window.scrollY;
    if (y > window.innerHeight) return;
    const factor = Math.min(y / window.innerHeight, 1);
    content.forEach(c => {
      c.style.transform = `translateY(${y * 0.3}px)`;
      c.style.opacity = String(1 - factor * 0.9);
    });
    if (sideLabel) sideLabel.style.opacity = String(1 - factor);
    if (counter) counter.style.opacity = String(1 - factor);
  }
  window.addEventListener('scroll', update, { passive: true });
  update();
}

/* ---------- Reveal animation styles (injected) ---------- */
const style = document.createElement('style');
style.textContent = `
  [data-reveal] { opacity: 0; transform: translateY(24px); transition: all 0.6s ease; }
  [data-reveal].reveal-in { opacity: 1; transform: translateY(0); }
  [data-reveal][data-reveal-delay="100"] { transition-delay: 0.1s; }
  [data-reveal][data-reveal-delay="200"] { transition-delay: 0.2s; }
  [data-reveal][data-reveal-delay="300"] { transition-delay: 0.3s; }
  [data-reveal][data-reveal-delay="400"] { transition-delay: 0.4s; }
`;
document.head.appendChild(style);
