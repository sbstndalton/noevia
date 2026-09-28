'use strict';
// The stream-guard (#516) integration seam in provider-egress.cjs: tool-call
// argument validation against an optional registered JSON-schema subset.
// OFF by default (a code flag, not a live preference) and a no-op with no
// schema registered even when flipped on — this proves both invariants, plus
// that turning it on for one tool never touches the existing egress rules
// (Diary/storage refusals) for that or any other tool.
const test = require('node:test');
const assert = require('node:assert/strict');
const egress = require('./provider-egress.cjs');

test.afterEach(() => {
  egress.__setStreamGuardEnabledForTests(false);
  egress.setToolArgumentSchema('fixture_tool', null);
});

test('off by default: a registered schema is never consulted unless explicitly enabled', () => {
  egress.setToolArgumentSchema('fixture_tool', { type: 'object', required: ['x'], additionalProperties: false, properties: { x: { type: 'string' } } });
  const refusal = egress.toolRefusal({ provider: { id: 'default' }, toolName: 'fixture_tool', rawArgs: '{"y":"bad"}' });
  assert.equal(refusal, null, 'default behaviour must be unchanged: the guard is off unless enabled in code');
});

test('enabled with no registered schema is a no-op for every tool', () => {
  egress.__setStreamGuardEnabledForTests(true);
  const refusal = egress.toolRefusal({ provider: { id: 'default' }, toolName: 'some_other_tool', rawArgs: '{"anything":true}' });
  assert.equal(refusal, null);
});

test('enabled with a registered schema refuses arguments that violate it, citing the violation', () => {
  egress.__setStreamGuardEnabledForTests(true);
  egress.setToolArgumentSchema('fixture_tool', { type: 'object', required: ['x'], additionalProperties: false, properties: { x: { type: 'string' } } });
  const refusal = egress.toolRefusal({ provider: { id: 'default' }, toolName: 'fixture_tool', rawArgs: '{"y":"bad"}' });
  assert.match(refusal, /fixture_tool arguments failed schema validation/);
  assert.match(refusal, /Unknown property 'y'/);
});

test('enabled with a registered schema lets valid arguments through to the existing rules unchanged', () => {
  egress.__setStreamGuardEnabledForTests(true);
  egress.setToolArgumentSchema('fixture_tool', { type: 'object', required: ['x'], additionalProperties: false, properties: { x: { type: 'string' } } });
  const refusal = egress.toolRefusal({ provider: { id: 'default' }, toolName: 'fixture_tool', rawArgs: '{"x":"ok"}' });
  assert.equal(refusal, null);
});

test('enabling the guard does not change the unrelated Diary/storage egress rules', () => {
  egress.__setStreamGuardEnabledForTests(true);
  const external = { id: 'chatgpt-prov', kind: 'chatgpt-oauth', label: 'ChatGPT' };
  const refusal = egress.toolRefusal({ provider: external, toolName: 'diary_search', rawArgs: '{}' });
  assert.match(refusal, /Diary content is never sent to/);
});

test('validateToolArguments is directly usable and returns null when disabled', () => {
  egress.setToolArgumentSchema('fixture_tool', { type: 'object', required: ['x'] });
  assert.equal(egress.validateToolArguments('fixture_tool', '{}'), null);
  egress.__setStreamGuardEnabledForTests(true);
  const violation = egress.validateToolArguments('fixture_tool', '{}');
  assert.ok(violation);
  assert.match(violation.message, /Missing required property x/);
});
