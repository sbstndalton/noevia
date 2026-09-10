const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const code = fs.readFileSync(path.join(__dirname, '../public/theme.js'), 'utf8');
for (const [name, read, expected] of [
  ['saved light preference', () => 'light', 'light'],
  ['new installation', () => null, 'dark'],
  ['unavailable browser storage', () => { throw new Error('Storage blocked'); }, 'dark'],
]) {
  test(`theme is ready before React with ${name}`, () => {
    const attributes = {};
    vm.runInNewContext(code, {
      localStorage: { getItem: read },
      document: {
        documentElement: { setAttribute: (key, value) => { attributes[key] = value; } },
        querySelector: () => ({ setAttribute: (key, value) => { attributes[key] = value; } }),
      },
    });
    assert.equal(attributes['data-theme'], expected);
    assert.equal(attributes.content, expected === 'light' ? '#faf9f7' : '#1c1d20');
  });
}
