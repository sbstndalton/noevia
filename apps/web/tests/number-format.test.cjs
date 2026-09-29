'use strict';
// #587: sizes, chart axes and rates in the Models area are written in the interface locale, not
// with toFixed's always-English "3.3". Covers the shared helper and the model-size formatter.
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), ts = require('typescript');
function load(file) {
  const code = ts.transpileModule(fs.readFileSync(path.join(__dirname, '../src', file), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const exports_ = {}; vm.runInNewContext(code, { exports: exports_, Intl, Map, Number }); return exports_;
}
const { formatNumber, localizeLeadingNumber } = load('number-format.ts');
const { formatModelSizeGB } = load('model-size.ts');
const NNBSP = ' ';

test('decimal separator follows the locale', () => {
  assert.equal(formatNumber(3.3, 'en-GB', 1), '3.3');
  assert.equal(formatNumber(3.3, 'de-DE', 1), '3,3');
  assert.equal(formatNumber(3.3, 'fr-FR', 1), '3,3');
});

test('grouping follows the locale', () => {
  assert.equal(formatNumber(131072, 'en-GB', 0), '131,072');
  assert.equal(formatNumber(131072, 'de-DE', 0), '131.072');
  assert.equal(formatNumber(131072, 'fr-FR', 0), `131${NNBSP}072`);
  assert.equal(formatNumber(1234.5, 'de-DE', 1), '1.234,5');
});

test('fixed, ranged and default fraction digits', () => {
  assert.equal(formatNumber(8, 'de-DE', 1), '8,0');
  assert.equal(formatNumber(8, 'de-DE', { max: 1 }), '8');
  assert.equal(formatNumber(8.25, 'de-DE', { max: 1 }), '8,3');
  assert.equal(formatNumber(1.2345, 'de-DE'), '1,23');
});

test('an invalid locale falls back instead of throwing', () => {
  assert.equal(typeof formatNumber(1.5, 'not a locale!', 1), 'string');
});

test('a server-formatted quantity keeps its unit and decimal count', () => {
  assert.equal(localizeLeadingNumber('5.3 TB', 'de-DE'), '5,3 TB');
  assert.equal(localizeLeadingNumber('139.7 GB', 'fr-FR'), '139,7 GB');
  assert.equal(localizeLeadingNumber('10 MB/s', 'de-DE'), '10 MB/s');
  assert.equal(localizeLeadingNumber('1500.5 MB', 'de-DE'), '1.500,5 MB');
  assert.equal(localizeLeadingNumber('—', 'de-DE'), '—');
});

test('model sizes use the locale separators', () => {
  assert.equal(formatModelSizeGB(3.3, 'en-GB'), '3.3 GB');
  assert.equal(formatModelSizeGB(3.3, 'de-DE'), '3,3 GB');
  assert.equal(formatModelSizeGB(3.3, 'fr-FR'), '3,3 GB');
  assert.equal(formatModelSizeGB(5300, 'de-DE'), '5.300 GB');
  assert.equal(formatModelSizeGB(5300.04, 'fr-FR'), `5${NNBSP}300 GB`);
  assert.equal(formatModelSizeGB(3, 'de-DE'), '3 GB');
  assert.equal(formatModelSizeGB(null, 'de-DE'), null);
  assert.equal(formatModelSizeGB(0, 'de-DE'), null);
});
