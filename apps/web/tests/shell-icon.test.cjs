'use strict';
// The close icon is two diagonals of the same 12-unit square; a typo once drew the second one
// half-length, which rendered as a skewed glyph on every dialog.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
test('close icon draws a symmetric ×', () => {
  const src = fs.readFileSync(path.join(__dirname, '../src/components/ShellIcon.tsx'), 'utf8');
  const d = src.match(/close: '([^']+)'/)[1];
  const nums = d.match(/-?\d+(\.\d+)?/g).map(Number);
  assert.deepEqual(nums, [6, 6, 12, 12, 6, 18, 18, 6], `unexpected close path ${d}`);
});
