'use strict';
// The role engine (#702) against a fake streaming engine: offline, synthetic task data only.
const test = require('node:test');
const assert = require('node:assert/strict');
const { createRoleEngine, buildMessages, loadedFromModelList, SHARED_FRAME, schemaConstraint } = require('./role-engine.cjs');
const { projectSharedDossier, projectRoleContext, allowedFields, PERSONA_FIELDS, REVISION_FIELDS, RoleContextLeakError, REDACTED } = require('./role-context.cjs');
const { createPlannerPlan } = require('./planner-plan.cjs');
const { createPlannerReview } = require('./code-review.cjs');
const { PLAN_ARTIFACT_SCHEMA } = require('./plan-constrained-decoding.cjs');

const MODEL = 'synthetic-coder-q4';
const OTHER = 'synthetic-chat-q8';
const MODEL_TEXT_CANARY = 'CANARY-model-output-7731';
const REQUEST_CANARY = 'CANARY-request-text-5512';
const SCHEMA = { type: 'object', additionalProperties: false, required: ['answer'], properties: { answer: { type: 'string' } } };
const GOOD = JSON.stringify({ answer: MODEL_TEXT_CANARY });

const state = (extra = {}) => ({
  taskId: 'task-702', tenantId: 'tenant-a', revision: 1,
  request: `Add a median helper to the synthetic repo. ${REQUEST_CANARY}`,
  projectInstructions: 'Keep functions small.',
  capabilities: [{ name: 'read' }, { name: 'edit' }],
  plan: { goal: 'median helper', steps: [{ do: 'write median', done_when: 'tests pass' }] },
  execution: { headSha: 'b'.repeat(40), changedFiles: ['median.js'], summary: 'wrote it' },
  change: { baseSha: 'a'.repeat(40), headSha: 'b'.repeat(40), files: [{ path: 'median.js', patch: '+module.exports = m;\n' }] },
  ...extra,
});

// One SSE event per pull, on demand (highWaterMark 0): `pulled` is exactly what the engine had to
// generate and send before the client stopped reading.
function sseResponse(events, probe) {
  const enc = new TextEncoder();
  let i = 0;
  const stream = new ReadableStream({
    pull(c) {
      if (i >= events.length) { c.close(); return; }
      const chunk = enc.encode(events[i++]);
      probe.pulled += 1; probe.bytes += chunk.byteLength;
      c.enqueue(chunk);
    },
    cancel() { probe.cancelled = true; },
  }, { highWaterMark: 0 });
  return new Response(stream, { status: 200, headers: { 'Content-Type': 'text/event-stream' } });
}
const delta = (content, extra = {}) => `data: ${JSON.stringify({ model: MODEL, choices: [{ delta: { content }, ...extra }] })}\n\n`;
const reasoning = (text) => `data: ${JSON.stringify({ choices: [{ delta: { reasoning_content: text } }] })}\n\n`;
const finalEvent = (timings = { prompt_n: 812, cache_n: 790, prompt_ms: 41.5, predicted_n: 12, predicted_ms: 300.25 }) =>
  `data: ${JSON.stringify({ choices: [{ delta: {}, finish_reason: 'stop' }], timings })}\n\ndata: [DONE]\n\n`;
const streamOf = (text, pieces = 4) => {
  const size = Math.ceil(text.length / pieces);
  const out = [];
  for (let k = 0; k < text.length; k += size) out.push(delta(text.slice(k, k + size)));
  return [...out, finalEvent()];
};

/** A fake engine: a router /models list and a streaming /chat/completions, scripted per request. */
function fakeEngine({ loaded = [MODEL], replies = [], status = null } = {}) {
  const calls = [], probes = [], modelReads = [];
  const engineState = { loaded };
  const fetch = async (url, init = {}) => {
    if (url.endsWith('/models')) {
      modelReads.push(url);
      if (engineState.loaded instanceof Error) return { ok: false, status: 503, json: async () => ({}) };
      return { ok: true, status: 200, json: async () => ({ data: [MODEL, OTHER].map((id) => ({ id, status: { value: engineState.loaded.includes(id) ? 'loaded' : 'unloaded' } })) }) };
    }
    const body = JSON.parse(init.body);
    const probe = { pulled: 0, bytes: 0, cancelled: false, signal: init.signal };
    calls.push({ url, body, headers: init.headers, signal: init.signal });
    probes.push(probe);
    const next = replies.shift();
    if (typeof next === 'function') return next(body, probe);
    if (typeof next === 'number') return new Response('engine detail: synthetic secret text', { status: next });
    return sseResponse(next || streamOf(GOOD), probe);
  };
  return { fetch, calls, probes, modelReads, engineState };
}

function engineFor(fake, { provider = null, logs = [], model = MODEL, external = false } = {}) {
  return createRoleEngine({ fetch: fake.fetch, log: (e) => logs.push(e), engine: () => ({ baseUrl: 'http://engine.invalid/v1', apiKey: 'k-local', model, provider, external }) });
}

async function pinned(fake, opts = {}) {
  const pin = await engineFor(fake, opts).pinModel({ taskId: 'task-702', ...(opts.thinking !== undefined ? { thinking: opts.thinking } : {}) });
  assert.equal(pin.ok, true, JSON.stringify(pin));
  return pin.session;
}

test('pinModel pins the configured model once; every call sends exactly that id, streamed, cache_prompt, thinking pinned', async () => {
  const fake = fakeEngine({ replies: [streamOf(GOOD), streamOf(GOOD)] });
  const session = await pinned(fake);
  assert.equal(session.model, MODEL);
  assert.equal(session.thinking, false);
  for (const role of ['planner', 'reviewer']) {
    const r = await session.call({ role, state: state(), instructions: `Act as ${role}.`, schema: SCHEMA });
    assert.equal(r.ok, true, JSON.stringify(r));
    assert.equal(JSON.parse(r.text).answer, MODEL_TEXT_CANARY);
  }
  for (const { body, url, headers } of fake.calls) {
    assert.equal(url, 'http://engine.invalid/v1/chat/completions');
    assert.equal(body.model, MODEL);
    assert.equal(body.stream, true);
    assert.equal(body.cache_prompt, true);
    assert.deepEqual(body.chat_template_kwargs, { enable_thinking: false });
    assert.equal(headers.Authorization, 'Bearer k-local');
  }
  // The router was asked before the pin and before every call.
  assert.equal(fake.modelReads.length, 3);
});

test('refusal on a model mismatch: pinning never triggers a swap, and nothing is sent', async () => {
  const logs = [];
  const fake = fakeEngine({ loaded: [OTHER] });
  const pin = await engineFor(fake, { logs }).pinModel({ taskId: 'task-702' });
  assert.equal(pin.ok, false);
  assert.equal(pin.code, 'model_mismatch');
  assert.equal(fake.calls.length, 0, 'no chat request was sent');
  assert.deepEqual(logs, [{ event: 'role.model_refused', taskId: 'task-702', stage: 'pin', pinned: MODEL, others: 1 }]);
  // Both resident is a mismatch too (the pinned one would have to share or swap).
  const both = fakeEngine({ loaded: [MODEL, OTHER] });
  assert.equal((await engineFor(both).pinModel({ taskId: 't' })).code, 'model_mismatch');
});

test('refusal mid-task: another model became resident between calls, and before the correction', async () => {
  const fake = fakeEngine({ replies: [streamOf(GOOD)] });
  const session = await pinned(fake);
  assert.equal((await session.call({ role: 'planner', state: state(), instructions: 'p', schema: SCHEMA })).ok, true);
  fake.engineState.loaded = [OTHER];
  const r = await session.call({ role: 'reviewer', state: state(), instructions: 'r', schema: SCHEMA });
  assert.equal(r.ok, false);
  assert.equal(r.code, 'model_mismatch');
  assert.equal(fake.calls.length, 1, 'the second role call was never sent');

  // The swap happens while the first attempt streams: the correction is refused, not sent.
  const swap = fakeEngine({ replies: [(_b, probe) => { swap.engineState.loaded = [OTHER]; return sseResponse([delta('{"wrong":'), finalEvent()], probe); }] });
  const s2 = await pinned(swap);
  const r2 = await s2.call({ role: 'planner', state: state(), instructions: 'p', schema: SCHEMA });
  assert.equal(r2.code, 'model_mismatch');
  assert.equal(swap.calls.length, 1);
});

test('pinModel: cold start, single resident model, unreadable router, external provider, invalid input', async () => {
  const cold = fakeEngine({ loaded: [] });
  const logs = [];
  const pin = await engineFor(cold, { logs }).pinModel({ taskId: 't', thinking: true });
  assert.equal(pin.ok, true);
  assert.equal(pin.session.thinking, true);
  assert.deepEqual(logs.at(-1), { event: 'role.pinned', taskId: 't', model: MODEL, thinking: true, cold: true });
  const only = fakeEngine({ loaded: [OTHER] });
  assert.equal((await engineFor(only, { model: null }).pinModel({ taskId: 't' })).session.model, OTHER);
  assert.equal((await engineFor(fakeEngine({ loaded: [] }), { model: null }).pinModel({ taskId: 't' })).code, 'no_model');
  const down = fakeEngine({ loaded: new Error('down') });
  assert.equal((await engineFor(down).pinModel({ taskId: 't' })).code, 'router_unavailable');
  const ext = fakeEngine();
  assert.equal((await engineFor(ext, { external: true }).pinModel({ taskId: 't' })).code, 'external');
  assert.equal(ext.modelReads.length, 0);
  assert.equal((await engineFor(ext).pinModel({ taskId: '' })).code, 'invalid');
  assert.equal((await engineFor(ext).pinModel({ taskId: 't', thinking: 'yes' })).code, 'invalid');
});

test('loadedFromModelList reads router status and a single server without status', () => {
  assert.deepEqual(loadedFromModelList({ data: [{ id: 'a', status: { value: 'loaded' } }, { id: 'b', status: { value: 'unloaded' } }, { id: 'c', status: 'loading' }] }), ['a', 'c']);
  assert.deepEqual(loadedFromModelList({ data: [{ id: 'solo' }] }), ['solo']);
  assert.deepEqual(loadedFromModelList(null), []);
});

test('halt mid-stream: the first violation aborts the request and stops pulling bytes, then one correction runs', async () => {
  // 2,000 more events would follow the violation; a guard that read to the end would pull them all.
  const tail = Array.from({ length: 2000 }, () => delta('"padding padding padding",'));
  const bad = [delta('{"ans'), delta('wer":"ok", "extra'), delta('":'), ...tail, finalEvent()];
  const logs = [];
  const fake = fakeEngine({ replies: [bad, streamOf(GOOD)] });
  const session = await pinned(fake, { logs });
  const r = await session.call({ role: 'planner', state: state(), instructions: 'p', schema: SCHEMA });
  assert.equal(r.ok, true);
  assert.equal(r.corrected, true);
  assert.equal(r.attempts, 2);
  const [first, second] = fake.probes;
  assert.ok(first.pulled <= 3, `pulled ${first.pulled} events after the violation`);
  const total = bad.reduce((n, e) => n + Buffer.byteLength(e), 0);
  assert.equal(first.bytes, bad.slice(0, first.pulled).reduce((n, e) => n + Buffer.byteLength(e), 0));
  assert.ok(first.bytes * 100 < total, `pulled ${first.bytes} of ${total} bytes`);
  assert.equal(first.cancelled, true, 'the body reader was cancelled');
  assert.equal(first.signal.aborted, true, 'the HTTP request was aborted');
  assert.equal(second.pulled, streamOf(GOOD).length, 'the corrected answer was read to its end');
  // The correction is user #3 and carries only the violation; the prefix is unchanged.
  const [a, b] = fake.calls.map((c) => c.body.messages);
  assert.equal(a.length, 3);
  assert.equal(b.length, 4);
  assert.deepEqual(b.slice(0, 3), a);
  assert.equal(b[3].content, `That answer was not valid: {"message":"Unknown property 'extra' at $","path":"$.extra"}. Answer again with only the JSON object.`);
  const entries = logs.filter((e) => e.event === 'role.call');
  assert.equal(entries.length, 2);
  assert.equal(entries[0].halted, true);
  assert.equal(entries[1].halted, false);
});

test('one bounded correction only: a second violation fails closed as invalid after exactly two requests', async () => {
  const fake = fakeEngine({ replies: [[delta('['), finalEvent()], [delta('"no"'), finalEvent()], streamOf(GOOD)] });
  const session = await pinned(fake);
  const r = await session.call({ role: 'planner', state: state(), instructions: 'p', schema: SCHEMA });
  assert.equal(r.ok, false);
  assert.equal(r.code, 'invalid');
  assert.equal(fake.calls.length, 2);
});

test('reasoning deltas are not validated; content after them is', async () => {
  const fake = fakeEngine({ replies: [[reasoning('let me think { not json'), ...streamOf(GOOD)]] });
  const session = await pinned(fake, { thinking: true });
  const r = await session.call({ role: 'planner', state: state(), instructions: 'p', schema: SCHEMA });
  assert.equal(r.ok, true);
  assert.equal(r.corrected, false);
  assert.deepEqual(fake.calls[0].body.chat_template_kwargs, { enable_thinking: true });
});

test('prefix byte-identity across roles and revisions: system and user #1 are identical, the persona differs', async () => {
  const fake = fakeEngine({ replies: [streamOf(GOOD), streamOf(GOOD), streamOf(GOOD)] });
  const session = await pinned(fake);
  const r1 = await session.call({ role: 'planner', state: state(), instructions: 'Plan it.', schema: SCHEMA });
  const r2 = await session.call({ role: 'reviewer', state: state(), instructions: 'Review it.', schema: SCHEMA });
  // Revision 2: new head SHA, new plan, new diff — the shared prefix must not move.
  const r3 = await session.call({ role: 'auditor', state: state({ revision: 2, execution: { headSha: 'c'.repeat(40) }, change: { baseSha: 'a'.repeat(40), headSha: 'c'.repeat(40), files: [] }, plan: { goal: 'other' } }), instructions: 'Audit it.', schema: SCHEMA });
  const bodies = fake.calls.map((c) => c.body);
  const prefixOf = (b) => JSON.stringify([b.model, b.chat_template_kwargs, b.messages[0], b.messages[1]]);
  assert.equal(prefixOf(bodies[0]), prefixOf(bodies[1]));
  assert.equal(prefixOf(bodies[0]), prefixOf(bodies[2]));
  assert.equal(r1.prefix, r2.prefix);
  assert.equal(r1.prefix, r3.prefix);
  assert.equal(bodies[0].messages[0].content, SHARED_FRAME);
  assert.notEqual(bodies[0].messages[2].content, bodies[1].messages[2].content);
  // The revision and the SHAs live in the persona block, never in the prefix.
  assert.ok(!bodies[2].messages[1].content.includes('c'.repeat(40)));
  assert.ok(!/"revision"/.test(bodies[2].messages[1].content));
  assert.match(bodies[1].messages[2].content, /"head_sha":"b{40}"/);
  assert.match(bodies[2].messages[2].content, /"revision":"2"/);
  // The frame is byte-constant: a second engine and task produce the very same system message.
  assert.equal(buildMessages({ dossier: '{}', instructions: 'x', fields: '{}' })[0].content, SHARED_FRAME);
});

test('a call for another task or an unpinned role is refused before anything is sent', async () => {
  const fake = fakeEngine();
  const pin = await engineFor(fake).pinModel({ taskId: 'task-702', roles: ['planner', 'reviewer'] });
  const session = pin.session;
  assert.equal((await session.call({ role: 'auditor', state: state(), instructions: 'a', schema: SCHEMA })).code, 'role_not_pinned');
  assert.equal((await session.call({ role: 'planner', state: state({ taskId: 'task-other' }), instructions: 'p', schema: SCHEMA })).code, 'task_mismatch');
  assert.equal(fake.calls.length, 0);
});

test('timings are captured per attempt with no model text and no prompt text', async () => {
  const logs = [];
  const fake = fakeEngine({ replies: [[delta('{"answer":"' + MODEL_TEXT_CANARY), delta('"}'), finalEvent()]] });
  const session = await pinned(fake, { logs });
  const r = await session.call({ role: 'planner', state: state(), instructions: 'p', schema: SCHEMA });
  assert.equal(r.ok, true);
  const [entry] = session.timings();
  assert.equal(entry.event, 'role.call');
  assert.equal(entry.prompt_n, 812);
  assert.equal(entry.cache_n, 790);
  assert.equal(entry.prompt_ms, 41.5);
  assert.equal(entry.predicted_n, 12);
  assert.equal(entry.predicted_ms, 300.25);
  assert.equal(entry.deltas, 2);
  assert.equal(entry.halted, false);
  assert.ok(Number.isFinite(entry.wall_ms) && Number.isFinite(entry.first_delta_ms) && entry.bytes > 0);
  const all = JSON.stringify(logs);
  for (const canary of [MODEL_TEXT_CANARY, REQUEST_CANARY, 'median', 'synthetic secret']) assert.ok(!all.includes(canary), `log carried ${canary}`);
});

test('engine errors: a non-OK status fails without reading the engine text; an aborted caller is aborted', async () => {
  const logs = [];
  const fake = fakeEngine({ replies: [500] });
  const session = await pinned(fake, { logs });
  const r = await session.call({ role: 'planner', state: state(), instructions: 'p', schema: SCHEMA });
  assert.deepEqual([r.ok, r.code], [false, 'error']);
  assert.ok(!JSON.stringify([r, logs]).includes('synthetic secret'));
  const controller = new AbortController();
  const slow = fakeEngine({ replies: [(_b, probe) => { setTimeout(() => controller.abort(), 5); return sseResponse([delta('{"answer":"'), ...Array.from({ length: 50 }, () => delta('x')), finalEvent()], probe); }] });
  const s2 = await pinned(slow);
  const aborted = await s2.call({ role: 'planner', state: state(), instructions: 'p', schema: SCHEMA, signal: controller.signal });
  // Either the abort lands mid-stream or the short stream completes first; never an unchecked answer.
  assert.ok(aborted.ok === true || aborted.code === 'aborted');
  controller.abort();
  assert.equal((await s2.call({ role: 'planner', state: state(), instructions: 'p', schema: SCHEMA, signal: controller.signal })).code, 'aborted');
});

test('constrained decoding reuses the #517 rules: capability-gated, never with thinking, one fallback on rejection', async () => {
  const capable = { capabilities: { jsonSchemaParam: true } };
  const fake = fakeEngine({ replies: [streamOf(GOOD)] });
  const session = await pinned(fake, { provider: capable });
  await session.call({ role: 'planner', state: state(), instructions: 'p', schema: SCHEMA, constrain: true, schemaName: 'x' });
  assert.equal(fake.calls[0].body.response_format.type, 'json_schema');
  assert.deepEqual(fake.calls[0].body.response_format.json_schema.schema, SCHEMA);
  assert.deepEqual(fake.calls[0].body.chat_template_kwargs, { enable_thinking: false });
  // Off unless asked, and never for a provider without the capability or with thinking pinned on.
  assert.equal(schemaConstraint({ enabled: false, provider: capable }).applied, false);
  assert.equal(schemaConstraint({ enabled: true, provider: {} }).reason, 'provider_unsupported');
  assert.equal(schemaConstraint({ enabled: true, provider: capable, thinking: true }).reason, 'thinking_enabled');
  // A 422 retries once unconstrained, and the correction does not ask again.
  const logs = [];
  const rej = fakeEngine({ replies: [422, [delta('[]'), finalEvent()], streamOf(GOOD)] });
  const s2 = await pinned(rej, { provider: capable, logs });
  const r = await s2.call({ role: 'planner', state: state(), instructions: 'p', schema: SCHEMA, constrain: true });
  assert.equal(r.ok, true);
  assert.equal(r.constraint.fallback, true);
  assert.equal(rej.calls.length, 3);
  assert.ok('response_format' in rej.calls[0].body);
  assert.ok(!('response_format' in rej.calls[1].body) && !('response_format' in rej.calls[2].body));
  assert.ok(logs.some((e) => e.event === 'plan.constraint_rejected' && e.status === 422));
});

// ── the shared dossier (role-context.cjs projectSharedDossier) ───────────────

test('dossier: an intersection allowlist with no persona, revision or SHA fields, deterministic', () => {
  const { dossier, meta } = projectSharedDossier(state());
  assert.deepEqual(Object.keys(dossier), ['request', 'task_id']);
  for (const role of ['planner', 'executor', 'auditor', 'reviewer']) for (const key of Object.keys(dossier)) assert.ok(allowedFields(role).includes(key));
  for (const key of [...PERSONA_FIELDS, ...REVISION_FIELDS]) assert.ok(!(key in dossier));
  // Even a single-role set never shares a revision-bound field.
  const solo = projectSharedDossier(state(), { roles: ['reviewer'] }).dossier;
  assert.ok(!JSON.stringify(solo).includes('b'.repeat(40)));
  assert.ok(!('revision' in solo) && !('plan' in solo) && !('change' in solo));
  assert.deepEqual(Object.keys(solo).sort(), ['capabilities', 'request', 'task_id']);
  // Planner + executor share their common allowlist (instructions, snippets, capabilities).
  const pe = projectSharedDossier(state(), { roles: ['planner', 'executor'] }).dossier;
  assert.deepEqual(Object.keys(pe), ['capabilities', 'project_instructions', 'request', 'task_id']);
  assert.equal(JSON.stringify(projectSharedDossier(state({ revision: 9 })).dossier), JSON.stringify(dossier));
  assert.deepEqual(meta.fields, ['request', 'task_id']);
});

test('dossier leaks: credentials redacted, role prompts, other tenants, Diary and approvals never pass', () => {
  const key = 'sk-' + 'A1b2C3d4E5f6G7h8J9k0';
  const r = projectSharedDossier(state({ request: `use ${key} please` }));
  assert.ok(r.dossier.request.includes(REDACTED));
  assert.equal(r.meta.redactions, 1);
  const prompt = 'You are the Planner, here is the private orchestration prompt that no other role may read at all.';
  assert.throws(() => projectSharedDossier(state({ request: prompt, roleSystemPrompts: { planner: prompt } })), RoleContextLeakError);
  assert.throws(() => projectSharedDossier(state({ request: 'from tenant-b-secret-notes', otherTenants: { 'tenant-b': ['tenant-b-secret-notes'] } })), RoleContextLeakError);
  assert.throws(() => projectSharedDossier(state({ request: 'Dear diary synthetic entry 42', diary: ['Dear diary synthetic entry 42'] })), RoleContextLeakError);
  assert.throws(() => projectSharedDossier(state({ request: 'approval appr-SECRET-1234', approvals: [{ id: 'appr-SECRET-1234', decision: 'approve' }] })), RoleContextLeakError);
  assert.throws(() => projectSharedDossier({ ...state(), tenantId: undefined }), /tenantId is required/);
  assert.throws(() => projectSharedDossier(state(), { roles: ['nobody'] }), /unknown role/);
  // A role's own instructions never reach the dossier, even when that role is in the set.
  const own = projectSharedDossier(state({ roleSystemPrompts: { planner: 'planner prompt text that is long enough to matter here' } }));
  assert.ok(!JSON.stringify(own.dossier).includes('planner prompt'));
});

test('a leaking context is refused by the engine before any request', async () => {
  const fake = fakeEngine();
  const session = await pinned(fake);
  const r = await session.call({ role: 'reviewer', state: state({ request: 'see tenant-b-secret-notes', otherTenants: { 'tenant-b': ['tenant-b-secret-notes'] } }), instructions: 'r', schema: SCHEMA });
  assert.equal(r.code, 'context_refused');
  assert.equal(fake.calls.length, 0);
});

// ── callers: planner-plan.cjs and code-review.cjs with a session ─────────────

const PLAN = { goal: 'median', context: [], constraints: [], investigation: [], steps: [{ n: 1, do: 'write', done_when: 'done' }], capabilities: ['read'], approval_boundaries: [], verification: [], completion: 'done', non_goals: [] };
const APPROVE = { verdict: 'approve', summary: 'fine', findings: [] };

test('planner with a session: one streamed call on the pinned model, plan validated, schema only with the flag', async () => {
  const fake = fakeEngine({ replies: [streamOf(JSON.stringify(PLAN)), streamOf(JSON.stringify(PLAN))] });
  const session = await pinned(fake, { provider: { capabilities: { jsonSchemaParam: true } } });
  const planner = createPlannerPlan({ enabled: () => false, engine: () => { throw Error('engine() is not consulted with a session'); } });
  const r = await planner.generate({ state: state(), session });
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.deepEqual(r.plan, PLAN);
  assert.equal(fake.calls[0].body.model, MODEL);
  assert.ok(!('response_format' in fake.calls[0].body));
  const on = createPlannerPlan({ enabled: () => true, engine: () => ({}) });
  assert.equal((await on.generate({ state: state(), session })).ok, true);
  assert.deepEqual(fake.calls[1].body.response_format.json_schema.schema, PLAN_ARTIFACT_SCHEMA);
});

test('planner with a session: a model mismatch fails closed with a plain reason', async () => {
  const fake = fakeEngine();
  const session = await pinned(fake);
  fake.engineState.loaded = [OTHER];
  const r = await createPlannerPlan({ engine: () => ({}) }).generate({ state: state(), session });
  assert.deepEqual([r.ok, r.code], [false, 'model_mismatch']);
});

test('review with a role engine: streamed verdict on the pinned model; a mismatch refuses rather than swaps', async () => {
  const fake = fakeEngine({ replies: [streamOf(JSON.stringify(APPROVE))] });
  const roleEngine = engineFor(fake);
  const review = createPlannerReview({ enabled: () => true, roleEngine });
  const r = await review.review({ state: state() });
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.equal(r.verdict.verdict, 'approve');
  assert.equal(fake.calls[0].body.model, MODEL);
  assert.equal(fake.calls[0].body.stream, true);
  fake.engineState.loaded = [OTHER];
  const refused = await review.review({ state: state() });
  assert.deepEqual([refused.ok, refused.code], [false, 'model_mismatch']);
  assert.equal(fake.calls.length, 1);
  // An external provider is refused, as before.
  const ext = await createPlannerReview({ enabled: () => true, roleEngine: engineFor(fakeEngine(), { external: true }) }).review({ state: state() });
  assert.equal(ext.ok, false);
  // The reviewer's persona carries the diff; the prefix carries none of it.
  const own = projectRoleContext('reviewer', state()).projection;
  assert.ok('change' in own);
  assert.ok(!fake.calls[0].body.messages[1].content.includes('median.js'));
  assert.ok(fake.calls[0].body.messages[2].content.includes('median.js'));
});
