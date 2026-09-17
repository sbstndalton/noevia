const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const code = fs.readFileSync(path.join(__dirname, '../public/theme.js'), 'utf8');
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
    assert.equal(attributes.content, expected === 'light' ? '#f7f9fc' : '#1c1d20');
  });
}

for (const palette of ['warm', 'cool', 'neutral', 'invalid']) test(`restores ${palette} palette before first paint`, () => {
  const attributes = {};
  vm.runInNewContext(code, {
    localStorage: { getItem: key => key === 'cowork-theme' ? 'light' : palette },
    document: {
      documentElement: { setAttribute: (key, value) => { attributes[key] = value; } },
      querySelector: () => ({ setAttribute: (key, value) => { attributes[key] = value; } }),
    },
  });
  assert.equal(attributes['data-theme'], 'light');
  assert.equal(attributes['data-palette'], palette === 'invalid' ? 'cool' : palette);
  assert.equal(attributes.content, {warm:'#fbf7f0',cool:'#f7f9fc',neutral:'#fafafa',invalid:'#f7f9fc'}[palette]);
});

for(const mode of ['light','dark'])test(`independent ${mode} palette restores before React`,()=>{
 const attributes={}; const storage={'cowork-theme':mode,'cowork-palette':'warm','cowork-palette-light':'sage','cowork-palette-dark':'iris'};
 vm.runInNewContext(code,{localStorage:{getItem:key=>storage[key]},document:{documentElement:{setAttribute:(k,v)=>attributes[k]=v},querySelector:()=>({setAttribute:(k,v)=>attributes[k]=v})}});
 assert.equal(attributes['data-palette'],mode==='light'?'sage':'iris');
 assert.equal(attributes.content,mode==='light'?'#f4f8f5':'#22202b');
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
