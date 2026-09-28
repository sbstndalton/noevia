'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  STATES, INITIAL_STATE, TRANSITIONS, TaskLifecycleError,
  canTransition, transition, foldEvents, deriveLifecycle, safeDeriveLifecycle,
} = require('./task-lifecycle.cjs');

// --- Helpers to build synthetic journals in the same shape jobs.cjs appends. Never real
// Diary prompts/corpus — these are invented event streams for this module only.
let seq = 0;
const ev = (type, data = {}) => ({ job: 'synthetic', seq: ++seq, type, at: seq, data });

// --- Exhaustive transition table coverage: every declared legal pair must succeed, every
// other ordered pair (including self-loops not explicitly listed, and unknown states) must
// be rejected with an explicit TaskLifecycleError.

test('every declared transition is legal in both canTransition and transition', () => {
  for (const from of STATES) {
    for (const to of TRANSITIONS[from]) {
      assert.equal(canTransition(from, to), true, `${from} -> ${to} should be legal`);
      assert.equal(transition(from, to), to);
    }
  }
});

test('staying in the same state is always legal, even from the terminal state', () => {
  for (const state of STATES) {
    assert.equal(canTransition(state, state), true);
    assert.equal(transition(state, state), state);
  }
});

test('every non-declared, non-identity pair is illegal and throws TaskLifecycleError', () => {
  let checked = 0;
  for (const from of STATES) {
    for (const to of STATES) {
      if (to === from) continue;
      if (TRANSITIONS[from].includes(to)) continue;
      checked++;
      assert.throws(() => transition(from, to), TaskLifecycleError, `${from} -> ${to} should be illegal`);
      assert.equal(canTransition(from, to), false, `${from} -> ${to} should be illegal`);
    }
  }
  // Sanity: this test actually exercised illegal pairs (guards against a vacuous pass if
  // someone widens the table to allow everything).
  assert.ok(checked > 10, `expected several illegal pairs, saw ${checked}`);
});

test('merged is terminal: no outgoing transitions to any other state', () => {
  for (const to of STATES) {
    if (to === 'merged') continue;
    assert.throws(() => transition('merged', to), TaskLifecycleError);
  }
});

test('illegal transitions name the offending states on the thrown error', () => {
  try {
    transition('planned', 'merged');
    assert.fail('expected a throw');
  } catch (e) {
    assert.ok(e instanceof TaskLifecycleError);
    assert.equal(e.from, 'planned');
    assert.equal(e.to, 'merged');
    assert.match(e.message, /planned -> merged/);
    assert.equal(e.status, 409);
  }
});

test('unknown states are rejected explicitly, not silently coerced', () => {
  assert.throws(() => transition('planned', 'shipped'), TaskLifecycleError);
  assert.throws(() => transition('done', 'planned'), TaskLifecycleError);
  assert.throws(() => canTransition('planned', 'shipped') && (() => { throw new Error('unreachable'); })(), TaskLifecycleError);
});

test('the full legal map matches the documented design (spot check)', () => {
  assert.deepEqual([...TRANSITIONS.planned], ['implementing', 'blocked']);
  assert.deepEqual([...TRANSITIONS.merged], []);
  assert.ok(TRANSITIONS.reviewing.includes('changes_requested'));
  assert.ok(TRANSITIONS.reviewing.includes('implementing'), 'an approved review resumes implementing');
  assert.ok(TRANSITIONS.changes_requested.includes('merged'), 'a task can still complete after a declined tool call with no further activity');
  assert.ok(TRANSITIONS.blocked.includes('implementing') && TRANSITIONS.blocked.includes('planned'));
});

// --- Derivation from synthetic journals mirroring jobs.cjs's real event vocabulary.

test('a bare job.created with nothing else derives the initial planned state', () => {
  seq = 0;
  const events = [ev('job.created', { kind: 'chat' })];
  assert.equal(deriveLifecycle(events), 'planned');
});

test('job.started moves planned -> implementing', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started')];
  assert.equal(deriveLifecycle(events), 'implementing');
});

test('an ordinary job with no approvals and no special stages completes straight to merged', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'chat' }),
    ev('job.started'),
    ev('step.started', { id: '1', title: 'work' }),
    ev('progress', { stage: 'Reading' }), // free-text stage, not a canonical lifecycle token
    ev('step.completed', { id: '1' }),
    ev('job.completed', { result: { ok: true } }),
  ];
  assert.equal(deriveLifecycle(events), 'merged');
});

test('a canonical "verifying" progress stage is recognized and ordered correctly', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('progress', { stage: 'verifying' }), ev('job.completed')];
  assert.equal(deriveLifecycle(events), 'merged');
});

test('a job that fails ends up blocked, regardless of how far it had progressed', () => {
  for (const extra of [[], [ev('progress', { stage: 'verifying' })], [ev('approval.requested', {})]]) {
    seq = 0;
    const events = [ev('job.created'), ev('job.started'), ...extra, ev('job.failed', { error: 'boom' })];
    assert.equal(deriveLifecycle(events), 'blocked');
  }
});

test('a job cancelled or interrupted also lands on blocked', () => {
  seq = 0;
  assert.equal(deriveLifecycle([ev('job.created'), ev('job.started'), ev('job.cancelled')]), 'blocked');
  seq = 0;
  assert.equal(deriveLifecycle([ev('job.created'), ev('job.started'), ev('job.interrupted', { reason: 'restart' })]), 'blocked');
});

test('an approval.requested during work moves to reviewing', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('approval.requested', { action: 'write' })];
  assert.equal(deriveLifecycle(events), 'reviewing');
});

test('an approved decision resumes implementing', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('approval.requested', { action: 'write' }),
    ev('approval.decided', { decision: 'approve' }),
  ];
  assert.equal(deriveLifecycle(events), 'implementing');
});

test('approve_all and allow_once are recognized approvals too', () => {
  for (const decision of ['approve_all', 'allow_once', 'allow', 'allowed']) {
    seq = 0;
    const events = [ev('job.created'), ev('job.started'), ev('approval.requested', {}), ev('approval.decided', { decision })];
    assert.equal(deriveLifecycle(events), 'implementing', `decision=${decision}`);
  }
});

test('a declined decision requests changes', () => {
  for (const decision of ['deny', 'denied', 'reject', 'reject_once', 'aborted', 'declined', undefined]) {
    seq = 0;
    const events = [ev('job.created'), ev('job.started'), ev('approval.requested', {}), ev('approval.decided', { decision })];
    assert.equal(deriveLifecycle(events), 'changes_requested', `decision=${JSON.stringify(decision)}`);
  }
});

test('a full plan -> implement -> verify -> review -> changes -> re-implement -> merged cycle', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }),
    ev('job.started'),
    ev('progress', { stage: 'verifying' }),
    ev('approval.requested', { action: 'write' }),
    ev('approval.decided', { decision: 'deny' }),           // -> changes_requested
    ev('approval.requested', { action: 'write' }),          // reviewer looks again (changes_requested -> reviewing is legal)
    ev('approval.decided', { decision: 'approve' }),        // -> implementing
    ev('progress', { stage: 'verifying' }),
    ev('job.completed', { result: {} }),
  ];
  assert.equal(deriveLifecycle(events), 'merged');
});

test('a job that completes while changes were requested and nothing else happened still merges', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('approval.requested', {}), ev('approval.decided', { decision: 'denied' }),
    ev('job.completed', {}),
  ];
  assert.equal(deriveLifecycle(events), 'merged');
});

test('unrecognized event types and non-canonical stages are no-ops', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('tool.started', { id: 't1' }), ev('tool.completed', { id: 't1' }),
    ev('tool.uncertain', {}), ev('artifact.created', { name: 'a' }),
    ev('checkpoint.created', { step: 1 }),
    ev('plan.proposed', { question: 'q' }),
    ev('progress', { stage: 'Downloading' }), // not canonical
    ev('assistant.output', { text: 'hi' }),
  ];
  assert.equal(deriveLifecycle(events), 'implementing');
});

test('an empty event list derives the initial state', () => {
  assert.equal(deriveLifecycle([]), 'planned');
  assert.equal(foldEvents([]), 'planned');
});

// --- Restart / replay determinism.

test('folding all events at once equals folding in arbitrary chunks', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('progress', { stage: 'verifying' }),
    ev('approval.requested', {}), ev('approval.decided', { decision: 'deny' }),
    ev('approval.requested', {}), ev('approval.decided', { decision: 'approve' }),
    ev('job.completed', {}),
  ];
  const whole = deriveLifecycle(events);
  for (const cut of [1, 2, 3, 4, 5, 6, 7]) {
    const first = foldEvents(events.slice(0, cut));
    const resumed = foldEvents(events.slice(cut), first);
    assert.equal(resumed, whole, `chunking at ${cut} diverged`);
  }
});

test('replaying the same journal twice from scratch is deterministic', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('approval.requested', {}), ev('approval.decided', { decision: 'approve' })];
  const first = deriveLifecycle(events);
  const second = deriveLifecycle(events.map((e) => ({ ...e }))); // fresh objects, same content
  assert.equal(first, second);
  assert.equal(first, 'implementing');
});

test('deriving from a fresh copy of the events array does not mutate the input', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started')];
  const snapshot = JSON.stringify(events);
  deriveLifecycle(events);
  assert.equal(JSON.stringify(events), snapshot);
});

// --- safeDeriveLifecycle: never throws, even on a journal shaped to force an illegal jump.

test('safeDeriveLifecycle returns null instead of throwing on an illegal derived jump', () => {
  seq = 0;
  // planned -> merged directly (job.completed with no job.started) is illegal per the table.
  const events = [ev('job.created'), ev('job.completed', {})];
  assert.throws(() => deriveLifecycle(events), TaskLifecycleError);
  assert.equal(safeDeriveLifecycle(events), null);
});

test('safeDeriveLifecycle still returns the real state for a well-formed journal', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('job.completed', {})];
  assert.equal(safeDeriveLifecycle(events), 'merged');
});

test('foldEvents rejects an unknown starting state explicitly', () => {
  assert.throws(() => foldEvents([], 'not-a-state'), TaskLifecycleError);
});

test('STATES and INITIAL_STATE match the states named in the issue', () => {
  assert.deepEqual([...STATES].sort(), [
    'blocked', 'changes_requested', 'implementing', 'merged', 'planned', 'reviewing', 'verifying',
  ].sort());
  assert.equal(INITIAL_STATE, 'planned');
});
