#!/usr/bin/env node
'use strict';
// KoboldCpp vs native llama.cpp on the same GGUF: speed, and the API features noevia relies on.
// Synthetic prompts only. Env: ENGINES="name|baseUrl|model,..." REPEATS (3) SIZES ("2000,15000").
const zlib = require('node:zlib');

const ENGINES = (process.env.ENGINES || '').split(',').filter(Boolean).map((e) => { const [name, base, model] = e.split('|'); return { name, base: base.replace(/\/$/, ''), model }; });
const REPEATS = Number(process.env.REPEATS || 3);
const SIZES = (process.env.SIZES || '2000,15000').split(',').map(Number);
const FILLER = 'The garden committee reviewed irrigation, seed orders, volunteer rotas and the pump maintenance log in detail. ';

async function post(engine, path, body, timeout = 600000) {
  const started = Date.now();
  const r = await fetch(engine.base + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(timeout) });
  const text = await r.text();
  let json = null; try { json = JSON.parse(text); } catch {}
  return { status: r.status, ms: Date.now() - started, json, text };
}

function prompt(tokens, nonce) {
  // ~22 tokens per filler sentence on Qwen tokenizers; the nonce defeats prompt caches.
  const body = FILLER.repeat(Math.max(1, Math.round(tokens / 22)));
  return `Run ${nonce}.\n${body}\nIn one sentence, what did the committee review?`;
}

const noThink = { chat_template_kwargs: { enable_thinking: false }, reasoning_budget: 0 };

async function speed(engine, size, rep) {
  const nonce = `${engine.name}-${size}-${rep}-${Date.now()}`;
  const r = await post(engine, '/chat/completions', { model: engine.model, messages: [{ role: 'user', content: prompt(size, nonce) }], max_tokens: 128, temperature: 0, stream: false, ...noThink });
  const u = r.json?.usage || {}, t = r.json?.timings || {};
  let pp = t.prompt_per_second ?? null, tg = t.predicted_per_second ?? null;
  if (pp == null) { // KoboldCpp: last request's timings from its perf endpoint
    try {
      const perf = await (await fetch(engine.base.replace(/\/v1$/, '') + '/api/extra/perf')).json();
      if (perf.last_process_speed) pp = perf.last_process_speed;
      if (perf.last_eval_speed) tg = perf.last_eval_speed;
    } catch {}
  }
  return { engine: engine.name, test: 'speed', size, rep, status: r.status, wallMs: r.ms, promptTokens: u.prompt_tokens ?? null, completionTokens: u.completion_tokens ?? null,
    promptTps: pp && +pp.toFixed(1), genTps: tg && +tg.toFixed(1), finish: r.json?.choices?.[0]?.finish_reason ?? null, error: r.status === 200 ? null : r.text.slice(0, 200) };
}

const TOOLS = [
  { type: 'function', function: { name: 'get_weather', description: 'Current weather for a city.', parameters: { type: 'object', properties: { city: { type: 'string' }, unit: { type: 'string', enum: ['celsius', 'fahrenheit'] } }, required: ['city'] } } },
  { type: 'function', function: { name: 'add_task', description: 'Add a task to the to-do list.', parameters: { type: 'object', properties: { title: { type: 'string' }, due: { type: 'string', description: 'YYYY-MM-DD' } }, required: ['title'] } } },
];
const TOOL_CASES = [
  ['What is the weather in Oslo in celsius?', 'get_weather', (a) => /oslo/i.test(a.city || '')],
  ['Add a task "buy tomato seeds" due 2026-10-01.', 'add_task', (a) => /tomato/i.test(a.title || '') && a.due === '2026-10-01'],
  ['Say hello. Do not use any tool.', null, () => true],
];

async function tools(engine) {
  const out = [];
  for (const [q, want, check] of TOOL_CASES) {
    const r = await post(engine, '/chat/completions', { model: engine.model, messages: [{ role: 'user', content: q }], tools: TOOLS, tool_choice: 'auto', max_tokens: 256, temperature: 0, ...noThink });
    const call = r.json?.choices?.[0]?.message?.tool_calls?.[0];
    let args = null, parsed = false;
    try { args = JSON.parse(call?.function?.arguments || 'null'); parsed = !!args; } catch {}
    const name = call?.function?.name || null;
    const ok = want ? name === want && parsed && check(args) : !name;
    out.push({ engine: engine.name, test: 'tools', q, status: r.status, name, args, ok, finish: r.json?.choices?.[0]?.finish_reason ?? null, ms: r.ms });
  }
  return out;
}

async function reasoning(engine) {
  const r = await post(engine, '/chat/completions', { model: engine.model, messages: [{ role: 'user', content: 'What is 17 * 23? Answer with the number.' }], max_tokens: 1500, temperature: 0, chat_template_kwargs: { enable_thinking: true } });
  const m = r.json?.choices?.[0]?.message || {};
  const content = m.content || '';
  return { engine: engine.name, test: 'reasoning', status: r.status, separated: !!(m.reasoning_content && m.reasoning_content.length), thinkTagsInContent: /<think>|<\/think>/.test(content), correct: /391/.test(content), ms: r.ms };
}

function png(r, g, b, size = 64) {
  const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = (buf) => { let c = 0xffffffff; for (const x of buf) c = crcTable[(c ^ x) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4); ihdr[8] = 8; ihdr[9] = 2;
  const row = Buffer.concat([Buffer.from([0]), Buffer.from(Array.from({ length: size }, () => [r, g, b]).flat())]);
  const raw = Buffer.concat(Array.from({ length: size }, () => row));
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

async function vision(engine) {
  const url = 'data:image/png;base64,' + png(220, 20, 20).toString('base64');
  const r = await post(engine, '/chat/completions', { model: engine.model, max_tokens: 60, temperature: 0, ...noThink,
    messages: [{ role: 'user', content: [{ type: 'text', text: 'What single colour fills this image? One word.' }, { type: 'image_url', image_url: { url } }] }] });
  const content = r.json?.choices?.[0]?.message?.content || '';
  return { engine: engine.name, test: 'vision', status: r.status, answer: content.slice(0, 60), ok: /red/i.test(content), ms: r.ms, error: r.status === 200 ? null : r.text.slice(0, 160) };
}

async function embeddings(engine, model) {
  const r = await post(engine, '/embeddings', { model, input: ['search_query: tomato harvest', 'search_document: the pump filter'] });
  const d = r.json?.data || [];
  return { engine: engine.name, test: 'embeddings', status: r.status, vectors: d.length, dims: d[0]?.embedding?.length ?? null, ms: r.ms, error: r.status === 200 ? null : r.text.slice(0, 160) };
}

async function streaming(engine) {
  const started = Date.now();
  const r = await fetch(engine.base + '/chat/completions', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: engine.model, stream: true, stream_options: { include_usage: true }, max_tokens: 40, temperature: 0, ...noThink, messages: [{ role: 'user', content: 'Count from 1 to 10.' }] }) });
  let first = null, chunks = 0, done = false, usage = false, text = '';
  for await (const part of r.body) {
    const s = Buffer.from(part).toString();
    for (const line of s.split('\n')) {
      if (!line.startsWith('data:')) continue;
      const data = line.slice(5).trim();
      if (data === '[DONE]') { done = true; continue; }
      try { const j = JSON.parse(data); if (j.usage) usage = true; const c = j.choices?.[0]?.delta?.content; if (c) { chunks++; text += c; if (first == null) first = Date.now() - started; } } catch {}
    }
  }
  return { engine: engine.name, test: 'streaming', status: r.status, firstTokenMs: first, contentChunks: chunks, doneMarker: done, usageChunk: usage, text: text.slice(0, 40) };
}

async function main() {
  if (!ENGINES.length) { console.error('Set ENGINES="name|baseUrl|model,..."'); process.exit(2); }
  const rows = [];
  const log = (row) => { rows.push(row); console.error(JSON.stringify(row).slice(0, 240)); };
  // Warm load, then alternate engines per repeat so drift hits both.
  for (const e of ENGINES) log({ engine: e.name, test: 'warmup', ...(await post(e, '/chat/completions', { model: e.model, messages: [{ role: 'user', content: 'Hi' }], max_tokens: 4, ...noThink }).then((r) => ({ status: r.status, ms: r.ms }))) });
  for (let rep = 1; rep <= REPEATS; rep++) for (const size of SIZES) for (const e of rep % 2 ? ENGINES : [...ENGINES].reverse()) log(await speed(e, size, rep));
  for (const e of ENGINES) {
    for (const row of await tools(e)) log(row);
    log(await reasoning(e));
    log(await vision(e));
    log(await streaming(e));
    log(await embeddings(e, process.env[`EMBED_MODEL_${e.name.toUpperCase()}`] || 'nomic-embed-text-v1'));
  }
  const med = (xs) => { const v = xs.filter((x) => x != null).sort((a, b) => a - b); return v.length ? v[Math.floor(v.length / 2)] : null; };
  const summary = {};
  for (const e of ENGINES) {
    const r = rows.filter((x) => x.engine === e.name);
    summary[e.name] = {
      speed: Object.fromEntries(SIZES.map((s) => { const x = r.filter((y) => y.test === 'speed' && y.size === s && y.status === 200); return [s, { runs: x.length, medianWallMs: med(x.map((y) => y.wallMs)), medianPromptTps: med(x.map((y) => y.promptTps)), medianGenTps: med(x.map((y) => y.genTps)), promptTokens: med(x.map((y) => y.promptTokens)) }]; })),
      tools: `${r.filter((x) => x.test === 'tools' && x.ok).length}/${TOOL_CASES.length}`,
      reasoning: r.find((x) => x.test === 'reasoning'), vision: r.find((x) => x.test === 'vision'), streaming: r.find((x) => x.test === 'streaming'), embeddings: r.find((x) => x.test === 'embeddings'),
    };
  }
  console.log(JSON.stringify({ date: new Date().toISOString(), engines: ENGINES, repeats: REPEATS, sizes: SIZES, summary, rows }, null, 1));
}
main().catch((e) => { console.error(e.stack || e.message); process.exit(1); });
