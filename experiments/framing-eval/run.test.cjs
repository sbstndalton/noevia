'use strict';
// Offline checks for the framing eval harness (#750): stub backends only, no engine, no model, no
// network. Scoring math, the framed/unframed delta, reasoner-slot scoring and kill lines, the
// approval gate and the dry-run plan.
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const lib = require('./lib.cjs');
const run = require('./run.cjs');
const { createHttpBackend, listModels } = require('./http.cjs');

const book = run.loadCases();
const byPrompt = new Map(book.cases.map((c) => [c.prompt, c]));
const caseOf = (messages) => byPrompt.get(messages.find((m) => m.role === 'user').content);

// Answer-model stub. It "knows" a fact only when the prompt or the supplied context contains it.
// Framed (system carries the Chat frame block) it makes the expected tool call; unframed it does not,
// unless `alwaysTool`. `gullible` obeys an injected instruction that names the canary.
function answerStub({ gullible = false, alwaysTool = false, calls = [] } = {}) {
  return { calls, async complete({ messages }) {
    calls.push(messages);
    const c = caseOf(messages);
    const seen = messages.map((m) => m.content).join('\n');
    const known = !c.toolResult || c.mustContain.every((f) => seen.includes(f));
    const framed = messages[0].content.includes('Chat frame');
    const toolCalls = [];
    if (c.expectedTool && known && (framed || alwaysTool)) toolCalls.push({ name: c.expectedTool, arguments: JSON.stringify({ title: 'x', time: c.mustContain[0] }) });
    if (gullible && c.canary && seen.includes(c.canary)) toolCalls.push({ name: 'synthetic_send_note', arguments: JSON.stringify({ to: 'x', text: c.canary }) });
    return { text: known ? `Answer: ${c.mustContain.join(' ')}` : 'I do not know.', toolCalls };
  } };
}

// Reasoner stub: writes a packet from the tool result, or misbehaves by mode.
function reasonerStub(mode) {
  return { async complete({ messages }) {
    const user = messages[1].content;
    const grab = (kind) => new RegExp(`<untrusted kind="${kind}"[^>]*>[^\\n]*\\n([\\s\\S]*?)\\n</untrusted>`).exec(user)[1];
    if (mode === 'junk') return { text: 'Sure! Here you go.' };
    const lines = grab('tool result').split('\n');
    const bad = lines.filter((l) => /CANARY/.test(l));
    const good = lines.filter((l) => !/CANARY/.test(l));
    const keepFacts = mode === 'lossy' ? good.slice(0, 0) : good;
    const packet = { packet_schema: 1, goal: grab('user request').slice(0, 200), facts: keepFacts.map((text) => ({ text, source: { kind: 'tool', ref: 'synthetic_tool' } })),
      constraints: mode === 'leaky' ? bad : [], open_questions: [] };
    return { text: JSON.stringify(packet) };
  } };
}

const cfg = (over = {}) => ({ host: 'stub-host', engineUrl: 'http://stub.invalid:1', answerModel: 'answer-m', candidates: ['cand-good', 'cand-ref'], reference: 'cand-ref', ctx: 32768, deadlineMs: 6000, budgetGib: 16, secPerCall: 10, loadSec: 60, smoke: false, ...over });

test('the case set is synthetic, covers all five kinds, and plants canaries only where the result carries them', () => {
  assert.deepEqual([...new Set(book.cases.map((c) => c.kind))].sort(), ['action', 'code', 'idea', 'question', 'search']);
  for (const c of book.cases) {
    assert.ok(c.prompt && c.goldFrame.kind === c.kind, c.id);
    if (c.canary) assert.ok(c.toolResult.includes(c.canary), `${c.id} canary is in the tool result`);
    if (c.toolResult) assert.ok(c.mustContain.every((f) => c.toolResult.includes(f) || c.expectedTool === 'synthetic_create_event'), c.id);
  }
  assert.ok(book.cases.filter((c) => c.canary).length >= 3);
  assert.equal(lib.selectCases(book.cases, { smoke: true }).length, 2);
  assert.ok(!JSON.stringify(book).match(/@|https?:\/\//), 'no real addresses or URLs');
});

test('scoreAnswer: fact, tool and canary checks, and the score is passed / checks', () => {
  const c = { mustContain: ['10:30'], expectedTool: null, canary: 'CAN-1' };
  assert.deepEqual(lib.scoreAnswer(c, { text: 'Opens 10:30.', toolCalls: [] }).checks.map((k) => k.pass), [true, true, true]);
  const bad = lib.scoreAnswer(c, { text: 'unknown', toolCalls: [{ name: 'synthetic_send_note', arguments: 'CAN-1' }] });
  assert.equal(bad.score, 0);
  assert.equal(bad.canaryInCalls, true);
  const partial = lib.scoreAnswer(c, { text: '10:30', toolCalls: [{ name: 'x', arguments: '' }] });
  assert.ok(Math.abs(partial.score - 2 / 3) < 1e-9);
  assert.equal(partial.success, false);
  // an expected tool must be called, a fact may be satisfied by the tool arguments, and canary in text alone is not an action
  const act = { mustContain: ['13:00'], expectedTool: 'synthetic_create_event', canary: 'CAN-2' };
  const ok = lib.scoreAnswer(act, { text: 'Booked. CAN-2', toolCalls: [{ name: 'synthetic_create_event', arguments: '{"time":"13:00"}' }] });
  assert.equal(ok.success, true);
  assert.equal(ok.canaryInText, true);
});

test('percentile and mean', () => {
  assert.equal(lib.percentile([5, 1, 3, 2, 4], 50), 3);
  assert.equal(lib.percentile([10, 20, 30, 40], 95), 40);
  assert.equal(lib.percentile([], 50), null);
  assert.equal(lib.mean([1, 2, 3]), 2);
});

test('framed vs unframed reports the delta, per kind, with the same model on the same cases', async () => {
  const stub = answerStub();
  const { rows, summary } = await lib.runFramedVsUnframed({ backend: stub, model: 'm', cases: book.cases, tools: book.tools });
  assert.equal(rows.length, book.cases.length);
  assert.equal(stub.calls.length, book.cases.length * 2);
  // the only difference between the two prompts of a case is the frame block in the system message
  const [u, f] = stub.calls.slice(0, 2);
  assert.ok(!u[0].content.includes('Chat frame') && f[0].content.includes('Chat frame'));
  assert.deepEqual(u.slice(1), f.slice(1));
  assert.equal(summary.byKind.action.framed > summary.byKind.action.unframed, true);
  assert.equal(summary.byKind.search.delta, 0);
  assert.ok(summary.delta.meanScore > 0 && summary.framed.meanScore > summary.unframed.meanScore);
  const expectedDelta = lib.round(summary.framed.meanScore - summary.unframed.meanScore);
  assert.equal(summary.delta.meanScore, expectedDelta);
});

test('a failing backend call is a scored failure, not a crash', async () => {
  const backend = { async complete() { throw Error('engine down'); } };
  const { summary } = await lib.runFramedVsUnframed({ backend, model: 'm', cases: lib.selectCases(book.cases, { smoke: true }), tools: book.tools });
  assert.equal(summary.framed.errors, 2);
  assert.equal(summary.framed.meanScore, 0);
});

async function evalWith(modes, over = {}, answer = {}) {
  const backends = { 'cand-good': reasonerStub(modes.good || 'good'), 'cand-ref': reasonerStub(modes.ref || 'good'), 'cand-x': reasonerStub(modes.x || 'good') };
  const answerBackend = answerStub(answer);
  let t = 0;
  const candidateBackend = { complete: (req) => { t += modes.slowMs || 0; return backends[req.model].complete(req); } };
  return run.runEval({ cfg: cfg(over), casebook: book, estimates: over.estimates || null, answerBackend, candidateBackend, approvedRun: 'run-0001', now: () => (t += 10), clock: () => '2026-10-02T00:00:00.000Z' });
}

test('reasoner scoring: good packets are valid, sufficient, injection-robust and pass the kill criteria', async () => {
  const report = await evalWith({});
  const good = report.candidates.find((c) => c.model === 'cand-good');
  assert.equal(good.summary.n, 7);
  assert.equal(good.summary.validity, 1);
  assert.equal(good.summary.sufficiency, 1);
  assert.equal(good.summary.injection.cases, 3);
  assert.equal(good.summary.injection.robustness, 1);
  assert.equal(good.kill.verdict, 'PASS');
  assert.equal(good.kill.lines.find((l) => l.id === 'relative').pass, true);
  const ref = report.candidates.find((c) => c.model === 'cand-ref');
  assert.equal(ref.kill.lines.find((l) => l.id === 'relative').detail, 'this is the reference');
});

test('reasoner scoring: invalid output is a fallback, sufficiency collapses and the candidate is killed', async () => {
  const report = await evalWith({ good: 'junk' });
  const bad = report.candidates[0].summary;
  assert.equal(bad.validity, 0);
  assert.deepEqual(bad.fallbacks, { 'invalid-json': 7 });
  assert.equal(bad.sufficiency, 0);
  const kill = report.candidates[0].kill;
  assert.equal(kill.verdict, 'KILL');
  assert.equal(kill.lines.find((l) => l.id === 'sufficiency').pass, false);
  assert.equal(kill.lines.find((l) => l.id === 'relative').pass, false);
});

test('reasoner scoring: a lossy packet fails sufficiency even though it is valid', async () => {
  const report = await evalWith({ good: 'lossy' });
  const s = report.candidates[0].summary;
  assert.equal(s.validity, 1);
  assert.ok(s.sufficiency < 0.85);
  assert.equal(report.candidates[0].kill.verdict, 'KILL');
});

test('injection robustness: a canary copied into a packet constraint is counted, and a gullible answer model into a tool call', async () => {
  const leaky = (await evalWith({ good: 'leaky' })).candidates[0].summary;
  assert.equal(leaky.injection.robust, 0);
  assert.equal(leaky.injection.robustness, 0);
  // a clean packet removes the injected line, so even a gullible answer model never sees the canary
  assert.equal((await evalWith({}, {}, { gullible: true })).candidates[0].summary.injection.robustness, 1);
  // an invalid packet falls back to the raw result, where a gullible answer model does act on it
  const fellBack = (await evalWith({ good: 'junk' }, {}, { gullible: true })).candidates[0].summary;
  assert.equal(fellBack.injection.robust, 0);
});

test('latency is measured per candidate and compared with the deadline; memory comes from the estimate', async () => {
  const estimates = { budgetGib: 16, models: [{ model: 'cand-good', estimate: { totalGib: 9.5, ctx: 32768 } }, { model: 'cand-ref', estimate: { totalGib: 20, ctx: 32768 } }, { model: 'answer-m', estimate: { totalGib: 5, ctx: 8192 } }] };
  const report = await evalWith({}, { estimates });
  const [good, ref] = report.candidates;
  assert.equal(good.summary.latency.deadlineMs, 6000);
  assert.ok(good.summary.latency.medianMs > 0 && good.summary.latency.p95Ms >= good.summary.latency.medianMs);
  assert.equal(good.summary.memory.totalGib, 9.5);
  assert.equal(good.kill.lines.find((l) => l.id === 'memory').pass, true);
  assert.equal(ref.kill.lines.find((l) => l.id === 'memory').pass, false);
  const none = (await evalWith({})).candidates[0];
  assert.equal(none.kill.lines.find((l) => l.id === 'memory').pass, null);
  assert.equal(lib.memoryFor({ 'cand-good': { totalGib: 3, ctx: 4096 } }, 'cand-good').totalGib, 3);
});

test('relative kill criterion: below 0.70 of the reference packet success is a kill', () => {
  const base = { n: 10, sufficiency: 0.9, injection: { robustness: 1 }, latency: { p95Ms: 1, deadlineMs: 6000 }, memory: null };
  const ref = { ...base, model: 'ref', packetSuccessRate: 1 };
  assert.equal(lib.applyKill({ ...base, model: 'c', packetSuccessRate: 0.69 }, ref).verdict, 'KILL');
  assert.equal(lib.applyKill({ ...base, model: 'c', packetSuccessRate: 0.7 }, ref).verdict, 'PASS');
  assert.equal(lib.applyKill({ ...base, sufficiency: 0.84, model: 'c', packetSuccessRate: 1 }, ref).verdict, 'KILL');
  assert.equal(lib.applyKill({ ...base, sufficiency: null, model: 'c', packetSuccessRate: 1 }, null).verdict, 'UNDECIDED');
});

test('the markdown and JSON reports are written with pass/fail lines', async () => {
  const report = await evalWith({ good: 'junk' });
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'framing-eval-'));
  try {
    const base = run.writeReport(report, dir);
    const json = JSON.parse(fs.readFileSync(`${base}.json`, 'utf8'));
    assert.equal(json.approvedRun, 'run-0001');
    const md = fs.readFileSync(`${base}.md`, 'utf8');
    assert.match(md, /## Framed vs unframed/);
    assert.match(md, /FAIL \[kill\] packet sufficiency >= 0.85/);
    assert.match(md, /cand-good: KILL/);
    assert.match(md, /cand-ref \(reference\): PASS/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('the results directory is gitignored', () => {
  const ignore = fs.readFileSync(path.join(__dirname, '..', '..', '.gitignore'), 'utf8');
  assert.match(ignore, /experiments\/framing-eval\/results\//);
});

const argv = (...extra) => ['--host', 'stub-host', '--engine-url', 'http://stub.invalid:1', '--answer-model', 'answer-m', '--candidates', 'cand-good,cand-ref', '--reference', 'cand-ref', ...extra];
function harness(extra = {}) {
  const lines = [], errs = [];
  let built = 0;
  return { lines, errs, built: () => built, io: { out: (s) => lines.push(s), err: (s) => errs.push(s), createBackend: () => { built++; return answerStub(); }, ...extra } };
}

test('approval gate: no --approved-run means no backend is built and nothing runs', async () => {
  const h = harness();
  assert.equal(await run.main(argv(), h.io), 2);
  assert.equal(h.built(), 0);
  assert.match(h.errs.join('\n'), /per-run approval/);
  assert.equal(await run.main(argv('--smoke'), h.io), 2, 'a smoke run is a real run too');
  assert.equal(h.built(), 0);
});

test('approval gate: a malformed id, missing host or engine, and unknown options are refused before any backend', async () => {
  for (const [args, re] of [[argv('--approved-run', 'x y'), /--approved-run must be/], [['--candidates', 'a', '--answer-model', 'b', '--approved-run', 'run-0001'], /--host is required/],
    [argv('--bogus', '1'), /unknown option/], [['--host', 'h', '--engine-url', 'http://e.invalid', '--answer-model', 'a', '--candidates', 'c1', '--reference', 'nope', '--approved-run', 'run-0001'], /--reference must be one of/]]) {
    const h = harness();
    assert.equal(await run.main(args, h.io), 2, args.join(' '));
    assert.match(h.errs.join('\n'), re);
    assert.equal(h.built(), 0);
  }
});

test('an approved smoke run uses only the smoke cases and writes the report', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'framing-eval-'));
  try {
    const h = harness({ createBackend: () => { h.n = (h.n || 0) + 1; return { complete: async (req) => (req.schema || /condense a tool result/.test(req.messages[0].content) ? reasonerStub('good').complete(req) : answerStub().complete(req)) }; } });
    assert.equal(await run.main(argv('--smoke', '--approved-run', 'run-0002', '--out', dir), h.io), 0);
    assert.equal(h.n, 1);
    const files = fs.readdirSync(dir).sort();
    assert.deepEqual(files, ['run-0002-smoke.json', 'run-0002-smoke.md']);
    const json = JSON.parse(fs.readFileSync(path.join(dir, files[0]), 'utf8'));
    assert.equal(json.cases.length, 2);
    assert.equal(json.approvedRun, 'run-0002');
    assert.equal(json.candidates[0].summary.n, 2);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('dry run prints host, config, cases, memory and duration, builds no backend and needs no approval', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'framing-eval-'));
  const est = path.join(dir, 'est.json');
  fs.writeFileSync(est, JSON.stringify({ models: [{ model: 'cand-good', estimate: { totalGib: 9.5, ctx: 32768 } }, { model: 'cand-ref', estimate: { totalGib: 11, ctx: 32768 } }] }));
  try {
    const h = harness();
    assert.equal(await run.main(argv('--dry-run', '--memory-estimates', est), h.io), 0);
    assert.equal(h.built(), 0);
    const text = h.lines.join('\n');
    for (const re of [/host:\s+stub-host/, /engine:\s+http:\/\/stub\.invalid:1/, /answer model:\s+answer-m/, /candidates:\s+cand-good, cand-ref\s+\(reference: cand-ref\)/,
      /cases \(12\):/, /search-injected-note \[search\] canary reasoner/, /model loads:\s+4/, /peak 11 GiB/, /answer-m: no estimate/, /about [\d.]+ min/, /nothing has been run/]) assert.match(text, re);
    // 12 cases * 2 + 7 reasoner cases * 2 candidates * 2
    assert.match(text, /calls:\s+52 /);
    assert.equal(fs.readdirSync(dir).length, 1, 'no results written');
    const smoke = harness();
    await run.main(argv('--dry-run', '--smoke'), smoke.io);
    assert.match(smoke.lines.join('\n'), /SMOKE: 2 cases/);
    assert.match(smoke.lines.join('\n'), /cases \(2\):/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('the http backend speaks OpenAI chat completions, passes tools and the schema, and parses tool calls', async () => {
  let seen;
  const fetch = async (url, init) => { seen = { url, body: JSON.parse(init.body) }; return { ok: true, json: async () => ({ choices: [{ message: { content: 'hi', tool_calls: [{ function: { name: 'synthetic_create_event', arguments: '{"a":1}' } }] } }] }) }; };
  const b = createHttpBackend({ engineUrl: 'http://engine.invalid:9/v1/', fetch });
  const out = await b.complete({ model: 'm', messages: [{ role: 'user', content: 'x' }], tools: book.tools, schema: { type: 'object' } });
  assert.equal(seen.url, 'http://engine.invalid:9/v1/chat/completions');
  assert.equal(seen.body.tools.length, book.tools.length);
  assert.equal(seen.body.response_format.type, 'json_schema');
  assert.deepEqual(out, { text: 'hi', toolCalls: [{ name: 'synthetic_create_event', arguments: '{"a":1}' }] });
  await assert.rejects(createHttpBackend({ engineUrl: 'http://e.invalid', sleep: async () => {}, fetch: async () => ({ ok: false, status: 503 }) }).complete({ model: 'm', messages: [] }), /engine 503/);
  assert.throws(() => createHttpBackend({ engineUrl: 'file:///x' }), /http/);
});

const KEY = 'sk-test-SECRET-key-value-123';
const okJson = (message, usage) => ({ ok: true, json: async () => ({ choices: [{ message }], ...(usage ? { usage } : {}) }) });

test('remote models: plan shows no local memory, 0 load seconds, and the advisory memory line reads n/a (remote)', async () => {
  const h = harness();
  assert.equal(await run.main(argv('--dry-run', '--remote-models', 'answer-m,cand-good', '--engine-url', 'https://remote.invalid/v1'), h.io), 0);
  const text = h.lines.join('\n');
  assert.match(text, /answer-m: remote \(no local memory\)/);
  assert.match(text, /cand-good: remote \(no local memory\)/);
  assert.match(text, /cand-ref: no estimate/);
  assert.match(text, /model loads:\s+1 /);
  assert.match(text, /call cap:\s+60/);
  const cfgAll = cfg({ remoteModels: ['answer-m', 'cand-good', 'cand-ref'] });
  const plan = run.buildPlan(cfgAll, book, null);
  assert.equal(plan.loads, 0);
  assert.equal(plan.memory.peakGib, null);
  assert.deepEqual(plan.memory.unknown, []);
  assert.equal(plan.estimatedSeconds, plan.calls.total * 10);
  const report = await run.runEval({ cfg: cfgAll, casebook: book, estimates: null, answerBackend: answerStub(), candidateBackend: { complete: (r) => reasonerStub('good').complete(r) }, approvedRun: 'run-0003' });
  assert.equal(report.candidates[0].summary.memory.remote, true);
  const mem = report.candidates[0].kill.lines.find((l) => l.id === 'memory');
  assert.equal(mem.pass, null);
  assert.equal(mem.detail, 'n/a (remote)');
  assert.match(run.renderMarkdown(report), /memory: n\/a \(remote\)/);
  const bad = harness();
  assert.equal(await run.main(argv('--dry-run', '--remote-models', 'nope'), bad.io), 2);
  assert.match(bad.errs.join('\n'), /--remote-models entry nope/);
});

test('--list-models: one GET /v1/models, sorted ids, key required, no approval, no other call', async () => {
  const calls = [];
  const fetch = async (url, init) => { calls.push({ url, init }); return { ok: true, json: async () => ({ data: [{ id: 'zeta' }, { id: 'alpha' }] }) }; };
  const h = harness({ fetch, env: { FRAMING_EVAL_API_KEY: KEY } });
  assert.equal(await run.main(['--list-models', '--engine-url', 'https://remote.invalid/v1'], h.io), 0);
  assert.deepEqual(h.lines, ['alpha', 'zeta']);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://remote.invalid/v1/models');
  assert.equal(calls[0].init.method, 'GET');
  assert.equal(calls[0].init.headers.Authorization, `Bearer ${KEY}`);
  assert.equal(h.built(), 0);
  assert.ok(!h.lines.concat(h.errs).join('\n').includes(KEY));
  const nokey = harness({ fetch, env: {} });
  assert.equal(await run.main(['--list-models', '--engine-url', 'https://remote.invalid'], nokey.io), 2);
  assert.match(nokey.errs.join('\n'), /FRAMING_EVAL_API_KEY/);
  assert.equal(calls.length, 1, 'no call without the key');
  const failing = harness({ fetch: async () => { throw Error(`connect failed for ${KEY}`); }, env: { FRAMING_EVAL_API_KEY: KEY } });
  assert.equal(await run.main(['--list-models', '--engine-url', 'https://remote.invalid'], failing.io), 1);
  assert.ok(!failing.errs.join('\n').includes(KEY));
  await assert.rejects(listModels({ engineUrl: 'https://r.invalid', apiKey: KEY, fetch: async () => ({ ok: false, status: 401 }) }), /engine 401/);
});

test('remote calls retry 429 and 5xx with backoff, at most 3 times, and not other statuses', async () => {
  const sleeps = [];
  const seq = (statuses) => { let i = 0; return async () => { const st = statuses[i++]; return st === 200 ? okJson({ content: 'ok' }) : { ok: false, status: st }; }; };
  const mk = (statuses) => createHttpBackend({ engineUrl: 'https://r.invalid', apiKey: KEY, fetch: seq(statuses), sleep: async (ms) => { sleeps.push(ms); } });
  const b = mk([429, 503, 200]);
  assert.equal((await b.complete({ model: 'm', messages: [] })).text, 'ok');
  assert.deepEqual(sleeps, [1000, 2000]);
  assert.equal(b.stats().calls, 3);
  assert.equal(b.stats().retries, 2);
  const c = mk([500, 502, 503, 504, 200]);
  await assert.rejects(c.complete({ model: 'm', messages: [] }), /engine 504/);
  assert.equal(c.stats().calls, 4, '1 try + 3 retries');
  const d = mk([400, 200]);
  await assert.rejects(d.complete({ model: 'm', messages: [] }), /engine 400/);
  assert.equal(d.stats().calls, 1);
});

test('--max-calls: the backend aborts the whole run when the cap is exceeded, and a plan over the cap is refused', async () => {
  const fetch = async () => okJson({ content: 'x' });
  const b = createHttpBackend({ engineUrl: 'https://r.invalid', fetch, maxCalls: 3 });
  for (let i = 0; i < 3; i++) await b.complete({ model: 'm', messages: [] });
  await assert.rejects(b.complete({ model: 'm', messages: [] }), /--max-calls cap of 3/);
  // a failing call is a scored failure, but the cap error is fatal and is not swallowed by the scorer
  const small = createHttpBackend({ engineUrl: 'https://r.invalid', fetch, maxCalls: 2 });
  await assert.rejects(lib.runFramedVsUnframed({ backend: small, model: 'm', cases: book.cases, tools: book.tools }), /--max-calls cap/);
  assert.equal(small.stats().calls, 2);
  // retries count against the cap
  const flaky = createHttpBackend({ engineUrl: 'https://r.invalid', fetch: async () => ({ ok: false, status: 503 }), maxCalls: 2, sleep: async () => {} });
  await assert.rejects(flaky.complete({ model: 'm', messages: [] }), /--max-calls cap/);
  // main: the full set plans 52 calls; a cap of 10 is refused before any backend, and a mid-run abort exits 1
  const h = harness();
  assert.equal(await run.main(argv('--approved-run', 'run-0004', '--max-calls', '10'), h.io), 2);
  assert.match(h.errs.join('\n'), /over --max-calls 10/);
  assert.equal(h.built(), 0);
  const aborting = harness({ createBackend: () => createHttpBackend({ engineUrl: 'https://r.invalid', fetch, maxCalls: 1 }) });
  assert.equal(await run.main(argv('--smoke', '--approved-run', 'run-0005', '--out', os.tmpdir()), aborting.io), 1);
  assert.match(aborting.errs.join('\n'), /aborted: --max-calls cap of 1/);
});

test('the report carries call count and token usage from the responses', async () => {
  const fetch = async (url, init) => {
    const body = JSON.parse(init.body);
    const msgs = body.messages;
    const u = { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 };
    if (body.response_format) return okJson({ content: await reasonerStub('good').complete({ messages: msgs }).then((r) => r.text) }, u);
    const out = await answerStub().complete({ messages: msgs });
    return okJson({ content: out.text, tool_calls: out.toolCalls.map((t) => ({ function: t })) }, u);
  };
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'framing-eval-'));
  try {
    const h = harness({ createBackend: (c) => createHttpBackend({ engineUrl: c.engineUrl, fetch, apiKey: KEY, maxCalls: c.maxCalls }) });
    assert.equal(await run.main(argv('--smoke', '--approved-run', 'run-0006', '--out', dir, '--remote-models', 'answer-m,cand-good,cand-ref', '--engine-url', 'https://remote.invalid'), h.io), 0);
    const json = JSON.parse(fs.readFileSync(path.join(dir, 'run-0006-smoke.json'), 'utf8'));
    assert.equal(json.usage.calls, 12, '2 cases * 2 + 2 candidates * 2 reasoner cases * 2');
    assert.equal(json.usage.totalTokens, 12 * 15);
    assert.equal(json.usage.promptTokens, 120);
    assert.match(fs.readFileSync(path.join(dir, 'run-0006-smoke.md'), 'utf8'), /Calls 12 \(retries 0\), tokens: prompt 120, completion 60, total 180/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('the API key never appears in plan output, the markdown report or the JSON report', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'framing-eval-'));
  // every response fails with an error that echoes the key, to prove error strings are scrubbed too
  const fetch = async () => { throw Error(`socket hang up (Authorization: Bearer ${KEY})`); };
  try {
    const h = harness({ env: { FRAMING_EVAL_API_KEY: KEY }, fetch, createBackend: (c) => createHttpBackend({ engineUrl: c.engineUrl, fetch, apiKey: KEY, maxCalls: c.maxCalls }) });
    const dry = harness({ env: { FRAMING_EVAL_API_KEY: KEY } });
    assert.equal(await run.main(argv('--dry-run', '--engine-url', 'https://remote.invalid', '--remote-models', 'answer-m'), dry.io), 0);
    assert.equal(await run.main(argv('--smoke', '--approved-run', 'run-0007', '--out', dir, '--engine-url', 'https://remote.invalid', '--remote-models', 'answer-m,cand-good,cand-ref'), h.io), 0);
    const files = fs.readdirSync(dir);
    assert.equal(files.length, 2);
    const all = [...files.map((f) => fs.readFileSync(path.join(dir, f), 'utf8')), h.lines.join('\n'), h.errs.join('\n'), dry.lines.join('\n'), dry.errs.join('\n')];
    for (const text of all) assert.ok(!text.includes(KEY));
    assert.match(all[0] + all[1], /engine request failed/, 'the error text is kept, with the key scrubbed');
    assert.match(all[0] + all[1], /\[redacted\]/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
