const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('typescript');
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(require('node:path').join(__dirname, '../src/settings-data.ts'), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, { exports: exportsObject });
const { parseUsage, parseUsers } = exportsObject;
const totals = { input: 0, output: 0, replies: 0 };
const usage = { days: [], models: [], allTime: totals, last7: totals, last30: totals, activeDays: 0, currentStreak: 0, longestStreak: 0, retentionDays: 365, timeZone: 'UTC' };
test('usage accepts an empty account without inventing activity', () => assert.equal(parseUsage(usage), usage));
test('malformed usage fails before rendering totals or calendar', () => {
  for (const value of [{}, null, { ...usage, allTime: {} }, { ...usage, days: [{ ...totals, day: 'invalid' }] }, { ...usage, models: [{ name: 'model', input: NaN }] }]) assert.throws(() => parseUsage(value), /invalid usage response/);
});
test('users accepts valid lists and empty accounts', () => {
  const value = { users: [{ id: 'test', username: 'alex', displayName: 'Alex', role: 'admin' }] };
  assert.equal(parseUsers(value), value);
  assert.equal(parseUsers({ users: [] }).users.length, 0);
});
test('malformed users fails before rendering the user list', () => {
  for (const value of [{}, null, { users: null }, { users: [null] }, { users: [{ id: 'test' }] }]) assert.throws(() => parseUsers(value), /invalid users response/);
});
