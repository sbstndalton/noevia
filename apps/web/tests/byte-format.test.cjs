'use strict';
// #610: a file size picks its own unit (B, KB, MB, GB) in the interface locale, so a 2 KB note is
// no longer "0.00 MB". Loads the helper from source in isolation, like number-format.test.cjs.
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), ts = require('typescript');
const code = ts.transpileModule(fs.readFileSync(path.join(__dirname, '../src/number-format.ts'), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
const ex = {}; vm.runInNewContext(code, { exports: ex, Intl, Map, Number, Math, Object });
const { formatBytes } = ex;
const plain = (s) => s.replace(/[  ]/g, ' ');

test('small files read in bytes and kilobytes, never as 0.00 MB', () => {
  assert.match(plain(formatBytes(110, 'en-GB')), /^110 (B|byte)/);
  assert.equal(plain(formatBytes(2048, 'en-GB')), '2 kB');
  assert.equal(plain(formatBytes(1536, 'en-GB')), '1.5 kB');
  assert.doesNotMatch(formatBytes(2048, 'en-GB'), /0[.,]00/);
  assert.match(plain(formatBytes(0, 'en-GB')), /^0 /);
});

test('the unit steps up at 1024 and stops at terabytes', () => {
  assert.equal(plain(formatBytes(1024 * 1024, 'en-GB')), '1 MB');
  assert.equal(plain(formatBytes(3.3 * 1024 ** 3, 'en-GB')), '3.3 GB');
  assert.equal(plain(formatBytes(5.3 * 1024 ** 4, 'en-GB')), '5.3 TB');
  assert.equal(plain(formatBytes(5.3 * 1024 ** 4, 'fr-FR')), '5,3 To');
  assert.equal(plain(formatBytes(3.3 * 1024 ** 3, 'fr-FR')), '3,3 Go');
  assert.equal(plain(formatBytes(150 * 1024, 'en-GB')), '150 kB');
});

test('separators and unit names follow the locale', () => {
  assert.equal(plain(formatBytes(1536, 'de-DE')), '1,5 kB');
  assert.equal(plain(formatBytes(1.5 * 1024 * 1024, 'de-DE')), '1,5 MB');
  assert.equal(plain(formatBytes(2048, 'fr-FR')), '2 ko');
  assert.equal(plain(formatBytes(1.5 * 1024 * 1024, 'fr-FR')), '1,5 Mo');
});

test('bad input and an unknown locale still give text', () => {
  assert.match(plain(formatBytes(NaN, 'en-GB')), /^0 /);
  assert.match(plain(formatBytes(-5, 'en-GB')), /^0 /);
  assert.match(formatBytes(2048, 'xx-invalid-locale-zz'), /2/);
});
