# Plan: keep auto-tune status polling ordered

Issue: #40

Status: plan only; implementation pending.

## Problem

Auto-tune polls once per second while a job is running. Requests can overlap, and every completion updates job/history. During asynchronous cancellation or ordinary completion, an older running response can arrive after a newer terminal response, restore the running UI, and restart polling.

## Intended changes

- Give status refreshes a request identity or abort superseded requests; only the current refresh may update job, history, errors, or completion callbacks.
- Invalidate status requests already in flight when start or cancel begins.
- Preserve the server contract that cancel returns HTTP 202 with the job still running while abort/restoration completes.
- Start and stop polling from the current authoritative job state.
- Keep the existing job-ID guard and strengthen it so `onChanged()` fires once for the current terminal transition, never from a stale response.
- Reset request ownership safely when the selected model changes or the component unmounts.

## Acceptance criteria

- A pre-cancel running response cannot replace a newer cancelled response or restore the Cancel button.
- Older running responses cannot replace passed or failed terminal state.
- A legitimate cancel response that remains running is displayed accurately until a current poll reports terminal state.
- Current refresh errors remain recoverable; stale failures do not obscure current state.
- Queue, resume, history, and per-model filtering behavior remain intact.

## Verification

- Add real-component deferred-response coverage for held pre-cancel poll → 202/running cancel → newer cancelled poll → old running response.
- Cover running → passed and running → failed responses out of order, asserting one `onChanged()` call.
- Cover stale errors, model changes, unmount, and successful restart after a cancelled job.
- Run web tests, typecheck, and production build.
- Exercise the AutoTune component in Chromium with synthetic model-manager APIs; do not run a model or benchmark.

## Compatibility constraints

Preserve model-manager endpoints, one-second polling cadence, asynchronous cancellation/restoration, confirmation gate, queue/resume semantics, and model-specific history. No live inference, benchmarks, configuration writes, or production APIs.
