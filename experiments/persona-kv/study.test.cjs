'use strict';
// Fake llama.cpp server on 127.0.0.1; no model is ever contacted.
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const S = require('./study.cjs');
const { PERSONAS, sharedPrefix, SEQUENCE } = require('./fixtures.cjs');

// One slot whose KV cache is the token list of the last prompt. Tokens = whitespace-split words.
function fakeLlama({ saveStatus = 200, restoreMissingStatus = 404, failCompletion = false, noStreamContent = false } = {}) {
  const calls = [];
  const files = new Map();
  let cache = [];
  const server = http.createServer((req, res) => {
    let data = '';
    req.on('data', d => { data += d; });
    req.on('end', () => {
      const body = data ? JSON.parse(data) : {};
      const url = new URL(req.url, 'http://x');
      calls.push({ method: req.method, path: url.pathname, action: url.searchParams.get('action'), body, auth: req.headers.authorization });
      const send = (status, obj) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj)); };
      if (url.pathname === '/health') return send(200, { status: 'ok' });
      if (url.pathname === '/props') return send(200, { model_path: '/models/synthetic-model.gguf', total_slots: 1, default_generation_settings: { n_ctx: 4096 } });
      if (url.pathname === '/slots/0') {
        const action = url.searchParams.get('action');
        if (action === 'erase') { cache = []; return send(200, { id_slot: 0, n_erased: 1 }); }
        if (action === 'save') {
          if (saveStatus !== 200) return send(saveStatus, { error: 'slot save disabled' });
          files.set(body.filename, cache.slice()); return send(200, { id_slot: 0, filename: body.filename, n_saved: cache.length, timings: { save_ms: 1 } });
        }
        if (action === 'restore') {
          if (!files.has(body.filename)) return send(restoreMissingStatus, { error: 'no such file' });
          cache = files.get(body.filename).slice(); return send(200, { id_slot: 0, filename: body.filename, n_restored: cache.length, timings: { restore_ms: 1 } });
        }
        return send(400, {});
      }
      if (url.pathname === '/completion') {
        if (failCompletion) return send(500, { error: 'boom' });
        const tokens = body.prompt.split(/\s+/).filter(Boolean);
        let common = 0;
        while (common < cache.length && common < tokens.length && cache[common] === tokens[common]) common++;
        if (common === tokens.length) common--; // llama.cpp always evaluates at least one token
        const promptN = tokens.length - common;
        cache = tokens.slice();
        res.writeHead(200, { 'content-type': 'text/event-stream' });
        setTimeout(() => {
          if (!noStreamContent) res.write(`data: ${JSON.stringify({ content: 'x', stop: false })}\n\n`);
          setTimeout(() => {
            res.end(`data: ${JSON.stringify({ content: '', stop: true, timings: { cache_n: common, prompt_n: promptN, prompt_ms: promptN * 0.5, predicted_n: body.n_predict } })}\n\n`);
          }, 2);
        }, 1 + promptN * 0.05);
        return;
      }
      send(404, {});
    });
  });
  return { server, calls, files };
}
async function withServer(opts, fn) {
  const f = fakeLlama(opts);
  await new Promise(r => f.server.listen(0, '127.0.0.1', r));
  try { return await fn(`http://127.0.0.1:${f.server.address().port}`, f); } finally { await new Promise(r => f.server.close(r)); }
}
const cfgFor = (baseUrl, extra = []) => S.parseArgs(['--base-url', baseUrl, '--out', 'unused', '--run-id', 'T1', ...extra]);
const capture = async fn => {
  const out = [], err = [], log = console.log, error = console.error;
  console.log = (...a) => out.push(a.join(' ')); console.error = (...a) => err.push(a.join(' '));
  try { const code = await fn(); return { code, out: out.join('\n'), err: err.join('\n') }; } finally { console.log = log; console.error = error; }
};

test('metrics maths: mean, median, nearest-rank percentile, reuse ratio, speed-up', () => {
  assert.equal(S.mean([1, 2, 3, null, NaN]), 2);
  assert.equal(S.mean([]), null);
  assert.equal(S.median([5, 1, 3]), 3);
  assert.equal(S.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 95), 10);
  assert.equal(S.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 50), 5);
  assert.equal(S.reuseRatio(75, 25), 0.75);
  assert.equal(S.reuseRatio(0, 0), null);
  assert.equal(S.reuseRatio(null, 5), null);
  assert.equal(S.speedup(100, 25), 4);
  assert.equal(S.speedup(100, 0), null);
  assert.deepEqual(S.extractTimings({ timings: { cache_n: 10, prompt_n: 4, prompt_ms: 8.5, predicted_n: 3 } }),
    { cacheN: 10, promptN: 4, promptMs: 8.5, predictedN: 3, predictedMs: null });
  assert.deepEqual(S.extractTimings({}), { cacheN: null, promptN: null, promptMs: null, predictedN: null, predictedMs: null });
});

test('summarize excludes step 0, separates revisits, and computes speed-up against cold', () => {
  const step = (arm, n, role, revisit, ttft, promptN, cacheN, actionMs = 0) => ({ type: 'step', arm, repeat: 1, step: n, role, revisit, error: null,
    ttftMs: ttft, switchMs: ttft + actionMs, promptN, cacheN, reuseRatio: S.reuseRatio(cacheN, promptN), promptMs: null });
  const records = [
    step('cold', 0, 'planner', false, 999, 100, 0), step('cold', 1, 'executor', false, 100, 100, 0), step('cold', 2, 'planner', true, 100, 100, 0),
    step('after-prefix', 0, 'planner', false, 999, 100, 0), step('after-prefix', 1, 'executor', false, 25, 20, 80), step('after-prefix', 2, 'planner', true, 25, 20, 80),
    { type: 'save', arm: 'restore-prefix', ms: 4, error: null },
  ];
  const s = S.summarize(records, { arms: ['cold', 'after-prefix'] });
  const [cold, warm] = s.arms;
  assert.equal(cold.switches.requests, 2);
  assert.equal(cold.switches.ttftMsMean, 100);
  assert.equal(cold.firstFill.ttftMsMean, 999);
  assert.equal(warm.switches.reuseRatioMean, 0.8);
  assert.equal(warm.revisits.requests, 1);
  assert.equal(warm.speedupVsCold.ttft, 4);
  assert.equal(warm.promptTokensSavedVsCold, 80);
  assert.equal(cold.speedupVsCold.ttft, 1);
});

test('summarize ignores errored rows in means but counts them', () => {
  const ok = { type: 'step', arm: 'cold', step: 1, role: 'executor', error: null, ttftMs: 10, switchMs: 10, promptN: 1, cacheN: 0, reuseRatio: 0 };
  const bad = { type: 'step', arm: 'cold', step: 2, role: 'laya', error: 'timeout', ttftMs: null, switchMs: null, promptN: null, cacheN: null, reuseRatio: null };
  const g = S.summarize([ok, bad], { arms: ['cold'] }).arms[0].switches;
  assert.equal(g.requests, 2); assert.equal(g.errors, 1); assert.equal(g.ttftMsMean, 10);
});

test('layouts: persona-first starts with the persona, after-prefix keeps the shared prefix as the leading bytes', () => {
  const prefix = sharedPrefix(6);
  const a = S.buildPrompt('after-prefix', 'planner', 't', prefix), s = S.buildPrompt('after-prefix', 'executor', 't', prefix);
  assert.ok(a.startsWith(prefix) && s.startsWith(prefix));
  const pa = S.buildPrompt('persona-first', 'planner', 't', prefix);
  assert.ok(pa.startsWith(PERSONAS.planner));
  assert.equal(sharedPrefix(6), prefix, 'prefix is deterministic');
  assert.throws(() => S.buildPrompt('nope', 'planner', 't', prefix));
});

test('matrix: five arms, sequence order, revisit flags and slot actions', () => {
  const cfg = cfgFor('http://127.0.0.1:1', ['--repeats', '2']);
  const m = S.buildMatrix(cfg);
  assert.equal(m.length, 2 * 5 * (SEQUENCE.length + 1));
  const rp = m.filter(r => r.repeat === 1 && r.arm === 'restore-persona');
  assert.deepEqual(rp[0].actions, ['erase', 'completion:prefix-only', 'save:prefix']);
  assert.deepEqual(rp[1].actions, ['restore:prefix', 'completion', 'save:planner']);
  const revisit = rp.find(r => r.step === 4); // planner again
  assert.equal(revisit.revisit, true);
  assert.deepEqual(revisit.actions, ['restore:planner', 'completion']);
  assert.deepEqual(m.find(r => r.arm === 'cold' && r.step === 1).actions, ['erase', 'completion']);
  assert.deepEqual(m.find(r => r.arm === 'after-prefix' && r.step === 1).actions, ['completion']);
  assert.equal(m.find(r => r.arm === 'persona-first' && r.step === 0).layout, 'persona-first');
  assert.equal(S.countCalls(S.buildMatrix(cfgFor('http://x', ['--smoke']))), S.buildMatrix(cfgFor('http://x', ['--smoke'])).reduce((n, r) => n + r.actions.length, 0));
});

test('config bounds and validation', () => {
  assert.throws(() => S.parseArgs(['--repeats', '11']), /repeats/);
  assert.throws(() => S.parseArgs(['--timeout-ms', '999999']), /timeout/);
  assert.throws(() => S.parseArgs(['--n-predict', '0']), /n-predict/);
  assert.throws(() => S.parseArgs(['--bogus']), /unknown/);
  const smoke = S.parseArgs(['--smoke', '--repeats', '9', '--base-url', 'http://h']);
  assert.equal(smoke.repeats, 1); assert.equal(smoke.steps, 3);
  assert.ok(S.validateConfig(S.parseArgs(['--out', 'o'])).some(p => /base URL/.test(p)));
  assert.ok(S.validateConfig(S.parseArgs(['--base-url', 'http://u:p@h', '--out', 'o'])).some(p => /credentials/.test(p)));
  assert.ok(S.validateConfig(S.parseArgs(['--base-url', 'http://h', '--out', 'o', '--arms', 'after-prefix'])).some(p => /cold/.test(p)));
  assert.ok(S.validateConfig(S.parseArgs(['--base-url', 'http://h', '--out', 'o', '--run-id', '../x'])).some(p => /run-id/.test(p)));
  assert.deepEqual(S.validateConfig(S.parseArgs(['--base-url', 'http://h', '--out', 'o'])), []);
});

test('refuses to run without --i-have-approval and makes no request', async () => {
  await withServer({}, async (url, f) => {
    const dir = path.join(os.tmpdir(), `persona-kv-refuse-${process.pid}`);
    const r = await capture(() => S.main(['--base-url', url, '--out', dir]));
    assert.equal(r.code, 2); assert.match(r.err, /refusing to run/);
    assert.equal(f.calls.length, 0);
    assert.equal(fs.existsSync(dir), false);
    const noUrl = await capture(() => S.main(['--i-have-approval', '--out', dir], {}));
    assert.equal(noUrl.code, 2);
  });
});

test('dry-run prints the matrix, needs no approval and makes no request', async () => {
  await withServer({}, async (url, f) => {
    const r = await capture(() => S.main(['--dry-run', '--base-url', url, '--smoke']));
    assert.equal(r.code, 0);
    const plan = JSON.parse(r.out);
    assert.equal(plan.type, 'dry-run'); assert.equal(plan.config.smoke, true);
    assert.equal(plan.plannedSteps, 5 * 3);
    assert.ok(plan.matrix.length > 0 && plan.endpoints.some(e => /slots/.test(e)));
    assert.equal(f.calls.length, 0);
  });
});

test('full run: records timings, slot save/restore sequencing and cache reuse', async () => {
  await withServer({}, async (url, f) => {
    const cfg = cfgFor(url, ['--smoke', '--n-predict', '2']);
    const res = await S.evaluate(cfg);
    assert.equal(res.server.modelPath, 'synthetic-model.gguf'); assert.equal(res.server.totalSlots, 1);
    assert.deepEqual(res.skipped, {});
    const steps = res.records.filter(r => r.type === 'step');
    assert.equal(steps.length, 5 * 3);
    const by = (arm, step) => steps.find(r => r.arm === arm && r.step === step);
    // cold: nothing cached on every step
    for (const n of [0, 1, 2]) assert.equal(by('cold', n).cacheN, 0);
    // persona-first: the persona differs from the very first word, so the cache cannot be reused
    assert.ok(by('persona-first', 1).cacheN <= 1); // at most the shared word "Persona"
    // after-prefix: the shared prefix is reused on a switch
    assert.ok(by('after-prefix', 1).cacheN >= sharedPrefix(4).split(/\s+/).length);
    assert.ok(by('after-prefix', 1).reuseRatio > 0.5);
    assert.ok(by('after-prefix', 1).promptN < by('cold', 1).promptN);
    // restore-prefix restores a saved state before each completion and reuses the prefix
    assert.ok(by('restore-prefix', 1).restored.nRestored > 0);
    assert.ok(by('restore-prefix', 1).cacheN >= sharedPrefix(4).split(/\s+/).length);
    assert.ok(by('restore-prefix', 1).switchMs >= by('restore-prefix', 1).ttftMs);
    for (const s of steps) { assert.ok(s.ttftMs > 0); assert.equal(s.error, null); assert.equal(s.cacheN + s.promptN > 0, true); }
    // call sequencing for the restore-persona arm (setup, then restore -> completion -> save per fresh persona)
    const slotCalls = f.calls.filter(c => c.path === '/slots/0' || c.path === '/completion');
    const idx = slotCalls.findIndex(c => c.body.filename === 'noevia-persona-kv-T1-prefix.bin' && c.action === 'save');
    assert.ok(idx > 0);
    const firstRestorePersonaSave = slotCalls.map(c => `${c.action || 'completion'}:${c.body.filename || ''}`);
    const startRp = firstRestorePersonaSave.lastIndexOf('save:noevia-persona-kv-T1-prefix.bin');
    assert.deepEqual(firstRestorePersonaSave.slice(startRp - 2, startRp + 6), [
      'erase:', 'completion:', 'save:noevia-persona-kv-T1-prefix.bin',
      'restore:noevia-persona-kv-T1-prefix.bin', 'completion:', 'save:noevia-persona-kv-T1-planner.bin',
      'restore:noevia-persona-kv-T1-prefix.bin', 'completion:',
    ]);
    // every completion is streamed, cache_prompt is on, and the prefix-only warm-up asks for one token
    assert.ok(f.calls.filter(c => c.path === '/completion').every(c => c.body.stream === true && c.body.cache_prompt === true && c.body.id_slot === 0));
    // only the study's own slot files are written
    assert.ok([...f.files.keys()].every(n => /^noevia-persona-kv-T1-[a-z]+\.bin$/.test(n)));
    // nothing but the documented endpoints is touched
    assert.ok(f.calls.every(c => ['/health', '/props', '/completion', '/slots/0'].includes(c.path)));
  });
});

test('persona revisit restores that persona state and reuses more than the prefix', async () => {
  await withServer({}, async url => {
    const cfg = cfgFor(url, ['--prefix-paragraphs', '3', '--repeats', '1', '--arms', 'cold,restore-persona']);
    const res = await S.evaluate(cfg);
    const rp = res.records.filter(r => r.type === 'step' && r.arm === 'restore-persona');
    const first = rp.find(r => r.step === 0), revisit = rp.find(r => r.step === 4);
    assert.equal(rp.find(r => r.step === 1).restored.state, 'prefix');
    assert.equal(revisit.restored.state, 'planner');
    assert.ok(revisit.revisit);
    // saved after planner's task 0; revisit uses task 0 again? step 4 -> task 0, so persona + task both cached
    assert.ok(revisit.cacheN > first.cacheN);
    assert.ok(res.summary.arms[1].revisits.requests === 4);
  });
});

test('slot save unavailable: slot arms are skipped and reported, others still run', async () => {
  await withServer({ saveStatus: 501 }, async url => {
    const res = await S.evaluate(cfgFor(url, ['--smoke']));
    assert.match(res.skipped['restore-prefix'], /slot-save-unavailable/);
    assert.match(res.skipped['restore-persona'], /slot-save-unavailable/);
    assert.equal(res.records.filter(r => r.type === 'step' && r.arm === 'after-prefix').length, 3);
    assert.equal(res.records.filter(r => r.type === 'step' && r.arm === 'restore-prefix').length, 0);
    const md = S.markdown(res, cfgFor(url, ['--smoke']));
    assert.match(md, /skipped: slot-save-unavailable/);
  });
});

test('repeated request failures abort the study', async () => {
  await withServer({ failCompletion: true }, async url => {
    await assert.rejects(S.evaluate(cfgFor(url, ['--smoke', '--arms', 'cold'])), /consecutive request errors/);
  });
});

test('unreachable server aborts with a clear error', async () => {
  const s = http.createServer(); await new Promise(r => s.listen(0, '127.0.0.1', r));
  const port = s.address().port; await new Promise(r => s.close(r));
  await assert.rejects(S.evaluate(cfgFor(`http://127.0.0.1:${port}`, ['--smoke', '--timeout-ms', '500'])), /unreachable/);
});

test('main writes results.json and summary.md, and will not overwrite them', async () => {
  await withServer({}, async url => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'persona-kv-'));
    try {
      const args = ['--i-have-approval', '--smoke', '--base-url', url, '--out', dir, '--run-id', 'T2'];
      const r = await capture(() => S.main(args));
      assert.equal(r.code, 0, r.err);
      const results = JSON.parse(fs.readFileSync(path.join(dir, 'results.json'), 'utf8'));
      assert.equal(results.config.runId, 'T2'); assert.equal(results.config.baseUrl, url);
      assert.equal(results.summary.arms.length, 5);
      assert.ok(results.records.some(x => x.type === 'step'));
      assert.match(fs.readFileSync(path.join(dir, 'summary.md'), 'utf8'), /\| after-prefix \|/);
      const again = await capture(() => S.main(args));
      assert.equal(again.code, 2); assert.match(again.err, /refusing to overwrite/);
    } finally { fs.rmSync(dir, { recursive: true, force: true }); }
  });
});

test('a bearer token is sent only from the environment', async () => {
  await withServer({}, async (url, f) => {
    const cfg = S.parseArgs(['--base-url', url, '--smoke', '--arms', 'cold'], { PERSONA_KV_API_KEY: 'k' });
    await S.evaluate(cfg);
    assert.ok(f.calls.every(c => c.auth === 'Bearer k'));
  });
});
