import test from 'node:test';
import assert from 'node:assert/strict';
import { createMotion, parallaxOffset } from '../site/app.mjs';

function fixture(reduced = false) {
  const queued = new Map();
  const styles = new Map();
  let counter = 0;
  let bounds = { top: 100, height: 700 };
  const image = {
    dataset: { parallax: '0.12' },
    parentElement: { getBoundingClientRect: () => bounds },
    style: { setProperty: (key, value) => styles.set(key, value), removeProperty: (key) => styles.delete(key) }
  };
  const button = { hidden: true, setAttribute(name, value) { this[name] = value; } };
  const body = { dataset: {} };
  const media = { matches: reduced };
  const motion = createMotion({ images: [image], button, body, media, viewport: () => 900,
    request: (callback) => { const id = ++counter; queued.set(id, callback); return id; },
    cancel: (id) => queued.delete(id)
  });
  const flush = () => { const callbacks = [...queued.values()]; queued.clear(); callbacks.forEach(fn => fn()); };
  return { motion, queued, styles, button, body, media, flush, move: value => { bounds = value; } };
}

test('parallax remains inside its image overscan, in both directions', () => {
  assert.equal(parallaxOffset(100, 700, 900, .12), 0);
  assert.ok(Math.abs(parallaxOffset(-10000, 700, 900, .12) - 49) < .001);
  assert.ok(Math.abs(parallaxOffset(10000, 700, 900, .12) + 49) < .001);
});

test('scroll bursts coalesce into one frame and finish without an idle animation loop', () => {
  const f = fixture();
  f.move({top: -100, height: 700});
  for (let i = 0; i < 100; i++) f.motion.schedule();
  assert.equal(f.queued.size, 1);
  f.flush();
  assert.equal(f.styles.get('--parallax-y'), '24.00px');
  assert.equal(f.queued.size, 0);
});

test('initial reduced motion does not schedule movement', () => {
  const f = fixture(true);
  f.motion.schedule();
  assert.equal(f.queued.size, 0);
  assert.equal(f.body.dataset.motion, 'paused');
  assert.equal(f.button.disabled, true);
  assert.equal(f.button.textContent, 'Reduced motion on');
});

test('a live OS preference change cancels pending work and clears movement', () => {
  const f = fixture();
  f.flush();
  f.motion.schedule();
  f.media.matches = true;
  f.motion.update();
  assert.equal(f.queued.size, 0);
  assert.equal(f.styles.size, 0);
  f.media.matches = false;
  f.motion.update();
  assert.equal(f.queued.size, 1);
});

test('manual pause survives OS preference changes and resumes explicitly', () => {
  const f = fixture();
  f.motion.toggle();
  assert.equal(f.button['aria-pressed'], 'true');
  assert.equal(f.button.textContent, 'Resume motion');
  assert.equal(f.queued.size, 0);
  f.media.matches = true; f.motion.update();
  f.media.matches = false; f.motion.update();
  assert.equal(f.queued.size, 0);
  f.motion.toggle();
  assert.equal(f.button['aria-pressed'], 'false');
  assert.equal(f.queued.size, 1);
});

test('offscreen images do not repaint and pagehide cancels a pending frame', () => {
  const f = fixture();
  f.move({top: 1200, height: 700});
  f.flush();
  assert.equal(f.styles.size, 0);
  f.motion.schedule();
  f.motion.stop();
  assert.equal(f.queued.size, 0);
});
