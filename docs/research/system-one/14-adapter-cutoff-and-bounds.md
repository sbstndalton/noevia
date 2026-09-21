# 14. Adapter continuation: total cutoff and conditional bounds

Date: 2026-09-21. Base: `d6e708164fb7805bdcd0e1e9a0edfb53573659c0`.
Status: **implementation patch, not committed upstream or deployed**. This is not a model benchmark.

## Change record

This bounded batch changes only the experimental runner's lifecycle and the option-logit
backend's incomplete-distribution accounting. The rerank and embedding backends are unchanged.
No dependencies, model assets, production configuration, or model-residency policies are added.
The previous results remain untouched. The readout contract is now `equal-bias-v4`.

### Total cutoff

`run-budget.cjs` supplies an independent timer and a shared AbortSignal. It covers the async
version probe, model startup, health polling, and inference. The signal is combined with each
request's existing deadline, not substituted for it. A monotonic elapsed-time check also refuses
new work after the deadline if event-loop delivery was delayed.

The runner requests TERM at cutoff, escalates to KILL after a separate 3-second grace, and waits
up to 5 seconds for exit confirmation. The end record distinguishes `cutoffMs`, `cleanupMs`,
`workerStopped`, and full `wallMs`. Completed decision rows remain append-only. Health polls have
a 1-second request timeout; startup retains its 120-second cap. The version probe is asynchronous,
limited to 2 seconds and cancellable. Memory sampling no longer synchronously blocks the timer.

This is an application-level cutoff, not a real-time OS guarantee. A blocked event loop or
uninterruptible OS operation can delay delivery. SIGKILL of the parent and machine failure cannot
promise a final JSONL record. No host is approved by this implementation.

### Correct conditional bounds

Let observed permitted mass for option i be `m_i`, let `S = sum(m_i)`, and let residual
`R = max(0, 1 - S)`. The residual can include non-label mass; treating all of it as potentially
missing permitted mass is conservative. An unobserved variant can contribute `x_i >= 0`, where
`sum(x_i) <= R`, and `x_i = 0` if all variants for that option were observed.

The complete conditional option probability is:

```
p_i = (m_i + x_i) / (S + sum(x_i))
```

A lower bound is `m_i / (S + R)` if another option has a missing variant, and `m_i / S` otherwise.
An upper bound is `(m_i + R) / (S + R)` if the option itself has a missing variant, and `m_i / S`
otherwise. Fully observed distributions yield point bounds. Unobserved options remain absent
from observed-ratio scores, with an explicit interval instead of a measured zero.

Selection robustness is checked in unnormalized mass: for every competitor j, the observed winner
must exceed `m_j + R` if j has a missing variant, and `m_j` otherwise. The denominator is common to
all options, so this comparison does not confuse independently attainable interval extrema.

Example: observed A=0.6000 and B=0.3995, with a missing B variant and R=0.0005. A's observed ratio
is approximately 0.60030015, but its lower bound is 0.6000. Missing B mass increases the denominator.

The backend rejects nonfinite/negative/out-of-range token probabilities, duplicate returned IDs,
and totals above one beyond a floating-point tolerance. These are data-validation checks, not
quality or calibration claims. `confidence` retains its existing raw preference-share meaning;
`metadata.calibrated` remains false. Exact ratios do not establish decision correctness.

## Current repository verification

Applied at the exact base on main. Local checks: 28 focused tests, 36 existing decision/experiment
tests, and 1138 web unit tests pass; typecheck, build and design lint pass. No real model
worker or inference ran. This is separate from the prior isolated evidence below.

## Verification performed (prior isolated bundle)

28 focused Node tests pass in an isolated Linux environment, Node v22.16.0:

- 12 mocked readout tests, including the numeric regression, missing variants, wholly unobserved
  options, all seven missing-variant patterns across an allocation grid, ambiguity, ties, and
  malformed probability responses.
- 8 budget tests: cutoff during a pending request, startup cancellation, refusal of new work,
  propagation of request cancellation, monotonic overdue checks, idempotence, disposal, and input
  validation.
- 8 runner integration tests: stalled health, stalled inference, stalled version probe, normal
  completion, retaining previous rows, SIGINT, a worker ignoring TERM, and startup failure.

The integration tests execute the actual runner, backend, decision layer, and harness. Only
scenario construction, rendering, and baseline selection are stubbed in the spawned test process.
Every worker path explicitly points to a temporary Node HTTP fixture. No real llama binary or
model is launched, and no global PATH lookup is used to select a test worker.

Run these focused tests from the repository root:

```sh
node --test apps/web/server/decision/readout-bounds.test.cjs \
  experiments/system-one/decisions/run-budget.test.cjs \
  experiments/system-one/decisions/run-cutoff.test.cjs
```

The full repository suite, typecheck, build, existing experiment suites, real llama.cpp scoring,
model memory behavior, cache reuse, and real cancellation/slot release were **not** verified in
this isolated patch workspace. Those must not be represented as passing based on this batch.
No code or tests ran on the user's MacBook or DaServer.

## Next boundary

Apply/review the patch against current `main`, run the authorized repository checks, and record
it as undeployed work in the existing changelog. Freeze the adapter after those checks. A real
10-case smoke test still requires an explicitly approved host, model/configuration, resource
budget, stop conditions, and expected impact. It validates the adapter only, not model quality.

The next independent implementation milestone is durable chat execution using Noevia-owned
state and existing job patterns. Do not enable autonomous switching, replace the live reranker,
change the native engine, or evaluate/download Laya as a side effect of this patch.
