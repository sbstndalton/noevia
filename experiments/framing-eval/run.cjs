#!/usr/bin/env node
'use strict';
// Framing eval CLI (#750). Real runs load models and need the owner's per-run approval, so:
//   --dry-run                 prints the plan (host, config, cases, estimated memory and duration); touches nothing
//   --smoke                   limits the case set to the two smoke cases
//   --approved-run <id>       REQUIRED for any run that calls an engine; the id is recorded in the report
// Without --dry-run and without --approved-run the process exits with code 2 before building a backend.
// Results go to experiments/framing-eval/results/ (gitignored): <run id>.json and <run id>.md.
//
//   node experiments/framing-eval/run.cjs --dry-run --host daserver --engine-url http://HOST:PORT \
//     --answer-model A --candidates B,C --reference C --memory-estimates estimates.json
const fs = require('node:fs'), path = require('node:path');
const lib = require('./lib.cjs');

const FLAGS = new Set(['dry-run', 'smoke']);
const VALUE_FLAGS = new Set(['host', 'engine-url', 'answer-model', 'candidates', 'reference', 'memory-estimates', 'budget-gib', 'deadline-ms', 'sec-per-call', 'load-sec', 'approved-run', 'out', 'cases']);

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
  out.candidates = String(out.candidates || '').split(',').map((s) => s.trim()).filter(Boolean);
  for (const k of ['budget-gib', 'deadline-ms', 'sec-per-call', 'load-sec']) if (out[k] !== undefined && !(Number(out[k]) > 0)) throw Error(`--${k} must be a positive number`);
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
  };
}

/** Argument problems for a run (or a dry run). Empty list = ok. */
function validate(cfg) {
  const p = [];
  if (!cfg.host) p.push('--host is required (a label for where the engine runs)');
  if (!cfg.engineUrl) p.push('--engine-url is required');
  if (!cfg.answerModel) p.push('--answer-model is required');
  if (!cfg.candidates.length) p.push('--candidates is required (comma separated model ids)');
  if (cfg.reference && !cfg.candidates.includes(cfg.reference)) p.push('--reference must be one of --candidates');
  return p;
}

/** Everything a run would do, computed without touching an engine. */
function buildPlan(cfg, casebook, estimates) {
  const cases = lib.selectCases(casebook.cases, { smoke: cfg.smoke });
  const reasonerCases = cases.filter(lib.hasReasonerResult);
  const sequence = [cfg.answerModel, ...cfg.candidates, cfg.answerModel].filter((m, i, a) => i === 0 || m !== a[i - 1]);
  const mem = (m) => lib.memoryFor(estimates, m);
  const models = [...new Set([cfg.answerModel, ...cfg.candidates])].map((m) => ({ model: m, memory: mem(m) }));
  const known = models.filter((m) => m.memory);
  const calls = { framedVsUnframed: cases.length * 2, reasoner: reasonerCases.length * cfg.candidates.length, packetAnswers: reasonerCases.length * cfg.candidates.length };
  const totalCalls = calls.framedVsUnframed + calls.reasoner + calls.packetAnswers;
  const kinds = {};
  for (const c of cases) kinds[c.kind] = (kinds[c.kind] || 0) + 1;
  return {
    config: cfg, cases: cases.map((c) => ({ id: c.id, kind: c.kind, canary: !!c.canary, reasoner: lib.hasReasonerResult(c) })), kinds,
    loadSequence: sequence, loads: sequence.length, calls: { ...calls, total: totalCalls },
    memory: { models, peakGib: known.length ? Math.max(...known.map((m) => m.memory.totalGib)) : null, unknown: models.filter((m) => !m.memory).map((m) => m.model),
      note: 'one model resident at a time; peak = the largest single model' },
    estimatedSeconds: totalCalls * cfg.secPerCall + sequence.length * cfg.loadSec,
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
    ...plan.memory.models.map((m) => `  - ${m.model}: ${m.memory ? `${m.memory.totalGib} GiB at ${m.memory.ctx || '?'} ctx${m.memory.ctx === lib.REASONER_CTX ? '' : ' (not the 32768 reasoner ctx)'}` : 'no estimate'}`),
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
    candidates.push({ ...run, summary: lib.summarizeCandidate(run, { memory: lib.memoryFor(estimates, model), budgetGib: cfg.budgetGib, deadlineMs: cfg.deadlineMs }) });
  }
  const reference = candidates.find((c) => c.model === cfg.reference)?.summary || null;
  for (const c of candidates) c.kill = lib.applyKill(c.summary, reference, cfg.budgetGib);
  return { approvedRun, startedAt, finishedAt: clock(), smoke: cfg.smoke, config: cfg, cases: cases.map((c) => c.id), framedVsUnframed: framed, candidates };
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
  for (const c of report.candidates) {
    const s = c.summary;
    L.push(`### ${c.model}${report.config.reference === c.model ? ' (reference)' : ''}: ${c.kill.verdict}`, '',
      `- packet validity: ${s.validity} (${s.validCount}/${s.n})${Object.keys(s.fallbacks).length ? `, fallbacks ${JSON.stringify(s.fallbacks)}` : ''}`,
      `- packet success ${s.packetSuccessRate} vs raw-result success ${s.rawSuccessRate}; sufficiency ${s.sufficiency}`,
      `- injection robustness: ${s.injection.robustness} (${s.injection.robust}/${s.injection.cases}); canary in facts ${s.injection.canaryInFacts} (facts are data)`,
      `- latency: median ${s.latency.medianMs} ms, p95 ${s.latency.p95Ms} ms, over deadline ${s.latency.overDeadline}`,
      `- memory: ${s.memory ? `${s.memory.totalGib} GiB at ${s.memory.ctx} ctx` : 'no estimate'}`, '',
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
async function main(argv, { out = (s) => process.stdout.write(`${s}\n`), err = (s) => process.stderr.write(`${s}\n`), createBackend = null, casebook = null } = {}) {
  let args;
  try { args = parseArgs(argv); } catch (e) { err(`error: ${e.message}`); return 2; }
  const cfg = config(args);
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
  const backend = (createBackend || ((c) => require('./http.cjs').createHttpBackend({ engineUrl: c.engineUrl })))(cfg);
  out(formatPlan(plan));
  const report = await runEval({ cfg, casebook: book, estimates, answerBackend: backend, approvedRun: args['approved-run'] });
  const base = writeReport(report, path.resolve(args.out || path.join(__dirname, 'results')));
  out(`\nreport: ${base}.md and ${base}.json`);
  for (const c of report.candidates) out(`${c.model}: ${c.kill.verdict}`);
  return 0;
}

if (require.main === module) main(process.argv.slice(2)).then((code) => process.exit(code), (e) => { console.error(e); process.exit(1); });

module.exports = { parseArgs, config, validate, buildPlan, formatPlan, runEval, renderMarkdown, writeReport, main, loadCases };
