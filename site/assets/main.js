/* Kyo landing page. No dependencies. The static HTML already reads as a finished page; this adds
   the working Today fragment, the board, the FAQ index, the crossfade and the entrances. */
(() => {
  window.__kyo = 1;
  const calm = matchMedia('(prefers-reduced-motion: reduce)');
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  /* ---------------------------------------------------------------- Today (the live thing) */
  const root = $('#today');
  if (root) {
    const CHECK = '<svg viewBox="0 0 14 14"><path d="M2.5 7.5l3 3 6-7"/></svg>';
    const dateEl = $('#today-date');
    const schedEl = $('#t-sched');
    const tasksEl = $('#t-tasks');
    const habitsEl = $('#t-habits');
    const endBtn = $('#end-day');
    const resetBtn = $('#reset-day');
    const form = $('#t-form');
    const input = $('#t-new');

    // Which weekday a calendar week starts on follows the visitor's locale, as it does in the app.
    const firstDay = (() => {
      try {
        const l = new Intl.Locale(navigator.language);
        const info = l.getWeekInfo ? l.getWeekInfo() : l.weekInfo;
        return info ? info.firstDay % 7 : 1;
      } catch { return 1; }
    })();

    const fmt = new Intl.DateTimeFormat(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
    const fmtDay = new Intl.DateTimeFormat(undefined, { weekday: 'long' });

    const EVENTS = [
      [['9:30', 'Standup', '15 min'], ['13:00', 'Lunch with Maya', 'Café Ora']],
      [['9:30', 'Standup', '15 min'], ['15:00', 'Design review', '45 min']],
      [['10:00', 'Dentist', '30 min']],
    ];
    const HABITS = [
      { id: 'stretch', name: 'Stretch for ten minutes', streak: 12 },
      { id: 'swim', name: 'Swim', target: 3, week: 2 },
      { id: 'journal', name: 'Journal', days: [2, 5], streak: 3 },
      { id: 'plants', name: 'Water the plants', days: [1, 4], streak: 6 },
    ];
    const START = [
      { id: 'a', text: 'Finish the slides for Thursday', done: false },
      { id: 'b', text: 'Pick up the dry cleaning', done: false },
      { id: 'd', text: 'Pay the water bill', done: true },
    ];
    const LATER = { id: 'later', text: 'Renew the library books', done: false, note: 'From Later' };

    const base = new Date(); base.setHours(12, 0, 0, 0);
    let state;
    let seq = 0;
    const fresh = () => ({
      offset: 0,
      tasks: START.map((t) => ({ ...t })),
      habits: HABITS.map((h) => ({ ...h, done: false })),
      carried: 0, fromLater: 0,
    });
    const dayAt = (o) => { const d = new Date(base); d.setDate(d.getDate() + o); return d; };
    const isDue = (h, d) => !h.days || h.days.includes(d.getDay());

    const taskEls = new Map();
    const mkTask = (t) => {
      const li = document.createElement('li');
      li.className = 't-row'; li.dataset.key = t.id;
      li.innerHTML = `<label><input type="checkbox"><span class="t-box" aria-hidden="true">${CHECK}</span><span class="t-text"></span></label>`;
      $('.t-text', li).textContent = t.text;
      $('input', li).addEventListener('change', (e) => { clearHot(); t.done = e.target.checked; sync({ flip: true }); });
      return li;
    };
    const noteFor = (t) => {
      const li = taskEls.get(t.id); if (!li) return;
      let n = $('.t-meta', li);
      if (t.note) {
        if (!n) { n = document.createElement('span'); n.className = 't-meta'; $('label', li).append(n); }
        n.textContent = t.note;
      } else if (n) n.remove();
    };

    const clearHot = () => $$('.is-hot', root).forEach((el) => el.classList.remove('is-hot'));
    root.addEventListener('pointerdown', clearHot, { once: true });

    const flip = (before) => {
      if (calm.matches) return;
      for (const [key, li] of taskEls) {
        const was = before.get(key); if (!was || !li.isConnected) continue;
        const now = li.getBoundingClientRect();
        const dy = was.top - now.top;
        if (Math.abs(dy) > 1) li.animate([{ transform: `translateY(${dy}px)` }, { transform: 'none' }], { duration: 420, easing: 'cubic-bezier(.22,1,.36,1)' });
      }
    };

    // Open tasks first, finished ones drop to the bottom: the app's own ordering.
    function sync({ flip: doFlip = false } = {}) {
      const before = new Map();
      if (doFlip) for (const [k, li] of taskEls) before.set(k, li.getBoundingClientRect());
      const order = [...state.tasks.filter((t) => !t.done), ...state.tasks.filter((t) => t.done)];
      for (const t of order) {
        if (!taskEls.has(t.id)) taskEls.set(t.id, mkTask(t));
        const li = taskEls.get(t.id);
        $('input', li).checked = t.done;
        tasksEl.append(li);
        noteFor(t);
      }
      for (const [k, li] of taskEls) if (!state.tasks.some((t) => t.id === k)) { li.remove(); taskEls.delete(k); }
      if (doFlip) flip(before);
      counts();
    }

    function counts() {
      const open = state.tasks.filter((t) => !t.done).length;
      $('#t-c-tasks').textContent = `${state.tasks.length - open} of ${state.tasks.length}`;
      const due = state.habits.filter((h) => isDue(h, dayAt(state.offset)));
      $('#t-c-habits').textContent = `${due.filter((h) => h.done).length} of ${due.length}`;
      let line = `${fmt.format(dayAt(state.offset))} · ${open} ${open === 1 ? 'task' : 'tasks'} left`;
      if (state.offset > 0 && state.carried + state.fromLater > 0) {
        const bits = [];
        if (state.carried) bits.push(`${state.carried} carried forward`);
        if (state.fromLater) bits.push(`${state.fromLater} from Later`);
        line = `${fmt.format(dayAt(state.offset))} · ${bits.join(', ')}`;
      }
      dateEl.textContent = line;
    }

    const meta = (h) => {
      if (h.target) return `<strong>${h.week}/${h.target}</strong> this week`;
      const n = h.streak + (h.done ? 1 : 0);
      return n > 0 ? `${n}-day streak` : '—';
    };
    function renderHabits(animate) {
      const d = dayAt(state.offset);
      habitsEl.replaceChildren();
      state.habits.filter((h) => isDue(h, d)).forEach((h, i) => {
        const li = document.createElement('li');
        li.className = 't-row';
        li.innerHTML = `<label><input type="checkbox"><span class="t-box" aria-hidden="true">${CHECK}</span><span class="t-text"></span><span class="t-meta"></span></label>`;
        $('.t-text', li).textContent = h.name;
        const m = $('.t-meta', li);
        const paint = () => { m.innerHTML = meta(h); };
        const cb = $('input', li); cb.checked = h.done; paint();
        cb.addEventListener('change', () => {
          clearHot();
          h.done = cb.checked;
          if (h.target) h.week += h.done ? 1 : -1;
          paint(); counts();
        });
        habitsEl.append(li);
        if (animate && !calm.matches) li.animate([{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }], { duration: 520, delay: 160 + i * 70, easing: 'cubic-bezier(.22,1,.36,1)', fill: 'backwards' });
      });
    }
    function renderSchedule(animate) {
      const ev = EVENTS[state.offset % EVENTS.length];
      schedEl.replaceChildren(...ev.map(([t, n, m], i) => {
        const li = document.createElement('li');
        li.className = 't-row t-event';
        li.innerHTML = '<time></time><span class="t-text"></span><span class="t-meta"></span>';
        $('time', li).textContent = t; $('.t-text', li).textContent = n; $('.t-meta', li).textContent = m;
        if (animate && !calm.matches) li.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 480, delay: 120 + i * 70, easing: 'ease', fill: 'backwards' });
        return li;
      }));
      $('#t-c-sched').textContent = ev.length;
    }

    function endDay() {
      endBtn.disabled = true;
      clearHot();
      const finish = () => {
        // Habits close out first: a streak grows on a checked due day and ends on a missed one; a missed
        // habit never moves to tomorrow.
        const today = dayAt(state.offset);
        const next = dayAt(state.offset + 1);
        for (const h of state.habits) {
          if (isDue(h, today) && !h.target) h.streak = h.done ? h.streak + 1 : 0;
          if (h.target && next.getDay() === firstDay) h.week = 0;
          h.done = false;
        }
        const keep = state.tasks.filter((t) => !t.done);
        state.carried = keep.length;
        state.fromLater = 0;
        keep.forEach((t) => { t.note = 'From yesterday'; });
        state.tasks = keep;
        if (state.offset === 0) { state.tasks.push({ ...LATER }); state.fromLater = 1; }
        state.offset += 1;
        const before = new Map();
        for (const [k, li] of taskEls) before.set(k, li.getBoundingClientRect());
        sync();
        flip(before);
        const fresh = taskEls.get(LATER.id);
        if (fresh && !calm.matches && state.offset === 1) fresh.animate([{ opacity: 0, transform: 'translateY(14px)' }, { opacity: 1, transform: 'none' }], { duration: 600, delay: 380, easing: 'cubic-bezier(.22,1,.36,1)', fill: 'backwards' });
        renderSchedule(true); renderHabits(true); counts();
        resetBtn.hidden = false; endBtn.disabled = false;
        if (!calm.matches) dateEl.animate([{ opacity: 0, transform: 'translateY(6px)' }, { opacity: 1, transform: 'none' }], { duration: 480, easing: 'cubic-bezier(.22,1,.36,1)' });
      };
      const leaving = $$('.t-row', tasksEl).filter((li) => $('input', li).checked);
      if (calm.matches || !leaving.length) { finish(); return; }
      let n = 0;
      leaving.forEach((li) => {
        const a = li.animate([{ opacity: 1 }, { opacity: 0, transform: 'translateX(-8px)' }], { duration: 260, easing: 'ease', fill: 'forwards' });
        a.onfinish = () => { if (++n === leaving.length) finish(); };
      });
    }

    function reset() {
      state = fresh();
      taskEls.forEach((li) => li.remove()); taskEls.clear();
      sync(); renderSchedule(true); renderHabits(true); counts();
      resetBtn.hidden = true;
    }

    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const text = input.value.trim(); if (!text) return;
      state.tasks.push({ id: 'n' + (++seq), text, done: false });
      input.value = '';
      sync();
      const li = taskEls.get('n' + seq);
      if (li && !calm.matches) li.animate([{ opacity: 0, transform: 'translateY(-8px)' }, { opacity: 1, transform: 'none' }], { duration: 360, easing: 'cubic-bezier(.22,1,.36,1)' });
    });

    endBtn.addEventListener('click', endDay);
    resetBtn.addEventListener('click', reset);

    state = fresh();
    tasksEl.replaceChildren();
    sync(); renderSchedule(false); renderHabits(false); counts();
    endBtn.disabled = false;
  }

  /* ---------------------------------------------------------------- board: one row open at a time */
  const board = $('#board');
  if (board) {
    board.addEventListener('click', (e) => {
      const btn = e.target.closest('.b-row > button'); if (!btn) return;
      $$('.b-row', board).forEach((r) => { const on = r === btn.parentElement; r.classList.toggle('is-open', on); $('button', r).setAttribute('aria-expanded', String(on)); });
    });
  }

  /* ---------------------------------------------------------------- Do later dates, from the visitor's day */
  (() => {
    const els = $$('[data-d]');
    if (!els.length) return;
    const f = new Intl.DateTimeFormat(undefined, { weekday: 'short', day: 'numeric', month: 'short' });
    const t = new Date();
    const add = (days, months = 0) => { const d = new Date(t); d.setMonth(d.getMonth() + months); d.setDate(d.getDate() + days); return d; };
    const nextFriday = () => { const d = new Date(t); do { d.setDate(d.getDate() + 1); } while (d.getDay() !== 5); return d; };
    const vals = [nextFriday(), add(7), add(0, 1)];
    els.forEach((el, i) => { if (vals[i]) el.textContent = f.format(vals[i]); });
  })();

  /* ---------------------------------------------------------------- FAQ index */
  (() => {
    const items = $$('.faq__item'); if (!items.length) return;
    const wide = matchMedia('(min-width: 1100px) and (hover: hover)');
    const select = (it) => items.forEach((x) => { const on = x === it; x.classList.toggle('is-on', on); $('.faq__q', x).setAttribute('aria-expanded', String(on)); });
    items.forEach((it) => {
      const q = $('.faq__q', it);
      q.addEventListener('click', () => select(it));
      q.addEventListener('focus', () => select(it));
      q.addEventListener('pointerenter', () => { if (wide.matches) select(it); });
    });
  })();

  /* ---------------------------------------------------------------- slow crossfade */
  (() => {
    const frame = $('#reel'); if (!frame) return;
    const imgs = $$('img', frame);
    const cap = $('#reel-cap');
    const captions = [
      'Shinagawa at sunrise, Utagawa Hiroshige, about 1834',
      'Nihonbashi at dawn, Utagawa Hiroshige',
      'New Year’s sunrise after snow at Susaki, Utagawa Hiroshige, about 1831',
      'A snowy morning at Koishikawa, Katsushika Hokusai',
    ];
    let i = 0, timer = null;
    const show = (n) => {
      imgs[i].classList.remove('is-on'); i = n; imgs[i].classList.add('is-on');
      cap.animate && !calm.matches && cap.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 1600, easing: 'ease' });
      cap.textContent = captions[i];
    };
    const start = () => { if (calm.matches || timer) return; timer = setInterval(() => show((i + 1) % imgs.length), 6600); };
    const stop = () => { clearInterval(timer); timer = null; };
    document.addEventListener('visibilitychange', () => (document.hidden ? stop() : start()));
    const io = new IntersectionObserver((es) => es.forEach((e) => (e.isIntersecting ? start() : stop())), { threshold: 0.2 });
    io.observe(frame);
    calm.addEventListener('change', () => { if (calm.matches) { stop(); if (i) show(0); } });
  })();

  /* ---------------------------------------------------------------- entrances: once, as sections arrive */
  (() => {
    const els = $$('[data-in]'); if (!els.length) return;
    if (calm.matches || !('IntersectionObserver' in window)) { els.forEach((e) => e.classList.add('is-in')); return; }
    const io = new IntersectionObserver((es) => es.forEach((e) => { if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); } }), { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    els.forEach((e) => io.observe(e));
    // Anything already in view at load, or never intersecting (a tall page jump), must not stay hidden.
    setTimeout(() => els.forEach((e) => { const r = e.getBoundingClientRect(); if (r.top < innerHeight && r.bottom > 0) e.classList.add('is-in'); }), 50);
    addEventListener('load', () => setTimeout(() => els.forEach((e) => { if (e.getBoundingClientRect().bottom < 0) e.classList.add('is-in'); }), 300));
  })();
})();
