'use strict';
// The Executor guard (#704): per-action schemas at the ACP boundary, the structured violation the
// agent gets back, the three-strike block, and that nothing changes with the flag off.
// Synthetic repositories and a scripted agent only; no model, no network.
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { execFileSync } = require('node:child_process');
const { createCodeHarness } = require('./code-harness.cjs');
const { createCodeWorkspaces } = require('./code-workspace.cjs');
const { createJobs } = require('./jobs.cjs');
const { connectAcp } = require('./code-acp.cjs');
const { ACTIONS } = require('./code-actions.cjs');
const {
  MAX_VIOLATIONS, ACP_KINDS, checkToolCall, checkFsCall, createExecutorGuard, executorGuardFlag, useExecutorGuard,
} = require('./code-tool-schemas.cjs');

const AGENT = require.resolve('./fixtures/fake-acp-agent.cjs');
const temps = [];
const temp = (p) => { const d = fs.mkdtempSync(path.join(os.tmpdir(), p)); temps.push(d); return d; };
test.after(() => { for (const d of temps) fs.rmSync(d, { recursive: true, force: true }); });

function repo() {
  const dir = temp('noevia-grepo-');
  const git = (...a) => execFileSync('git', a, { cwd: dir, stdio: 'ignore' });
  git('init', '-q', '-b', 'main'); git('config', 'user.email', 'qa@example.invalid'); git('config', 'user.name', 'QA');
  fs.writeFileSync(path.join(dir, 'a.txt'), 'a\nb\nc'); git('add', '.'); git('commit', '-qm', 'first');
  return dir;
}

const OPTIONS = [{ optionId: 'y', kind: 'allow_once' }, { optionId: 'ya', kind: 'allow_always' },
  { optionId: 'n', kind: 'reject_once' }, { optionId: 'na', kind: 'reject_always' }];
const ON = { enabled: () => true }, OFF = { enabled: () => false };
const ROOT = '/work/tree';
const inRoot = (p) => { const r = path.resolve(ROOT, p); return r === ROOT || r.startsWith(ROOT + '/'); };

// ── The schemas, on their own ────────────────────────────────────────────────────────────────

test('well-formed calls from the harnesses noevia runs pass every schema', () => {
  const ok = [
    // OpenCode, measured in experiments/acp-spike: an edit names `filepath` + `diff` and a location.
    { toolCallId: 'c1', kind: 'edit', title: `${ROOT}/median.js`, locations: [{ path: `${ROOT}/median.js` }], rawInput: { filepath: `${ROOT}/median.js`, diff: '@@' } },
    { toolCallId: 'c2', kind: 'execute', title: 'node test.js', rawInput: { command: 'node test.js', cwd: ROOT } },
    // pi bridge: bash as `execute`, write as `edit` with `path`, grep as `search`.
    { toolCallId: 'pi-bash', kind: 'execute', title: 'ls', rawInput: { command: 'ls -la' } },
    { toolCallId: 'pi-write', kind: 'edit', title: 'write', rawInput: { path: 'src/x.js', content: 'x'.repeat(100000) }, locations: [{ path: 'src/x.js' }] },
    { toolCallId: 'pi-grep', kind: 'search', title: 'grep', rawInput: { pattern: 'TODO', path: '.' } },
    { toolCallId: 'r', kind: 'read', rawInput: { filePath: `${ROOT}/a.txt` }, locations: [{ path: `${ROOT}/a.txt`, line: 3 }] },
    { kind: 'think', title: 'Thinking' },
    { kind: 'fetch', rawInput: { url: 'https://registry.npmjs.org/x' } },
    { kind: 'execute', rawInput: { command: ['npm', 'test'] } },
    { kind: 'other', title: 'todowrite', rawInput: { todos: [{ content: 'x' }] } },
    { toolCallId: 'only-id' },
  ];
  for (const call of ok) assert.equal(checkToolCall(call, { contains: inRoot }), null, JSON.stringify(call).slice(0, 80));
});

test('each malformed call names the argument that is wrong, with a hint for its kind', () => {
  const bad = [
    [{ kind: 'execute', rawInput: {} }, '$.rawInput.command', /Missing command/],
    [{ kind: 'execute' }, '$.rawInput.command', /Missing command/],
    [{ kind: 'execute', rawInput: { command: 42 } }, '$.rawInput.command', /expected string \| array/],
    [{ kind: 'execute', rawInput: { command: 'ls', cwd: '/etc' } }, '$.rawInput.cwd', /outside the task workspace/],
    [{ kind: 'execute', rawInput: 'rm -rf /' }, '$.rawInput', /expected object/],
    [{ kind: 'edit', title: 'Edit', rawInput: { content: 'x' } }, '$.locations', /names no file/],
    [{ kind: 'edit', locations: [{ path: '/etc/passwd' }] }, '$.locations[0].path', /outside the task workspace/],
    [{ kind: 'edit', locations: [{ line: 1 }] }, '$.locations[0]', /Missing required property path/],
    [{ kind: 'edit', locations: 'a.txt' }, '$.locations', /expected array/],
    [{ kind: 'delete', rawInput: { path: '' } }, '$.rawInput.path', /Empty path/],
    [{ kind: 'move', rawInput: { path: 'a\0b' } }, '$.rawInput.path', /NUL/],
    [{ kind: 'read', locations: [{ path: '../../outside.txt' }] }, '$.locations[0].path', /outside/],
    [{ kind: 'fetch', rawInput: { url: 'file:///etc/passwd' } }, '$.rawInput.url', /http\(s\) URL/],
    [{ kind: 'fetch', rawInput: {} }, '$.rawInput.url', /Missing URL/],
    [{ kind: 'launch_missiles', rawInput: { command: 'ls' } }, '$.kind', /Unknown tool kind/],
    [{ kind: 'think', toolCallId: 7 }, '$.toolCallId', /expected string/],
    [{ kind: 'other', locations: [{ path: '/home/agent/.ssh/id_rsa' }] }, '$.locations[0].path', /outside/],
  ];
  for (const [call, at, message] of bad) {
    const found = checkToolCall(call, { contains: inRoot });
    assert.ok(found, JSON.stringify(call));
    assert.equal(found.path, at, JSON.stringify(call));
    assert.match(found.message, message, JSON.stringify(call));
    assert.ok(found.hint, 'a hint the agent can act on');
  }
  assert.ok(ACP_KINDS.includes('switch_mode') && ACP_KINDS.length === 10);
});

test('an unknown containment answer (workspace not held) adds no refusal of its own', () => {
  assert.equal(checkToolCall({ kind: 'edit', locations: [{ path: '/anywhere' }] }, { contains: () => null }), null);
});

test('fs/read_text_file and fs/write_text_file params have their own schemas', () => {
  const opts = { contains: inRoot, maxBytes: 16 };
  assert.equal(checkFsCall('fs/read_text_file', { sessionId: 's', path: `${ROOT}/a.txt`, line: 2, limit: 1 }, opts), null);
  assert.equal(checkFsCall('fs/write_text_file', { sessionId: 's', path: 'b.txt', content: 'hello' }, opts), null);
  const cases = [
    ['fs/read_text_file', {}, '$', /Missing required property path/],
    ['fs/read_text_file', null, '$', /expected object/],
    ['fs/read_text_file', { path: 5 }, '$.path', /expected string/],
    ['fs/read_text_file', { path: '/etc/shadow' }, '$.path', /outside/],
    ['fs/read_text_file', { path: 'a.txt', line: 0 }, '$.line', /1 or more/],
    ['fs/read_text_file', { path: 'a.txt', limit: 2.5 }, '$.limit', /integer/],
    ['fs/write_text_file', { path: 'b.txt' }, '$', /Missing required property content/],
    ['fs/write_text_file', { path: 'b.txt', content: { text: 'x' } }, '$.content', /expected string/],
    ['fs/write_text_file', { path: 'b.txt', content: 'x'.repeat(17) }, '$.content', /larger than 16 bytes/],
    ['fs/write_text_file', { path: '../escape.txt', content: 'x' }, '$.path', /outside/],
  ];
  for (const [method, params, at, message] of cases) {
    const found = checkFsCall(method, params, opts);
    assert.ok(found, `${method} ${JSON.stringify(params)}`);
    assert.equal(found.path, at, `${method} ${JSON.stringify(params)}`);
    assert.match(found.message, message);
  }
});

test('the guard counts violations, reports each as a structured Invalid-params error, and blocks at the limit', () => {
  const events = [], logs = [];
  let halted = 0;
  const guard = createExecutorGuard({ contains: inRoot, event: (type, data) => events.push({ type, data }), log: (e) => logs.push(e), onBlocked: () => halted++ });
  assert.equal(guard.permission({ kind: 'execute', rawInput: { command: 'ls' } }), null, 'a good call passes and is not counted');
  const first = guard.permission({ kind: 'execute', rawInput: {} }, ACTIONS.EXECUTE);
  assert.equal(first.code, -32602);
  const v1 = first.data.noeviaViolation;
  assert.deepEqual(v1.violation, { message: 'Missing command at $.rawInput.command', path: '$.rawInput.command' });
  assert.equal(v1.type, 'schema_violation_correction', 'the Laya correction shape');
  assert.equal(v1.tool, 'session/request_permission');
  assert.deepEqual([v1.count, v1.limit, v1.blocked], [1, MAX_VIOLATIONS, false]);
  assert.match(first.message, /violation 1 of 3/);
  assert.match(first.message, /Correct the arguments/);
  assert.deepEqual(JSON.parse(first.message.split('\n')[1]).noeviaViolation, v1, 'the message carries the same structure');
  const decided = events.find((e) => e.type === 'approval.decided');
  assert.equal(decided.data.decision, 'denied');
  assert.equal(decided.data.automatic, true);
  assert.equal(decided.data.action, ACTIONS.EXECUTE);

  assert.equal(guard.readTextFile({ path: '/etc/hosts' }).data.noeviaViolation.count, 2);
  const third = guard.writeTextFile({ path: 'x' });
  assert.equal(third.data.noeviaViolation.blocked, true);
  assert.match(third.message, /stopped the task/);
  assert.equal(guard.blocked, true);
  assert.equal(halted, 1);
  const step = events.filter((e) => e.type.startsWith('step.'));
  assert.deepEqual(step.map((e) => e.type), ['step.started', 'step.completed']);
  assert.equal(step[1].data.blocked, true);

  // Once blocked, even a good call is refused, and nothing more is counted or halted.
  const after = guard.permission({ kind: 'execute', rawInput: { command: 'ls' } });
  assert.equal(after.data.noeviaViolation.blocked, true);
  assert.equal(guard.violations, 3);
  assert.equal(halted, 1);
  const blocked = guard.blockedError();
  assert.equal(blocked.result.blocked, true);
  assert.equal(blocked.result.reason, 'executor_guard');
  assert.equal(blocked.result.violations.length, 3);
  assert.ok(logs.every((e) => !('content' in e)), 'the log never carries file content');
});

test('the deployment flag is off until installed, and off whenever its check misbehaves', () => {
  assert.equal(executorGuardFlag.enabled(), false);
  try {
    useExecutorGuard(() => true); assert.equal(executorGuardFlag.enabled(), true);
    useExecutorGuard(() => 'yes'); assert.equal(executorGuardFlag.enabled(), false);
    useExecutorGuard(() => { throw Error('no store'); }); assert.equal(executorGuardFlag.enabled(), false);
    assert.throws(() => useExecutorGuard(true), TypeError);
  } finally { useExecutorGuard(() => false); }
});

// ── In the harness, with a scripted agent ─────────────────────────────────────────────────────

async function waitDone(jobs, taskId) {
  for (let i = 0; i < 400 && !['completed', 'failed', 'cancelled'].includes(jobs.get(taskId)?.status); i++) {
    await new Promise((r) => setTimeout(r, 5));
  }
  return jobs.get(taskId);
}

/** One task; `script(handlers, cwd, signal)` plays the agent; `answers` are the person's. */
async function run({ guard, script, answers = [], capabilities = [] }) {
  const dir = temp('noevia-gjobs-');
  const jobs = createJobs({ dir });
  const workspaces = createCodeWorkspaces({ dir, epoch: 'test' });
  const asked = [], logs = [];
  let signal = null;
  const harness = createCodeHarness({
    jobs, workspaces, guard, log: (e) => logs.push(e),
    engine: () => ({ baseUrl: 'http://engine.test/v1', model: 'synthetic-coder', apiKey: null, contextTokens: 8192 }),
    askApproval: async (request) => { asked.push(request); return answers.shift() ?? 'deny'; },
  });
  const started = await harness.start({
    repoPath: repo(), prompt: 'fix the bug', capabilities,
    connect: async (args) => {
      signal = args.signal;
      return { agent: {}, prompt: async () => {
        await script(args.handlers, args.cwd, args.signal);
        if (args.signal.aborted) throw Object.assign(Error('Cancelled'), { publicMessage: 'The task was cancelled.' });
        return { stopReason: 'end_turn' };
      } };
    },
  });
  const job = await waitDone(jobs, started.taskId);
  return { ...started, jobs, job, asked, logs, signal };
}
const attempt = async (fn) => { try { return { value: await fn() }; } catch (error) { return { error }; } };

test('bad then corrected arguments: the bad call is refused with its violation, the corrected one reaches the approval card', async () => {
  const outcomes = [];
  const r = await run({
    guard: ON, answers: ['approve'],
    script: async (h) => {
      outcomes.push(await attempt(() => h.requestPermission({ toolCall: { toolCallId: 'c1', kind: 'execute', title: 'bash', rawInput: { description: 'run the tests' } }, options: OPTIONS })));
      outcomes.push(await attempt(() => h.requestPermission({ toolCall: { toolCallId: 'c2', kind: 'execute', title: 'npm test', rawInput: { command: 'npm test' } }, options: OPTIONS })));
    },
  });
  assert.equal(outcomes[0].error.code, -32602);
  assert.equal(outcomes[0].error.data.noeviaViolation.violation.path, '$.rawInput.command');
  assert.deepEqual(outcomes[1].value, { outcome: 'selected', optionId: 'y' });
  assert.equal(r.asked.length, 1, 'only the corrected call was put in front of the person');
  assert.equal(r.asked[0].command, 'npm test');
  assert.equal(r.job.status, 'completed');
  assert.equal(r.job.result.violations, 1);
  assert.equal(r.job.result.denied, 1);
  assert.ok(r.logs.some((e) => e.event === 'code.guard_violation' && e.count === 1));
});

test('the guard never approves: a well-formed write still asks, and Decline and a timeout still refuse', async () => {
  const picks = [];
  const r = await run({
    guard: ON, answers: ['deny', 'timeout', 'approve_all'],
    script: async (h, cwd) => {
      const edit = () => ({ toolCall: { kind: 'edit', title: 'Edit a.txt', locations: [{ path: path.join(cwd, 'a.txt') }], rawInput: { path: path.join(cwd, 'a.txt') } }, options: OPTIONS });
      picks.push(await h.requestPermission(edit()));
      picks.push(await h.requestPermission(edit()));
      picks.push(await h.requestPermission(edit()));
      picks.push(await h.requestPermission(edit())); // "Allow for this task" stands, as before
    },
  });
  assert.equal(r.asked.length, 3);
  assert.deepEqual(picks.map((p) => p.optionId), ['n', 'n', 'y', 'y']);
  assert.equal(r.job.result.violations, 0);
});

test('fs reads and writes outside the schema are refused by the guard, and good ones still run', async () => {
  const out = [];
  const r = await run({
    guard: ON,
    script: async (h, cwd) => {
      out.push(await attempt(() => h.readTextFile({ sessionId: 's', path: path.join(cwd, 'a.txt'), line: 2, limit: 1 })));
      out.push(await attempt(() => h.writeTextFile({ sessionId: 's', path: path.join(cwd, 'b.txt') })));
      out.push(await attempt(() => h.writeTextFile({ sessionId: 's', path: path.join(cwd, 'b.txt'), content: 'fixed' })));
    },
  });
  assert.deepEqual(out[0].value, { content: 'b' });
  assert.equal(out[1].error.data.noeviaViolation.tool, 'fs/write_text_file');
  assert.equal(out[1].error.data.noeviaViolation.violation.message, 'Missing required property content at $');
  assert.equal(out[2].value, null);
  assert.equal(r.job.status, 'completed');
  assert.equal(r.job.result.violations, 1);
});

test('three violations stop the task as blocked: the agent is halted and no card is ever shown', async () => {
  const out = [];
  const r = await run({
    guard: ON, answers: ['approve', 'approve'],
    script: async (h, cwd, signal) => {
      out.push(await attempt(() => h.requestPermission({ toolCall: { kind: 'execute', rawInput: {} }, options: OPTIONS })));
      out.push(await attempt(() => h.readTextFile({ path: '/etc/passwd' })));
      out.push(await attempt(() => h.requestPermission({ toolCall: { kind: 'edit', rawInput: {} }, options: OPTIONS })));
      // The agent tries again with a perfectly good call: too late.
      out.push(await attempt(() => h.requestPermission({ toolCall: { kind: 'edit', locations: [{ path: path.join(cwd, 'a.txt') }] }, options: OPTIONS })));
      await new Promise((resolve) => { if (signal.aborted) resolve(); else signal.addEventListener('abort', resolve, { once: true }); });
    },
  });
  assert.deepEqual(out.map((o) => o.error?.data?.noeviaViolation?.count), [1, 2, 3, 3]);
  assert.deepEqual(out.map((o) => o.error?.data?.noeviaViolation?.blocked), [false, false, true, true]);
  assert.equal(r.asked.length, 0, 'nothing reached the person, and nothing was allowed');
  assert.equal(r.signal.aborted, true, 'the agent was stopped');
  assert.equal(r.job.status, 'failed');
  assert.equal(r.job.lifecycle, 'blocked');
  assert.match(r.job.error, /^Blocked: the coding agent sent 3 malformed tool calls/);
  assert.equal(r.job.result.blocked, true);
  assert.equal(r.job.result.reason, 'executor_guard');
  assert.deepEqual(r.job.result.violations.map((v) => v.tool), ['session/request_permission', 'fs/read_text_file', 'session/request_permission']);
  const step = r.job.steps.find((s) => s.id === 'executor.guard');
  assert.equal(step.status, 'failed');
});

test('a blocked task stays blocked even when the agent ignores the stop and finishes its turn', async () => {
  const r = await run({
    guard: ON,
    script: async (h) => {
      for (let i = 0; i < 3; i++) await attempt(() => h.requestPermission({ toolCall: { kind: 'fetch', rawInput: {} }, options: OPTIONS }));
    },
  });
  // The halt lands on the next turn of the event loop, after this agent has already answered
  // end_turn: the harness still ends the task as blocked rather than completed.
  assert.equal(r.job.status, 'failed');
  assert.equal(r.job.result.blocked, true);
});

test('flag off: the same malformed calls take exactly the path they took before', async () => {
  const out = [];
  const r = await run({
    guard: OFF, answers: ['deny', 'deny', 'deny'],
    script: async (h, cwd) => {
      for (let i = 0; i < 3; i++) out.push(await attempt(() => h.requestPermission({ toolCall: { kind: 'execute', rawInput: {} }, options: OPTIONS })));
      out.push(await attempt(() => h.readTextFile({ path: '/etc/passwd' })));
      out.push(await attempt(() => h.writeTextFile({ path: path.join(cwd, 'c.txt') })));
    },
  });
  assert.equal(r.asked.length, 3, 'the unreadable command still goes to the person');
  assert.equal(r.asked[0].reason, 'The harness did not say what it would run.');
  assert.deepEqual(out.slice(0, 3).map((o) => o.value?.optionId), ['n', 'n', 'n']);
  assert.equal(out[3].error.message, 'Outside this task’s workspace');
  assert.equal(out[3].error.data, undefined);
  assert.equal(out[4].value, null, 'a write with no content still writes an empty file, as before');
  assert.equal(r.job.status, 'completed');
  assert.equal('violations' in r.job.result, false, 'no new field in the result');
  assert.equal(r.job.steps.some((s) => s.id === 'executor.guard'), false);
});

test('the deployment default is off: a harness built without a guard runs unguarded', async () => {
  const r = await run({
    guard: undefined, answers: ['deny'],
    script: async (h) => { await h.requestPermission({ toolCall: { kind: 'execute', rawInput: {} }, options: OPTIONS }); },
  });
  assert.equal(r.asked.length, 1);
  assert.equal('violations' in r.job.result, false);
});

// ── Over a real ACP connection (the scripted fake agent subprocess) ────────────────────────────

async function runAcp({ guard, steps, answers = [] }) {
  const dir = temp('noevia-gacp-');
  const jobs = createJobs({ dir });
  const workspaces = createCodeWorkspaces({ dir, epoch: 'test' });
  const asked = [];
  let prompt = null;
  const harness = createCodeHarness({
    jobs, workspaces, guard,
    engine: () => ({ baseUrl: 'http://engine.test/v1', model: 'synthetic-coder', apiKey: null }),
    askApproval: async (request) => { asked.push(request); return answers.shift() ?? 'deny'; },
  });
  const started = await harness.start({
    repoPath: repo(), prompt: 'fix the bug',
    connect: async (args) => {
      const agent = await connectAcp({ command: process.execPath, args: [AGENT], cwd: args.cwd, handlers: args.handlers,
        signal: args.signal, graceMs: 50, env: { SCRIPT: JSON.stringify(steps(args.cwd)) } });
      return { ...agent, agent: agent.agent, prompt: async (text) => { prompt = await agent.prompt(text); return prompt; } };
    },
  });
  const job = await waitDone(jobs, started.taskId);
  return { job, asked, seen: prompt?.seen || null };
}

test('over ACP: the violation reaches the agent as a JSON-RPC Invalid-params error with data, and the corrected call is approved', async () => {
  const r = await runAcp({
    guard: ON, answers: ['approve'],
    steps: (cwd) => [
      { permission: { sessionId: 'session-1', toolCall: { toolCallId: 'e1', kind: 'edit', title: 'write', rawInput: { content: 'x' } }, options: OPTIONS } },
      { permission: { sessionId: 'session-1', toolCall: { toolCallId: 'e2', kind: 'edit', title: 'write', locations: [{ path: path.join(cwd, 'a.txt') }], rawInput: { filePath: path.join(cwd, 'a.txt'), content: 'x' } }, options: OPTIONS } },
      { write: { sessionId: 'session-1', path: path.join(cwd, 'a.txt'), content: 'x' } },
    ],
  });
  assert.equal(r.job.status, 'completed');
  const [bad, good, wrote] = r.seen;
  assert.equal(bad.error.code, -32602);
  assert.equal(bad.error.data.noeviaViolation.violation.path, '$.locations');
  assert.match(bad.error.message, /names no file/);
  assert.equal(good.noeviaSaid, 'selected');
  assert.deepEqual(good.result.outcome, { outcome: 'selected', optionId: 'y' });
  assert.equal(wrote.result, null);
  assert.equal(r.asked.length, 1);
});

test('over ACP: after the third violation the agent subprocess is stopped and the task is blocked', async () => {
  const r = await runAcp({
    guard: ON,
    steps: () => [
      { permission: { sessionId: 'session-1', toolCall: { kind: 'execute', rawInput: {} }, options: OPTIONS } },
      { read: { sessionId: 'session-1', path: '/etc/passwd' } },
      { write: { sessionId: 'session-1', path: 'notes.txt', content: 7 } },
      { hang: true },
    ],
  });
  assert.equal(r.job.status, 'failed');
  assert.equal(r.job.lifecycle, 'blocked');
  assert.equal(r.job.result.blocked, true);
  assert.equal(r.asked.length, 0);
});
