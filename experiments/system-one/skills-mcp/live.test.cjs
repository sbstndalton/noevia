'use strict';
// Mocked OpenAI-compatible endpoint on 127.0.0.1; no model is ever contacted.
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { parseArgs, validateConfig, evaluate, markdown, main } = require('./live.cjs');
const { liveCases, validateLiveCases } = require('./live-fixtures.cjs');

const TOPICS = ['calendar', 'files', 'wiki'];
// Default behaviour: select the item whose label names the task topic; call <topic>_read.
function defaultHandler(body) {
  const system = body.messages[0].content;
  if (system.startsWith('Select at most')) {
    const { task, items } = JSON.parse(body.messages[1].content);
    const topic = TOPICS.find(t => task.toLowerCase().includes(t) && !task.toLowerCase().includes(' files'));
    const selected = topic ? items.filter(i => i.label.toLowerCase().startsWith(topic)).map(i => i.id) : [];
    return { content: JSON.stringify({ selected, scores: Object.fromEntries(selected.map(id => [id, 0.9])), confidence: 0.9, abstain: !selected.length }), usage: { prompt_tokens: 50, completion_tokens: 10 } };
  }
  const tools = body.tools || [];
  const topic = TOPICS.find(t => body.messages[1].content.toLowerCase().includes(t));
  const read = tools.find(t => t.function.name === `${topic}_read`);
  const prompt = 100 + tools.length * 40 + (system.length > 900 ? 25 : 0);
  if (!read) return { content: 'no tool', usage: { prompt_tokens: prompt, completion_tokens: 3 } };
  return { tool_calls: [{ id: 'c1', type: 'function', function: { name: read.function.name, arguments: '{}' } }], usage: { prompt_tokens: prompt, completion_tokens: 8 } };
}

async function withServer(handler, fn) {
  const seen = [];
  const server = http.createServer((req, res) => {
    let data = '';
    req.on('data', d => { data += d; });
    req.on('end', () => {
      const body = JSON.parse(data); seen.push({ url: req.url, body, auth: req.headers.authorization });
      const out = handler(body, seen.length);
      if (out.status) { res.writeHead(out.status); res.end(); return; }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ choices: [{ message: { role: 'assistant', content: out.content ?? null, tool_calls: out.tool_calls } }], usage: out.usage }));
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try { return await fn(`http://127.0.0.1:${server.address().port}/v1`, seen); }
  finally { await new Promise(resolve => server.close(resolve)); }
}
const cfgFor = (baseUrl, extra = []) => parseArgs(['--base-url', baseUrl, '--model', 'mock', '--repeats', '2', '--timeout-ms', '5000', ...extra], {});

test('config needs an explicit endpoint and model; no default host', () => {
  const cfg = parseArgs([], {});
  assert.equal(cfg.baseUrl, '');
  assert.ok(validateConfig(cfg).some(p => /base URL/.test(p)));
  assert.ok(validateConfig(cfg).some(p => /model/.test(p)));
  const env = parseArgs(['--dry-run'], { SKILL_EVAL_BASE_URL: 'http://127.0.0.1:1/v1', SKILL_EVAL_MODEL: 'm' });
  assert.deepEqual(validateConfig(env), []);
  assert.ok(validateConfig(parseArgs(['--base-url', 'http://u:p@h/v1', '--model', 'm', '--dry-run'], {})).some(p => /credentials/.test(p)));
  assert.ok(validateConfig(parseArgs(['--base-url', 'http://h/v1', '--model', 'm'], {})).some(p => /--out/.test(p)));
  assert.ok(validateConfig(parseArgs(['--base-url', 'http://h/v1', '--model', 'm', '--dry-run', '--arms', 'baseline,magic'], {})).length);
  assert.throws(() => parseArgs(['--repeats', '0'], {}), /repeats/);
  assert.throws(() => parseArgs(['--bogus'], {}), /unknown/);
});

test('fixtures extend the offline format and validate', () => {
  const cases = liveCases();
  assert.deepEqual(validateLiveCases(cases), []);
  assert.ok(cases.some(c => c.split === 'held-out') && cases.some(c => c.split === 'development'));
  const broken = structuredClone(cases); broken[0].expected.allowedTools.push('rm_rf');
  assert.match(validateLiveCases(broken).join(), /not in fake catalogue/);
});

test('dry run validates without calling the endpoint', async () => {
  await withServer(defaultHandler, async (baseUrl, seen) => {
    const logs = []; const orig = console.log; console.log = s => logs.push(s);
    try { assert.equal(await main(['--dry-run', '--base-url', baseUrl, '--model', 'mock']), 0); } finally { console.log = orig; }
    assert.equal(seen.length, 0);
    assert.equal(JSON.parse(logs[0]).ok, true);
  });
});

test('three arms, repeated runs, all metrics recorded from the endpoint usage', async () => {
  await withServer(defaultHandler, async (baseUrl, seen) => {
    const cfg = cfgFor(baseUrl);
    const { records, summary } = await evaluate(cfg);
    const n = liveCases().length;
    assert.equal(records.length, n * 3 * 2);
    assert.deepEqual(summary.arms.map(a => a.arm), ['baseline', 'embedding', 'system-one']);
    for (const r of records) {
      assert.ok(Number.isFinite(r.latencyMs.total) && Number.isFinite(r.latencyMs.task));
      assert.ok(Number.isFinite(r.usage.task.prompt)); assert.ok(Number.isFinite(r.measuredSchemaBodyTokens));
      assert.equal(r.scriptExecution, 'disabled'); assert.equal(r.toolExecution, 'none');
      assert.equal(r.seed, 265 + r.repetition);
      assert.doesNotMatch(JSON.stringify(r), /Find calendar|Cite the returned/, 'no task text or skill bodies in records');
    }
    const one = records.find(r => r.arm === 'system-one' && r.fixtureId === 'exact-calendar');
    assert.equal(one.selectionCorrect, true); assert.equal(one.taskCompleted, true); assert.equal(one.fallback, null);
    assert.equal(one.usage.selection.prompt, 50);
    assert.ok(one.bodyBytes > 0);
    const base = records.find(r => r.arm === 'baseline' && r.fixtureId === 'exact-calendar');
    assert.equal(base.selectionCorrect, false); assert.equal(base.bodyBytes, 0); assert.equal(base.schemaCount, 6);
    assert.ok(base.measuredSchemaBodyTokens > one.measuredSchemaBodyTokens, 'baseline ships more schemas');
    assert.equal(records.find(r => r.arm === 'embedding' && r.fixtureId === 'exact-files').selectionCorrect, true);
    // Only system-one calls the selection endpoint; every request carries the explicit model and a seed.
    assert.ok(seen.every(s => s.url === '/v1/chat/completions' && s.body.model === 'mock' && Number.isInteger(s.body.seed) && s.body.temperature === 0));
    assert.equal(seen.filter(s => s.body.messages[0].content.startsWith('Select')).length, n * 2);
    assert.equal(summary.indicators.zeroUnauthorizedActions, true);
    const md = markdown(summary);
    assert.match(md, /\| system-one \| held-out \|/);
    assert.match(md, /Adopt \/ revise \/ defer: _to be recorded by the owner_/);
  });
});

test('unauthorized actions: any tool call outside the allowed set is counted, never executed', async () => {
  const handler = body => {
    if (body.messages[0].content.startsWith('Select')) return defaultHandler(body);
    const names = (body.tools || []).map(t => t.function.name);
    const calls = ['calendar_write', 'install_server', 'calendar_read'].map((name, i) => ({ id: `c${i}`, type: 'function', function: { name, arguments: '{}' } }));
    return { tool_calls: calls.filter(c => names.includes(c.function.name) || c.function.name === 'install_server'), usage: { prompt_tokens: 10 } };
  };
  await withServer(handler, async baseUrl => {
    const cfg = cfgFor(baseUrl, ['--repeats', '1', '--arms', 'baseline']);
    const { records, summary } = await evaluate(cfg, { cases: liveCases().filter(c => c.id === 'malicious-description') });
    assert.equal(records[0].unauthorizedActions, 2);
    assert.deepEqual(records[0].toolCalls, ['calendar_write', 'install_server', 'calendar_read']);
    assert.equal(records[0].taskCompleted, false);
    assert.equal(records[0].toolChoiceCorrect, true);
    assert.equal(summary.indicators.zeroUnauthorizedActions, false);
    assert.equal(records[0].measuredSchemaBodyTokens, 0);
  });
});

test('fallbacks: malformed proposal, endpoint error on selection, and task endpoint errors', async () => {
  let mode = 'malformed';
  const handler = body => {
    if (body.messages[0].content.startsWith('Select')) return mode === 'malformed' ? { content: 'not json', usage: { prompt_tokens: 5 } } : mode === 'selection-500' ? { status: 500 } : defaultHandler(body);
    if (mode === 'task-500' && body.max_tokens !== 1) return { status: 503 };
    return defaultHandler(body);
  };
  await withServer(handler, async baseUrl => {
    const cfg = cfgFor(baseUrl, ['--repeats', '1', '--arms', 'system-one']);
    const cases = liveCases().filter(c => c.id === 'exact-calendar');
    let { records } = await evaluate(cfg, { cases });
    assert.equal(records[0].fallback, 'malformed');
    assert.equal(records[0].schemaCount, 6, 'fallback restores baseline tools');
    assert.equal(records[0].taskCompleted, true);
    mode = 'selection-500';
    ({ records } = await evaluate(cfg, { cases }));
    assert.equal(records[0].fallback, 'backend-error');
    assert.equal(records[0].selectionError, 'http-500');
    mode = 'task-500';
    const r = await evaluate(cfg, { cases });
    assert.equal(r.records[0].taskError, 'http-503');
    assert.equal(r.records[0].taskCompleted, false);
    assert.equal(r.summary.arms[0].all.endpointErrors, 1);
    assert.equal(r.summary.arms[0].all.fallbacks, 0);
  });
});

test('missing or partial usage on the endpoint response yields null prompt/completion tokens', async () => {
  const handler = body => {
    if (body.messages[0].content.startsWith('Select')) return defaultHandler(body);
    const tools = body.tools || [];
    const topic = TOPICS.find(t => body.messages[1].content.toLowerCase().includes(t));
    const read = tools.find(t => t.function.name === `${topic}_read`);
    // No `usage` at all on the bare call, and a partial `usage` (completion_tokens only) on the task call.
    if (body.max_tokens === 1) return { content: 'ok' };
    return { tool_calls: [{ id: 'c1', type: 'function', function: { name: read.function.name, arguments: '{}' } }], usage: { completion_tokens: 8 } };
  };
  await withServer(handler, async baseUrl => {
    const cfg = cfgFor(baseUrl, ['--repeats', '1', '--arms', 'system-one']);
    const { records } = await evaluate(cfg, { cases: liveCases().filter(c => c.id === 'exact-calendar') });
    assert.deepEqual(records[0].usage.bare, { prompt: null, completion: null });
    assert.equal(records[0].usage.task.prompt, null);
    assert.equal(records[0].measuredSchemaBodyTokens, null);
    assert.equal(records[0].bareError, null);
  });
});

test('a bare-call failure is scored on its own, never as a task failure', async () => {
  const handler = body => {
    if (body.messages[0].content.startsWith('Select')) return defaultHandler(body);
    if (body.max_tokens === 1) return { status: 500 };
    return defaultHandler(body);
  };
  await withServer(handler, async baseUrl => {
    const cfg = cfgFor(baseUrl, ['--repeats', '1', '--arms', 'baseline']);
    const { records } = await evaluate(cfg, { cases: liveCases().filter(c => c.id === 'exact-calendar') });
    assert.equal(records[0].bareError, 'http-500');
    assert.equal(records[0].usage.bare, null);
    assert.equal(records[0].measuredSchemaBodyTokens, null);
    assert.equal(records[0].taskError, null, 'the task call itself still ran and succeeded');
    assert.equal(records[0].taskCompleted, true);
  });
});

test('a task call that never responds times out cleanly via AbortSignal', async () => {
  const server = http.createServer((req, res) => {
    let data = '';
    req.on('data', d => { data += d; });
    req.on('end', () => {
      const body = JSON.parse(data);
      if (body.max_tokens === 1) {
        // The bare-usage call still succeeds; only the task call is left hanging below.
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ choices: [{ message: { role: 'assistant', content: 'ok' } }], usage: { prompt_tokens: 5 } }));
        return;
      }
      // Never respond: the client's AbortSignal.timeout must fire.
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}/v1`;
    const cfg = parseArgs(['--base-url', baseUrl, '--model', 'mock', '--repeats', '1', '--arms', 'baseline', '--timeout-ms', '50'], {});
    const { records } = await evaluate(cfg, { cases: liveCases().filter(c => c.id === 'exact-calendar') });
    assert.equal(records[0].taskError, 'timeout');
    assert.equal(records[0].taskCompleted, false);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

test('main() exits 1 when unauthorized actions occur, run as a real CLI process', async () => {
  await withServer((body => {
    if (body.messages[0].content.startsWith('Select')) return defaultHandler(body);
    const names = (body.tools || []).map(t => t.function.name);
    const calls = ['calendar_write', 'calendar_read'].map((name, i) => ({ id: `c${i}`, type: 'function', function: { name, arguments: '{}' } }));
    return { tool_calls: calls.filter(c => names.includes(c.function.name)), usage: { prompt_tokens: 10 } };
  }), async baseUrl => {
    const out = fs.mkdtempSync(path.join(os.tmpdir(), 'skill-eval-cli-'));
    try {
      // spawn (not spawnSync): the mock server above runs on this same process's event loop, and
      // a synchronous spawn would freeze that loop, starving the server the child is calling.
      const { spawn } = require('node:child_process');
      const child = spawn(process.execPath, [path.join(__dirname, 'live.cjs'), '--base-url', baseUrl, '--model', 'mock',
        '--repeats', '1', '--timeout-ms', '5000', '--out', out], { stdio: 'ignore' });
      const status = await new Promise((resolve, reject) => {
        child.on('error', reject);
        child.on('exit', resolve);
      });
      assert.equal(status, 1);
    } finally { fs.rmSync(out, { recursive: true, force: true }); }
  });
});

test('live run writes JSONL and a markdown summary and refuses to overwrite', async () => {
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'skill-eval-'));
  try {
    await withServer(defaultHandler, async baseUrl => {
      const orig = console.log; console.log = () => {};
      try {
        assert.equal(await main(['--base-url', baseUrl, '--model', 'mock', '--repeats', '1', '--out', out]), 0);
        const lines = fs.readFileSync(path.join(out, 'results.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
        assert.equal(lines.at(-1).type, 'summary');
        assert.equal(lines.filter(l => l.type === 'run').length, liveCases().length * 3);
        assert.match(fs.readFileSync(path.join(out, 'summary.md'), 'utf8'), /Task completion/);
        const origErr = console.error; console.error = () => {};
        try { assert.equal(await main(['--base-url', baseUrl, '--model', 'mock', '--out', out]), 2); } finally { console.error = origErr; }
      } finally { console.log = orig; }
    });
  } finally { fs.rmSync(out, { recursive: true, force: true }); }
});
