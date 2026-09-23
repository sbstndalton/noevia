# Auto-tune step by step: one model, one setting, every step visible

Status: plan only; implementation pending. Requested by the user on 2026-09-23 after a live run on `aa5132b`.

Tuning is a script. No AI agent should need to tune a model by hand, pick values, or drive it step by step. The user's requirement is that the script itself works step by step.

## Today (`apps/web/server/llamacpp-full-autotune.cjs`)

- `start()` takes **one** maintenance lease (`maintenance.hold('Chat is paused while automatic model tuning runs.')`, line ~237) for the whole run and releases it only in `run()`'s `finally`. With "Tune untuned models" (`untuned: true`, six models live) chat is paused for all of them at once, possibly for hours.
- Inside one model, KV cache → context → drafting/batch run as child jobs under that same lease, with one rollback journal. Nothing is final until the whole model is.
- On restart, `recover()` marks the job and every pending queue item `interrupted`. The queue is abandoned and has to be started again. Only the speed stage (`llamacpp-autotune.cjs`) reuses earlier partial measurements.

## Wanted (user's choices)

1. **One model at a time.** The queue takes a lease per model, not per queue. Between models the lease is released, so chat works again, then the next model's lease is taken. If chat is in use, it waits for it to go idle, bounded, rather than preempting it.
2. **One setting at a time.** Each model runs as ordered phases: KV cache type → context size → drafting (MTP/n-gram) → batch/ubatch. Each phase:
   - measures, quality-checks and **commits** its winner to `models.ini` (with the existing revision and external-edit guard) before the next phase starts;
   - records the committed value and its evidence in the state file;
   - rolls back only its own change if it fails or is cancelled. Earlier committed phases stay.
3. **Every step visible and resumable.**
   - The job exposes `models[] → phases[] → steps[]`, each `pending | running | passed | failed | skipped | interrupted`, with the measured value and the reason.
   - The page lists them live, not just a single `phase` string.
   - After a restart or cancel, **Resume** continues from the first unfinished phase of the first unfinished model, reusing committed results.

## Constraints to keep

- A deterministic script, with no model or AI deciding what to try. Existing candidate lists, quality probes, memory floor and time budgets stay as they are.
- `models.ini` edits keep the revision check and back up before each commit. External edits still stop the run.
- One run at a time server-wide. The pause message still names the model and the phase ("Chat is paused while noevia tunes Qwen3.5-4B: context size").
- The existing `llamacpp-calibration.cjs` (context only) becomes the context phase, or is called by it, so there aren't two implementations.

## Tests

- Queue of 3 fake models: the lease is released between models (chat can run between them), and model 2 fails without undoing model 1.
- Phase commit: kill after the context phase, restart, Resume → KV and context are not re-measured; drafting starts.
- A phase that fails restores only its own setting.
- UI (`qa/models-autotune.cjs`): the phase list renders with states; Resume appears after an interrupted run; 375/768/1440 light/dark.
