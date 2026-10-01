'use strict';
// The coding sandbox's supervisor (spec-agent-execution §3).
//
// It exists so that a coding agent never runs inside the container that holds noevia's state,
// sessions and credentials — and so that noevia never needs a Docker socket to start one, which
// is the highest-severity finding `research-master-container.md` recorded.
//
// What it does is deliberately almost nothing: accept one connection, read one noevia line
// saying which worktree to run in, spawn the agent, and pipe. Everything after that first line
// is the ACP stream, byte for byte, in both directions. It makes no decisions about
// permissions, paths or tools — noevia does, at the other end of the pipe.
//
// What it does decide is what it will be told:
//   * `cwd` must resolve (realpath, so a symlink cannot point out) inside WORKSPACE_ROOT.
//   * Only an allowlisted set of environment variables is accepted, and nothing of this
//     process's own environment is passed on.
//   * One agent per connection; closing the connection kills that agent's process group.
//   * Its own limits (#115), not only the container's: at most `maxConnections` live connections
//     (CODE_SANDBOX_MAX_CONNECTIONS, default 4; more are refused with a JSON-RPC error), and an
//     agent running longer than `maxWallMs` (CODE_SANDBOX_MAX_WALL_MS, default 2 h) is stopped
//     — SIGTERM to its group, SIGKILL after the grace period.
//
//   * A second mode, `verify` (#703), runs the operator's test command for one repository in a
//     read-only checkout and reports only what the server measured. See `runVerify` below.
//
// It listens on an internal network only. There is no authentication here on purpose: a
// deployment that lets anything but noevia reach this port has already lost, and a shared
// secret in an env var would suggest otherwise. The compose override is the control.
const net = require('node:net'), fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { spawn } = require('node:child_process');

const MAX_START_LINE = 64 * 1024;
const DEFAULT_MAX_CONNECTIONS = 4;
const DEFAULT_MAX_WALL_MS = 2 * 60 * 60 * 1000;
const positive = (value, fallback) => { const n = Number(value); return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback; };
// Passed through when noevia sends them; everything else is dropped without comment.
const ALLOWED_ENV = new Set(['HOME', 'PATH', 'LANG', 'TMPDIR',
  'HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy', 'NO_PROXY', 'CURL_HOME', 'WGETRC']);

// ---- verify mode (#703) ----
//
// Server-measured verification. noevia asks "run the tests of repository R at commit S in this
// checkout"; the supervisor answers with an exit code and a bounded tail of output, nothing else.
// What makes the answer worth trusting:
//   * The command is the OPERATOR's: `CODE_VERIFY=name|command`, one entry per line, read from this
//     container's own environment at start. noevia sends a repository NAME, never a command, and
//     nothing is ever read from the repository (no `.noevia/verify.json`, no script discovery).
//     A command such as `npm test` still runs the repository's own test code — that is the point
//     of a test — but the decision about pass or fail is the exit status measured here.
//   * The checkout must be read-only to this process and detached at exactly the requested commit:
//     noevia builds it (code-workspace.cjs `verifyCheckout`), owned by noevia's user, mode 0555/0444.
//     A tree the harness can write — its own task clone — fails the write check and is refused.
//   * A fixed environment: PATH, a fresh HOME/TMPDIR under this container's /tmp, LANG and CI. No
//     proxy variables (so no route out of the internal network), and nothing noevia sent.
//   * A wall-time limit (CODE_VERIFY_WALL_MS, default 10 min, never above the agent limit), a CPU
//     limit per process, no core dumps, stdin closed, its own process group killed at the end, and
//     the container's own pids/memory limits underneath.
//   * Output is kept as a rolling tail of at most CODE_VERIFY_TAIL_BYTES (default 16 KiB) and sent
//     back as a JSON string inside ONE result line, so nothing the tests print can forge a result.
const DEFAULT_VERIFY_WALL_MS = 10 * 60 * 1000;
const DEFAULT_VERIFY_TAIL_BYTES = 16 * 1024;
const MAX_VERIFY_TAIL_BYTES = 256 * 1024;
const REPO_NAME = /^[A-Za-z0-9_.-]{1,64}$/;
const COMMIT = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;

/** `CODE_VERIFY=name|command` per line. First entry for a name wins; malformed lines are dropped. */
function parseVerify(raw) {
  const out = new Map();
  for (const line of String(raw || '').split(/\r?\n/)) {
    const bar = line.indexOf('|');
    if (bar < 1) continue;
    const name = line.slice(0, bar).trim(), command = line.slice(bar + 1).trim();
    if (!REPO_NAME.test(name) || !command || command.length > 4096 || out.has(name)) continue;
    out.set(name, command);
  }
  return out;
}

/**
 * Why `dir` is not a checkout the tests may run in, or null when it is: a plain `.git` directory
 * whose HEAD is detached at exactly `sha`, and neither the tree nor its `.git` writable by us.
 */
function verifyCheckoutReason(dir, sha, access = fs.accessSync, selfUid = currentUid()) {
  const gitDir = path.join(dir, '.git');
  let st;
  try { st = fs.lstatSync(gitDir); } catch { return 'the checkout has no .git directory'; }
  if (!st.isDirectory()) return 'the checkout’s .git is not a plain directory';
  // Mode bits alone are not read-only to their owner, who can chmod them back. The checkout must
  // belong to noevia's user, which the sandbox deliberately is not (CODE_HARNESS_USER).
  for (const target of [dir, gitDir]) {
    let owner;
    try { owner = fs.statSync(target).uid; } catch { return 'the checkout could not be read'; }
    if (selfUid !== null && owner === selfUid) return 'the checkout belongs to the sandbox user, so it is not read-only to the tests';
  }
  let head = '';
  try { head = fs.readFileSync(path.join(gitDir, 'HEAD'), 'utf8').trim(); } catch { return 'the checkout has no HEAD'; }
  if (head !== sha) return 'the checkout is not detached at the requested commit';
  for (const target of [dir, gitDir]) {
    let writable = true;
    try { access(target, fs.constants.W_OK); } catch { writable = false; }
    if (writable) return 'the checkout is writable, so it is not one noevia prepared for verification';
  }
  return null;
}

function currentUid() { return typeof process.getuid === 'function' ? process.getuid() : null; }

/** The only environment a verify command gets. Nothing from noevia, no proxy. */
function verifyEnv(home, basePath = process.env.PATH) {
  return { PATH: basePath || '/usr/local/bin:/usr/bin:/bin', HOME: home, TMPDIR: home, LANG: 'C.UTF-8', CI: 'true', NO_COLOR: '1' };
}

/** A rolling buffer that keeps only the last `cap` bytes of everything written to it. */
function createTail(cap) {
  let chunks = [], kept = 0, total = 0;
  return {
    push(chunk) {
      const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk));
      total += buf.length;
      chunks.push(buf); kept += buf.length;
      if (kept > cap * 2) { const all = Buffer.concat(chunks); chunks = [all.subarray(all.length - cap)]; kept = cap; }
    },
    read() {
      const all = Buffer.concat(chunks);
      const tail = all.length > cap ? all.subarray(all.length - cap) : all;
      return { tail: tail.toString('utf8'), tailBytes: tail.length, totalBytes: total, truncated: total > tail.length };
    },
  };
}

function insideRoot(root, candidate) {
  let resolvedRoot, resolved;
  try { resolvedRoot = fs.realpathSync(root); } catch { return null; }
  try { resolved = fs.realpathSync(String(candidate || '')); } catch { return null; }
  const rel = path.relative(resolvedRoot, resolved);
  if (rel !== '' && (rel.startsWith('..') || path.isAbsolute(rel))) return null;
  return resolved;
}

function cleanEnv(env, fallbackHome = process.env.HOME) {
  const out = {};
  for (const [key, value] of Object.entries(env || {})) {
    if (ALLOWED_ENV.has(key) && typeof value === 'string' && value.length < 4096) out[key] = value;
  }
  // A harness with no HOME misbehaves in its own ways, so fall back to this container's own —
  // which is a tmpfs, inside the sandbox, and not the task's repository.
  if (!out.HOME && fallbackHome) out.HOME = fallbackHome;
  return out;
}

/**
 * @param {{command: string, args?: string[], root: string, spawnFn?: Function,
 *          log?: (line: string) => void, graceMs?: number, maxConnections?: number, maxWallMs?: number,
 *          kill?: Function, verify?: Map<string, string>|string, verifyWallMs?: number,
 *          verifyTailBytes?: number, shell?: string, scratchRoot?: string, verifyPath?: string,
 *          access?: (target: string, mode?: number) => void, selfUid?: number|null}} deps
 */
function createSupervisor({ command, args = [], root, spawnFn = spawn, log = () => {}, graceMs = 5000,
  maxConnections = DEFAULT_MAX_CONNECTIONS, maxWallMs = DEFAULT_MAX_WALL_MS, kill = process.kill.bind(process),
  verify = new Map(), verifyWallMs = DEFAULT_VERIFY_WALL_MS, verifyTailBytes = DEFAULT_VERIFY_TAIL_BYTES,
  shell = '/bin/sh', scratchRoot = os.tmpdir(), verifyPath = process.env.PATH, access = fs.accessSync,
  selfUid = currentUid() }) {
  const cap = positive(maxConnections, DEFAULT_MAX_CONNECTIONS);
  const wall = positive(maxWallMs, DEFAULT_MAX_WALL_MS);
  const verifyCommands = verify instanceof Map ? verify : parseVerify(verify);
  const verifyWall = Math.min(positive(verifyWallMs, DEFAULT_VERIFY_WALL_MS), wall);
  const tailCap = Math.min(positive(verifyTailBytes, DEFAULT_VERIFY_TAIL_BYTES), MAX_VERIFY_TAIL_BYTES);
  let live = 0;
  const sockets = new Set();
  const server = net.createServer((socket) => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.setEncoding('utf8');
    if (live >= cap) {
      log(`refused: ${live} agents already running (limit ${cap})`);
      socket.on('error', () => {});
      socket.end(JSON.stringify({ jsonrpc: '2.0', id: null,
        error: { code: -32000, message: `The sandbox is already running ${cap} agents; try again when one finishes.` } }) + '\n');
      return;
    }
    live++;
    let counted = true;
    const release = () => { if (counted) { counted = false; live--; } };
    let wallTimer = null;
    // `pid` outlives `agent`: the agent exiting does not end its process group, and anything it
    // left running in the background must still be stopped when the connection goes.
    // `done` is set once this connection has been refused or its agent has gone; after that no
    // byte on the socket is read, buffered or allowed to start a second agent.
    let buffer = '', agent = null, pid = null, done = false, stopped = false;

    const refuse = (reason) => {
      done = true;
      buffer = '';
      log(`refused: ${reason}`);
      // Answered in the agent's own language so the failure reaches the task as a message
      // rather than as a dead socket.
      socket.end(JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32000, message: reason } }) + '\n');
    };

    const stopAgent = () => {
      done = true;
      agent = null;
      if (wallTimer) { clearTimeout(wallTimer); wallTimer = null; }
      if (!pid || stopped) return;
      stopped = true;
      const group = -pid;
      try { kill(group, 'SIGTERM'); } catch { /* ESRCH: the whole group is already gone */ }
      const timer = setTimeout(() => { try { kill(group, 'SIGKILL'); } catch { /* gone */ } }, graceMs);
      timer.unref?.();
    };

    socket.on('data', (chunk) => {
      if (done) return;
      if (agent) return agent.stdin.write(chunk);   // the ACP stream, untouched
      buffer += chunk;
      if (buffer.length > MAX_START_LINE) return refuse('start line too long');
      const end = buffer.indexOf('\n');
      if (end === -1) return;
      const line = buffer.slice(0, end);
      const rest = buffer.slice(end + 1);
      buffer = '';
      let start;
      try { start = JSON.parse(line); } catch { return refuse('the first line must be noevia’s start message'); }
      if (start && start.noevia === 'verify') return runVerify(start);
      if (!start || start.noevia !== 'start') return refuse('the first line must be noevia’s start message');
      const cwd = insideRoot(root, start.cwd);
      if (!cwd) return refuse('that workspace is not inside this sandbox');

      const child = spawnFn(command, args, { cwd, env: cleanEnv(start.env), stdio: ['pipe', 'pipe', 'pipe'], detached: true });
      agent = child;
      pid = child.pid || null;
      log(`started ${command} in ${cwd}`);
      wallTimer = setTimeout(() => {
        wallTimer = null;
        log(`agent ran past its ${wall} ms limit; stopping it`);
        stopAgent();
        if (!socket.destroyed) {
          socket.end(JSON.stringify({ jsonrpc: '2.0', id: null,
            error: { code: -32000, message: 'The agent ran past the sandbox time limit and was stopped.' } }) + '\n');
        }
      }, wall);
      wallTimer.unref?.();
      child.stdin.on('error', () => { /* the agent closed its stdin; exit/close handles the rest */ });
      child.stdout.on('data', (out) => socket.write(out));
      child.stderr.setEncoding('utf8');
      child.stderr.on('data', (out) => log(`agent: ${String(out).slice(0, 2000).trimEnd()}`));
      child.on('error', (error) => { log(`agent failed: ${error.message}`); stopAgent(); socket.destroy(); });
      child.on('exit', (code, sig) => {
        log(`agent exited (${sig || code})`);
        // Its children may still be running in its group; stop them now, not only at close.
        stopAgent();
        socket.end();
      });
      if (rest) child.stdin.write(rest);
    });

    // One verify run on this connection. Everything after the first line is ignored (`done`), and
    // the only thing ever written back is one `verify-result` line.
    function runVerify(start) {
      done = true;
      buffer = '';
      const answer = (result) => {
        if (!socket.destroyed) socket.end(JSON.stringify({ noevia: 'verify-result', ...result }) + '\n');
      };
      const fail = (error, message) => { log(`verify refused: ${message}`); answer({ ok: false, error, message }); };
      const name = typeof start.repo === 'string' ? start.repo : '';
      const sha = typeof start.headSha === 'string' ? start.headSha : '';
      if (!REPO_NAME.test(name)) return fail('bad_request', 'verify needs a repository name');
      if (!COMMIT.test(sha)) return fail('bad_request', 'verify needs a full commit id');
      const command = verifyCommands.get(name);
      if (!command) return fail('not_configured', `no verification command is configured for ${name} (CODE_VERIFY)`);
      const cwd = insideRoot(root, start.cwd);
      if (!cwd) return fail('outside', 'that checkout is not inside this sandbox');
      const why = verifyCheckoutReason(cwd, sha, access, selfUid);
      if (why) return fail('not_read_only', why);
      let home;
      try { home = fs.mkdtempSync(path.join(scratchRoot, 'noevia-verify-')); }
      catch (e) { return fail('scratch', `could not create a scratch directory: ${e.message}`); }
      const cleanup = () => { try { fs.rmSync(home, { recursive: true, force: true }); } catch { /* tmpfs; gone with the container */ } };
      const cpuSeconds = Math.max(1, Math.ceil(verifyWall / 1000));
      // The operator's command is handed to the shell as "$1", never spliced into the script.
      const script = `ulimit -c 0 2>/dev/null; ulimit -t ${cpuSeconds} 2>/dev/null; exec ${shell} -c "$1"`;
      const tail = createTail(tailCap);
      const began = Date.now();
      let timedOut = false, exit = null, finished = false;
      const finish = () => {
        if (finished) return;
        finished = true;
        if (wallTimer) { clearTimeout(wallTimer); wallTimer = null; }
        stopAgent();   // its background children too
        cleanup();
        const { tail: text, tailBytes, totalBytes, truncated } = tail.read();
        log(`verify of ${name} at ${sha.slice(0, 12)} ended (${timedOut ? 'timed out' : exit?.signal || exit?.code})`);
        answer({ ok: true, repo: name, headSha: sha, exitCode: exit && Number.isInteger(exit.code) ? exit.code : null,
          signal: exit?.signal || null, timedOut, durationMs: Date.now() - began, tail: text, tailBytes, totalBytes, truncated });
      };
      let child;
      try {
        child = spawnFn(shell, ['-c', script, 'noevia-verify', command],
          { cwd, env: verifyEnv(home, verifyPath), stdio: ['ignore', 'pipe', 'pipe'], detached: true });
      } catch (e) { cleanup(); return fail('spawn', `could not start the verification: ${e.message}`); }
      agent = child;
      pid = child.pid || null;
      log(`verify of ${name} at ${sha.slice(0, 12)} started`);
      wallTimer = setTimeout(() => {
        wallTimer = null;
        timedOut = true;
        log(`verify ran past its ${verifyWall} ms limit; stopping it`);
        stopAgent();
        // A group that ignores SIGTERM is SIGKILLed after the grace period; answer then at the latest.
        const t = setTimeout(finish, graceMs + 50); t.unref?.();
      }, verifyWall);
      wallTimer.unref?.();
      child.stdout?.on('data', (out) => tail.push(out));
      child.stderr?.on('data', (out) => tail.push(out));
      child.on('error', (error) => { log(`verify failed to run: ${error.message}`); exit = exit || { code: null, signal: null }; finish(); });
      // 'close' waits for the pipes; a background child holding them must not keep the answer
      // back, so 'exit' stops the group and answers after a short drain.
      child.on('exit', (code, signal) => {
        exit = { code, signal };
        const t = setTimeout(finish, Math.min(graceMs, 500)); t.unref?.();
        child.on('close', finish);
      });
    }

    // The connection IS the lifetime. noevia hanging up, the task being cancelled and the web
    // container restarting all look the same from here, and all mean: stop the agent.
    socket.on('close', () => { release(); stopAgent(); });
    socket.on('error', () => { stopAgent(); socket.destroy(); });
  });

  return { server, live: () => live, listen: (port, host = '0.0.0.0') => new Promise((r) => server.listen(port, host, () => r(server.address()))),
    // net.Server has no closeAllConnections: every socket is tracked and destroyed here, so
    // close() cannot wait forever on a connection whose agent never exits.
    close: () => new Promise((r) => { for (const s of sockets) s.destroy(); server.close(() => r()); }) };
}

module.exports = { createSupervisor, insideRoot, cleanEnv, ALLOWED_ENV, DEFAULT_MAX_CONNECTIONS, DEFAULT_MAX_WALL_MS,
  parseVerify, verifyCheckoutReason, verifyEnv, createTail, DEFAULT_VERIFY_WALL_MS, DEFAULT_VERIFY_TAIL_BYTES };

if (require.main === module) {
  const command = process.env.CODE_HARNESS_COMMAND;
  const root = process.env.WORKSPACE_ROOT;
  if (!command || !root) {
    console.error('code-sandbox: CODE_HARNESS_COMMAND and WORKSPACE_ROOT are required');
    process.exit(2);
  }
  const { listen } = createSupervisor({ command, args: String(process.env.CODE_HARNESS_ARGS || '').split(' ').filter(Boolean),
    root, log: (line) => console.log(`[code-sandbox] ${line}`),
    maxConnections: positive(process.env.CODE_SANDBOX_MAX_CONNECTIONS, DEFAULT_MAX_CONNECTIONS),
    maxWallMs: positive(process.env.CODE_SANDBOX_MAX_WALL_MS, DEFAULT_MAX_WALL_MS),
    // Verify mode (#703): off unless the operator names a command per repository.
    verify: parseVerify(process.env.CODE_VERIFY),
    verifyWallMs: positive(process.env.CODE_VERIFY_WALL_MS, DEFAULT_VERIFY_WALL_MS),
    verifyTailBytes: positive(process.env.CODE_VERIFY_TAIL_BYTES, DEFAULT_VERIFY_TAIL_BYTES) });
  listen(Number(process.env.PORT || 8030)).then((address) => {
    console.log(`[code-sandbox] listening on ${address.address}:${address.port}, workspaces under ${root}`);
  });
}
