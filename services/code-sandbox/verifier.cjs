'use strict';
// The verifier: server-measured tests for Code tasks (#703, part of #511).
//
// Same image as the coding sandbox, but its OWN container (`code-verify` in
// deploy/examples/code-sandbox.override.yml), and that separation is the security boundary. The
// coding agent runs as uid 1000 with a writable /tmp, a writable HOME and the task repositories
// it can write. Anything it leaves behind — a process that survived its turn, an `.npmrc` with a
// `script-shell`, a `.gitconfig`, a `.pth` file, a swapped loose object — must not reach the run
// that decides whether its work passes. So the verifier:
//
//   * runs as a different uid (1002), with no network at all (`network_mode: none`; noevia
//     reaches it over a unix socket on a volume only web and the verifier mount), its own tmpfs
//     /tmp and HOME, and the workspaces volume mounted READ-ONLY;
//   * takes the command only from its own environment, `CODE_VERIFY=name|command` (one per line).
//     noevia sends a repository name, a source path and a commit — never a command — and nothing is
//     read from the repository to decide what runs;
//   * makes a REAL copy: `git clone --no-local` from the read-only source into its own tmpfs. The
//     pack protocol makes index-pack recompute every object id, so a swapped or corrupted object
//     cannot pass as the commit; `git fsck` checks the copy again, and HEAD and its tree are read
//     back and must match the requested commit. The source's own config is refused if it names
//     anything git would run (hooks, fsmonitor, filters, includes …), because the local transport
//     runs upload-pack inside the source repository;
//   * gives the command a fixed environment: PATH, a fresh HOME/TMPDIR inside the run's own scratch
//     directory, LANG, CI, NO_COLOR. No proxy variables, nothing noevia sent;
//   * bounds it: one run at a time by default, stdin closed, no core dumps, a CPU limit per
//     process, a wall-time limit (CODE_VERIFY_WALL_MS, default 10 min) covering the copy and the
//     run, its process group killed at the end or when noevia hangs up, plus the container's own
//     pids/memory/CPU limits;
//   * returns output as data: a rolling tail of CODE_VERIFY_TAIL_BYTES (default 16 KiB) inside ONE
//     JSON result line, so nothing a test prints can forge a result.
//
// Every run's scratch directory is removed when it ends; leftovers from a crash are swept at start.
// Failures to remove are logged, never swallowed.
const net = require('node:net'), fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { spawn, execFile } = require('node:child_process');

const MAX_START_LINE = 64 * 1024;
const DEFAULT_WALL_MS = 10 * 60 * 1000;
const DEFAULT_TAIL_BYTES = 16 * 1024;
const MAX_TAIL_BYTES = 256 * 1024;
const DEFAULT_CONCURRENCY = 1;
const SCRATCH_PREFIX = 'noevia-verify-';
const REPO_NAME = /^[A-Za-z0-9_.-]{1,64}$/;
const COMMIT = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const positive = (value, fallback) => { const n = Number(value); return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback; };

// Switched off on every git call here; the source's config is also checked for them up front,
// because `-c` does not reach the upload-pack the local transport starts in the source.
const GIT_OFF = ['-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null', '-c', 'core.attributesFile=/dev/null',
  '-c', 'protocol.file.allow=always', '-c', 'advice.detachedHead=false'];
const HOSTILE_KEYS = [
  /^filter\./, /^diff\..*\.(command|textconv)$/, /^merge\..*\.driver$/, /^core\.fsmonitor$/, /^core\.hookspath$/,
  /^core\.sshcommand$/, /^core\.gitproxy$/, /^core\.worktree$/, /^core\.askpass$/, /^core\.editor$/, /^core\.pager$/,
  /^core\.alternaterefscommand$/, /^credential\.(.*\.)?helper$/, /^alias\./, /^include\./, /^includeif\./,
  /^uploadpack\./, /^receive\./, /^sendemail\./, /^pack\./, /^protocol\./, /^transfer\./,
];

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

function insideRoot(root, candidate) {
  let resolvedRoot, resolved;
  try { resolvedRoot = fs.realpathSync(root); } catch { return null; }
  try { resolved = fs.realpathSync(String(candidate || '')); } catch { return null; }
  const rel = path.relative(resolvedRoot, resolved);
  if (rel !== '' && (rel.startsWith('..') || path.isAbsolute(rel))) return null;
  return resolved;
}

/** The only environment a verify command gets. Nothing from noevia, no proxy. */
function verifyEnv(home, tmp, basePath = process.env.PATH) {
  return { PATH: basePath || '/usr/local/bin:/usr/bin:/bin', HOME: home, TMPDIR: tmp, LANG: 'C.UTF-8', CI: 'true', NO_COLOR: '1' };
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

/** Walk without following symlinks: a chmod through one would land outside the copy. */
function walkNoFollow(target, visit, pre = false) {
  let st; try { st = fs.lstatSync(target); } catch { return; }
  if (st.isSymbolicLink()) return;
  if (pre) visit(target, st);
  if (st.isDirectory()) for (const name of fs.readdirSync(target)) walkNoFollow(path.join(target, name), visit, pre);
  if (!pre) visit(target, st);
}
function makeReadOnly(target) {
  walkNoFollow(target, (entry, st) => {
    if (st.isDirectory()) fs.chmodSync(entry, 0o555);
    else if (st.isFile()) fs.chmodSync(entry, (st.mode & 0o111) ? 0o555 : 0o444);
  });
}
function removeTree(target) {
  // Top-down: a 0555 directory must be opened before its children can be removed.
  walkNoFollow(target, (entry, st) => { if (st.isDirectory()) fs.chmodSync(entry, 0o700); }, true);
  fs.rmSync(target, { recursive: true, force: true });
}

/**
 * @param {{root: string, scratchRoot?: string, verify?: Map<string, string>|string, wallMs?: number,
 *          tailBytes?: number, graceMs?: number, shell?: string, verifyPath?: string, git?: string,
 *          concurrency?: number, log?: (line: string) => void, spawnFn?: Function,
 *          kill?: (pid: number, signal: string) => void}} deps
 *
 * `root` is where the read-only source repositories are mounted (VERIFY_SOURCE_ROOT).
 */
function createVerifier({ root, scratchRoot = os.tmpdir(), verify = new Map(), wallMs = DEFAULT_WALL_MS,
  tailBytes = DEFAULT_TAIL_BYTES, graceMs = 5000, shell = '/bin/sh', verifyPath = process.env.PATH, git = 'git',
  concurrency = DEFAULT_CONCURRENCY, log = () => {}, spawnFn = spawn, kill = process.kill.bind(process) }) {
  const commands = verify instanceof Map ? verify : parseVerify(verify);
  const wall = positive(wallMs, DEFAULT_WALL_MS);
  const tailCap = Math.min(positive(tailBytes, DEFAULT_TAIL_BYTES), MAX_TAIL_BYTES);
  const cap = positive(concurrency, DEFAULT_CONCURRENCY);
  let running = 0;
  const sockets = new Set();

  const removeLogged = (target, why) => {
    try { removeTree(target); }
    catch (e) { log(`could not remove ${why} ${target}: ${e.message}`); }
  };
  /** Leftovers from a run the process did not live to clean up. */
  function sweep() {
    let names = [];
    try { names = fs.readdirSync(scratchRoot); } catch (e) { log(`could not read ${scratchRoot} to sweep it: ${e.message}`); return 0; }
    const stale = names.filter((n) => n.startsWith(SCRATCH_PREFIX));
    for (const name of stale) removeLogged(path.join(scratchRoot, name), 'leftover verify directory');
    return stale.length;
  }

  /** Why the source repository must not be read by git, or null. Its config is read as a file. */
  function sourceReason(src, env) {
    const gitDir = path.join(src, '.git');
    let st;
    try { st = fs.lstatSync(gitDir); } catch { return 'the source has no .git directory'; }
    if (!st.isDirectory()) return 'the source’s .git is not a plain directory';
    const configFile = path.join(gitDir, 'config');
    if (!fs.existsSync(configFile)) return null;
    // `--file` reads the file as data: no ownership check, no includes followed.
    return new Promise((resolve) => {
      execFile(git, ['config', '--file', configFile, '--name-only', '--list'], { env, timeout: 10_000 }, (error, stdout) => {
        if (error) return resolve('the source’s .git/config could not be read');
        const bad = String(stdout).split('\n').map((k) => k.trim().toLowerCase()).filter((k) => k && HOSTILE_KEYS.some((re) => re.test(k)));
        resolve(bad.length ? `the source’s .git/config sets ${[...new Set(bad)].slice(0, 5).join(', ')}` : null);
      });
    });
  }

  const server = net.createServer((socket) => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.on('error', () => {});
    socket.setEncoding('utf8');
    let buffer = '', started = false, closed = false;
    const answer = (result) => { if (!socket.destroyed) socket.end(JSON.stringify({ noevia: 'verify-result', ...result }) + '\n'); };
    const refuse = (error, message) => { log(`refused: ${message}`); answer({ ok: false, error, message }); };
    let abort = () => {};
    socket.on('close', () => { closed = true; abort(); });
    socket.on('data', (chunk) => {
      if (started) return;   // one request per connection; nothing after it is read
      buffer += chunk;
      if (buffer.length > MAX_START_LINE) { started = true; return refuse('bad_request', 'request line too long'); }
      const end = buffer.indexOf('\n');
      if (end === -1) return;
      started = true;
      const line = buffer.slice(0, end);
      buffer = '';
      let msg;
      try { msg = JSON.parse(line); } catch { return refuse('bad_request', 'the first line must be a verify request'); }
      if (!msg || msg.noevia !== 'verify') return refuse('bad_request', 'the first line must be a verify request');
      const name = typeof msg.repo === 'string' ? msg.repo : '';
      const sha = typeof msg.headSha === 'string' ? msg.headSha : '';
      if (!REPO_NAME.test(name)) return refuse('bad_request', 'verify needs a repository name');
      if (!COMMIT.test(sha)) return refuse('bad_request', 'verify needs a full commit id');
      const command = commands.get(name);
      if (!command) return refuse('not_configured', `no verification command is configured for ${name} (CODE_VERIFY)`);
      const src = insideRoot(root, msg.source);
      if (!src) return refuse('outside', 'that source repository is not under the verifier’s read-only root');
      if (running >= cap) return refuse('busy', `the verifier is already running ${cap} verification${cap === 1 ? '' : 's'}; try again when it finishes`);
      running++;
      run({ name, sha, command, src }).catch((e) => { log(`verify crashed: ${e.message}`); refuse('internal', 'the verifier failed'); })
        .finally(() => { running--; });
    });

    async function run({ name, sha, command, src }) {
      const began = Date.now();
      const deadline = began + wall;
      const work = fs.mkdtempSync(path.join(scratchRoot, SCRATCH_PREFIX));
      const home = path.join(work, 'home'), tmp = path.join(work, 'tmp'), tree = path.join(work, 'tree');
      fs.mkdirSync(home, { mode: 0o700 }); fs.mkdirSync(tmp, { mode: 0o700 });
      // git's own config for the copy step: trusts exactly this source (it belongs to another uid),
      // and nothing else. Outside the command's HOME, so the tests never see it.
      const gitConfig = path.join(work, 'gitconfig');
      fs.writeFileSync(gitConfig, `[safe]\n\tdirectory = ${src}\n\tdirectory = ${path.join(src, '.git')}\n`, { mode: 0o600 });
      const gitEnv = { PATH: verifyPath || '/usr/bin:/bin', HOME: home, LANG: 'C.UTF-8', GIT_CONFIG_GLOBAL: gitConfig,
        GIT_CONFIG_NOSYSTEM: '1', GIT_TERMINAL_PROMPT: '0', GIT_ASKPASS: '/bin/false' };
      const controller = new AbortController();
      let pid = null, stopped = false, timedOut = false;
      const stopGroup = () => {
        if (!pid || stopped) return;
        stopped = true;
        try { kill(-pid, 'SIGTERM'); } catch { /* gone */ }
        const t = setTimeout(() => { try { kill(-pid, 'SIGKILL'); } catch { /* gone */ } }, graceMs); t.unref?.();
      };
      abort = () => { controller.abort(); stopGroup(); };
      const finish = (result) => { removeLogged(work, 'verify directory'); if (!closed) answer(result); };
      const gitRun = (args, cwd) => new Promise((resolve, reject) => {
        const left = deadline - Date.now();
        if (left <= 0) return reject(Object.assign(Error('ran out of time preparing the copy'), { timeout: true }));
        execFile(git, [...GIT_OFF, ...args], { cwd, env: gitEnv, timeout: left, signal: controller.signal, maxBuffer: 1024 * 1024, encoding: 'utf8' },
          (error, stdout, stderr) => error ? reject(Object.assign(error, { detail: String(stderr || '').split('\n')[0].slice(0, 200) })) : resolve(String(stdout).trim()));
      });

      // 1. The copy, verified.
      try {
        const hostile = await sourceReason(src, gitEnv);
        if (hostile) return finish({ ok: false, error: 'hostile_source', message: hostile });
        await gitRun(['clone', '--quiet', '--no-local', '--no-hardlinks', '--no-checkout', src, tree]);
        await gitRun(['fsck', '--no-dangling', '--no-progress'], tree);
        const commit = await gitRun(['rev-parse', '--verify', '--end-of-options', `${sha}^{commit}`], tree);
        if (commit !== sha) return finish({ ok: false, error: 'head_mismatch', message: 'the source does not hold that commit' });
        await gitRun(['checkout', '--quiet', '--detach', sha], tree);
        const head = await gitRun(['rev-parse', 'HEAD'], tree);
        const treeId = await gitRun(['rev-parse', 'HEAD^{tree}'], tree);
        const expectedTree = await gitRun(['rev-parse', `${sha}^{tree}`], tree);
        if (head !== sha || treeId !== expectedTree) return finish({ ok: false, error: 'head_mismatch', message: 'the copy did not land on the requested commit' });
        makeReadOnly(tree);
      } catch (e) {
        if (closed) return finish({});
        const message = e.timeout || e.killed ? 'ran out of time preparing the copy' : `could not make a verified copy of that commit${e.detail ? `: ${e.detail}` : ''}`;
        log(`copy failed for ${name} at ${sha.slice(0, 12)}: ${e.detail || e.message}`);
        return finish({ ok: false, error: 'checkout', message });
      }
      if (closed) return finish({});

      // 2. The operator's command.
      const remaining = deadline - Date.now();
      const cpuSeconds = Math.max(1, Math.ceil(wall / 1000));
      // The command is handed to the shell as "$1", never spliced into the script.
      const script = `ulimit -c 0 2>/dev/null; ulimit -t ${cpuSeconds} 2>/dev/null; exec ${shell} -c "$1"`;
      const tail = createTail(tailCap);
      log(`verify of ${name} at ${sha.slice(0, 12)} started`);
      await new Promise((resolve) => {
        let exit = null, done = false;
        const end = () => {
          if (done) return;
          done = true;
          clearTimeout(timer);
          stopGroup();   // its background children too
          const { tail: text, tailBytes, totalBytes, truncated } = tail.read();
          log(`verify of ${name} at ${sha.slice(0, 12)} ended (${timedOut ? 'timed out' : exit?.signal || exit?.code})`);
          finish({ ok: true, repo: name, headSha: sha, exitCode: exit && Number.isInteger(exit.code) ? exit.code : null,
            signal: exit?.signal || null, timedOut, durationMs: Date.now() - began, tail: text, tailBytes, totalBytes, truncated });
          resolve();
        };
        let child;
        try {
          child = spawnFn(shell, ['-c', script, 'noevia-verify', command],
            { cwd: tree, env: verifyEnv(home, tmp, verifyPath), stdio: ['ignore', 'pipe', 'pipe'], detached: true });
        } catch (e) { exit = { code: null, signal: null }; log(`could not start: ${e.message}`); done = true; finish({ ok: false, error: 'spawn', message: 'could not start the verification' }); resolve(); return; }
        pid = child.pid || null;
        const timer = setTimeout(() => {
          timedOut = true;
          log(`verify ran past its ${wall} ms limit; stopping it`);
          stopGroup();
          const t = setTimeout(end, graceMs + 50); t.unref?.();
        }, Math.max(1, remaining));
        timer.unref?.();
        child.stdout?.on('data', (out) => tail.push(out));
        child.stderr?.on('data', (out) => tail.push(out));
        child.on('error', (error) => { log(`verify failed to run: ${error.message}`); exit = exit || { code: null, signal: null }; end(); });
        // 'close' waits for the pipes; a background child holding them must not hold the answer back.
        child.on('exit', (code, signal) => {
          exit = { code, signal };
          const t = setTimeout(end, Math.min(graceMs, 500)); t.unref?.();
          child.on('close', end);
        });
      });
    }
  });

  return {
    server, sweep, running: () => running,
    /** A unix socket path (production: VERIFY_SOCKET) or a TCP port (tests). */
    listen: (target, host = '127.0.0.1') => new Promise((resolve, reject) => {
      sweep();
      server.once('error', reject);
      if (typeof target === 'string') {
        try { fs.unlinkSync(target); } catch (e) { if (e.code !== 'ENOENT') log(`could not remove the old socket: ${e.message}`); }
        server.listen(target, () => { try { fs.chmodSync(target, 0o660); } catch (e) { log(`could not chmod the socket: ${e.message}`); } resolve(target); });
      } else server.listen(target, host, () => resolve(server.address()));
    }),
    close: () => new Promise((r) => { for (const s of sockets) s.destroy(); server.close(() => r()); }),
  };
}

module.exports = { createVerifier, parseVerify, verifyEnv, createTail, insideRoot, makeReadOnly, removeTree,
  HOSTILE_KEYS, DEFAULT_WALL_MS, DEFAULT_TAIL_BYTES, SCRATCH_PREFIX };

if (require.main === module) {
  const root = process.env.VERIFY_SOURCE_ROOT;
  const socketPath = process.env.VERIFY_SOCKET;
  if (!root || !socketPath) {
    console.error('code-verify: VERIFY_SOURCE_ROOT and VERIFY_SOCKET are required');
    process.exit(2);
  }
  const verifier = createVerifier({ root, verify: parseVerify(process.env.CODE_VERIFY),
    wallMs: positive(process.env.CODE_VERIFY_WALL_MS, DEFAULT_WALL_MS),
    tailBytes: positive(process.env.CODE_VERIFY_TAIL_BYTES, DEFAULT_TAIL_BYTES),
    concurrency: positive(process.env.CODE_VERIFY_CONCURRENCY, DEFAULT_CONCURRENCY),
    log: (line) => console.log(`[code-verify] ${line}`) });
  verifier.listen(socketPath).then(() => {
    console.log(`[code-verify] listening on ${socketPath}, sources under ${root} (read-only), ${parseVerify(process.env.CODE_VERIFY).size} repositories configured`);
  });
}
