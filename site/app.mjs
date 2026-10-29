// Decorative movement never owns scrolling or the visibility of page content.
export function parallaxOffset(top, height, viewport, speed) {
  const distance = (viewport - height) / 2 - top;
  const limit = height * 0.07;
  return Math.max(-limit, Math.min(limit, distance * speed));
}

export function createMotion({ images, button, body, media, viewport, request, cancel }) {
  let paused = false;
  let frame = null;
  const disabled = () => paused || media.matches;
  const paint = () => {
    frame = null;
    if (disabled()) return;
    for (const image of images) {
      const { top, height } = image.parentElement.getBoundingClientRect();
      if (top < viewport() && top + height > 0) {
        const offset = parallaxOffset(top, height, viewport(), Number(image.dataset.parallax));
        image.style.setProperty('--parallax-y', `${offset.toFixed(2)}px`);
      }
    }
  };
  const schedule = () => {
    if (!disabled() && frame === null) frame = request(paint);
  };
  const update = () => {
    if (frame !== null) cancel(frame);
    frame = null;
    body.dataset.motion = disabled() ? 'paused' : 'active';
    button.hidden = false;
    button.disabled = media.matches;
    button.textContent = media.matches ? 'Reduced motion on' : paused ? 'Resume motion' : 'Pause motion';
    button.setAttribute('aria-pressed', String(disabled()));
    if (disabled()) {
      for (const image of images) image.style.removeProperty('--parallax-y');
    } else schedule();
  };
  const toggle = () => { paused = !paused; update(); };
  const stop = () => { if (frame !== null) cancel(frame); frame = null; };
  update();
  return { schedule, update, toggle, stop };
}

if (typeof document !== 'undefined') {
  const media = window.matchMedia('(prefers-reduced-motion: reduce)');
  const button = document.querySelector('#motion-toggle');
  const motion = createMotion({
    images: document.querySelectorAll('[data-parallax]'), button, body: document.body, media,
    viewport: () => window.innerHeight,
    request: (callback) => window.requestAnimationFrame(callback),
    cancel: (id) => window.cancelAnimationFrame(id)
  });
  window.addEventListener('scroll', motion.schedule, { passive: true });
  window.addEventListener('resize', motion.schedule, { passive: true });
  window.addEventListener('pagehide', motion.stop);
  window.addEventListener('pageshow', motion.update);
  media.addEventListener('change', motion.update);
  button.addEventListener('click', motion.toggle);

  const steps = [...document.querySelectorAll('[data-stage]')];
  const panels = [...document.querySelectorAll('.stage-panel')];
  const select = (id) => {
    for (const panel of panels) panel.hidden = panel.id !== id;
    for (const step of steps) {
      if (step.hash === `#${id}`) step.setAttribute('aria-current', 'step');
      else step.removeAttribute('aria-current');
    }
  };
  const fromHash = () => {
    const id = window.location.hash.slice(1);
    if (panels.some((panel) => panel.id === id)) select(id);
  };
  select(panels.some((panel) => `#${panel.id}` === window.location.hash) ? window.location.hash.slice(1) : 'stage-spec');
  for (const step of steps) step.addEventListener('click', (event) => {
    // Preserve ordinary link behavior for modified clicks and no-JS readers.
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    select(step.hash.slice(1));
    window.history.replaceState(null, '', step.hash);
  });
  window.addEventListener('hashchange', fromHash);
}
