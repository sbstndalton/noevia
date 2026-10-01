'use strict';
// #697: one model at a time within an inference memory budget. Synthetic GGUF headers, a fake
// router and fake sysfs only; no model is ever loaded and no real engine is contacted.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { createInferenceBudget, hostRamGib, cacheRamLimits, clampCacheRam, DEFAULT_BUDGET_GIB } = require('./inference-budget.cjs');
const { estimateFootprint, suggest, kvCacheBytes } = require('./llamacpp-autoconfig.cjs');
const { createPresetStore } = require('./llamacpp-presets.cjs');
const { createModelManager } = require('./model-manager.cjs');
const { createInferenceBudgetWatch, gpuMemoryFiles, readGpuMemory, engineReaderFromModelLoader } = require('./inference-budget-watch.cjs');
const { rerankTarget } = require('./rerank-target.cjs');
const { keepAlongside } = require('./llamacpp-manager.cjs');

const GIB = 1024 ** 3;
const meminfo = gib => () => `MemTotal:       ${Math.round(gib * 1048576)} kB\nMemAvailable:   1 kB\n`;
const memStore = () => { const m = new Map(); return { get: k => m.get(k), set: (k, v) => m.set(k, v), m }; };

// Synthetic GGUF v3 header (no tensors), as in llamacpp-autoconfig.test.cjs.
function gguf(kv) {
  const u32 = n => { const b = Buffer.alloc(4); b.writeUInt32LE(n); return b; };
  const u64 = n => { const b = Buffer.alloc(8); b.writeBigUInt64LE(BigInt(n)); return b; };
  const str = s => { const b = Buffer.from(s); return Buffer.concat([u64(b.length), b]); };
  const val = (type, v) => type === 4 ? u32(v) : type === 8 ? str(v) : (() => { throw Error('type'); })();
  return Buffer.concat([Buffer.from('GGUF'), u32(3), u64(0), u64(Object.keys(kv).length), ...Object.entries(kv).map(([k, [t, v]]) => Buffer.concat([str(k), u32(t), val(t, v)]))]);
}
const qwen35 = { 'general.architecture': [8, 'qwen35'], 'qwen35.context_length': [4, 262144], 'qwen35.embedding_length': [4, 4096], 'qwen35.block_count': [4, 32], 'qwen35.attention.head_count': [4, 16], 'qwen35.attention.head_count_kv': [4, 4], 'qwen35.attention.key_length': [4, 256], 'qwen35.attention.value_length': [4, 256], 'qwen35.full_attention_interval': [4, 4], 'qwen35.ssm.state_size': [4, 128], 'tokenizer.chat_template': [8, '{{ messages }}'] };
const qwenMeta = { arch: 'qwen35', contextLength: 262144, embeddingLength: 4096, blockCount: 32, headCount: 16, headCountKv: 4, keyLength: 256, valueLength: 256, fullAttentionInterval: 4, hasChatTemplate: true };

function tmp(t) { const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'budget-697-')); t.after(() => fs.rmSync(dir, { recursive: true, force: true })); return dir; }

// ── The budget setting ───────────────────────────────────────────────────────

test('the budget defaults to 16 GiB only when the deployment sets nothing', () => {
  assert.equal(createInferenceBudget({ store: memStore(), env: {}, readMeminfo: meminfo(29.7) }).get().budgetGib, DEFAULT_BUDGET_GIB);
  const fromEnv = createInferenceBudget({ store: memStore(), env: { INFERENCE_MEMORY_BUDGET_GIB: '12' }, readMeminfo: meminfo(29.7) }).get();
  assert.equal(fromEnv.budgetGib, 12); assert.equal(fromEnv.source, 'deployment'); assert.equal(fromEnv.defaultGib, 12);
  assert.equal(createInferenceBudget({ store: memStore(), env: { INFERENCE_MEMORY_BUDGET_GIB: 'lots' }, readMeminfo: meminfo(29.7) }).get().budgetGib, DEFAULT_BUDGET_GIB);
});

test('an administrator saves the budget; it persists and wins over the deployment value', () => {
  const store = memStore(), audit = [];
  const b = createInferenceBudget({ store, env: { INFERENCE_MEMORY_BUDGET_GIB: '12' }, readMeminfo: meminfo(64), audit: (...a) => audit.push(a) });
  const saved = b.save({ budgetGib: 24.5 }, 'admin-1');
  assert.equal(saved.budgetGib, 24.5); assert.equal(saved.source, 'admin');
  assert.deepEqual(audit, [['inference.budget', 'admin-1', { budgetGib: 24.5 }]]);
  // A fresh process reads the stored figure, not the deployment default.
  assert.equal(createInferenceBudget({ store, env: { INFERENCE_MEMORY_BUDGET_GIB: '12' }, readMeminfo: meminfo(64) }).budgetGib(), 24.5);
});

test('the budget is validated from 2 GiB to host RAM less 4 GiB, read from /proc/meminfo', () => {
  const b = createInferenceBudget({ store: memStore(), env: {}, readMeminfo: meminfo(29.7) });
  assert.deepEqual(b.range(), { minGib: 2, maxGib: 25, hostRamGib: 29.7 });
  for (const bad of [1.9, 25.5, 0, -3, '16', null, Number.NaN, 8.25]) assert.throws(() => b.save({ budgetGib: bad }, 'a'), e => e.status === 400 && e.messageId === 'invalidBudget', String(bad));
  assert.equal(b.save({ budgetGib: 2 }, 'a').budgetGib, 2);
  assert.equal(b.save({ budgetGib: 25 }, 'a').budgetGib, 25);
  // Unreadable meminfo (not Linux): a wide upper bound instead of refusing every value.
  const blind = createInferenceBudget({ store: memStore(), env: {}, readMeminfo: () => { throw Error('ENOENT'); } });
  assert.equal(blind.range().hostRamGib, null); assert.equal(blind.save({ budgetGib: 48 }, 'a').budgetGib, 48);
  assert.equal(hostRamGib(() => 'garbage'), null);
});

test('a saved budget larger than a smaller host can hold is limited on read', () => {
  const store = memStore();
  createInferenceBudget({ store, env: {}, readMeminfo: meminfo(128) }).save({ budgetGib: 100 }, 'a');
  const later = createInferenceBudget({ store, env: {}, readMeminfo: meminfo(29.7) }).get();
  assert.equal(later.budgetGib, 25); assert.equal(later.limited, true);
});

// ── Prompt cache limits ─────────────────────────────────────────────────────

test('cache-ram limits default to a 1024 MiB cap and a 2048 MiB hard maximum', () => {
  assert.deepEqual(cacheRamLimits({}), { capMib: 1024, hardMaxMib: 2048 });
  assert.deepEqual(cacheRamLimits({ LLAMACPP_AUTOCONFIG_CACHE_RAM_MAX_MIB: '4096', LLAMACPP_CACHE_RAM_HARD_MAX_MIB: '3072' }), { capMib: 3072, hardMaxMib: 3072 });
  const limits = { capMib: 1024, hardMaxMib: 2048 };
  assert.equal(clampCacheRam('8192', limits), '2048'); assert.equal(clampCacheRam('-1', limits), '2048');
  assert.equal(clampCacheRam('512', limits), '512'); assert.equal(clampCacheRam('0', limits), '0'); assert.equal(clampCacheRam('x', limits), 'x');
});

test('every preset write leaves an explicit, bounded cache-ram', t => {
  const dir = tmp(t), file = path.join(dir, 'models.ini');
  fs.writeFileSync(file, 'version = 1\n\n[a]\nmodel = /models/a.gguf\n\n[b]\nmodel = /models/b.gguf\ncache-ram = 8192\n');
  const store = createPresetStore(file, { cacheRam: { capMib: 1024, hardMaxMib: 2048 } });
  const commit = c => fs.writeFileSync(file, c.text);
  const save = (model, options) => commit(store.prepare({ model, baseRevision: store.get(model).revision, options }));
  save('a', { 'ctx-size': '8192' });
  assert.equal(store.get('a').options['cache-ram'], '1024', 'a missing value becomes the cap, not the 8 GiB engine default');
  save('b', { 'ctx-size': '8192' });
  assert.equal(store.get('b').options['cache-ram'], '2048', 'an older oversized value is brought down to the hard maximum');
  save('a', { 'cache-ram': '16384' }); assert.equal(store.get('a').options['cache-ram'], '2048');
  save('a', { 'cache-ram': '-1' }); assert.equal(store.get('a').options['cache-ram'], '2048');
  save('a', { 'cache-ram': '512' }); assert.equal(store.get('a').options['cache-ram'], '512');
  save('a', { 'cache-ram': '' }); assert.equal(store.get('a').options['cache-ram'], '1024', 'clearing it writes the cap');
  save('new', { 'ctx-size': '4096' }); assert.equal(store.get('new').options['cache-ram'], '1024', 'a new section too');
  assert.throws(() => store.prepare({ model: 'a', baseRevision: store.get('a').revision, options: { 'cache-ram': 'lots' } }), /Invalid preset option: cache-ram/);
  assert.equal(fs.readFileSync(file, 'utf8').match(/cache-ram/g).length, 3, 'one line per section, never duplicated');
});

test('a bounded global cache-ram is inherited rather than repeated in the section', t => {
  const dir = tmp(t), file = path.join(dir, 'models.ini');
  fs.writeFileSync(file, 'version = 1\n\n[*]\ncache-ram = 768\n\n[a]\nmodel = /models/a.gguf\n');
  const store = createPresetStore(file, { cacheRam: { capMib: 1024, hardMaxMib: 2048 } });
  const c = store.prepare({ model: 'a', baseRevision: store.get('a').revision, options: { 'ctx-size': '8192' } });
  assert.doesNotMatch(c.text.split('[a]')[1], /cache-ram/);
});

// ── The estimate ─────────────────────────────────────────────────────────────

test('the footprint is (weights + KV at the preset context and cache types + projector + runtime) x 1.05 + cache-ram', () => {
  const kvQ8 = kvCacheBytes(qwenMeta, 32768) / GIB;
  const q8 = estimateFootprint({ meta: qwenMeta, modelBytes: 5 * GIB, options: { 'ctx-size': '32768', 'cache-type-k': 'q8_0', 'cache-type-v': 'q8_0', 'cache-ram': '1024' } });
  assert.equal(q8.ctx, 32768); assert.equal(q8.kvGib, Math.round(kvQ8 * 100) / 100); assert.equal(q8.cacheRamGib, 1);
  assert.equal(q8.totalGib, Math.round(((5 + kvQ8 + 1) * 1.05 + 1) * 100) / 100);
  // f16 (llama.cpp's default) holds 2 bytes per element against q8_0's 1.0625.
  const f16 = estimateFootprint({ meta: qwenMeta, modelBytes: 5 * GIB, options: { 'ctx-size': '32768', 'cache-ram': '1024' } });
  assert.ok(Math.abs(f16.kvGib - kvQ8 * 2 / 1.0625) < 0.01);
  // No cache-ram line: llama-server's 8 GiB default is what it would hold.
  assert.equal(estimateFootprint({ meta: qwenMeta, modelBytes: 5 * GIB, options: { 'ctx-size': '4096' } }).cacheRamGib, 8);
  const unbounded = estimateFootprint({ meta: qwenMeta, modelBytes: 5 * GIB, options: { 'cache-ram': '-1' } });
  assert.equal(unbounded.cacheRamUnbounded, true); assert.equal(unbounded.totalGib, null);
  // No ctx-size: the model's trained context, which is what the engine would allocate.
  assert.equal(estimateFootprint({ meta: qwenMeta, modelBytes: GIB, options: {} }).ctx, 262144);
  const vision = estimateFootprint({ meta: qwenMeta, modelBytes: 5 * GIB, mmprojBytes: GIB, options: { 'ctx-size': '4096', 'cache-ram': '0' } });
  assert.ok(vision.extraGib > 1 + 1 + 0.5 - 0.01, 'projector weights and vision scratch count');
});

test('autoconfig never suggests settings whose estimate, prompt cache included, exceeds the budget', () => {
  for (const budgetGib of [4, 8, 10, 12, 20]) {
    const r = suggest({ meta: qwenMeta, modelBytes: 5 * GIB, budgetGib, cacheRamMaxMib: 1024 });
    if (r.error) { assert.match(r.error, /more than the \d+ GiB budget/, `${budgetGib}: ${r.error}`); continue; }
    const est = estimateFootprint({ meta: qwenMeta, modelBytes: 5 * GIB, options: r.values });
    assert.ok(est.totalGib <= budgetGib, `${budgetGib} GiB: suggested ${r.values['ctx-size']} costs ${est.totalGib}`);
    assert.ok(Number(r.values['cache-ram']) <= 1024);
  }
});

// ── The load guard ───────────────────────────────────────────────────────────

function fixture(t, { section, budget = 2, state = { big: 'unloaded', small: 'unloaded', chat: 'loaded' } }) {
  const dir = tmp(t);
  fs.writeFileSync(path.join(dir, 'q.gguf'), gguf(qwen35));
  const ini = path.join(dir, 'models.ini');
  fs.writeFileSync(ini, `version = 1\n\n[big]\nmodel = /models/q.gguf\nctx-size = 262144\ncache-type-k = q8_0\ncache-type-v = q8_0\ncache-ram = 1024\n\n[small]\nmodel = /models/q.gguf\nctx-size = 4096\ncache-ram = 0\n\n[chat]\nmodel = /models/q.gguf\nctx-size = 4096\ncache-ram = 0\n${section || ''}`);
  const calls = [];
  let budgetGib = budget;
  const manager = createModelManager({ kind: 'llamacpp', baseUrl: 'http://synthetic', presetPath: ini, autoconfig: { modelsPath: dir },
    inferenceBudget: { budgetGib: () => budgetGib },
    fetchJson: async (url, options = {}) => {
      const p = new URL(url).pathname, body = options.body ? JSON.parse(options.body) : {};
      calls.push(`${options.method || 'GET'} ${p}${body.model ? ' ' + body.model : ''}`);
      if (p === '/models/unload') state[body.model] = 'unloaded';
      if (p === '/models/load') state[body.model] = 'loaded';
      return { ok: true, status: 200, body: p === '/models' ? { data: Object.entries(state).map(([id, value]) => ({ id, status: { value } })) } : { success: true } };
    } });
  return { manager, calls, state, setBudget: v => { budgetGib = v; } };
}

test('a load above the budget is refused before anything is evicted, with a clear error', async t => {
  const { manager, calls, state } = fixture(t, {});
  const r = await manager.load('big');
  assert.equal(r.ok, false); assert.equal(r.status, 409); assert.equal(r.body.code, 'inference_budget');
  assert.match(r.body.error, /^big needs about [\d.]+ GiB to load .*above the 2 GiB inference memory budget/);
  assert.match(r.body.error, /Settings → Models & routing/);
  assert.equal(state.chat, 'loaded', 'the loaded chat model was not unloaded for a load that cannot happen');
  assert.ok(!calls.some(c => c.startsWith('POST /models/')), calls.join('\n'));
});

test('the chat path refuses an over-budget model in makeRoomFor, leaving the current one loaded', async t => {
  const { manager, calls, state } = fixture(t, {});
  await assert.rejects(manager.makeRoomFor('big'), e => e.status === 409 && /inference memory budget/.test(e.publicMessage) && e.code === 'inference_budget');
  assert.equal(state.chat, 'loaded'); assert.ok(!calls.some(c => c.includes('/models/unload')));
});

test('calibration and auto-tune loads (the shared request helper) pass the same guard', async t => {
  const { manager, calls } = fixture(t, {});
  const refused = await manager.request('/models/load', { method: 'POST', body: JSON.stringify({ model: 'big' }) }, 1000);
  assert.equal(refused.status, 409); assert.equal(refused.body.code, 'inference_budget');
  assert.ok(!calls.includes('POST /models/load big'));
  const ok = await manager.request('/models/load', { method: 'POST', body: JSON.stringify({ model: 'small' }) }, 1000);
  assert.equal(ok.ok, true); assert.ok(calls.includes('POST /models/load small'));
});

test('a model that fits loads normally, and raising the budget lets the large one through', async t => {
  const { manager, state, setBudget } = fixture(t, {});
  assert.equal((await manager.load('small')).ok, true); assert.equal(state.small, 'loaded'); assert.equal(state.chat, 'unloaded');
  setBudget(64);
  assert.equal((await manager.load('big')).ok, true);
});

test('an unbounded prompt cache is refused under any budget', async t => {
  const { manager } = fixture(t, { section: '\n[open]\nmodel = /models/q.gguf\nctx-size = 4096\ncache-ram = -1\n', budget: 64, state: { open: 'unloaded' } });
  const r = await manager.load('open');
  assert.equal(r.status, 409); assert.match(r.body.error, /unbounded prompt cache/);
});

test('no budget, or a model whose file cannot be read, is not blocked (the watchdog still applies)', async t => {
  const none = fixture(t, { budget: 0 });
  assert.equal((await none.manager.load('big')).ok, true);
  const missing = fixture(t, { section: '\n[ghost]\nmodel = /models/absent.gguf\n', state: { ghost: 'unloaded' } });
  assert.equal((await missing.manager.load('ghost')).ok, true);
});

test('the Models page gets each model\'s estimate against the budget, read-only', async t => {
  const { manager, calls } = fixture(t, {});
  const r = await manager.inferenceEstimates();
  assert.equal(r.body.budgetGib, 2);
  const by = Object.fromEntries(r.body.models.map(m => [m.model, m]));
  assert.equal(by.big.fits, false); assert.equal(by.small.fits, true); assert.ok(by.big.estimate.totalGib > 2);
  assert.ok(calls.every(c => c === 'GET /models'), 'listing only');
});

test('autoconfig sizes against the inference budget, lowered only by an explicit autoconfig figure', async t => {
  const { manager } = fixture(t, { budget: 12 });
  assert.equal(manager.sizingBudgetGib(), 12);
  const dir = tmp(t); fs.writeFileSync(path.join(dir, 'q.gguf'), gguf(qwen35)); fs.writeFileSync(path.join(dir, 'models.ini'), 'version = 1\n\n[m]\nmodel = /models/q.gguf\n');
  const make = (autoconfig, budget) => createModelManager({ kind: 'llamacpp', baseUrl: 'http://synthetic', presetPath: path.join(dir, 'models.ini'), autoconfig: { modelsPath: dir, ...autoconfig }, inferenceBudget: { budgetGib: () => budget }, fetchJson: async () => ({ ok: true, status: 200, body: { data: [] } }) });
  // The container memory limit (budgetGib fallback) does not count GTT: the inference budget wins.
  assert.equal(make({ budgetGib: 14 }, 20).sizingBudgetGib(), 20);
  assert.equal((await make({ budgetGib: 14 }, 20).estimateMemory('m')).body.budgetGib, 20);
  assert.equal(make({ budgetGib: 14, explicitBudgetGib: 10 }, 20).sizingBudgetGib(), 10);
  assert.equal(make({ budgetGib: 14 }, 0).sizingBudgetGib(), 14, 'no inference budget: the deployment figure as before');
});

// ── Runtime safety net ──────────────────────────────────────────────────────

function watchFixture({ used, env = {}, loaded = ['chat'], budget = 12 }) {
  const log = [], unloaded = [];
  let t = 0;
  const w = createInferenceBudgetWatch({ env, budgetGib: () => budget, readGpu: async () => used.gpu, readEngine: async () => used.engine,
    listLoaded: async () => loaded, unload: async m => { unloaded.push(m); return { ok: true }; }, log: l => log.push(l), now: () => t,
    setIntervalFn: () => ({ unref() {} }), clearIntervalFn: () => {} });
  return { w, log, unloaded, advance: ms => { t += ms; } };
}

test('usage above the budget by more than 10% for two readings unloads the model and logs numbers only', async () => {
  const used = { gpu: { gttGib: 12, vramGib: 0.5 }, engine: { containerGib: 1.5 } }; // 14 GiB > 13.2
  const { w, log, unloaded } = watchFixture({ used });
  assert.equal((await w.tick()).state, 'over'); assert.deepEqual(unloaded, []);
  const r = await w.tick();
  assert.equal(r.state, 'unloaded'); assert.deepEqual(unloaded, ['chat']);
  assert.equal(log.length, 1);
  const event = JSON.parse(log[0].replace('[inference-budget] ', ''));
  assert.deepEqual(Object.keys(event).sort(), ['budgetGib', 'containerGib', 'event', 'failed', 'gttGib', 'limitGib', 'models', 'usedGib', 'vramGib'].sort());
  assert.equal(event.event, 'unload'); assert.equal(event.usedGib, 14); assert.equal(event.limitGib, 13.2);
});

test('usage within the 10% overshoot, or a single spike, leaves the model alone', async () => {
  const used = { gpu: { gttGib: 12.6, vramGib: 0.5 }, engine: { containerGib: 0 } }; // 13.1 <= 13.2
  const a = watchFixture({ used });
  for (let i = 0; i < 5; i++) assert.equal((await a.w.tick()).state, 'ok');
  assert.deepEqual(a.unloaded, []);
  const spike = { gpu: { gttGib: 20, vramGib: 0 }, engine: null };
  const b = watchFixture({ used: spike });
  await b.w.tick(); spike.gpu.gttGib = 4; assert.equal((await b.w.tick()).state, 'ok'); spike.gpu.gttGib = 20; await b.w.tick();
  assert.deepEqual(b.unloaded, [], 'strikes reset after a reading under the limit');
});

test('after an unload the watchdog waits out its cooldown before acting again', async () => {
  const used = { gpu: { gttGib: 20, vramGib: 0 }, engine: null };
  const f = watchFixture({ used });
  await f.w.tick(); await f.w.tick(); assert.equal(f.unloaded.length, 1);
  await f.w.tick(); await f.w.tick(); assert.equal(f.unloaded.length, 1);
  f.advance(61000); await f.w.tick(); assert.equal(f.unloaded.length, 2);
});

test('the overshoot and interval are configurable and the watchdog can be turned off', async () => {
  const used = { gpu: { gttGib: 12.5, vramGib: 0 }, engine: null };
  const strict = watchFixture({ used, env: { INFERENCE_BUDGET_OVERSHOOT_PCT: '0' } });
  await strict.w.tick(); await strict.w.tick(); assert.deepEqual(strict.unloaded, ['chat']);
  assert.equal(watchFixture({ used, env: { INFERENCE_BUDGET_WATCH_INTERVAL_MS: '30000' } }).w.intervalMs, 30000);
  const offWatch = watchFixture({ used, env: { INFERENCE_BUDGET_WATCH: 'off' } }).w;
  assert.equal(offWatch.enabled, false); assert.equal(offWatch.start(), false);
  assert.equal(watchFixture({ used }).w.start(), true, 'on by default');
});

test('with nothing measurable the watchdog does nothing', async () => {
  const f = watchFixture({ used: { gpu: null, engine: null } });
  assert.equal((await f.w.tick()).state, 'unavailable'); assert.deepEqual(f.unloaded, []);
});

test('GPU memory comes from the configured sysfs counters, or every DRM card when unset', () => {
  const files = { '/sys/class/drm/card1/device/mem_info_gtt_used': String(12 * GIB), '/sys/class/drm/card1/device/mem_info_vram_used': String(GIB / 2) };
  const exists = f => Object.hasOwn(files, f);
  const auto = gpuMemoryFiles({}, { readdir: () => ['card0', 'card1', 'card1-DP-1', 'renderD129'], exists });
  assert.deepEqual(auto, { gtt: ['/sys/class/drm/card1/device/mem_info_gtt_used'], vram: ['/sys/class/drm/card1/device/mem_info_vram_used'] });
  assert.deepEqual(readGpuMemory(auto, f => files[f]), { gttGib: 12, vramGib: 0.5 });
  const pinned = gpuMemoryFiles({ INFERENCE_GTT_USED_PATH: '/host-sys/card7/mem_info_gtt_used' }, { readdir: () => { throw Error('unused'); }, exists: () => false });
  assert.deepEqual(pinned, { gtt: ['/host-sys/card7/mem_info_gtt_used'], vram: [] });
  assert.equal(readGpuMemory(pinned, () => { throw Error('EACCES'); }), null);
});

test('engine container memory is read from the model manager\'s backend telemetry', async () => {
  const fetchJson = async url => { assert.match(url, /\/api\/v1\/backends$/); return { ok: true, status: 200, body: { backends: [{ stats: { ok: true, container: { mem_used_gb: 3.5 }, gpu: { shared_used_gb: 9, vram_used_gb: 0.4 } } }, { stats: { ok: false } }] } }; };
  assert.deepEqual(await engineReaderFromModelLoader({ env: { MODEL_LOADER_URL: 'http://model-loader:8090' }, fetchJson })(), { containerGib: 3.5, gttGib: 9, vramGib: 0.4 });
  assert.equal(await engineReaderFromModelLoader({ env: {}, fetchJson })(), null);
});

// ── Reranker routing ─────────────────────────────────────────────────────────

test('the RAG reranker never runs on the shared engine unless the operator allows it', () => {
  const base = { NOEVIA_FEATURE_RAG_RERANK: 'true', RERANK_MODEL: 'reranker', INFERENCE_BASE_URL: 'http://llama:8080/v1' };
  const shared = rerankTarget({ ...base, RERANK_BASE_URL: 'http://llama:8080/v1' });
  assert.equal(shared.enabled, false); assert.equal(shared.shared, true); assert.match(shared.reason, /shared inference engine/);
  assert.equal(rerankTarget({ ...base, RERANK_BASE_URL: 'http://LLAMA:8080' }).enabled, false, 'same origin, any path or case');
  const sidecar = rerankTarget({ ...base, RERANK_BASE_URL: 'http://rerank:8080/v1' });
  assert.equal(sidecar.enabled, true); assert.equal(sidecar.shared, false);
  assert.equal(rerankTarget({ ...base, RERANK_BASE_URL: 'http://llama:8080/v1', RERANK_SHARED_ENGINE: 'allow' }).enabled, true);
  assert.equal(rerankTarget({ ...base, NOEVIA_FEATURE_RAG_RERANK: 'false', RERANK_BASE_URL: 'http://rerank:8080/v1' }).enabled, false);
});

test('only models the engine itself serves are kept beside the chat model', () => {
  assert.deepEqual(keepAlongside({ EMBEDDING_MODEL: 'nomic', EMBEDDING_BASE_URL: 'http://embed:8080/v1' }), [], 'embeddings on their own sidecar');
  assert.deepEqual(keepAlongside({ EMBEDDING_MODEL: 'nomic' }), ['nomic']);
  const rr = { NOEVIA_FEATURE_RAG_RERANK: '1', RERANK_MODEL: 'reranker', INFERENCE_BASE_URL: 'http://llama:8080/v1', EMBEDDING_BASE_URL: 'http://embed:8080/v1' };
  assert.deepEqual(keepAlongside({ ...rr, RERANK_BASE_URL: 'http://llama:8080/v1' }), [], 'refused on the shared engine');
  assert.deepEqual(keepAlongside({ ...rr, RERANK_BASE_URL: 'http://rerank:8080/v1' }), [], 'its own sidecar: nothing to keep in the engine');
  assert.deepEqual(keepAlongside({ ...rr, RERANK_BASE_URL: 'http://llama:8080/v1', RERANK_SHARED_ENGINE: 'allow' }), ['reranker']);
});

// ── Compose ─────────────────────────────────────────────────────────────────

test('the engine runs one model at a time in every compose file that defines it', () => {
  const root = path.resolve(__dirname, '../../..');
  for (const file of ['compose.llamacpp.yaml', 'deploy/examples/unraid-llamacpp.override.yml']) {
    const text = fs.readFileSync(path.join(root, file), 'utf8');
    const command = /^\s{4}command: (\[.*\])$/m.exec(text.split(/^\s{2}llama:$/m)[1])?.[1];
    assert.ok(command, file);
    const args = JSON.parse(command);
    assert.equal(args[args.indexOf('--models-max') + 1], '1', file);
  }
});

test('the optional reranker sidecar is CPU-only, bounded and off the engine', () => {
  const root = path.resolve(__dirname, '../../..');
  const text = fs.readFileSync(path.join(root, 'compose.rerank.yaml'), 'utf8');
  const service = text.split(/^\s{2}rerank:$/m)[1].split(/^\s{2}\w[\w-]*:$/m)[0];
  for (const flag of ['"--device"', '"none"', '"--reranking"']) assert.ok(service.includes(flag), flag);
  assert.match(service, /mem_limit: \$\{RERANK_MEMORY_LIMIT:-1536m\}/);
  assert.doesNotMatch(service, /devices:/, 'no GPU device');
  assert.match(text, /RERANK_BASE_URL: http:\/\/rerank:8080\/v1/);
});
