'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
function load(file, extra = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '../src', file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText, { exports, require, ...extra });
  return exports;
}
const calendar = load('logo-calendar.ts');
test('seasonal boundaries follow local months and explicit hemisphere', () => {
  const north = ['winter','winter','spring','spring','spring','summer','summer','summer','autumn','autumn','autumn','winter'];
  const south = ['summer','summer','autumn','autumn','autumn','winter','winter','winter','spring','spring','spring','summer'];
  for (let month = 0; month < 12; month++) {
    const first = new Date(2026, month, 1, 0, 0);
    const last = new Date(2026, month + 1, 1, 0, 0, 0, -1);
    for (const date of [first, last]) {
      assert.equal(calendar.calendarLogo('seasonal', 'north', date), north[month]);
      assert.equal(calendar.calendarLogo('seasonal', 'south', date), south[month]);
      assert.equal(calendar.calendarLogo('default', 'south', date), 'default');
    }
  }
  assert.equal(calendar.calendarLogo('seasonal', 'north', new Date('invalid')), 'default');
});
test('monthly occasions keep their month in both hemispheres and otherwise use the season', () => {
  const occasions = { 1:'rose', 2:'clover', 9:'harvest', 11:'festive' };
  for (let month = 0; month < 12; month++) for (const hemisphere of ['north', 'south']) {
    const date = new Date(2028, month, 15);
    assert.equal(calendar.calendarLogo('monthly', hemisphere, date), occasions[month] || calendar.calendarLogo('seasonal', hemisphere, date));
  }
});
test('test button visits each palette once and wraps to the unchanged default', () => {
  let current = 'default';
  const seen = [];
  for (let i = 0; i < calendar.LOGO_PALETTES.length; i++) { current = calendar.nextLogoPalette(current); seen.push(current); }
  assert.equal(new Set(seen).size, calendar.LOGO_PALETTES.length);
  assert.deepEqual(seen, ['spring','summer','autumn','winter','rose','clover','harvest','festive','default']);
});
test('runtime applies saved choice, keeps preview transient, refreshes on date and storage changes, and cleans up', () => {
  const attrs = {}, stored = new Map([['noevia:logo-calendar','seasonal'], ['noevia:logo-hemisphere','south']]);
  const listeners = new Map(), timers = new Map();
  const document = { documentElement: { dataset: {}, getAttribute: k => attrs[k], setAttribute: (k,v) => { attrs[k]=v; } },
    addEventListener: (k,v) => listeners.set(k,v), removeEventListener: k => listeners.delete(k) };
  const localStorage = { getItem: k => stored.get(k) ?? null, setItem: (k,v) => stored.set(k,v) };
  const family = load('theme-family.ts');
  const preferences = load('preferences.ts', { document, localStorage, require: m => m === './theme-family' ? family : require(m) });
  let month = 0;
  const fakeCalendar = { ...calendar, calendarLogo: (mode,hemisphere) => calendar.calendarLogo(mode,hemisphere,new Date(2026,month,1)) };
  const window = { setInterval: fn => { timers.set(1,fn); return 1; }, addEventListener: (k,v) => listeners.set(k,v), removeEventListener: k => listeners.delete(k) };
  const runtime = load('logo-appearance.ts', { document, localStorage, window, clearInterval: k => timers.delete(k),
    require: m => m === './preferences' ? preferences : m === './logo-calendar' ? fakeCalendar : require(m) });
  const stop = runtime.startLogoAppearance();
  const palette = () => document.documentElement.dataset.logoPalette;
  assert.equal(palette(), 'summer');
  month = 6; timers.get(1)(); assert.equal(palette(), 'winter');
  runtime.previewLogo('rose'); assert.equal(palette(), 'rose');
  assert.equal(stored.get('noevia:logo-calendar'), 'seasonal');
  runtime.previewLogo(null); assert.equal(palette(), 'winter');
  stored.set('noevia:logo-calendar', 'monthly'); month = 11;
  listeners.get('storage')({key:'noevia:logo-calendar'}); assert.equal(palette(), 'festive');
  stored.clear(); listeners.get('storage')({key:null}); assert.equal(palette(), 'default');
  stop(); assert.equal(timers.size,0); assert.equal(listeners.size,0);
});
