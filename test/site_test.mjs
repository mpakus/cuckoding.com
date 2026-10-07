import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../site/site.js", import.meta.url), "utf8");

function browser({ reduced = false, saved = null, denied = false } = {}) {
  const events = {};
  const frames = [];
  const attributes = {};
  let offset;
  let bounds = { top: 100, height: 400 };
  const toggle = { hidden: true, setAttribute: (k, v) => attributes[k] = v, addEventListener: (_, callback) => events.click = callback };
  const media = { matches: reduced, addEventListener: (_, callback) => events.media = callback };
  const nodes = {
    "#arena-art": { style: { setProperty: (_, value) => offset = Number.parseFloat(value) } },
    "#art-window": { getBoundingClientRect: () => bounds },
    "#motion-toggle": toggle,
  };
  const storage = {
    getItem: () => { if (denied) throw new Error("Denied"); return saved; },
    setItem: (_, value) => { if (denied) throw new Error("Denied"); saved = value; },
  };
  runInNewContext(source, {
    document: { querySelector: selector => nodes[selector] },
    window: { matchMedia: () => media, addEventListener: (name, callback) => events[name] = callback },
    innerHeight: 800,
    localStorage: storage,
    requestAnimationFrame: callback => frames.push(callback),
  });
  return { events, frames, toggle, media, attributes, get offset() { return offset; }, get saved() { return saved; }, bounds: value => bounds = value, flush: () => frames.splice(0).forEach(callback => callback()) };
}

test("parallax responds to scroll, coalesces frames and stays inside image overscan", () => {
  const ui = browser();
  assert.equal(ui.toggle.hidden, false);
  assert.equal(ui.offset, 9);
  ui.bounds({ top: -10000, height: 200 });
  ui.events.scroll();
  ui.events.scroll();
  assert.equal(ui.frames.length, 1);
  ui.flush();
  assert.equal(ui.offset, 12);
  ui.bounds({ top: 10000, height: 400 });
  ui.events.resize();
  ui.flush();
  assert.equal(ui.offset, -24);
  assert.equal(ui.frames.length, 0, "No perpetual animation loop");
});

test("pause persists and system reduced motion always stops displacement", () => {
  const ui = browser();
  ui.events.click();
  assert.equal(ui.offset, 0);
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
  assert.equal(restored.offset, 0);
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
