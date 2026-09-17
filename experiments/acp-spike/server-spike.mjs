// CodeHarness spike on DaServer (D14): OpenCode over ACP, a real local model, inside a sandbox.
// Runs INSIDE the sandbox container (see README "Server spike"): read-only root, non-root, no
// capabilities, only /work writable, network = an internal Docker network whose only other member
// is the engine. The client approves edits inside /work, rejects everything else, allows commands
// (the sandbox is what contains them) and logs every tool call, permission and client fs call.
// After the agent stops, the harness checks the task and probes the sandbox from the same process.
import fs from 'node:fs'; import path from 'node:path'; import { spawn, spawnSync } from 'node:child_process';
import { Readable, Writable } from 'node:stream';
import { ClientSideConnection, ndJsonStream, PROTOCOL_VERSION } from '@agentclientprotocol/sdk';

const WORK = '/work', BASE = process.env.MODEL_BASE, MODEL = process.env.MODEL, CTX = Number(process.env.MODEL_CTX || 16384);
const LIMIT_MS = Number(process.env.LIMIT_MS || 900000);
if (!BASE || !MODEL) { console.error('Set MODEL_BASE and MODEL'); process.exit(2); }
const inside = (p) => { const r = path.resolve(WORK, p); return r === WORK || r.startsWith(WORK + '/'); };
const log = { model: MODEL, started: new Date().toISOString(), toolCalls: [], permissions: [], clientFs: [], terminal: [], errors: [] };

// Synthetic task: a small bug with a test. Nothing from any real repository.
fs.rmSync(path.join(WORK, 'task'), { recursive: true, force: true });
fs.mkdirSync(path.join(WORK, 'task'), { recursive: true });
const TASK = path.join(WORK, 'task');
fs.writeFileSync(path.join(TASK, 'stats.js'), `// Returns the median of a non-empty array of numbers.\nfunction median(values) {\n  const sorted = values.sort();\n  const mid = Math.floor(sorted.length / 2);\n  return sorted[mid];\n}\nmodule.exports = { median };\n`);
fs.writeFileSync(path.join(TASK, 'test.js'), `const assert = require('node:assert/strict');\nconst { median } = require('./stats.js');\nassert.equal(median([3, 1, 2]), 2);\nassert.equal(median([10, 2, 33, 4]), 7);\nconst input = [5, 1, 4];\nmedian(input);\nassert.deepEqual(input, [5, 1, 4], 'median must not modify its input');\nconsole.log('all tests passed');\n`);
const testSha = fs.readFileSync(path.join(TASK, 'test.js'), 'utf8');
const pinned = { edit: 'ask', bash: 'ask', webfetch: 'ask' };
fs.writeFileSync(path.join(TASK, 'opencode.json'), JSON.stringify({
  $schema: 'https://opencode.ai/config.json', autoupdate: false, share: 'disabled',
  provider: { local: { npm: '@ai-sdk/openai-compatible', name: 'noevia engine', options: { baseURL: BASE, apiKey: 'none' },
    models: { [MODEL]: { name: MODEL, tool_call: true, limit: { context: CTX, output: 4096 } } } } },
  model: `local/${MODEL}`, small_model: `local/${MODEL}`, permission: pinned,
}));

const agent = spawn('/app/node_modules/.bin/opencode', ['acp'], { cwd: TASK, env: { PATH: process.env.PATH, HOME: process.env.HOME, XDG_CONFIG_HOME: '/tmp/cfg', XDG_DATA_HOME: '/tmp/data', XDG_CACHE_HOME: '/tmp/cache', OPENCODE_DISABLE_AUTOUPDATE: '1' }, stdio: ['pipe', 'pipe', 'pipe'] });
let stderr = ''; agent.stderr.on('data', (d) => { stderr = (stderr + d).slice(-20000); });
const terms = {};
const conn = new ClientSideConnection(() => ({
  async requestPermission(p) {
    const tc = p.toolCall || {}, kind = tc.kind || 'other';
    const locations = (tc.locations || []).map((l) => l.path);
    // Edits only inside the worktree; commands allowed (sandboxed); fetch and anything else refused.
    const allow = (kind === 'edit' && locations.length > 0 && locations.every(inside)) || kind === 'execute';
    const opt = p.options.find((o) => o.kind === (allow ? 'allow_once' : 'reject_once')) || p.options[0];
    log.permissions.push({ kind, title: String(tc.title || '').slice(0, 160), locations, decision: opt.kind });
    return { outcome: { outcome: 'selected', optionId: opt.optionId } };
  },
  async sessionUpdate(n) {
    const u = n.update;
    if (u.sessionUpdate === 'tool_call' || u.sessionUpdate === 'tool_call_update') log.toolCalls.push({ type: u.sessionUpdate, kind: u.kind, status: u.status, title: String(u.title || '').slice(0, 120) });
  },
  async readTextFile(p) { log.clientFs.push({ op: 'read', path: p.path, inside: inside(p.path) }); if (!inside(p.path)) throw Error('outside the worktree'); return { content: fs.existsSync(p.path) ? fs.readFileSync(p.path, 'utf8') : '' }; },
  async writeTextFile(p) { log.clientFs.push({ op: 'write', path: p.path, inside: inside(p.path) }); if (!inside(p.path)) throw Error('outside the worktree'); fs.writeFileSync(p.path, p.content); return {}; },
  async createTerminal(p) {
    log.terminal.push({ command: p.command, args: p.args });
    const child = spawn(p.command, p.args || [], { cwd: inside(p.cwd || TASK) ? (p.cwd || TASK) : TASK, shell: !p.args?.length });
    const t = { out: '', code: null }; child.stdout.on('data', (d) => { t.out += d; }); child.stderr.on('data', (d) => { t.out += d; });
    t.done = new Promise((r) => child.on('exit', (code) => { t.code = code; r(); }));
    const id = `t${log.terminal.length}`; terms[id] = t; return { terminalId: id };
  },
  async terminalOutput(p) { const t = terms[p.terminalId]; return { output: t.out.slice(-20000), truncated: t.out.length > 20000, exitStatus: t.code === null ? undefined : { exitCode: t.code } }; },
  async waitForTerminalExit(p) { const t = terms[p.terminalId]; await t.done; return { exitCode: t.code }; },
  async releaseTerminal() { return {}; },
  async killTerminal() { return {}; },
}), ndJsonStream(Writable.toWeb(agent.stdin), Readable.toWeb(agent.stdout)));

const started = Date.now();
let timer;
try {
  await Promise.race([
    (async () => {
      const init = await conn.initialize({ protocolVersion: PROTOCOL_VERSION, clientCapabilities: { fs: { readTextFile: true, writeTextFile: true }, terminal: true } });
      log.agent = init.agentInfo || null;
      const session = await conn.newSession({ cwd: TASK, mcpServers: [] });
      const result = await conn.prompt({ sessionId: session.sessionId, prompt: [{ type: 'text', text: 'In this folder, fix the bug in stats.js so that `node test.js` passes. Do not change test.js. Run the test to check your fix.' }] });
      log.stopReason = result.stopReason;
    })(),
    new Promise((_, reject) => { timer = setTimeout(() => reject(Error(`time limit ${LIMIT_MS} ms`)), LIMIT_MS); }),
  ]);
} catch (e) { log.errors.push(String(e?.message || e)); }
clearTimeout(timer);
log.wallMs = Date.now() - started;
agent.kill();

// Outcome, checked by the harness rather than trusted from the agent.
const run = spawnSync('node', ['test.js'], { cwd: TASK, encoding: 'utf8', timeout: 20000 });
log.testPassed = run.status === 0;
log.testOutput = (run.stdout + run.stderr).slice(-400);
log.testUnchanged = fs.readFileSync(path.join(TASK, 'test.js'), 'utf8') === testSha;
log.solved = log.testPassed && log.testUnchanged;

// Sandbox probes from inside the same container.
const probe = (name, fn) => { try { log.probes[name] = fn(); } catch (e) { log.probes[name] = `blocked: ${String(e.code || e.message).slice(0, 80)}`; } };
log.probes = {};
probe('writeRoot', () => { fs.writeFileSync('/etc/noevia-escape', 'x'); return 'WROTE /etc'; });
probe('writeApp', () => { fs.writeFileSync('/app/noevia-escape', 'x'); return 'WROTE /app'; });
probe('dockerSocket', () => (fs.existsSync('/var/run/docker.sock') ? 'PRESENT' : 'absent'));
probe('secretsInEnv', () => Object.keys(process.env).filter((k) => /TOKEN|KEY|SECRET|PASSWORD/i.test(k)).join(',') || 'none');
const net = async (url) => { try { const r = await fetch(url, { signal: AbortSignal.timeout(6000) }); return `REACHED ${r.status}`; } catch (e) { return `blocked: ${String(e.cause?.code || e.message).slice(0, 60)}`; } };
log.probes.internet = await net('https://huggingface.co/');
log.probes.modelLoader = await net('http://model-loader:8090/api/v1/health');
log.probes.web = await net('http://web:8020/');
log.probes.diary = await net('http://diary:8000/');
log.probes.engine = await net(`${BASE}/models`);
log.stderrTail = stderr.split('\n').filter(Boolean).slice(-8);
console.log(JSON.stringify(log, null, 2));
process.exit(0);
