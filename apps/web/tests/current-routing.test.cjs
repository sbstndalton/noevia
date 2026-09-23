'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const exports_ = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '../src/current-routing.ts'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText, { exports: exports_ });
const { currentRoutingDecision } = exports_;

test('stats routing follows only the latest assistant turn in the visible chat', () => {
  const route = { status: 'accepted', effectiveRole: 'smart' };
  const firstChat = [{ role: 'user', content: 'one' }, { role: 'assistant', content: 'answer', routingDecision: route }];
  const otherChat = [{ role: 'user', content: 'two' }, { role: 'assistant', content: 'other answer' }];
  assert.equal(currentRoutingDecision(firstChat, true), route);
  assert.equal(currentRoutingDecision(firstChat, false), null);
  assert.equal(currentRoutingDecision(otherChat, true), null);
  assert.equal(currentRoutingDecision([...firstChat, { role: 'user', content: 'next' }], true), null);
  assert.equal(currentRoutingDecision([...firstChat, { role: 'user', content: 'next' }, { role: 'assistant', content: '' }], true), null);
  assert.equal(currentRoutingDecision([...firstChat, { role: 'user', content: 'manual' }, { role: 'assistant', content: 'manual answer' }], true), null);
  assert.equal(currentRoutingDecision(structuredClone(firstChat), true).effectiveRole, 'smart');
});
