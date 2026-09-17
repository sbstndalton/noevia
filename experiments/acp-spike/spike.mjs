// ACP spike: does an agent ask permission (and use client fs) before writing files?
// Fake OpenAI-compatible model scripts the tool calls; nothing leaves this machine.
import http from 'node:http'; import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
import { spawn } from 'node:child_process'; import { Readable, Writable } from 'node:stream';
import { ClientSideConnection, ndJsonStream, PROTOCOL_VERSION } from '@agentclientprotocol/sdk';

const policy = process.argv[2] || 'reject'; // reject | allow
const ws = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'acp-ws-')));
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'acp-home-'));
const log = { policy, toolsOffered: [], toolCalls: [], permissions: [], clientFs: [], modelRounds: 0 };
let step = 0;
const sse = (res, chunks) => { res.writeHead(200, { 'Content-Type': 'text/event-stream' }); for (const c of chunks) res.write(`data: ${JSON.stringify(c)}\n\n`); res.end('data: [DONE]\n\n'); };
const model = http.createServer(async (req, res) => {
  let raw = ''; for await (const c of req) raw += c;
  if (!req.url.includes('chat/completions')) { res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end('{"data":[{"id":"m"}]}'); }
  const body = JSON.parse(raw); log.modelRounds++;
  const names = (body.tools || []).map((t) => t.function?.name); if (!log.toolsOffered.length) log.toolsOffered = names;
  const hasToolResult = body.messages.some((m) => m.role === 'tool');
  const base = { id: 'x', object: 'chat.completion.chunk', created: 1, model: 'm' };
  if (!body.tools?.length) return sse(res, [{ ...base, choices: [{ index: 0, delta: { role: 'assistant', content: 'Title' }, finish_reason: 'stop' }] }]);
  if (!hasToolResult && step === 0) {
    step = 1;
    const tool = names.includes('write') ? 'write' : names.find((n) => /write|edit|create/i.test(n));
    const args = JSON.stringify({ filePath: path.join(ws, 'hello.txt'), content: 'written by agent\n' });
    return sse(res, [{ ...base, choices: [{ index: 0, delta: { role: 'assistant', tool_calls: [{ index: 0, id: 'call_1', type: 'function', function: { name: tool, arguments: args } }] }, finish_reason: null }] },
      { ...base, choices: [{ index: 0, delta: {}, finish_reason: 'tool_calls' }] }]);
  }
  return sse(res, [{ ...base, choices: [{ index: 0, delta: { role: 'assistant', content: 'Done.' }, finish_reason: 'stop' }] }]);
});
await new Promise((r) => model.listen(0, '127.0.0.1', r));
fs.writeFileSync(path.join(ws, 'opencode.json'), JSON.stringify({
  $schema: 'https://opencode.ai/config.json', autoupdate: false, share: 'disabled',
  provider: { fake: { npm: '@ai-sdk/openai-compatible', name: 'Fake', options: { baseURL: `http://127.0.0.1:${model.address().port}/v1`, apiKey: 'synthetic' }, models: { m: { name: 'm', tool_call: true } } } },
  model: 'fake/m', small_model: 'fake/m', ...(process.env.ASK ? { permission: { edit: 'ask', bash: 'ask', webfetch: 'ask' } } : {}),
}));
const agent = spawn(path.resolve('node_modules/.bin/opencode'), ['acp'], { cwd: ws, env: { ...process.env, HOME: home, XDG_CONFIG_HOME: path.join(home, '.config'), XDG_DATA_HOME: path.join(home, '.data'), XDG_CACHE_HOME: path.join(home, '.cache'), OPENCODE_DISABLE_AUTOUPDATE: '1' }, stdio: ['pipe', 'pipe', 'pipe'] });
let stderr = ''; agent.stderr.on('data', (d) => { stderr += d; });
const conn = new ClientSideConnection(() => ({
  async requestPermission(p) {
    log.permissions.push({ title: p.toolCall?.title, kind: p.toolCall?.kind, options: p.options.map((o) => o.kind) });
    const want = policy === 'allow' ? 'allow_once' : 'reject_once';
    const opt = p.options.find((o) => o.kind === want) || p.options[0];
    return { outcome: { outcome: 'selected', optionId: opt.optionId } };
  },
  async sessionUpdate(n) { const u = n.update; if (u.sessionUpdate === 'tool_call' || u.sessionUpdate === 'tool_call_update') log.toolCalls.push({ type: u.sessionUpdate, kind: u.kind, status: u.status, title: u.title }); },
  async readTextFile(p) { log.clientFs.push({ op: 'read', path: p.path }); return { content: fs.existsSync(p.path) ? fs.readFileSync(p.path, 'utf8') : '' }; },
  async writeTextFile(p) { log.clientFs.push({ op: 'write', path: p.path }); fs.writeFileSync(p.path, p.content); return {}; },
}), ndJsonStream(Writable.toWeb(agent.stdin), Readable.toWeb(agent.stdout)));
const timeout = setTimeout(() => { log.error = 'timeout'; finish(); }, 120000);
function finish() {
  clearTimeout(timeout);
  log.fileExists = fs.existsSync(path.join(ws, 'hello.txt'));
  log.stderrTail = stderr.split('\n').filter(Boolean).slice(-5);
  console.log(JSON.stringify(log, null, 2));
  agent.kill(); model.close(); fs.rmSync(ws, { recursive: true, force: true }); fs.rmSync(home, { recursive: true, force: true }); process.exit(0);
}
try {
  const init = await conn.initialize({ protocolVersion: PROTOCOL_VERSION, clientCapabilities: { fs: { readTextFile: true, writeTextFile: true }, terminal: false } });
  log.agent = init.agentInfo || null; log.protocolVersion = init.protocolVersion;
  const session = await conn.newSession({ cwd: ws, mcpServers: [] });
  const result = await conn.prompt({ sessionId: session.sessionId, prompt: [{ type: 'text', text: 'Create hello.txt' }] });
  log.stopReason = result.stopReason;
} catch (e) { log.error = String(e?.message || e); }
finish();
