'use strict';
// Pure, deterministic task-lifecycle layer for the vision multi-agent pipeline (#511/#512).
// This module knows nothing about models, HTTP, or storage: it is a state machine plus a
// derivation function over the *existing* jobs.cjs journal event vocabulary (see jobs.cjs
// `TYPES`). It never adds a new job event type and never changes job.cjs semantics — it only
// reads the same append-only events a job already writes and infers a coarser, higher-level
// "where is this task in its life" state that the current job.status (queued/running/
// waiting_approval/completed/failed/cancelled/interrupted) does not express.
//
// Offline, no model calls, no UI. See docs/spec-agent-execution.md and the #511 fit-gap
// analysis: "lifecycle lacks planned/verifying/reviewing/changes_requested/merged/blocked".

const STATES = Object.freeze([
  'planned',
  'implementing',
  'verifying',
  'reviewing',
  'changes_requested',
  'merged',
  'blocked',
]);
const STATE_SET = new Set(STATES);
const INITIAL_STATE = 'planned';

// Guarded transition table: the only legal moves. `merged` is terminal (no outgoing edges).
// Anything not listed here is illegal and `transition()` throws for it.
const TRANSITIONS = Object.freeze({
  planned: Object.freeze(['implementing', 'blocked']),
  implementing: Object.freeze(['verifying', 'reviewing', 'merged', 'blocked']),
  verifying: Object.freeze(['reviewing', 'implementing', 'merged', 'blocked']),
  reviewing: Object.freeze(['implementing', 'changes_requested', 'merged', 'blocked']),
  changes_requested: Object.freeze(['implementing', 'reviewing', 'merged', 'blocked']),
  blocked: Object.freeze(['implementing', 'planned']),
  merged: Object.freeze([]),
});

class TaskLifecycleError extends Error {
  constructor(message, { from, to } = {}) {
    super(message);
    this.name = 'TaskLifecycleError';
    this.from = from;
    this.to = to;
    this.status = 409;
  }
}

function assertKnownState(state, label) {
  if (!STATE_SET.has(state)) {
    throw new TaskLifecycleError(`Unknown task-lifecycle state: ${label} = ${JSON.stringify(state)}`, { [label]: state });
  }
}

// True/false, never throws. Staying in the same state is always allowed (a no-op transition).
function canTransition(from, to) {
  assertKnownState(from, 'from');
  assertKnownState(to, 'to');
  if (from === to) return true;
  return TRANSITIONS[from].includes(to);
}

// Guarded transition: returns `to` on success, throws TaskLifecycleError on an illegal move
// (including moves out of the terminal `merged` state, or into/out of an unknown state).
function transition(from, to) {
  if (!canTransition(from, to)) {
    throw new TaskLifecycleError(`Illegal task-lifecycle transition: ${from} -> ${to}`, { from, to });
  }
  return to;
}

// Caller-chosen `progress` stage tokens that this layer treats as meaningful. Any other
// stage string (the vast majority of existing job kinds use free-text stages for UI
// display) is ignored here, exactly as before this module existed.
const CANONICAL_STAGES = new Set(['implementing', 'verifying', 'reviewing']);

// Decision strings observed across existing approval call sites (approvals.cjs uses
// approve/deny/approve_all; browser-service/code-harness relay whatever askApproval
// resolves to, including 'denied' for an automatic policy refusal, and 'aborted' for a
// cancelled wait). Anything not recognized as an approval is treated as a decline: a
// vision-layer reviewer should never silently treat an unrecognized answer as "approved".
const APPROVE_DECISIONS = new Set(['approve', 'approve_all', 'allow', 'allow_once', 'allowed']);

function isApproved(decision) {
  return APPROVE_DECISIONS.has(decision);
}

// One step of the fold: applies a single existing jobs.cjs journal event to a lifecycle
// state and returns the next state. Unrecognized/irrelevant event types (step.*, tool.*,
// artifact.created, checkpoint.created, tool.uncertain, plan.*, assistant.output, and
// `progress` events with a non-canonical stage) are no-ops, by design: most existing job
// kinds never touch review/verification concepts and must keep deriving a harmless state
// instead of throwing.
function applyEvent(state, event) {
  if (!event || typeof event.type !== 'string') return state;
  const data = event.data || {};
  switch (event.type) {
    case 'job.created':
      return state; // already `planned` (or wherever a prior fold left it)
    case 'job.started':
      return advance(state, 'implementing');
    case 'progress':
      return CANONICAL_STAGES.has(data.stage) ? advance(state, data.stage) : state;
    case 'approval.requested':
      return advance(state, 'reviewing');
    case 'approval.decided':
      return advance(state, isApproved(data.decision) ? 'implementing' : 'changes_requested');
    case 'job.completed':
      return advance(state, 'merged');
    case 'job.failed':
    case 'job.cancelled':
    case 'job.interrupted':
      return advance(state, 'blocked');
    default:
      return state;
  }
}

// A derived jump that is illegal per the guarded table is rejected the same way an explicit
// caller-driven `transition()` would be: this is what "illegal transitions are rejected with
// explicit errors" means for derivation too. Callers deriving lifecycle from a real job's
// journal (task-lifecycle-wiring is defensive — see jobs.cjs) should expect this can throw
// on a journal that was never shaped with this layer in mind, and treat that as "no derived
// lifecycle available" rather than a crash.
function advance(from, to) {
  if (from === to) return from;
  return transition(from, to);
}

// Pure fold over an ordered event array (as produced by jobs.cjs's own journal reader),
// starting from `fromState` (defaults to the initial state). Deterministic and side-effect
// free: replaying the same events, in the same order, from the same starting state always
// yields the same result — including in chunks (fold(events.slice(0, k)) then
// fold(events.slice(k), thatResult) === fold(events)), which is what a server restart relies
// on: the journal is replayed from disk, not resumed from in-memory state.
function foldEvents(events, fromState = INITIAL_STATE) {
  assertKnownState(fromState, 'fromState');
  let state = fromState;
  for (const event of events || []) state = applyEvent(state, event);
  return state;
}

// Convenience: derive the lifecycle state for a full journal from the beginning.
function deriveLifecycle(events) {
  return foldEvents(events, INITIAL_STATE);
}

// Defensive variant for wiring into read paths that must never throw: returns null instead
// of raising when the journal implies an illegal transition (e.g. a job kind whose events
// were never authored with this lifecycle in mind). Never hides a bug from `transition()` or
// `deriveLifecycle()` themselves — only from call sites that attach this as extra, optional
// information on top of an existing, already-correct job object.
function safeDeriveLifecycle(events) {
  try {
    return deriveLifecycle(events);
  } catch (e) {
    if (e instanceof TaskLifecycleError) return null;
    throw e;
  }
}

module.exports = {
  STATES,
  INITIAL_STATE,
  TRANSITIONS,
  TaskLifecycleError,
  canTransition,
  transition,
  foldEvents,
  deriveLifecycle,
  safeDeriveLifecycle,
};
