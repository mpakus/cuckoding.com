// Focused native-scroll regression. Run: node test/github_page_motion_test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('github.page/script.js', 'utf8');

for (const initiallyReduced of [false, true]) {
  const listeners = {};
  const media = { matches: initiallyReduced, addEventListener: (_, fn) => { listeners.motion = fn; } };
  const reveal = { visible: false, setAttribute() { this.visible = true; }, getBoundingClientRect: () => ({top: 2000, bottom: 2100}) };
  const layers = [5000, -5000].map(top => ({
    dataset: {parallax: '0.025'}, style: {},
    parentElement: {getBoundingClientRect: () => ({top, height: 500})},
    removeAttribute() { this.style = {}; }
  }));
  const progress = {style: {}};
  const root = {scrollHeight: 4000, classList: {add() {}}};
  const window = {
    innerHeight: 800, scrollY: 1600, matchMedia: () => media,
    addEventListener: (name, fn) => { listeners[name] = fn; },
    IntersectionObserver: true
  };
  vm.runInNewContext(source, {
    window,
    document: {
      documentElement: root,
      querySelectorAll: selector => selector === '[data-reveal]' ? [reveal] : layers,
      querySelector: () => progress
    },
    requestAnimationFrame: fn => fn(),
    IntersectionObserver: class {
      observe() {}
      unobserve() {}
    }
  });
  if (initiallyReduced) {
    assert.equal(reveal.visible, true, 'Reduced motion shows content immediately');
    assert.ok(layers.every(layer => !layer.style.transform));
    assert.equal(progress.style.transform, undefined);
  } else {
    assert.equal(reveal.visible, false);
    assert.equal(progress.style.transform, 'scaleX(0.5)');
    assert.match(layers[0].style.transform, /translate3d\(0, -24px, 0\)/);
    assert.match(layers[1].style.transform, /translate3d\(0, 24px, 0\)/);
    media.matches = true;
    listeners.motion();
    assert.equal(reveal.visible, true, 'Changing motion preference reveals pending content');
    assert.ok(layers.every(layer => !layer.style.transform), 'Preference change clears decorative transforms');
    listeners.scroll();
    assert.ok(layers.every(layer => !layer.style.transform), 'Reduced-motion scrolling stays still');
  }
}
console.log('Pages motion: initial and changed reduced-motion states, visible content, bounded parallax pass');
