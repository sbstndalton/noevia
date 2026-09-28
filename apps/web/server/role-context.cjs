'use strict';
// role-context.cjs — per-role context projection for the vision multi-agent pipeline (#511/#515).
//
// Builds the bounded, model-facing context each sub-role receives from a task/orchestrator state
// object: planner (Astra), executor (Sol) and auditor (Luna). Modelled on PromptArchitect's
// allowlisted outbound payload builder (docs/spec-agent-execution.md §2, reference implementation
// `outbound_payload`/`audit_outbound` in experiments/prompt-preparation/run.py — Python, so it is
// mirrored here rather than imported).
//
// Rules this module enforces in code, not by instructing a model:
//   * Strict per-role ALLOWLISTS. A projection is constructed field by field from the spec in
//     ROLE_SPECS; nothing is copied by spreading, so an unknown or newly added state field is
//     dropped by construction. There is no denylist of fields anywhere.
//   * Never in a projection: the orchestrator's meta-prompt or routing, another role's system
//     prompt, credentials/tokens/cookies, other tenants' ids or data, Diary content, raw
//     approval internals (ids, cards, arguments, tokens). The auditor only sees counts of the
//     three write-approval decisions (approve / deny / approve_all), never the approvals.
//   * Snippets are admitted only from allowlisted source classes and only when they belong to
//     the task's own tenant; a task without a tenant id is refused.
//   * Per-field size caps (code-point safe) and a total cap; deterministic serialisation.
//   * Fail closed: after building, the projection is scanned for sensitive values taken from the
//     state itself (meta-prompt, other roles' prompts, credential/Diary/other-tenant leaves) and
//     for credential patterns. Any hit throws RoleContextLeakError — no silent repair, matching
//     "any hit invalidates the run" in the PromptArchitect outbound audit.
//
// Pure: no model calls, no I/O, no HTTP. NOT wired into any live chat path — no multi-role
// runner exists yet. A future runner prepends nothing but this projection (plus the original
// request, which the projection already carries as authoritative intent).

const ROLES = Object.freeze(['planner', 'executor', 'auditor']);
const ROLE_NAMES = Object.freeze({ planner: 'Astra', executor: 'Sol', auditor: 'Luna' });

// The three write-approval decisions (approvals.cjs `decide`). Counts only.
const APPROVAL_DECISIONS = Object.freeze(['approve', 'deny', 'approve_all']);

// Snippet source classes a sub-role may see. Diary, private collections and anything unknown are
// excluded by not being listed.
const SNIPPET_SOURCES = Object.freeze(['project', 'selected', 'repo-public']);

const TRUNCATION_MARK = '…[truncated]';

const CAPS = Object.freeze({
  request: 4000,
  roleInstructions: 4000,
  projectInstructions: 3000,
  shortText: 600,
  listItem: 400,
  listItems: 12,
  steps: 12,
  snippetText: 1000,
  snippets: 3,
  capabilities: 24,
  capabilityDescription: 300,
  identifier: 120,
  changedFiles: 50,
  testResults: 20,
  stepResults: 12,
  total: 40000,
});

class RoleContextError extends Error {
  constructor(message, code) {
    super(message);
    this.name = 'RoleContextError';
    this.code = code;
  }
}

class RoleContextLeakError extends RoleContextError {
  constructor(classes) {
    // Names the leaked classes only — never echoes the leaked value itself.
    super(`role context would leak forbidden content: ${classes.join(', ')}`, 'leak');
    this.name = 'RoleContextLeakError';
    this.classes = classes;
  }
}

// ── field sanitisers ────────────────────────────────────────────────────────

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

// Code-point safe truncation so a cap never splits a surrogate pair.
function capText(value, max) {
  if (typeof value !== 'string') return undefined;
  const text = value.normalize('NFC');
  const points = Array.from(text);
  if (points.length <= max) return text;
  const keep = Math.max(0, max - Array.from(TRUNCATION_MARK).length);
  return points.slice(0, keep).join('') + TRUNCATION_MARK;
}

function capIdentifier(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return capText(value, CAPS.identifier);
}

/** @param {unknown} value @param {number} [maxItems] @param {number} [maxChars] */
function capList(value, maxItems = CAPS.listItems, maxChars = CAPS.listItem) {
  if (!Array.isArray(value)) return undefined;
  const out = [];
  for (const item of value) {
    if (out.length >= maxItems) break;
    const text = capText(item, maxChars);
    if (text !== undefined) out.push(text);
  }
  return out;
}

function capInt(value, { min = 0, max = 1e9 } = {}) {
  if (typeof value !== 'number' || !Number.isInteger(value)) return undefined;
  return Math.min(max, Math.max(min, value));
}

function capSteps(value) {
  if (!Array.isArray(value)) return undefined;
  const out = [];
  for (const step of value) {
    if (out.length >= CAPS.steps) break;
    if (!isPlainObject(step)) continue;
    const doText = capText(step.do, CAPS.shortText);
    if (doText === undefined) continue;
    const entry = { n: out.length + 1, do: doText };
    const doneWhen = capText(step.done_when, CAPS.shortText);
    if (doneWhen !== undefined) entry.done_when = doneWhen;
    out.push(entry);
  }
  return out;
}

function capCapabilities(value) {
  if (!Array.isArray(value)) return undefined;
  const byName = new Map();
  for (const cap of value) {
    const name = capIdentifier(isPlainObject(cap) ? cap.name : cap);
    if (!name || byName.has(name)) continue;
    const entry = { name };
    const description = isPlainObject(cap) ? capText(cap.description, CAPS.capabilityDescription) : undefined;
    if (description !== undefined) entry.description = description;
    byName.set(name, entry);
  }
  return [...byName.keys()].sort().slice(0, CAPS.capabilities).map((k) => byName.get(k));
}

// Only snippets from allowlisted source classes that belong to the task's own tenant. A snippet
// with no tenant id is taken to be the task's own (the caller selected it for this task); one
// carrying a *different* tenant id is dropped. The tenant id is used for the check and is never
// copied into the projection.
function capSnippets(value, tenantId) {
  if (!Array.isArray(value)) return undefined;
  const out = [];
  for (const snip of value) {
    if (out.length >= CAPS.snippets) break;
    if (!isPlainObject(snip)) continue;
    if (!SNIPPET_SOURCES.includes(snip.source)) continue;
    if (snip.tenantId !== undefined && snip.tenantId !== tenantId) continue;
    const text = capText(snip.text, CAPS.snippetText);
    if (text === undefined) continue;
    const entry = { source: snip.source, text };
    const label = capText(snip.label, CAPS.identifier);
    if (label !== undefined) entry.label = label;
    out.push(entry);
  }
  return out;
}

function capPlan(plan, keys) {
  if (!isPlainObject(plan)) return undefined;
  const out = {};
  for (const key of keys) {
    let v;
    if (key === 'goal' || key === 'completion') v = capText(plan[key], CAPS.shortText);
    else if (key === 'steps') v = capSteps(plan.steps);
    else if (key === 'capabilities') v = capList(plan.capabilities, CAPS.capabilities, CAPS.identifier);
    else v = capList(plan[key]);
    if (v !== undefined) out[key] = v;
  }
  return out;
}

function capTestResults(value) {
  if (!Array.isArray(value)) return undefined;
  const out = [];
  for (const t of value) {
    if (out.length >= CAPS.testResults) break;
    if (!isPlainObject(t)) continue;
    const name = capText(t.name, CAPS.identifier);
    if (name === undefined || typeof t.passed !== 'boolean') continue;
    out.push({ name, passed: t.passed });
  }
  return out;
}

function capStepResults(value) {
  if (!Array.isArray(value)) return undefined;
  const out = [];
  for (const s of value) {
    if (out.length >= CAPS.stepResults) break;
    if (!isPlainObject(s)) continue;
    const n = capInt(s.n, { min: 1, max: CAPS.steps });
    const status = ['done', 'skipped', 'failed'].includes(s.status) ? s.status : undefined;
    if (n === undefined || status === undefined) continue;
    const entry = { n, status };
    const note = capText(s.note, CAPS.shortText);
    if (note !== undefined) entry.note = note;
    out.push(entry);
  }
  return out;
}

function capExecution(execution) {
  if (!isPlainObject(execution)) return undefined;
  const out = {};
  const summary = capText(execution.summary, CAPS.shortText);
  if (summary !== undefined) out.summary = summary;
  const headSha = typeof execution.headSha === 'string' && /^[0-9a-f]{7,64}$/.test(execution.headSha) ? execution.headSha : undefined;
  if (headSha !== undefined) out.head_sha = headSha;
  const files = capList(execution.changedFiles, CAPS.changedFiles, CAPS.identifier * 2);
  if (files !== undefined) out.changed_files = files;
  const tests = capTestResults(execution.testResults);
  if (tests !== undefined) out.test_results = tests;
  const steps = capStepResults(execution.stepResults);
  if (steps !== undefined) out.step_results = steps;
  return out;
}

// Counts of the three write-approval decisions only. Ids, cards, arguments, tokens, timestamps
// and any unknown decision value are never read into the projection.
function approvalOutcomes(approvals) {
  const counts = { approve: 0, deny: 0, approve_all: 0 };
  if (!Array.isArray(approvals)) return counts;
  for (const a of approvals) {
    if (isPlainObject(a) && APPROVAL_DECISIONS.includes(a.decision)) counts[a.decision] += 1;
  }
  return counts;
}

// ── per-role allowlists ─────────────────────────────────────────────────────
// Each entry: output key -> function(state, ctx) returning the capped value or undefined.
// This table IS the allowlist; a field that is not listed cannot reach a projection.

const PLAN_KEYS_EXECUTOR = Object.freeze(['goal', 'steps', 'constraints', 'capabilities', 'approval_boundaries', 'verification', 'completion', 'non_goals']);
const PLAN_KEYS_AUDITOR = Object.freeze(['goal', 'steps', 'constraints', 'approval_boundaries', 'verification', 'completion', 'non_goals']);

const common = {
  role: (_s, ctx) => ctx.role,
  role_name: (_s, ctx) => ROLE_NAMES[ctx.role],
  task_id: (s) => capIdentifier(s.taskId),
  revision: (s) => capIdentifier(s.revision),
  request: (s) => capText(s.request, CAPS.request),
  role_instructions: (s, ctx) => (isPlainObject(s.roleSystemPrompts) ? capText(s.roleSystemPrompts[ctx.role], CAPS.roleInstructions) : undefined),
};

const ROLE_SPECS = Object.freeze({
  planner: Object.freeze({
    ...common,
    project_instructions: (s) => capText(s.projectInstructions, CAPS.projectInstructions),
    snippets: (s, ctx) => capSnippets(s.snippets, ctx.tenantId),
    capabilities: (s) => capCapabilities(s.capabilities),
    constraints: (s) => capList(s.constraints),
    context_limit: (s) => capInt(s.contextLimit, { min: 0, max: 10_000_000 }),
  }),
  executor: Object.freeze({
    ...common,
    project_instructions: (s) => capText(s.projectInstructions, CAPS.projectInstructions),
    plan: (s) => capPlan(s.plan, PLAN_KEYS_EXECUTOR),
    snippets: (s, ctx) => capSnippets(s.snippets, ctx.tenantId),
    capabilities: (s) => capCapabilities(s.capabilities),
  }),
  auditor: Object.freeze({
    ...common,
    plan: (s) => capPlan(s.plan, PLAN_KEYS_AUDITOR),
    lifecycle_state: (s) => capIdentifier(s.lifecycleState),
    execution: (s) => capExecution(s.execution),
    approval_outcomes: (s) => approvalOutcomes(s.approvals),
  }),
});

function allowedFields(role) {
  const spec = ROLE_SPECS[role];
  if (!spec) throw new RoleContextError(`unknown role: ${String(role)}`, 'unknown_role');
  return Object.keys(spec).sort();
}

// ── deterministic serialisation ─────────────────────────────────────────────

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (isPlainObject(value)) {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      if (value[key] !== undefined) out[key] = canonicalize(value[key]);
    }
    return out;
  }
  return value;
}

// Sorted keys, no whitespace, arrays in order. Same projection -> byte-identical string.
function serializeProjection(projection) {
  return JSON.stringify(canonicalize(projection));
}

// ── leak detection ──────────────────────────────────────────────────────────

function escapeNonAscii(text) {
  return text.replace(/[\u007f-￿]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
}

// Decode literal "\uXXXX" sequences written into string content, so an escaped canary is caught.
function decodeLiteralEscapes(text) {
  return text.replace(/\\u([0-9a-fA-F]{4})/g, (_m, hex) => String.fromCharCode(parseInt(hex, 16)));
}

function collectStrings(value, out = []) {
  if (typeof value === 'string') out.push(value);
  else if (Array.isArray(value)) for (const v of value) collectStrings(v, out);
  else if (isPlainObject(value)) {
    for (const key of Object.keys(value)) {
      out.push(key);
      collectStrings(value[key], out);
    }
  }
  return out;
}

// Every representation of the projection a leak could hide in: the canonical serialisation, its
// ASCII-escaped form, each decoded string and key (nested), those with literal \u escapes decoded,
// and NFKC-folded, case-folded variants of all of it (catches full-width lookalikes).
function haystacks(projection) {
  const serialized = serializeProjection(projection);
  const base = [serialized, escapeNonAscii(serialized), ...collectStrings(projection)];
  const expanded = [];
  for (const h of base) {
    expanded.push(h);
    const decoded = decodeLiteralEscapes(h);
    if (decoded !== h) expanded.push(decoded);
  }
  const folded = expanded.map((h) => h.normalize('NFKC').toLowerCase());
  return expanded.concat(folded);
}

function needles(item) {
  const text = String(item);
  const nfkc = text.normalize('NFKC');
  return [...new Set([text, escapeNonAscii(text), JSON.stringify(text).slice(1, -1), nfkc.toLowerCase()])];
}

// Returns the forbidden entries (strings or RegExps) found anywhere in the projection.
function findLeaks(projection, forbidden) {
  const hay = haystacks(projection);
  const hits = [];
  for (const item of forbidden || []) {
    if (item instanceof RegExp) {
      const re = new RegExp(item.source, item.flags.replace('g', ''));
      if (hay.some((h) => re.test(h))) hits.push(item);
      continue;
    }
    if (typeof item !== 'string' || item.length === 0) continue;
    const ns = needles(item);
    if (hay.some((h) => ns.some((n) => h.includes(n)))) hits.push(item);
  }
  return hits;
}

// Test helper and runtime guard: throws if any forbidden string/RegExp appears in any form.
function assertNoLeak(projection, forbidden) {
  const hits = findLeaks(projection, forbidden);
  if (hits.length) throw new RoleContextLeakError(hits.map((h) => `forbidden[${forbidden.indexOf(h)}]`));
  return true;
}

// Credential shapes that must never reach any role, whatever field they arrive in.
const CREDENTIAL_PATTERNS = Object.freeze([
  /(?<![A-Za-z0-9])sk-(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{16,}/,
  /(?<![A-Za-z])bearer\s+(?=[A-Za-z0-9._~+/-]*\d)[A-Za-z0-9._~+/-]{16,}/i,
  /gh[pousr]_[A-Za-z0-9]{20,}/,
  /AKIA[0-9A-Z]{16}/,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /xox[abpr]-[A-Za-z0-9-]{10,}/,
]);

const MIN_SENSITIVE_LENGTH = 8;
const ORCHESTRATOR_SENSITIVE_KEYS = Object.freeze(['metaPrompt', 'systemPrompt', 'routing', 'notes', 'scratchpad']);
const APPROVAL_SENSITIVE_KEYS = Object.freeze(['id', 'token', 'args', 'arguments', 'userId', 'chatId']);

function leafStrings(value, out = [], depth = 0) {
  if (depth > 32) return out;
  if (typeof value === 'string') { if (value.length >= MIN_SENSITIVE_LENGTH) out.push(value); }
  else if (Array.isArray(value)) for (const v of value) leafStrings(v, out, depth + 1);
  else if (isPlainObject(value)) for (const k of Object.keys(value)) leafStrings(value[k], out, depth + 1);
  return out;
}

// Sensitive values drawn from the state itself, grouped by class, so a projection that copied one
// verbatim through an allowlisted field (e.g. a plan step quoting the meta-prompt) is refused.
function sensitiveClasses(state, role) {
  const classes = {};
  // The orchestrator's own text: its meta-prompt, system prompt, routing and notes. Its other
  // fields (e.g. a status word) are not treated as secrets, to avoid refusing on common words.
  const o = isPlainObject(state.orchestrator) ? state.orchestrator : {};
  classes.orchestrator = leafStrings(ORCHESTRATOR_SENSITIVE_KEYS.map((k) => o[k]));
  const prompts = isPlainObject(state.roleSystemPrompts) ? state.roleSystemPrompts : {};
  classes.other_role_prompts = leafStrings(Object.keys(prompts).filter((r) => r !== role).map((r) => prompts[r]));
  classes.credentials = leafStrings([state.credentials, state.secrets, state.tokens]);
  classes.diary = leafStrings(state.diary);
  classes.other_tenants = leafStrings(state.otherTenants);
  if (Array.isArray(state.snippets)) {
    classes.other_tenants.push(...leafStrings(state.snippets.filter((s) => isPlainObject(s) && s.tenantId !== undefined && s.tenantId !== state.tenantId).map((s) => s.text)));
    classes.diary.push(...leafStrings(state.snippets.filter((s) => isPlainObject(s) && s.source === 'diary').map((s) => s.text)));
  }
  // Approval ids, tokens and arguments. The tool name on a card is not listed: it legitimately
  // matches a capability name the role is allowed to see.
  classes.approval_internals = leafStrings((Array.isArray(state.approvals) ? state.approvals : []).map((a) => (isPlainObject(a) ? [...APPROVAL_SENSITIVE_KEYS.map((k) => a[k]), ...(isPlainObject(a.card) ? APPROVAL_SENSITIVE_KEYS.map((k) => a.card[k]) : [])] : undefined)));
  // Other tenants' ids are forbidden too, even when short.
  const otherIds = [];
  if (isPlainObject(state.otherTenants)) otherIds.push(...Object.keys(state.otherTenants));
  if (Array.isArray(state.snippets)) for (const s of state.snippets) if (isPlainObject(s) && typeof s.tenantId === 'string' && s.tenantId !== state.tenantId) otherIds.push(s.tenantId);
  classes.other_tenant_ids = otherIds.filter((id) => id.length >= 3);
  return classes;
}

function guardProjection(projection, state, role) {
  const leaked = [];
  const classes = sensitiveClasses(state, role);
  for (const name of Object.keys(classes).sort()) {
    if (classes[name].length && findLeaks(projection, classes[name]).length) leaked.push(name);
  }
  if (findLeaks(projection, CREDENTIAL_PATTERNS).length) leaked.push('credential_pattern');
  if (leaked.length) throw new RoleContextLeakError(leaked);
}

// ── builder ─────────────────────────────────────────────────────────────────

function deepFreeze(value) {
  if (value && typeof value === 'object') {
    for (const v of Object.values(value)) deepFreeze(v);
    Object.freeze(value);
  }
  return value;
}

function buildRoleContext(role, state) {
  const spec = ROLE_SPECS[role];
  if (!spec) throw new RoleContextError(`unknown role: ${String(role)}`, 'unknown_role');
  if (!isPlainObject(state)) throw new RoleContextError('state must be an object', 'invalid_state');
  if (typeof state.tenantId !== 'string' || !state.tenantId) throw new RoleContextError('state.tenantId is required', 'missing_tenant');
  const ctx = { role, tenantId: state.tenantId };
  const projection = {};
  for (const key of Object.keys(spec).sort()) {
    const value = spec[key](state, ctx);
    if (value !== undefined) projection[key] = value;
  }
  const canonical = canonicalize(projection);
  const size = Array.from(serializeProjection(canonical)).length;
  if (size > CAPS.total) throw new RoleContextError(`projection exceeds ${CAPS.total} characters`, 'too_large');
  guardProjection(canonical, state, role);
  return deepFreeze(canonical);
}

function buildAllRoleContexts(state) {
  const out = {};
  for (const role of ROLES) out[role] = buildRoleContext(role, state);
  return out;
}

module.exports = {
  ROLES,
  ROLE_NAMES,
  APPROVAL_DECISIONS,
  SNIPPET_SOURCES,
  CAPS,
  CREDENTIAL_PATTERNS,
  TRUNCATION_MARK,
  RoleContextError,
  RoleContextLeakError,
  allowedFields,
  buildRoleContext,
  buildAllRoleContexts,
  serializeProjection,
  findLeaks,
  assertNoLeak,
};
