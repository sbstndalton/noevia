// Regression for the LibraryTab delete-cleanup error toast never being visible: onDeleted() used
// to fire (unmounting the card via refresh) and only afterwards was the local error state set on
// a branch that no longer rendered. The fix routes the settings-cleanup error through onDeleted's
// argument so the parent's persistent error banner shows it even after the card unmounts.
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path');
const src = fs.readFileSync(path.join(__dirname, '../src/components/models/LibraryTab.tsx'), 'utf8');

test('DeleteModel forwards the cleanup error through onDeleted instead of a local error branch', () => {
  const calls = [...src.matchAll(/setConfirming\(false\);\s*onDeleted\(([^)]*)\);/g)].map(m => m[1]);
  assert.equal(calls.length, 2, 'expected both delete branches to forward via onDeleted(...)');
  for (const arg of calls) assert.match(arg, /outcome\.error/);
});

test('LibraryTab surfaces a forwarded delete error on its persistent error banner before refreshing', () => {
  assert.match(src, /onDeleted=\{\(err\) => \{ if \(err\) setError\(err\); onChanged\(\); \}\}/);
});

test('ModelCard/DeleteModel onDeleted signature accepts an optional error', () => {
  assert.match(src, /onDeleted:\s*\(error\?:\s*string\s*\|\s*null\)\s*=>\s*void/g);
});
