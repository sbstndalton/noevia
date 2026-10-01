'use strict';
// Server-measured verification for Code tasks (#703, part of #511).
//
// The pipeline (#705) asks one question after the Executor's work is on the branch: do the
// operator's tests pass at exactly this commit? This module answers it without believing anything
// the agent said. The checkout is prepared by noevia (code-workspace.cjs `verifyCheckout`: a
// read-only clone detached at the branch's current tip in the SOURCE repository), and the command
// is run by the sandbox supervisor in its `verify` mode with the command the OPERATOR configured
// there (`CODE_VERIFY=name|command` in the code-sandbox container). noevia sends a repository
// name, a path and a commit id — never a command — and gets back an exit status and a bounded
// tail of output.
//
// Trust rules:
//   * The only test report the pipeline may accept is the object `run()` returns. Those objects are
//     frozen and remembered in a module-private WeakSet; `isMeasured(report)` is the check. A report
//     read back from a job journal, an artifact, a file in the repository or anything the agent
//     emitted is a different object and is never measured — even if every field matches.
//   * `passed` is computed here from the measured exit status: exit 0, no signal, no timeout.
//   * The output tail is untrusted data: re-capped here in bytes, stripped of control characters
//     other than newline and tab, and never parsed for a verdict.
//   * The supervisor's answer is read as ONE line of at most MAX_ANSWER_BYTES. Its commit id must
//     equal the one asked for.
//
// Events: `step.started` / `step.completed` with id `tests`, and an `artifact.created` with
// `kind: 'test-report'` carrying the report, through the `emit(type, data)` the caller supplies.
const net = require('node:net');
const { splitEndpoint } = require('./code-acp.cjs');

const STEP_ID = 'tests';
const STEP_TITLE = 'Run the tests';
const DEFAULT_TAIL_BYTES = 16 * 1024;
const MAX_TAIL_BYTES = 256 * 1024;
// JSON escaping can expand a byte to six characters; the line is bounded well above that.
const MAX_ANSWER_BYTES = 2 * 1024 * 1024;
// Longer than the supervisor's own default wall limit (10 min) so its answer normally arrives first.
const DEFAULT_TIMEOUT_MS = 12 * 60 * 1000;
const COMMIT = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const REPO_NAME = /^[A-Za-z0-9_.-]{1,64}$/;

const measured = new WeakSet();

/** Keep the last `cap` bytes of a string, without splitting a UTF-8 character at the cut. */
function tailUtf8(text, cap) {
  const buf = Buffer.from(String(text || ''), 'utf8');
  if (buf.length <= cap) return buf.toString('utf8');
  let start = buf.length - cap;
  while (start < buf.length && (buf[start] & 0xc0) === 0x80) start++;
  return buf.subarray(start).toString('utf8');
}

/** Untrusted output, made safe to store and show: no escape sequences or other controls. */
function cleanTail(text, cap) {
  // eslint-disable-next-line no-control-regex
  return tailUtf8(String(text || '').replace(/\r\n?/g, '\n').replace(/[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/g, ''), cap);
}

/** True only for a report this module produced in this process. */
function isMeasured(report) {
  return !!report && typeof report === 'object' && measured.has(report);
}

/**
 * Ask the supervisor to verify. Resolves with the parsed answer object or rejects with a reason.
 * `connectFn(port, host)` is `net.connect` in production.
 */
function askSupervisor({ endpoint, connectFn, request, timeoutMs, signal }) {
  return new Promise((resolve, reject) => {
    let host, port;
    try { [host, port] = splitEndpoint(endpoint); } catch (e) { reject(Object.assign(Error(e.message), { code: 'config' })); return; }
    let settled = false, received = '', bytes = 0;
    const socket = connectFn(port, host);
    const done = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener?.('abort', onAbort);
      // Hanging up is what stops the run in the sandbox, so this is also the cancel path.
      try { socket.destroy(); } catch { /* already gone */ }
      if (error) reject(error); else resolve(value);
    };
    const onAbort = () => done(Object.assign(Error('Verification was cancelled.'), { code: 'cancelled' }));
    const timer = setTimeout(() => done(Object.assign(Error('The sandbox did not answer in time.'), { code: 'timeout' })), timeoutMs);
    timer.unref?.();
    if (signal?.aborted) { onAbort(); return; }
    signal?.addEventListener?.('abort', onAbort, { once: true });
    socket.setEncoding?.('utf8');
    socket.write(JSON.stringify(request) + '\n');
    socket.on('data', (chunk) => {
      if (settled) return;
      bytes += Buffer.byteLength(chunk);
      if (bytes > MAX_ANSWER_BYTES) return done(Object.assign(Error('The sandbox answer was too large.'), { code: 'bad_answer' }));
      received += chunk;
      const end = received.indexOf('\n');
      if (end === -1) return;
      let answer;
      try { answer = JSON.parse(received.slice(0, end)); }
      catch { return done(Object.assign(Error('The sandbox answer was not readable.'), { code: 'bad_answer' })); }
      done(null, answer);
    });
    socket.on('error', (error) => done(Object.assign(Error(`The coding sandbox is unreachable (${error.message}).`), { code: 'unreachable' })));
    socket.on('close', () => done(Object.assign(Error('The coding sandbox closed the connection without an answer.'), { code: 'unreachable' })));
  });
}

/**
 * @param {{endpoint?: string|null, connectFn?: Function, timeoutMs?: number, tailBytes?: number,
 *          log?: (entry: object) => void, now?: () => number}} [deps]
 *
 * `endpoint` is the sandbox (`CODE_HARNESS_ENDPOINT`). Without one there is nowhere isolated to run
 * tests, so verification is unavailable — it is never run beside noevia's own state.
 */
function createCodeVerify({ endpoint = process.env.CODE_HARNESS_ENDPOINT || null, connectFn = net.connect,
  timeoutMs = DEFAULT_TIMEOUT_MS, tailBytes = DEFAULT_TAIL_BYTES, log = () => {}, now = Date.now } = {}) {
  const cap = Math.min(Math.max(1024, Math.floor(Number(tailBytes) || DEFAULT_TAIL_BYTES)), MAX_TAIL_BYTES);

  /**
   * Verify one revision. Never throws for an expected failure; the outcome says what happened.
   *
   * @param {{workspaces: {verifyCheckout: Function}, taskId: string, repo: string, headSha: string,
   *          revision: number, emit?: (type: string, data: object) => void, signal?: AbortSignal}} args
   * @returns {Promise<{status: 'passed'|'failed'|'error'|'unavailable', report: object|null,
   *          error: {code: string, message: string}|null}>}
   */
  async function run({ workspaces, taskId, repo, headSha, revision, emit = () => {}, signal = undefined }) {
    const started = now();
    emit('step.started', { id: STEP_ID, title: STEP_TITLE });
    const stop = (status, code, message) => {
      log({ event: 'code.verify', taskId, revision, status, code });
      emit('step.completed', { id: STEP_ID, failed: true, reason: message });
      return { status, report: null, error: { code, message } };
    };
    if (!endpoint) return stop('unavailable', 'no_sandbox', 'Verification needs the coding sandbox (CODE_HARNESS_ENDPOINT).');
    if (!REPO_NAME.test(String(repo || ''))) return stop('error', 'bad_request', 'Verification needs the repository name.');
    if (!COMMIT.test(String(headSha || ''))) return stop('error', 'bad_sha', 'Verification needs a full commit id.');
    if (!Number.isInteger(revision) || revision < 0) return stop('error', 'bad_request', 'Verification needs the revision number.');

    let checkout;
    try { checkout = workspaces.verifyCheckout(taskId, headSha); }
    catch (e) { return stop('error', e.code || 'checkout', e.message || 'Could not prepare the verification checkout.'); }

    let answer;
    try {
      answer = await askSupervisor({ endpoint, connectFn, timeoutMs, signal,
        request: { noevia: 'verify', repo, cwd: checkout.path, headSha } });
    } catch (e) {
      return stop('error', e.code || 'unreachable', e.message);
    } finally {
      try { checkout.dispose(); } catch { /* best effort */ }
    }

    if (!answer || answer.noevia !== 'verify-result') return stop('error', 'bad_answer', 'The sandbox answer was not a verification result.');
    if (answer.ok !== true) {
      const code = typeof answer.error === 'string' ? answer.error.slice(0, 40) : 'refused';
      const message = typeof answer.message === 'string' ? cleanTail(answer.message, 500) : 'The sandbox refused the verification.';
      return stop(code === 'not_configured' ? 'unavailable' : 'error', code, message);
    }
    if (answer.headSha !== headSha) return stop('error', 'bad_answer', 'The sandbox answered for a different commit.');
    const exitCode = Number.isInteger(answer.exitCode) ? answer.exitCode : null;
    const signalName = typeof answer.signal === 'string' && /^SIG[A-Z0-9]{1,10}$/.test(answer.signal) ? answer.signal : null;
    const timedOut = answer.timedOut === true;
    const tail = cleanTail(typeof answer.tail === 'string' ? answer.tail : '', cap);
    const totalBytes = Number.isSafeInteger(answer.totalBytes) && answer.totalBytes >= 0 ? answer.totalBytes : null;
    const report = Object.freeze({
      kind: 'test-report',
      passed: exitCode === 0 && !signalName && !timedOut,
      exitCode,
      signal: signalName,
      timedOut,
      tail,
      tailBytes: Buffer.byteLength(tail),
      totalBytes,
      truncated: answer.truncated === true || (totalBytes !== null && totalBytes > Buffer.byteLength(tail)),
      headSha,
      revision,
      repo,
      durationMs: Math.max(0, now() - started),
      measuredBy: 'sandbox',
    });
    measured.add(report);
    log({ event: 'code.verify', taskId, revision, status: report.passed ? 'passed' : 'failed', exitCode, timedOut });
    emit('artifact.created', { ...report });
    emit('step.completed', { id: STEP_ID, failed: !report.passed });
    return { status: report.passed ? 'passed' : 'failed', report, error: null };
  }

  return { available: () => !!endpoint, run, isMeasured };
}

module.exports = { createCodeVerify, isMeasured, cleanTail, tailUtf8, STEP_ID, DEFAULT_TAIL_BYTES, MAX_ANSWER_BYTES };
