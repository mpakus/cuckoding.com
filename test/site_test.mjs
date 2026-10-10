import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../site/site.js", import.meta.url), "utf8");

function browser({ reduced = false, saved = null, denied = false } = {}) {
  const events = {};
  const frames = [];
  const attributes = {};
  const root = { dataset: {} };
  const motions = [["depth", "sword", "morgenstern"], ["vault", "emissary"], ["depth", "pan", "dance"], ["depth", "leisure", "weight"]];
  const layers = motions.map(names => names.map(motion => ({ dataset: { motion }, style: {} })));
  const styles = layers.map(scene => scene[0].style);
  const bounds = [{ top: 100, height: 1200, width: 1000 }, { top: 1100, height: 600, width: 1000 }, { top: 2100, height: 500, width: 1000 }, { top: 3100, height: 500, width: 1000 }];
  const scenes = styles.map((style, i) => ({
    getBoundingClientRect: () => bounds[i],
    querySelector: () => ({ getBoundingClientRect: () => ({ height: 600, width: 1000 }) }),
    querySelectorAll: () => layers[i],
  }));
  const offsets = () => styles.map(style => Number.parseFloat(style.transform.split(",")[1]));
  const toggle = { hidden: true, setAttribute: (k, v) => attributes[k] = v, addEventListener: (_, callback) => events.click = callback };
  const media = { matches: reduced, addEventListener: (_, callback) => events.media = callback };
  const nodes = {
    "#motion-toggle": toggle,
  };
  const storage = {
    getItem: () => { if (denied) throw new Error("Denied"); return saved; },
    setItem: (_, value) => { if (denied) throw new Error("Denied"); saved = value; },
  };
  runInNewContext(source, {
    document: { documentElement: root, querySelector: selector => nodes[selector], querySelectorAll: () => scenes },
    window: { matchMedia: () => media, addEventListener: (name, callback) => events[name] = callback },
    innerHeight: 800,
    localStorage: storage,
    requestAnimationFrame: callback => frames.push(callback),
  });
  return { root, layers, events, frames, toggle, media, attributes, get offset() { return offsets()[0]; }, get offsets() { return offsets(); }, get saved() { return saved; }, bounds: (value, index = 0) => bounds[index] = value, flush: () => frames.splice(0).forEach(callback => callback()) };
}

test("parallax responds to scroll, coalesces frames and stays inside image overscan", () => {
  const ui = browser();
  assert.equal(ui.toggle.hidden, false);
  assert.ok(Math.abs(ui.offset + 9.9) < 0.00001);
  const start = ui.layers[0][1].style.transform;
  assert.match(start, /translate3d\(-66/);
  ui.bounds({ top: -10000, height: 1200, width: 1000 });
  ui.events.scroll();
  ui.events.scroll();
  assert.equal(ui.frames.length, 1);
  ui.flush();
  assert.equal(ui.offset, 33);
  assert.match(ui.layers[0][1].style.transform, /translate3d\(0px/);
  assert.match(ui.layers[0][2].style.transform, /translate3d\(0px/);
  ui.bounds({ top: 10000, height: 1200, width: 1000 });
  ui.events.resize();
  ui.flush();
  assert.equal(ui.offset, -33);
  assert.equal(ui.frames.length, 0, "No perpetual animation loop");
});

test("pause persists and system reduced motion always stops displacement", () => {
  const ui = browser();
  ui.events.click();
  assert.deepEqual(ui.offsets, [0, 0, 0, 0]);
  assert.ok(ui.layers.flat().every(layer => layer.style.transform.startsWith("translate3d(0px, 0px, 0) rotate(0deg)")));
  assert.equal(ui.saved, "paused");
  assert.equal(ui.attributes["aria-pressed"], "true");
  assert.equal(ui.toggle.textContent, "Resume parallax");
  ui.events.scroll();
  assert.equal(ui.frames.length, 0);
  const restored = browser({ saved: ui.saved });
  assert.equal(restored.offset, 0);
  restored.events.click();
  assert.equal(restored.saved, "running");
  assert.notEqual(restored.offset, 0);
  restored.media.matches = true;
  restored.events.media();
  assert.deepEqual(restored.offsets, [0, 0, 0, 0]);
  assert.equal(restored.toggle.disabled, true);
  assert.equal(restored.toggle.textContent, "Reduced motion on");
  restored.media.matches = false;
  restored.events.media();
  assert.equal(restored.toggle.disabled, false);
  assert.notEqual(restored.offset, 0);
});

test("reduced motion on first load and denied storage remain usable", () => {
  const quiet = browser({ reduced: true, saved: "running" });
  assert.equal(quiet.offset, 0);
  quiet.events.scroll();
  assert.equal(quiet.frames.length, 0);
  const denied = browser({ denied: true });
  denied.events.click();
  assert.equal(denied.offset, 0);
  denied.events.click();
  assert.notEqual(denied.offset, 0);
});


test("each character moves independently, including the darker finale", () => {
  const ui = browser();
  // All below-fold scenes start in their first pose; bringing the page through
  // the duel reaches the crossed pose without an animation clock.
  const sword = ui.layers[0][1].style.transform;
  const mace = ui.layers[0][2].style.transform;
  assert.notEqual(sword, mace);
  ui.bounds({ top: -650, height: 1200, width: 1000 });
  ui.events.scroll(); ui.flush();
  assert.match(ui.layers[0][1].style.transform, /^translate3d\(0px/);
  for (let index = 1; index < 4; index++) ui.bounds({ top: 50, height: 600, width: 1000 }, index);
  ui.events.scroll(); ui.flush();
  for (const scene of ui.layers.slice(2)) assert.notEqual(scene[1].style.transform, scene[2].style.transform);
  assert.match(ui.layers[3][1].style.transform, /, -[0-9.]+px/);
  assert.match(ui.layers[3][2].style.transform, /, [0-9.]+px/);
  assert.equal(ui.layers.flat().length, 11);
});

test("hero camera has bounded depth, reverses with scrolling and pauses without collapsing the page", () => {
  const ui = browser();
  const [vault, emissary] = ui.layers[1];
  assert.equal(ui.root.dataset.motion, "enabled");
  const initial = emissary.style.transform;
  ui.bounds({ top: -400, height: 1400, width: 1000 }, 1);
  ui.events.scroll(); ui.flush();
  assert.match(emissary.style.transform, /scale\(1.21\)/);
  assert.notEqual(vault.style.transform, emissary.style.transform);
  ui.bounds({ top: -5000, height: 1400, width: 1000 }, 1);
  ui.events.scroll(); ui.flush();
  assert.match(emissary.style.transform, /scale\(1.42\)/);
  ui.bounds({ top: 0, height: 1400, width: 1000 }, 1);
  ui.events.scroll(); ui.flush();
  assert.equal(emissary.style.transform, initial);
  ui.events.click();
  assert.equal(ui.root.dataset.motion, "enabled", "Pause does not move the page by collapsing sticky sections");
  assert.equal(emissary.style.transform, initial);
  ui.media.matches = true; ui.events.media();
  assert.equal(ui.root.dataset.motion, "reduced");
  ui.bounds({ top: -100, height: 600, width: 1000 }, 1);
  ui.media.matches = false; ui.events.media();
  ui.events.click();
  assert.match(emissary.style.transform, /scale\(1.42\)/, "A short frame still produces a finite, bounded pose");
});
