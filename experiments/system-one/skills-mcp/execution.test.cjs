'use strict';

// Offline collaborator contract, NOT a handleChat/browser/model/MCP end-to-end test.
// Explicit harness wiring mirrors chat.cjs: resolve -> allowed set -> exchange ->
// account policy -> approval -> cancellation -> toolbox executor. Only storage,
// discovery and execution dependencies are synthetic; gate collaborators are real.
const test = require('node:test');
const assert = require('node:assert/strict');
const { createToolExchange } = require('../../../apps/web/server/tool-exchange.cjs');
const { createApprovals } = require('../../../apps/web/server/approvals.cjs');
const { createToolPolicy } = require('../../../apps/web/server/tool-policy.cjs');
const { createToolboxes } = require('../../../apps/web/server/toolboxes.cjs');

// Deliberately narrow adapter: tests policy logic, not SQLite persistence/constraints.
function policyStorage() {
  const rows = new Map();
  const key = (user, tool) => JSON.stringify([user, tool]);
  return {
    exec(sql) { assert.match(sql, /^CREATE TABLE IF NOT EXISTS tool_policies/); },
    transaction(fn) { return fn; },
    prepare(sql) {
      if (sql.startsWith('SELECT mode')) return { get: (u, t) => rows.get(key(u, t)) };
      if (sql.startsWith('SELECT tool')) return { all: (u) => [...rows.values()].filter(r => r.user === u) };
      if (sql.startsWith('INSERT INTO tool_policies')) return { run: (u, t, mode) => rows.set(key(u, t), { user: u, tool: t, mode }) };
      throw Error(`Unexpected synthetic database query: ${sql}`);
    },
  };
}
const schema = (name, description = 'Synthetic fixture') => ({ type: 'function', function: { name, description, parameters: { type: 'object', properties: {} } } });

function harness() {
  const calls = [];
  const approvals = createApprovals();
  const policy = createToolPolicy({ db: policyStorage() });
  const boxes = [
    { id: 'read', reads: ['fixture_read'], tools: [schema('fixture_read')] },
    { id: 'write', tools: [schema('fixture_write'), schema('fixture_blocked'), ...Array.from({ length: 16 }, (_, i) => schema(`fixture_extra_${i}`)), schema('fixture_huge', 'x'.repeat(40000))] },
    { id: 'unselected', tools: [schema('fixture_unselected')] },
  ];
  const toolboxes = createToolboxes({
    mcpBoxes: () => boxes,
    mcpTools: () => new Map(boxes.flatMap(b => b.tools.map(t => [t.function.name, {}]))),
    prefill: { budgetFor: () => null },
    executeMcp: async (name, args) => { calls.push({ name, args }); return 'synthetic execution'; },
  });
  let nextApproval = 0;
  function session({ user = 'user-a', chat = 'chat-a', selected = ['read', 'write'], narrowed = ['read'] } = {}) {
    const controller = new AbortController();
    const blocked = name => policy.mode(user, name, toolboxes.isWriteTool(name)) === 'block';
    const resolve = ids => toolboxes.resolveTools({ toolboxes: ids }, 'fixture-9B', blocked);
    const initial = resolve(narrowed);
    const allowed = new Set(initial.tools.map(t => t.function.name));
    const exchange = createToolExchange({ allowed, isWrite: toolboxes.isWriteTool, signal: controller.signal });
    let widened = false;
    return {
      controller, allowed, initial,
      moreTools() {
        if (widened) return null;
        widened = true;
        const full = resolve(selected);
        for (const t of full.tools) allowed.add(t.function.name);
        return full;
      },
      run(name, args = {}) {
        const raw = JSON.stringify(args);
        return exchange({ name, args: raw }, async markWriteAttempt => {
          const mode = policy.mode(user, name, toolboxes.isWriteTool(name));
          if (mode === 'block') return 'ERROR: blocked in account settings';
          if (mode === 'ask' && !approvals.chatWideApproved(user, chat)) {
            const decision = await approvals.awaitApproval({ id: `synthetic-${++nextApproval}`, userId: user, chatId: chat, abortSignal: controller.signal });
            if (decision !== 'approve') return `ERROR: ${decision}; tool not run`;
          }
          if (controller.signal.aborted) return 'ERROR: exchange cancelled; tool was not run.';
          markWriteAttempt();
          return toolboxes.executeToolCall({ toolboxes: selected }, name, raw, allowed);
        });
      },
    };
  }
  function decide(action) {
    assert.equal(approvals.pendingApprovals.size, 1);
    [...approvals.pendingApprovals.values()][0].decide(action);
  }
  return { calls, approvals, policy, toolboxes, session, decide };
}

test('selected write schema grants no authority; Allow once does not approve another call', async () => {
  const h = harness();
  const s = h.session({ narrowed: ['write'] });
  assert.ok(s.allowed.has('fixture_write'));
  assert.equal(h.policy.mode('user-a', 'fixture_write', true), 'ask');
  assert.throws(() => h.policy.set('user-a', 'fixture_write', 'allow', h.toolboxes.isWriteTool), /Writes always ask/);
  const first = s.run('fixture_write', { value: 1 });
  assert.equal(h.calls.length, 0);
  h.decide('approve');
  assert.equal(await first, 'synthetic execution');
  const second = s.run('fixture_write', { value: 2 });
  assert.equal(h.calls.length, 1);
  h.decide('deny');
  assert.match(await second, /deny/);
  assert.equal(h.calls.length, 1);
  assert.equal(h.approvals.chatWideApproved('user-a', 'chat-a'), false);
});

test('Decline is a normal result and repeated identical denied calls never execute', async () => {
  const h = harness();
  const s = h.session({ narrowed: ['write'] });
  const pending = s.run('fixture_write');
  h.decide('deny');
  assert.match(await pending, /deny/);
  assert.match(await s.run('fixture_write'), /deny/);
  assert.equal(h.calls.length, 0);
  assert.equal(h.approvals.pendingApprovals.size, 0);
});

test('Allow for this chat persists only for the same account and chat', async () => {
  const h = harness();
  const s = h.session({ narrowed: ['write'] });
  const pending = s.run('fixture_write');
  h.decide('approve_all');
  await pending;
  assert.equal(await h.session({ narrowed: ['write'] }).run('fixture_write'), 'synthetic execution');
  for (const scope of [{ chat: 'chat-b' }, { user: 'user-b' }]) {
    const other = h.session({ ...scope, narrowed: ['write'] }).run('fixture_write');
    h.decide('deny');
    assert.match(await other, /deny/);
  }
  assert.equal(h.calls.length, 2);
});

test('execution ceiling rejects unknown and unselected tools before approval or execution', async () => {
  const h = harness();
  const s = h.session();
  for (const name of ['unknown', 'fixture_unselected', 'fixture_write']) {
    assert.match(await s.run(name), /not enabled/);
    assert.match(await h.toolboxes.executeToolCall({}, name, '{}', s.allowed), /not enabled/);
  }
  assert.equal(h.approvals.pendingApprovals.size, 0);
  assert.equal(h.calls.length, 0);
});

test('account block excludes selection and overrides an existing chat grant at execution', async () => {
  const h = harness();
  const s = h.session({ narrowed: ['write'] });
  const pending = s.run('fixture_write');
  h.decide('approve_all');
  await pending;
  h.policy.set('user-a', 'fixture_write', 'block', h.toolboxes.isWriteTool);
  assert.match(await s.run('fixture_write', { changed: true }), /blocked/);
  assert.equal(h.session({ narrowed: ['write'] }).allowed.has('fixture_write'), false);
  assert.equal(h.session({ user: 'user-b', narrowed: ['write'] }).allowed.has('fixture_write'), true);
  assert.equal(h.calls.length, 1);
});

test('cancellation before, during and immediately after approval prevents execution', async () => {
  for (const timing of ['before', 'during', 'after']) {
    const h = harness();
    const s = h.session({ narrowed: ['write'] });
    if (timing === 'before') s.controller.abort();
    const pending = s.run('fixture_write');
    if (timing === 'after') h.decide('approve');
    s.controller.abort();
    assert.match(await pending, /cancelled|aborted/);
    assert.equal(h.calls.length, 0);
    assert.equal(h.approvals.pendingApprovals.size, 0);
  }
});

test('more_tools restores only permitted project selection under real count and token budgets', async () => {
  const h = harness();
  h.policy.set('user-a', 'fixture_blocked', 'block', h.toolboxes.isWriteTool);
  const s = h.session();
  const full = s.moreTools();
  assert.equal(full.tools.length, 12);
  assert.ok(full.estTokens <= full.budget);
  assert.ok(full.dropped.some(x => /cap/.test(x)));
  assert.ok(s.allowed.has('fixture_write'));
  for (const name of ['fixture_blocked', 'fixture_unselected', 'fixture_extra_15', 'fixture_huge']) {
    assert.equal(s.allowed.has(name), false);
    assert.match(await s.run(name), /not enabled/);
  }
  assert.equal(s.moreTools(), null);
  const pending = s.run('fixture_write');
  assert.equal(h.calls.length, 0);
  h.decide('deny');
  await pending;
  // Put the oversized definition first so token budget (not count cap) binds.
  const budgetBoxes = createToolboxes({ boxes: [{ id: 'huge', tools: [schema('huge', 'x'.repeat(40000))] }], prefill: { budgetFor: () => null } });
  const budget = budgetBoxes.resolveTools({ toolboxes: ['huge'] }, 'fixture-9B');
  assert.equal(budget.tools.length, 0);
  assert.match(budget.dropped[0], /budget/);
  assert.equal(h.calls.length, 0);
});
