#!/usr/bin/env node
'use strict';
// Framing eval CLI (#750). Real runs load models and need the owner's per-run approval, so:
//   --dry-run                 prints the plan (host, config, cases, estimated memory and duration); touches nothing
//   --smoke                   limits the case set to the two smoke cases
//   --remote-models a,b       ids served by a remote OpenAI-compatible API: no memory estimate, 0 load seconds
//   --max-calls <n>           safety cap on API calls (default 60); a run over it is refused, or aborted when retries exceed it
//   --list-models             read-only GET <engine>/v1/models; needs FRAMING_EVAL_API_KEY, no --approved-run
//   --approved-run <id>       REQUIRED for any run that calls an engine; the id is recorded in the report
// Without --dry-run and without --approved-run the process exits with code 2 before building a backend.
// Results go to experiments/framing-eval/results/ (gitignored): <run id>.json and <run id>.md.
//
//   node experiments/framing-eval/run.cjs --dry-run --host daserver --engine-url http://HOST:PORT \
//     --answer-model A --candidates B,C --reference C --memory-estimates estimates.json
const fs = require('node:fs'), path = require('node:path');
const lib = require('./lib.cjs');
const http = require('./http.cjs');

const FLAGS = new Set(['dry-run', 'smoke', 'list-models']);
const VALUE_FLAGS = new Set(['host', 'engine-url', 'answer-model', 'candidates', 'reference', 'memory-estimates', 'budget-gib', 'deadline-ms', 'sec-per-call', 'load-sec', 'approved-run', 'out', 'cases', 'remote-models', 'max-calls']);

function parseArgs(argv) {
  const out = { candidates: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) throw Error(`unexpected argument ${a}`);
    const [k, inline] = a.slice(2).split(/=(.*)/s);
    if (FLAGS.has(k)) { out[k] = true; continue; }
    if (!VALUE_FLAGS.has(k)) throw Error(`unknown option --${k}`);
    const v = inline !== undefined ? inline : argv[++i];
    if (v === undefined || v.startsWith('--')) throw Error(`--${k} needs a value`);
    out[k] = v;
  }
  const ids = (v) => String(v || '').split(',').map((x) => x.trim()).filter(Boolean);
  out.candidates = ids(out.candidates);
  out['remote-models'] = ids(out['remote-models']);
  for (const k of ['budget-gib', 'deadline-ms', 'sec-per-call', 'load-sec', 'max-calls']) if (out[k] !== undefined && !(Number(out[k]) > 0)) throw Error(`--${k} must be a positive number`);
  return out;
}

function loadCases(file) { return JSON.parse(fs.readFileSync(file || path.join(__dirname, 'cases.json'), 'utf8')); }
function loadEstimates(file) { return file ? JSON.parse(fs.readFileSync(file, 'utf8')) : null; }

function config(args) {
  return {
    host: args.host || null, engineUrl: args['engine-url'] || null,
    answerModel: args['answer-model'] || null, candidates: args.candidates, reference: args.reference || null,
    ctx: lib.REASONER_CTX, deadlineMs: Number(args['deadline-ms']) || 6000, budgetGib: Number(args['budget-gib']) || 16,
    secPerCall: Number(args['sec-per-call']) || 10, loadSec: Number(args['load-sec']) || 60, smoke: !!args.smoke,
    remoteModels: args['remote-models'] || [], maxCalls: Number(args['max-calls']) || http.DEFAULT_MAX_CALLS,
  };
}

/** Argument problems for a run (or a dry run). Empty list = ok. */
function validate(cfg) {
  const p = [];
  if (!cfg.host) p.push('--host is required (a label for where the engine runs)');
  if (!cfg.engineUrl) p.push('--engine-url is required');
  if (!cfg.answerModel) p.push('--answer-model is required');
  if (!cfg.candidates.length) p.push('--candidates is required (comma separated model ids)');
  for (const m of cfg.remoteModels || []) if (m !== cfg.answerModel && !cfg.candidates.includes(m)) p.push(`--remote-models entry ${m} is neither the answer model nor a candidate`);
  if (cfg.reference && !cfg.candidates.includes(cfg.reference)) p.push('--reference must be one of --candidates');
  return p;
}

/** Everything a run would do, computed without touching an engine. */
function buildPlan(cfg, casebook, estimates) {
  const cases = lib.selectCases(casebook.cases, { smoke: cfg.smoke });
  const reasonerCases = cases.filter(lib.hasReasonerResult);
  const sequence = [cfg.answerModel, ...cfg.candidates, cfg.answerModel].filter((m, i, a) => i === 0 || m !== a[i - 1]);
  const remote = new Set(cfg.remoteModels || []);
  const models = [...new Set([cfg.answerModel, ...cfg.candidates])].map((m) => (remote.has(m) ? { model: m, remote: true, memory: null } : { model: m, remote: false, memory: lib.memoryFor(estimates, m) }));
  const known = models.filter((m) => m.memory);
  const loads = sequence.filter((m) => !remote.has(m)).length;
  const calls = { framedVsUnframed: cases.length * 2, reasoner: reasonerCases.length * cfg.candidates.length, packetAnswers: reasonerCases.length * cfg.candidates.length };
  const totalCalls = calls.framedVsUnframed + calls.reasoner + calls.packetAnswers;
  const kinds = {};
  for (const c of cases) kinds[c.kind] = (kinds[c.kind] || 0) + 1;
  return {
    config: cfg, cases: cases.map((c) => ({ id: c.id, kind: c.kind, canary: !!c.canary, reasoner: lib.hasReasonerResult(c) })), kinds,
    loadSequence: sequence, loads, maxCalls: cfg.maxCalls, calls: { ...calls, total: totalCalls },
    memory: { models, peakGib: known.length ? Math.max(...known.map((m) => m.memory.totalGib)) : null, unknown: models.filter((m) => !m.remote && !m.memory).map((m) => m.model),
      note: 'one model resident at a time; peak = the largest single model' },
    estimatedSeconds: totalCalls * cfg.secPerCall + loads * cfg.loadSec,
  };
}

function formatPlan(plan) {
  const c = plan.config;
  const peak = plan.memory.peakGib;
  const mins = (plan.estimatedSeconds / 60).toFixed(1);
  return [
    `framing eval plan${c.smoke ? ' (SMOKE: 2 cases)' : ''}  -- nothing has been run`,
    `host:            ${c.host || '(unset)'}`,
    `engine:          ${c.engineUrl || '(unset)'}`,
    `answer model:    ${c.answerModel || '(unset)'}`,
    `candidates:      ${c.candidates.join(', ') || '(none)'}${c.reference ? `  (reference: ${c.reference})` : ''}`,
    `reasoner ctx:    ${c.ctx}   deadline ${c.deadlineMs} ms   budget ${c.budgetGib} GiB`,
    `cases (${plan.cases.length}):      ${Object.entries(plan.kinds).map(([k, n]) => `${k} ${n}`).join(', ')}`,
    ...plan.cases.map((x) => `  - ${x.id} [${x.kind}]${x.canary ? ' canary' : ''}${x.reasoner ? ' reasoner' : ''}`),
    `model loads:     ${plan.loads}  (${plan.loadSequence.join(' -> ')})`,
    `calls:           ${plan.calls.total}  (framed/unframed ${plan.calls.framedVsUnframed}, reasoner ${plan.calls.reasoner}, packet answers ${plan.calls.packetAnswers})`,
    `memory:          peak ${peak == null ? 'unknown' : `${peak} GiB`} (${plan.memory.note})`,
    ...plan.memory.models.map((m) => `  - ${m.model}: ${m.remote ? 'remote (no local memory)' : m.memory ? `${m.memory.totalGib} GiB at ${m.memory.ctx || '?'} ctx${m.memory.ctx === lib.REASONER_CTX ? '' : ' (not the 32768 reasoner ctx)'}` : 'no estimate'}`),
    ...(c.remoteModels?.length ? [`remote models:   ${c.remoteModels.join(', ')}  (remote OpenAI-compatible API; 0 load seconds)`] : []),
    `call cap:        ${plan.maxCalls} (--max-calls; the run aborts when exceeded)`,
    `duration:        about ${mins} min (${c.secPerCall} s/call, ${c.loadSec} s/load; an estimate)`,
    'To run, the owner approves host, config, cases, memory and duration, then pass --approved-run <id>. Start with --smoke.',
  ].join('\n');
}

/** The whole run against injected backends (tests) or the real one. Phase order keeps model loads to a minimum. */
async function runEval({ cfg, casebook, estimates, answerBackend, candidateBackend = answerBackend, approvedRun, now = Date.now, clock = () => new Date().toISOString() }) {
  const cases = lib.selectCases(casebook.cases, { smoke: cfg.smoke });
  const tools = casebook.tools;
  const startedAt = clock();
  const framed = await lib.runFramedVsUnframed({ backend: answerBackend, model: cfg.answerModel, cases, tools, now });
  const rawRows = {};
  for (const r of framed.rows) rawRows[r.id] = r.framed;
  const candidates = [];
  for (const model of cfg.candidates) {
    const run = await lib.runReasonerCandidate({ backend: candidateBackend, model, answerBackend, answerModel: cfg.answerModel, cases, tools, rawRows, deadlineMs: cfg.deadlineMs, now });
    candidates.push({ ...run, summary: lib.summarizeCandidate(run, { remote: (cfg.remoteModels || []).includes(model), memory: lib.memoryFor(estimates, model), budgetGib: cfg.budgetGib, deadlineMs: cfg.deadlineMs }) });
  }
  const reference = candidates.find((c) => c.model === cfg.reference)?.summary || null;
  for (const c of candidates) c.kill = lib.applyKill(c.summary, reference, cfg.budgetGib);
  return { approvedRun, startedAt, finishedAt: clock(), usage: typeof answerBackend.stats === 'function' ? answerBackend.stats() : null, smoke: cfg.smoke, config: cfg, cases: cases.map((c) => c.id), framedVsUnframed: framed, candidates };
}

const mark = (p) => (p === null ? 'n/a' : p ? 'PASS' : 'FAIL');
function renderMarkdown(report) {
  const f = report.framedVsUnframed.summary;
  const L = [`# Framing eval ${report.approvedRun}${report.smoke ? ' (smoke)' : ''}`, '',
    `Host ${report.config.host}, answer model ${report.config.answerModel}, ${report.cases.length} cases, ${report.startedAt} to ${report.finishedAt}.`, '',
    '## Framed vs unframed', '', '| | framed | unframed | delta |', '| --- | --- | --- | --- |',
    `| mean score | ${f.framed.meanScore} | ${f.unframed.meanScore} | ${f.delta.meanScore} |`,
    `| success rate | ${f.framed.successRate} | ${f.unframed.successRate} | ${f.delta.successRate} |`,
    `| errors | ${f.framed.errors} | ${f.unframed.errors} | |`, '', '| kind | n | framed | unframed | delta |', '| --- | --- | --- | --- | --- |',
    ...Object.entries(f.byKind).map(([k, v]) => `| ${k} | ${v.n} | ${v.framed} | ${v.unframed} | ${v.delta} |`), '',
    `Framed not worse than unframed (advisory): ${mark(f.delta.meanScore >= 0)}`, '', '## Reasoner-slot candidates', ''];
  if (report.usage) L.splice(2, 0, `Calls ${report.usage.calls} (retries ${report.usage.retries}), tokens: prompt ${report.usage.promptTokens}, completion ${report.usage.completionTokens}, total ${report.usage.totalTokens}${report.usage.callsWithoutUsage ? ` (${report.usage.callsWithoutUsage} responses carried no usage)` : ''}.`, '');
  for (const c of report.candidates) {
    const s = c.summary;
    L.push(`### ${c.model}${report.config.reference === c.model ? ' (reference)' : ''}: ${c.kill.verdict}`, '',
      `- packet validity: ${s.validity} (${s.validCount}/${s.n})${Object.keys(s.fallbacks).length ? `, fallbacks ${JSON.stringify(s.fallbacks)}` : ''}`,
      `- packet success ${s.packetSuccessRate} vs raw-result success ${s.rawSuccessRate}; sufficiency ${s.sufficiency}`,
      `- injection robustness: ${s.injection.robustness} (${s.injection.robust}/${s.injection.cases}); canary in facts ${s.injection.canaryInFacts} (facts are data)`,
      `- latency: median ${s.latency.medianMs} ms, p95 ${s.latency.p95Ms} ms, over deadline ${s.latency.overDeadline}`,
      `- memory: ${s.memory?.remote ? 'n/a (remote)' : s.memory ? `${s.memory.totalGib} GiB at ${s.memory.ctx} ctx` : 'no estimate'}`, '',
      ...c.kill.lines.map((l) => `- ${mark(l.pass)} ${l.kill ? '[kill]' : '[advisory]'} ${l.label} (${l.detail})`), '');
  }
  return L.join('\n');
}

function writeReport(report, dir) {
  fs.mkdirSync(dir, { recursive: true });
  const base = path.join(dir, `${report.approvedRun}${report.smoke ? '-smoke' : ''}`);
  fs.writeFileSync(`${base}.json`, JSON.stringify(report, null, 2));
  fs.writeFileSync(`${base}.md`, renderMarkdown(report));
  return base;
}

/** CLI entry. `io` and `deps` are injectable for tests. Returns the exit code. */
async function main(argv, { out = (s) => process.stdout.write(`${s}\n`), err = (s) => process.stderr.write(`${s}\n`), createBackend = null, casebook = null, fetch: fetchImpl = globalThis.fetch, env = process.env } = {}) {
  let args;
  try { args = parseArgs(argv); } catch (e) { err(`error: ${e.message}`); return 2; }
  const cfg = config(args);
  if (args['list-models']) {
    // read-only: one GET /v1/models, no inference, so no approval; it still needs the key and makes no other call
    if (!cfg.engineUrl) { err('error: --engine-url is required'); return 2; }
    if (!env.FRAMING_EVAL_API_KEY) { err('error: set FRAMING_EVAL_API_KEY (the key is read from the environment and never printed)'); return 2; }
    try { for (const id of await http.listModels({ engineUrl: cfg.engineUrl, fetch: fetchImpl, apiKey: env.FRAMING_EVAL_API_KEY })) out(id); return 0; } catch (e) { err(`error: ${e.message}`); return 1; }
  }
  const problems = validate(cfg);
  if (problems.length) { err(`error: ${problems.join('; ')}`); return 2; }
  let plan, book, estimates;
  try { book = casebook || loadCases(args.cases); estimates = loadEstimates(args['memory-estimates']); plan = buildPlan(cfg, book, estimates); } catch (e) { err(`error: ${e.message}`); return 2; }
  if (args['dry-run']) { out(formatPlan(plan)); return 0; }
  if (!args['approved-run']) {
    err('refused: a real run loads models and needs the owner\'s per-run approval. Review the plan below, get the approval, then pass --approved-run <id>.');
    err(formatPlan(plan));
    return 2;
  }
  if (!lib.APPROVED_RUN_ID.test(args['approved-run'])) { err('refused: --approved-run must be 4-64 characters of letters, digits, dot, dash or underscore'); return 2; }
  if (plan.calls.total > cfg.maxCalls) { err(`refused: the plan needs ${plan.calls.total} calls, over --max-calls ${cfg.maxCalls}. Use --smoke, fewer candidates, or raise --max-calls on purpose.`); return 2; }
  const backend = (createBackend || ((c) => http.createHttpBackend({ engineUrl: c.engineUrl, apiKey: env.FRAMING_EVAL_API_KEY || '', maxCalls: c.maxCalls, fetch: fetchImpl })))(cfg);
  out(formatPlan(plan));
  let report;
  try { report = await runEval({ cfg, casebook: book, estimates, answerBackend: backend, approvedRun: args['approved-run'] }); } catch (e) {
    err(`aborted: ${e.message}`);
    if (typeof backend.stats === 'function') err(`calls made: ${backend.stats().calls}`);
    return 1;
  }
  const base = writeReport(report, path.resolve(args.out || path.join(__dirname, 'results')));
  out(`\nreport: ${base}.md and ${base}.json`);
  for (const c of report.candidates) out(`${c.model}: ${c.kill.verdict}`);
  return 0;
}

if (require.main === module) main(process.argv.slice(2)).then((code) => process.exit(code), (e) => { console.error(e); process.exit(1); });

module.exports = { parseArgs, config, validate, buildPlan, formatPlan, runEval, renderMarkdown, writeReport, main, loadCases };
