const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const code = fs.readFileSync(path.join(__dirname, '../../public/theme.js'), 'utf8');
for (const [name, read, expected, systemLight] of [
  ['saved light preference', () => 'light', 'light', false],
  ['new installation on a dark system', () => null, 'dark', false],
  ['new installation on a light system', () => null, 'light', true],
  ['saved system preference on a light system', (k) => (k === 'cowork-theme' ? 'system' : null), 'light', true],
  ['saved dark preference on a light system', (k) => (k === 'cowork-theme' ? 'dark' : null), 'dark', true],
  ['unavailable browser storage', () => { throw new Error('Storage blocked'); }, 'dark', false],
]) {
  test(`theme is ready before React with ${name}`, () => {
    const attributes = {};
    vm.runInNewContext(code, {
      matchMedia: (query) => ({ matches: query.includes('light') ? systemLight : !systemLight }),
      localStorage: { getItem: read },
      document: {
        documentElement: { setAttribute: (key, value) => { attributes[key] = value; } },
        querySelector: () => ({ setAttribute: (key, value) => { attributes[key] = value; } }),
      },
    });
    assert.equal(attributes['data-theme'], expected);
    assert.equal(attributes.content, expected === 'light' ? '#faf9f5' : '#151515');
  });
}

// Accent palettes were restored at the user's request (2026-09-18): the saved one is
// applied before paint, like the theme, so there is no flash of the wrong accent.
for (const [stored, expected] of [['warm', 'warm'], ['sage', 'sage'], ['iris', 'iris'], ['cool', 'cool'], ['neutral', 'neutral'], ['invalid', 'iris'], [null, 'iris']]) {
  test(`a stored ${stored ?? 'missing'} palette resolves to ${expected} before paint`, () => {
    const attributes = {};
    vm.runInNewContext(code, {
      localStorage: { getItem: key => key === 'cowork-theme' ? 'light' : stored },
      document: {
        documentElement: { setAttribute: (key, value) => { attributes[key] = value; } },
        querySelector: () => ({ setAttribute: (key, value) => { attributes[key] = value; } }),
      },
    });
    assert.equal(attributes['data-theme'], 'light');
    assert.equal(attributes['data-palette'], expected);
    assert.equal(attributes.content, '#faf9f5');
  });
}

test('the per-mode palette key wins over the shared one', () => {
  const attributes = {};
  vm.runInNewContext(code, {
    localStorage: { getItem: key => key === 'cowork-theme' ? 'light' : key === 'cowork-palette-light' ? 'sage' : 'warm' },
    document: {
      documentElement: { setAttribute: (key, value) => { attributes[key] = value; } },
      querySelector: () => ({ setAttribute: (key, value) => { attributes[key] = value; } }),
    },
  });
  assert.equal(attributes['data-palette'], 'sage');
});

test('unavailable storage still resolves an accent', () => {
  const attributes = {};
  vm.runInNewContext(code, {
    matchMedia: () => ({ matches: false }),
    localStorage: { getItem: () => { throw new Error('Storage blocked'); } },
    document: {
      documentElement: { setAttribute: (key, value) => { attributes[key] = value; } },
      querySelector: () => ({ setAttribute: (key, value) => { attributes[key] = value; } }),
    },
  });
  assert.equal(attributes['data-palette'], 'iris');
});

test('theme-color matches the page surface token in both modes', () => {
  const tokens = fs.readFileSync(path.join(__dirname, '../../src/styles/system/tokens.css'), 'utf8');
  const surface = (selector) => tokens.slice(tokens.indexOf(selector)).match(/--md-surface:\s*(#[\da-f]{6});/i)[1];
  assert.match(code, new RegExp(surface(":root, [data-theme='dark'] {")));
  assert.match(code, new RegExp(surface("[data-theme='light'] {")));
});

// #951: one design system. A browser that saved a retired theme family or material gets the
// new look silently: no data-family attribute, and the stale keys are forgotten.
for (const stored of [{ 'noevia:theme-family': 'glass' }, { 'noevia:material': 'liquid' }, { 'noevia:theme-family': 'brutalist', 'noevia:material': 'soft' }, {}]) {
  test(`a retired family or material is forgotten silently: ${JSON.stringify(stored)}`, () => {
    const attributes = {}, removed = [];
    vm.runInNewContext(code, {
      localStorage: { getItem: (key) => (key in stored ? stored[key] : null), removeItem: (key) => removed.push(key) },
      document: { documentElement: { setAttribute: (key, value) => { attributes[key] = value; } }, querySelector: () => ({ setAttribute: () => {} }) },
    });
    assert.equal(attributes['data-family'], undefined);
    assert.deepEqual(removed.sort(), ['noevia:material', 'noevia:theme-family']);
    assert.equal(attributes['data-theme'], 'dark');
  });
}
test('blocked storage cannot break the retired-key cleanup', () => {
  const attributes = {};
  vm.runInNewContext(code, {
    localStorage: { getItem: () => null, removeItem: () => { throw new Error('Storage blocked'); } },
    document: { documentElement: { setAttribute: (key, value) => { attributes[key] = value; } }, querySelector: () => ({ setAttribute: () => {} }) },
  });
  assert.equal(attributes['data-motion'], 'system');
});

// Presentation preferences restore in the same pass as the theme. Applied
// after React mounts they would flash the previous setting, which is the whole
// reason this file exists.
for (const [name, stored, expected] of [
  ['saved preferences', { 'noevia:chat-font': 'serif', 'noevia:density': 'compact', 'noevia:motion': 'reduced' },
    { 'data-chat-font': 'serif', 'data-density': 'compact', 'data-motion': 'reduced' }],
  ['a new installation', {},
    { 'data-chat-font': 'sans', 'data-density': 'comfortable', 'data-motion': 'system' }],
  ['values that are not offered', { 'noevia:chat-font': 'comic', 'noevia:density': '../../etc', 'noevia:motion': '1' },
    { 'data-chat-font': 'sans', 'data-density': 'comfortable', 'data-motion': 'system' }],
]) {
  test(`presentation preferences are ready before React with ${name}`, () => {
    const attributes = {};
    vm.runInNewContext(code, {
      localStorage: { getItem: (key) => (key in stored ? stored[key] : null) },
      document: {
        documentElement: { setAttribute: (key, value) => { attributes[key] = value; } },
        querySelector: () => ({ setAttribute: () => {} }),
      },
    });
    for (const [attribute, value] of Object.entries(expected)) assert.equal(attributes[attribute], value, attribute);
  });
}

test('presentation preferences survive blocked storage', () => {
  const attributes = {};
  vm.runInNewContext(code, {
    localStorage: { getItem: () => { throw new Error('Storage blocked'); } },
    document: {
      documentElement: { setAttribute: (key, value) => { attributes[key] = value; } },
      querySelector: () => ({ setAttribute: () => {} }),
    },
  });
  assert.equal(attributes['data-chat-font'], 'sans');
  assert.equal(attributes['data-density'], 'comfortable');
  assert.equal(attributes['data-motion'], 'system');
});
