// Run: node test/github_page_art_mode_test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('github.page/script.js', 'utf8');
const html = fs.readFileSync('github.page/index.html', 'utf8');
const attributes = text => Object.fromEntries([...text.matchAll(/([\w-]+)="([^"]*)"/g)].map(m => [m[1], m[2]]));

assert.match(html, /data-art-controls hidden/, 'No-JS page keeps Irony and hides the unavailable switch');

for (const initial of [null, 'classic', 'irony', 'invalid', 'storage-denied']) {
  let stored = initial;
  const denied = initial === 'storage-denied';
  const images = [...html.matchAll(/<img\b[^>]*data-classic-src[^>]*>/g)].map(([tag]) => {
    const attrs = attributes(tag);
    return {
      original: {...attrs},
      dataset: {classicSrc: attrs['data-classic-src'], classicAlt: attrs['data-classic-alt']},
      getAttribute: name => attrs[name], setAttribute: (name, value) => { attrs[name] = value; }
    };
  });
  const captions = [...html.matchAll(/<([a-z]+)\b([^>]*data-classic-copy="[^"]+"[^>]*)>([^<]*)<\/\1>/g)]
    .map(([, , attrs, text]) => ({original: text, textContent: text, dataset: {classicCopy: attributes(attrs)['data-classic-copy']}}));
  const choices = ['classic', 'irony'].map(value => ({name: 'illustration-mode', value, checked: value === 'irony'}));
  const status = {textContent: ''};
  const events = {};
  const controls = {
    hidden: true, querySelectorAll: () => choices, querySelector: () => status,
    addEventListener: (name, fn) => { events[name] = fn; }
  };
  vm.runInNewContext(source, {
    window: {
      innerHeight: 800, scrollY: 0,
      matchMedia: () => ({matches: true, addEventListener() {}}), addEventListener() {},
      localStorage: {
        getItem() { if (denied) throw Error('denied'); return stored; },
        setItem(key, value) { assert.equal(key, 'cuckoding-illustration-mode'); if (denied) throw Error('denied'); stored = value; }
      }
    },
    document: {
      documentElement: {scrollHeight: 1000},
      querySelector: selector => selector === '[data-art-controls]' ? controls : null,
      querySelectorAll: selector => ({'[data-classic-src]': images, '[data-classic-copy]': captions}[selector] || [])
    },
    requestAnimationFrame: fn => fn()
  });

  const assertMode = mode => {
    const irony = mode === 'irony';
    assert.equal(controls.hidden, false);
    assert.equal(choices.filter(choice => choice.checked).length, 1);
    assert.equal(choices.find(choice => choice.checked).value, mode);
    assert.equal(images.length, 3, 'All three illustrations participate');
    images.forEach(image => assert.match(image.original.src, /^assets\/irony-/, 'No-JS artwork defaults to Irony'));
    assert.match(html, /value="irony" checked/, 'No-JS radio defaults to Irony');
    assert.equal(captions.length, 6, 'Artwork captions and hero labels participate');
    images.forEach(image => {
      assert.equal(image.getAttribute('src'), irony ? image.original.src : image.dataset.classicSrc);
      assert.equal(image.getAttribute('alt'), irony ? image.original.alt : image.dataset.classicAlt);
    });
    captions.forEach(caption => assert.equal(caption.textContent, irony ? caption.original : caption.dataset.classicCopy));
    assert.match(status.textContent, irony ? /^Irony mode/ : /^Classic mode/);
  };
  assertMode(initial === 'classic' ? 'classic' : 'irony');
  for (const mode of ['irony', 'classic', 'irony', 'classic']) {
    events.change({target: choices.find(choice => choice.value === mode)});
    assertMode(mode);
    if (!denied) assert.equal(stored, mode);
  }
  events.change({target: {name: 'illustration-mode', value: 'unexpected'}});
  assertMode('classic');
}
console.log('Pages art modes: defaults, restore, invalid/denied storage, repeated switching, alt text and captions pass');
