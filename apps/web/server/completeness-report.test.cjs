'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { derive } = require('./jobs.cjs');
const { canTransitionToReviewing } = require('./task-lifecycle.cjs');
const { CHECK_NAMES, buildCompletenessReport, canEnterReviewing } = require('./completeness-report.cjs');

// --- Helpers to build synthetic journals in the exact shape jobs.cjs appends, then fold them
// through jobs.cjs's own `derive()` the same way a real caller (jobs.get(id)) would. Never real
// Diary prompts/corpus — every event stream below is invented for this module only.
let seq = 0;
const ev = (type, data = {}) => ({ job: 'synthetic', seq: ++seq, type, at: seq, data });
function buildJob(events) { return derive(events); }

function names(report) { return report.checks.map((c) => c.name).sort(); }
function statusOf(report, name) { return report.checks.find((c) => c.name === name).status; }

test('CHECK_NAMES matches the checks a report actually produces', () => {
  seq = 0;
  const events = [ev('job.created', { kind: 'chat' })];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.deepEqual(names(report), [...CHECK_NAMES].sort());
});

// --- tests-run -------------------------------------------------------------------------------

test('tests-run is unknown when no test-shaped tool/step event exists', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('tool.completed', { id: 't1', name: 'write_file' }), ev('job.completed')];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'tests-run'), 'unknown');
});

test('tests-run passes when a matching tool.completed event succeeded (exitCode 0, not failed)', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('tool.completed', { id: 't1', name: 'run tests', failed: false, exitCode: 0 }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'tests-run'), 'pass');
});

test('tests-run fails when a matching tool.completed event has a non-zero exit code', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('tool.completed', { id: 't1', name: 'pytest', failed: false, exitCode: 1 }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'tests-run'), 'fail');
});

test('tests-run fails when a matching tool.completed event is explicitly marked failed', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('tool.completed', { id: 't1', name: 'jest', failed: true }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'tests-run'), 'fail');
});

test('tests-run recognizes a matching step.completed by its paired step.started title', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('step.started', { id: 's1', title: 'Run the test suite' }),
    ev('step.completed', { id: 's1' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'tests-run'), 'pass');
});

test('tests-run treats a failed step.completed as a failing test step', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('step.started', { id: 's1', title: 'Run tests' }),
    ev('step.completed', { id: 's1', failed: true }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'tests-run'), 'fail');
});

test('tests-run ignores a spoofed name on an unrelated event type', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('artifact.created', { name: 'all tests passed' }), // not a tool/step event
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'tests-run'), 'unknown');
});

// --- artifacts-present -------------------------------------------------------------------------

test('artifacts-present is unknown when no expectation was declared', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('artifact.created', { name: 'report.md' }), ev('job.completed')];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'artifacts-present'), 'unknown');
});

test('artifacts-present passes when every expected artifact is present', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('artifact.created', { name: 'report.md' }),
    ev('artifact.created', { name: 'diff.patch' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events, expectedArtifacts: ['report.md', 'diff.patch'] });
  assert.equal(statusOf(report, 'artifacts-present'), 'pass');
});

test('artifacts-present fails and names the missing artifact(s)', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('artifact.created', { name: 'report.md' }), ev('job.completed')];
  const report = buildCompletenessReport({ job: buildJob(events), events, expectedArtifacts: ['report.md', 'diff.patch'] });
  const c = report.checks.find((x) => x.name === 'artifacts-present');
  assert.equal(c.status, 'fail');
  assert.deepEqual(c.evidence.missing, ['diff.patch']);
});

test('artifacts-present passes vacuously when an empty expectation list is explicitly declared', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('job.completed')];
  const report = buildCompletenessReport({ job: buildJob(events), events, expectedArtifacts: [] });
  assert.equal(statusOf(report, 'artifacts-present'), 'pass');
});

// --- plan-steps-closed -------------------------------------------------------------------------

test('plan-steps-closed is unknown when no plan and no steps were recorded', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('job.completed')];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'plan-steps-closed'), 'unknown');
});

test('plan-steps-closed is unknown when the plan was explicitly skipped', () => {
  seq = 0;
  const events = [ev('job.created', { kind: 'code' }), ev('job.started'), ev('plan.skipped', { question: 'q' }), ev('job.completed')];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'plan-steps-closed'), 'unknown');
});

test('plan-steps-closed passes when every started step also completed', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('plan.proposed', { subQuestions: ['do the thing'] }),
    ev('step.started', { id: 's1', title: 'harness.config' }),
    ev('step.completed', { id: 's1' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'plan-steps-closed'), 'pass');
});

test('plan-steps-closed fails when a step started but never completed', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('plan.proposed', { subQuestions: ['do the thing'] }),
    ev('step.started', { id: 's1', title: 'harness.config' }),
    // no matching step.completed
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  const c = report.checks.find((x) => x.name === 'plan-steps-closed');
  assert.equal(c.status, 'fail');
  assert.deepEqual(c.evidence.open.map((s) => s.id), ['s1']);
});

test('plan-steps-closed is unknown when a plan was proposed but no step events exist at all', () => {
  seq = 0;
  const events = [ev('job.created', { kind: 'code' }), ev('job.started'), ev('plan.proposed', { subQuestions: ['x'] })];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'plan-steps-closed'), 'unknown');
});

// --- no-unresolved-uncertainty -------------------------------------------------------------------------

test('no-unresolved-uncertainty passes on a clean journal', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('job.completed')];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'no-unresolved-uncertainty'), 'pass');
});

test('no-unresolved-uncertainty fails when a tool.uncertain event was ever recorded', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('tool.uncertain', { reason: 'ambiguous result' }), ev('job.completed')];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'no-unresolved-uncertainty'), 'fail');
});

test('no-unresolved-uncertainty fails while an approval is still pending', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('approval.requested', { action: 'shell.exec' })];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'no-unresolved-uncertainty'), 'fail');
});

test('no-unresolved-uncertainty passes once the pending approval is decided', () => {
  seq = 0;
  const events = [
    ev('job.created'), ev('job.started'),
    ev('approval.requested', { action: 'shell.exec' }),
    ev('approval.decided', { decision: 'approve' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'no-unresolved-uncertainty'), 'pass');
});

// --- checkpoint-head-recorded -------------------------------------------------------------------------

test('checkpoint-head-recorded is unknown when no checkpoint exists', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('job.completed')];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'checkpoint-head-recorded'), 'unknown');
});

test('checkpoint-head-recorded is unknown (not failing) when a checkpoint exists without a SHA (pre-#513 shape)', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('checkpoint.created', { branch: 'task/abc', task: 'do the thing' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'checkpoint-head-recorded'), 'unknown');
});

test('checkpoint-head-recorded passes once a well-formed head SHA is recorded', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('checkpoint.created', { branch: 'task/abc', sha: 'a1b2c3d4e5f6' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'checkpoint-head-recorded'), 'pass');
});

test('checkpoint-head-recorded fails when a SHA field is present but malformed', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('checkpoint.created', { branch: 'task/abc', headSha: 'not-a-sha!' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'checkpoint-head-recorded'), 'fail');
});

test('checkpoint-head-recorded reflects the latest checkpoint.created event', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('checkpoint.created', { branch: 'task/abc' }),
    ev('checkpoint.created', { branch: 'task/abc', sha: 'deadbeef' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'checkpoint-head-recorded'), 'pass');
});

// --- canEnterReviewing guard -------------------------------------------------------------------------

test('canEnterReviewing is false when any check is unknown', () => {
  seq = 0;
  const events = [ev('job.created'), ev('job.started'), ev('job.completed')];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(report.overall, 'unknown');
  assert.equal(canEnterReviewing(report), false);
});

test('canEnterReviewing is false when any check fails, even if others pass', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('tool.completed', { id: 't1', name: 'run tests', exitCode: 0 }),
    ev('checkpoint.created', { sha: 'deadbeef' }),
    ev('tool.uncertain', { reason: 'ambiguous' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events, expectedArtifacts: [] });
  assert.equal(report.overall, 'fail');
  assert.equal(canEnterReviewing(report), false);
});

test('canEnterReviewing is true only when every check explicitly passes', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('tool.completed', { id: 't1', name: 'run tests', exitCode: 0 }),
    ev('artifact.created', { name: 'report.md' }),
    ev('step.started', { id: 's1', title: 'harness.config' }),
    ev('step.completed', { id: 's1' }),
    ev('checkpoint.created', { sha: 'deadbeef' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events, expectedArtifacts: ['report.md'] });
  assert.equal(report.overall, 'pass');
  assert.equal(canEnterReviewing(report), true);
});

test('canEnterReviewing is false on an empty/malformed report', () => {
  assert.equal(canEnterReviewing(null), false);
  assert.equal(canEnterReviewing({}), false);
  assert.equal(canEnterReviewing({ checks: [] }), false);
});

test('buildCompletenessReport requires a job object', () => {
  assert.throws(() => buildCompletenessReport({ events: [] }), /requires a derived job/);
});

// --- Spoof resistance: nothing here ever trusts a caller-chosen flag riding on a
// model/page-reachable event's `data`. This is the exact scenario #514 calls out: an approval
// card claiming `testsPassed: true` (or `review`/`merged`) must never count as evidence.

test('a spoofed testsPassed flag on an approval card never satisfies tests-run', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('approval.requested', { action: 'shell.exec', testsPassed: true, review: true }),
    ev('approval.decided', { decision: 'approve', testsPassed: true, merged: true }),
    ev('job.completed', { result: { testsPassed: true, reviewed: true } }),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'tests-run'), 'unknown');
  assert.equal(canEnterReviewing(report), false);
});

test('a spoofed testsPassed flag on a tool.completed event cannot override its own failed exit code', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('tool.completed', { id: 't1', name: 'run tests', testsPassed: true, failed: true, exitCode: 1 }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(statusOf(report, 'tests-run'), 'fail');
});

test('a spoofed artifact name matching an expectation string does not fabricate the artifact itself', () => {
  seq = 0;
  // The approval card *claims* the artifact exists; no artifact.created event backs it up.
  const events = [
    ev('job.created'), ev('job.started'),
    ev('approval.requested', { action: 'write', claimedArtifact: 'report.md' }),
    ev('approval.decided', { decision: 'approve' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events, expectedArtifacts: ['report.md'] });
  assert.equal(statusOf(report, 'artifacts-present'), 'fail');
});

test('the report never reads approval.requested/approval.decided data at all for any check', () => {
  seq = 0;
  const spoofedData = {
    testsPassed: true, review: true, merged: true, reviewed: true, approved: true,
    sha: 'deadbeef', headSha: 'deadbeef', artifacts: ['report.md'], steps: [{ id: 's1', status: 'completed' }],
  };
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('approval.requested', spoofedData),
    // Deliberately no approval.decided: the approval-card data claims everything is already
    // reviewed/merged/tested, but the approval itself is still open.
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events, expectedArtifacts: ['report.md'] });
  assert.equal(statusOf(report, 'tests-run'), 'unknown');
  assert.equal(statusOf(report, 'artifacts-present'), 'fail');
  assert.equal(statusOf(report, 'plan-steps-closed'), 'unknown');
  assert.equal(statusOf(report, 'checkpoint-head-recorded'), 'unknown');
  assert.equal(statusOf(report, 'no-unresolved-uncertainty'), 'fail'); // the approval is still pending
  assert.equal(canEnterReviewing(report), false);
});

// --- Integration with task-lifecycle.cjs's pure guard -------------------------------------------------------------------------

test('canTransitionToReviewing is false when the state table forbids the move, even with a perfect report', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('tool.completed', { id: 't1', name: 'run tests', exitCode: 0 }),
    ev('artifact.created', { name: 'report.md' }),
    ev('step.started', { id: 's1', title: 'harness.config' }),
    ev('step.completed', { id: 's1' }),
    ev('checkpoint.created', { sha: 'deadbeef' }),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events, expectedArtifacts: ['report.md'] });
  assert.equal(canEnterReviewing(report), true);
  // 'implementing' cannot legally move directly to 'reviewing'... actually it can (see table);
  // use a state that genuinely forbids it instead: 'merged' is terminal.
  assert.equal(canTransitionToReviewing('merged', report), false);
});

test('canTransitionToReviewing is false when the state table allows the move but the report is incomplete', () => {
  seq = 0;
  const events = [ev('job.created', { kind: 'code' }), ev('job.started')];
  const report = buildCompletenessReport({ job: buildJob(events), events });
  assert.equal(canTransitionToReviewing('implementing', report), false);
});

test('canTransitionToReviewing is true only when both the state table and the report agree', () => {
  seq = 0;
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('tool.completed', { id: 't1', name: 'run tests', exitCode: 0 }),
    ev('artifact.created', { name: 'report.md' }),
    ev('step.started', { id: 's1', title: 'harness.config' }),
    ev('step.completed', { id: 's1' }),
    ev('checkpoint.created', { sha: 'deadbeef' }),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events, expectedArtifacts: ['report.md'] });
  assert.equal(canTransitionToReviewing('implementing', report), true);
});

test("canTransitionToReviewing never changes the derived lifecycle itself (#522's guarantee holds)", () => {
  seq = 0;
  const { deriveLifecycle } = require('./task-lifecycle.cjs');
  const events = [
    ev('job.created', { kind: 'code' }), ev('job.started'),
    ev('tool.completed', { id: 't1', name: 'run tests', exitCode: 0 }),
    ev('artifact.created', { name: 'report.md' }),
    ev('step.started', { id: 's1', title: 'harness.config' }),
    ev('step.completed', { id: 's1' }),
    ev('checkpoint.created', { sha: 'deadbeef' }),
    ev('job.completed'),
  ];
  const report = buildCompletenessReport({ job: buildJob(events), events, expectedArtifacts: ['report.md'] });
  canTransitionToReviewing('implementing', report); // calling the guard must not mutate anything
  assert.equal(deriveLifecycle(events), 'verifying'); // never 'reviewing', exactly as #522 requires
});
