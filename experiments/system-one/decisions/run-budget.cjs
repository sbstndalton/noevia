'use strict';
// A run-wide cutoff. No model or process is started here. The caller terminates its own worker.
// Timers are not real-time guarantees: a blocked event loop or uninterruptible OS I/O can delay
// delivery. check() also observes monotonic elapsed time before any new work is admitted.
const { performance } = require('node:perf_hooks');

function createRunBudget({ maxMs, onCutoff = () => {}, now = () => performance.now(),
  setTimer = setTimeout, clearTimer = clearTimeout, fetchImpl = globalThis.fetch }) {
  if (!Number.isFinite(maxMs) || maxMs <= 0 || maxMs > 2147483647) throw Error('invalid run time limit');
  const controller = new AbortController(), started = now();
  let cutoffMs = null, timer;
  const cancel = (reason) => {
    if (controller.signal.aborted) return;
    cutoffMs = now() - started;
    clearTimer(timer);
    controller.abort(reason instanceof Error ? reason : Error(String(reason)));
    onCutoff(controller.signal.reason);
  };
  const check = () => {
    if (!controller.signal.aborted && now() - started >= maxMs) cancel(Error('wall-clock limit'));
    controller.signal.throwIfAborted();
  };
  timer = setTimer(() => cancel(Error('wall-clock limit')), maxMs);
  const fetchWithinBudget = (url, init = {}) => {
    check();
    const signal = init.signal ? AbortSignal.any([controller.signal, init.signal]) : controller.signal;
    signal.throwIfAborted();
    return fetchImpl(url, { ...init, signal });
  };
  return {
    signal: controller.signal, check, cancel, fetch: fetchWithinBudget,
    elapsedMs: () => now() - started, cutoffMs: () => cutoffMs,
    dispose: () => clearTimer(timer),
  };
}

module.exports = { createRunBudget };
