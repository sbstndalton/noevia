'use strict';
// Deterministic, model-free completeness auditor (#514, part of #511's fit-gap: "no
// completeness report"). Given a job's own derived shape (jobs.cjs `derive()`/`get()`) and its
// raw, ordered journal events, this module produces a structured report of named checks — each
// pass/fail/unknown with its evidence — and a pure guard, `canEnterReviewing()`, that a future
// reviewer/merge feature can consult before letting a task leave `implementing`/`verifying` for
// `reviewing` (see task-lifecycle.cjs).
//
// No models, no HTTP, no storage: pure functions over data the caller already has in hand.
//
// Trust model (same "server-emitted event types only" boundary task-lifecycle.cjs's honesty
// constraint (#522) draws): every check below is decided from the *structured* fields of
// specific event types that only server/harness code appends — `step.completed`'s `failed`
// boolean, `tool.completed`'s `failed`/`exitCode`, `artifact.created`'s presence, `plan.*`'s
// shape, `checkpoint.created`'s recorded fields, and the append-only `pendingApproval`/
// `uncertain` bookkeeping jobs.cjs's own `derive()` already does. No check here ever reads a
// free-form, caller-chosen key (e.g. a `testsPassed`, `review`, or `merged` flag) out of an
// event's `data` as proof of anything: `approval.requested`/`approval.decided`'s payload is the
// per-tool-call write-approval card, built by spreading page- or model-influenced content
// (browser-service.cjs's `{ ...card, jobId }`), and `job.completed`'s `result` is whatever the
// harness or model reported — neither is evidence of a real test run, review or merge, and a
// forged claim on either is inert here by construction (see the spoof-resistance tests).
//
// This module deliberately does NOT change the derived lifecycle: `job.lifecycle` from
// jobs.cjs/task-lifecycle.cjs is unaffected by anything here, and `canEnterReviewing()` is a
// pure, read-only guard — nothing in this file appends an event, mutates `job`, or calls
// `transition()`. It is wired into task-lifecycle.cjs only as an additional guard function
// exported for a future `transition()` caller to use; today nothing calls it automatically.

const CHECK_NAMES = Object.freeze([
  'tests-run',
  'artifacts-present',
  'plan-steps-closed',
  'no-unresolved-uncertainty',
  'checkpoint-head-recorded',
]);

// Used only to shortlist *candidate* tool/step events for the tests-run check — never to decide
// pass/fail by itself. The verdict always comes from the candidate's structured `failed`/
// `exitCode` field, not from this text match, because a `tool.completed`/`tool.started` event's
// `name`/`title` can itself be agent-supplied (code-harness.cjs sets `tool.started`'s `name`
// from the ACP agent's own `update.title`).
const TEST_NAME_PATTERN = /\b(tests?|spec|specs)\b|jest|mocha|pytest|vitest|typecheck/i;

const CHECKPOINT_SHA_KEYS = Object.freeze(['sha', 'headSha', 'head_sha', 'commitSha', 'commit_sha', 'commit']);
const SHA_SHAPE = /^[0-9a-f]{7,40}$/i;

function check(name, status, evidence, detail) {
  return { name, status, detail, evidence };
}

// Candidate test-shaped tool/step completions, each reduced to only its structured outcome
// fields (never the free-text name/title itself as a verdict).
function findTestCandidates(events) {
  const stepTitles = new Map();
  for (const e of events || []) {
    if (e?.type === 'step.started' && e.data?.id != null) stepTitles.set(e.data.id, e.data.title || null);
  }
  const candidates = [];
  for (const e of events || []) {
    const d = e?.data || {};
    if (e?.type === 'tool.completed' && typeof d.name === 'string' && TEST_NAME_PATTERN.test(d.name)) {
      candidates.push({ source: 'tool.completed', id: d.id ?? null, label: d.name, failed: d.failed === true, exitCode: typeof d.exitCode === 'number' ? d.exitCode : null });
    } else if (e?.type === 'step.completed') {
      const title = stepTitles.get(d.id) || '';
      if (TEST_NAME_PATTERN.test(title)) candidates.push({ source: 'step.completed', id: d.id ?? null, label: title, failed: d.failed === true, exitCode: null });
    }
  }
  return candidates;
}

function testsRunCheck(events) {
  const candidates = findTestCandidates(events);
  if (!candidates.length) {
    return check('tests-run', 'unknown', { candidates: [] }, 'No recorded tool or step event indicates a test run.');
  }
  const failing = candidates.filter((c) => c.failed || (c.exitCode !== null && c.exitCode !== 0));
  if (failing.length) {
    return check('tests-run', 'fail', { candidates, failing }, `${failing.length} of ${candidates.length} recorded test-shaped event(s) did not pass.`);
  }
  return check('tests-run', 'pass', { candidates }, `${candidates.length} recorded test-shaped event(s) all passed.`);
}

// `expectedArtifacts` is declared by the caller (e.g. from the job kind's own contract), never
// inferred from anything the model said. `undefined`/`null` means no expectation was declared
// for this job, which is 'unknown', not a pass — silence is not evidence.
function artifactsPresentCheck(job, expectedArtifacts) {
  const found = (job?.artifacts || []).map((a) => a?.name).filter((n) => typeof n === 'string');
  if (expectedArtifacts == null) {
    return check('artifacts-present', 'unknown', { expected: null, found }, 'No expected-artifact list was declared for this job.');
  }
  const expected = [...expectedArtifacts];
  const missing = expected.filter((name) => !found.includes(name));
  if (missing.length) {
    return check('artifacts-present', 'fail', { expected, found, missing }, `Missing expected artifact(s): ${missing.join(', ')}.`);
  }
  return check('artifacts-present', 'pass', { expected, found }, 'All expected artifacts are present.');
}

// `job.plan` and `job.steps` are exactly what jobs.cjs's own `derive()` already folds from
// `plan.proposed`/`plan.edited`/`plan.skipped` and `step.started`/`step.completed` — this check
// re-reads that same derived shape rather than re-parsing events, so it can never disagree with
// the job object a caller already has.
function planStepsClosedCheck(job) {
  const plan = job?.plan || null;
  const steps = job?.steps || [];
  if (plan && plan.status === 'skipped') {
    return check('plan-steps-closed', 'unknown', { plan, steps }, 'The plan was explicitly skipped; there are no steps to close.');
  }
  if (!plan && !steps.length) {
    return check('plan-steps-closed', 'unknown', { plan, steps }, 'No plan was proposed and no steps were recorded.');
  }
  const open = steps.filter((s) => s.status === 'running');
  if (open.length) {
    return check('plan-steps-closed', 'fail', { plan, steps, open }, `${open.length} step(s) started but never completed: ${open.map((s) => s.id).join(', ')}.`);
  }
  if (!steps.length) {
    return check('plan-steps-closed', 'unknown', { plan, steps }, 'A plan was proposed but no step events were recorded to verify closure.');
  }
  return check('plan-steps-closed', 'pass', { plan, steps }, `All ${steps.length} recorded step(s) are closed.`);
}

// `job.uncertain` (tool.uncertain events) and `job.pendingApproval` (open approval.requested with
// no matching approval.decided/terminal event yet) are both append-only bookkeeping jobs.cjs's
// own `derive()` already maintains; this never inspects the *content* of either event's `data`
// (which can carry agent/page-influenced fields) for anything beyond "does one exist".
function unresolvedCheck(job) {
  const uncertain = job?.uncertain || [];
  const pendingApproval = job?.pendingApproval || null;
  if (uncertain.length || pendingApproval) {
    const parts = [];
    if (uncertain.length) parts.push(`${uncertain.length} unresolved tool.uncertain event(s)`);
    if (pendingApproval) parts.push('a pending approval');
    return check('no-unresolved-uncertainty', 'fail', { uncertainCount: uncertain.length, pendingApproval: !!pendingApproval }, `${parts.join(' and ')} remain.`);
  }
  return check('no-unresolved-uncertainty', 'pass', { uncertainCount: 0, pendingApproval: false }, 'No unresolved uncertainty or pending approval.');
}

// The checkpoint head SHA (#513) may not exist yet on this journal's `checkpoint.created`
// events — code-harness.cjs today records only `branch`/`task`/`identityHash`/`identity`/`meta`.
// A missing SHA is therefore explicitly 'unknown', never a failure: this check cannot punish a
// job for a field #513 hasn't landed to populate.
function checkpointHeadCheck(job) {
  const checkpoint = job?.checkpoint || null;
  if (!checkpoint) {
    return check('checkpoint-head-recorded', 'unknown', { checkpoint: null }, 'No checkpoint was recorded for this job.');
  }
  const key = CHECKPOINT_SHA_KEYS.find((k) => typeof checkpoint[k] === 'string' && checkpoint[k].length > 0);
  if (!key) {
    return check('checkpoint-head-recorded', 'unknown', { checkpoint }, 'A checkpoint was recorded but carries no head SHA (expected until #513 lands).');
  }
  const sha = checkpoint[key];
  if (!SHA_SHAPE.test(sha)) {
    return check('checkpoint-head-recorded', 'fail', { checkpoint, field: key, sha }, `Checkpoint head SHA field "${key}" does not look like a commit SHA: ${JSON.stringify(sha)}.`);
  }
  return check('checkpoint-head-recorded', 'pass', { checkpoint, field: key, sha }, `Checkpoint head SHA recorded (${key}).`);
}

function overallOf(checks) {
  if (checks.some((c) => c.status === 'fail')) return 'fail';
  if (checks.some((c) => c.status === 'unknown')) return 'unknown';
  return 'pass';
}

/**
 * Build the completeness report for one job.
 * @param {{job: object, events?: Array<object>, expectedArtifacts?: string[]|null}} input
 *   - `job`: the derived job shape from jobs.cjs's `derive()`/`get()` (steps, artifacts, plan,
 *     checkpoint, uncertain, pendingApproval, …). Required.
 *   - `events`: the same job's raw, ordered journal events (for tool/step-level evidence the
 *     derived job doesn't retain, e.g. a `tool.completed`'s `name`). Optional; defaults to [].
 *   - `expectedArtifacts`: names the caller expects `artifact.created` to have produced for this
 *     job. `null`/omitted means no expectation was declared (check is 'unknown', not 'pass').
 */
function buildCompletenessReport({ job, events = [], expectedArtifacts = null } = {}) {
  if (!job || typeof job !== 'object') throw Object.assign(Error('buildCompletenessReport requires a derived job'), { status: 400 });
  const checks = [
    testsRunCheck(events),
    artifactsPresentCheck(job, expectedArtifacts),
    planStepsClosedCheck(job),
    unresolvedCheck(job),
    checkpointHeadCheck(job),
  ];
  return { jobId: job.id ?? null, checks, overall: overallOf(checks) };
}

// Pure guard: false whenever any required check failed OR is unknown — "unknown" is treated the
// same as "not proven", not as a pass. True only when every check explicitly passed.
function canEnterReviewing(report) {
  if (!report || !Array.isArray(report.checks) || !report.checks.length) return false;
  return report.checks.every((c) => c.status === 'pass');
}

module.exports = { CHECK_NAMES, buildCompletenessReport, canEnterReviewing };
