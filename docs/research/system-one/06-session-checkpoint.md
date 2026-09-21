# 6. Session checkpoint / resume specification (draft for review)

**Rule:** a noevia session survives the complete death of its System-Two model. Canonical state
is noevia's. A model is a disposable worker that can be killed, swapped (doc 12) or replaced
between steps without losing the task.

Implementation note: [the first internal slice](15-durable-chat-slice.md) reuses jobs.cjs,
keeps restored approvals non-authorizing, and fails closed on journal corruption rather than
rolling back across potentially uncertain side effects. Remaining sections are the broader draft.

## 6.1 Gap today (from doc 1)

- A **chat turn** lives only in `chat.cjs` locals until the browser saves the transcript after the
  reply. That includes the partial answer, tool rounds, tool results and approvals already granted.
- A model crash, an engine restart, a process restart, or a swap mid-turn loses the turn.
- **Code tasks** and **research runs** already survive, through `jobs.cjs` (an append-only event
  journal with `recover()`). The same primitive is the right base for chat.

## 6.2 Session and step model

A turn becomes a durable job of kind `chat` in the per-user journal. It advances in **steps**, and
every step boundary is a safe switch point:

```
step kinds: retrieve · decide · generate · tool_call · tool_result · approval · evaluate · compact · switch_model
```

Each completed step appends one event. The state at any boundary is the fold of the events, which
is the same shape `jobs.cjs` `derive()` already uses.

## 6.3 Checkpoint contents (external and explicit only)

```js
{ v: 1, sessionId, turnId, step: n, at,
  conversation:  { transcriptRef, revision },          // saved transcript + un-saved messages of this turn
  instructions:  { systemParts: [hash, …], projectRev },// what was sent, by content hash
  task:          { phase, plan: [...], openItems: [...], goal },          // structured, model-written but noevia-validated
  workingMemory: [ { key, value, source } ],
  retrieval:     [ { file, chunk, score, rerankScore } ],                 // references, not copies
  tools:         { offered: [names], history: [ { call, args, result, status, approvalId? } ], pending: [...] },
  retries:       [ { step, reason, model, outcome } ],
  model:         { role, id, sha, settings: { effort, temperature, ctx } },
  compaction:    { summary, covered, prefix },                            // today's chat-context state
  kv:            { file?, compat? } }                                     // optional, see 6.6
```

**Never included:** hidden chain-of-thought, activations, or a model's private reasoning channel.
Reasoning text the model emitted *as output* may be kept as ordinary content if the user can see it.

## 6.4 Write discipline

- Append-only JSON lines per turn, `fsync` on step completion, and a content hash per record.
- A checkpoint is valid only if its hash chain verifies. **Corrupted tail → roll back to the last
  valid step** and replay from there. Never guess past a bad record.
- Approvals are **not** restored as granted. A restart must re-ask; that rule is kept from
  `approvals.cjs`. A pending approval restores as "pending, re-ask".
- Tool calls with side effects record `started` before execution and `result` after. A restore
  that finds `started` without `result` marks the call **outcome unknown**, shows it to the user,
  and never re-runs it automatically. This is the same rule DAV and the Diary already follow.

## 6.5 Baseline resume (the correctness path)

```
load model (ModelManager.ensureLoaded) → rebuild messages from checkpoint → prefill → continue at step n+1
```

This works across a different model, a different runtime, or a remote provider, because nothing in
it is model-specific. Its cost is one prefill of the rebuilt context. Doc 9 measures it.

## 6.6 KV-cache persistence (an optimisation only)

llama.cpp can save and restore a slot's KV cache to a file (`/slots/{id}?action=save|restore`,
`--slot-save-path`) [P]. Use it to skip the prefill **only when every compatibility key matches**:

| Key | Why |
|---|---|
| model file sha256 | weights and quantisation |
| tokenizer / chat template hash | the token sequence must be identical |
| context size, rope scaling, `n_batch`/`n_ubatch` | tensor shapes and positions |
| KV cache type (`f16`, `q8_0` …) and flash-attention setting | memory layout |
| engine version and backend (Vulkan / CUDA / Metal / CPU) | the file format is not a stable API |
| exact prefix token hash | the restored KV must match the rebuilt prompt |

On any mismatch or restore error, discard the KV file and use the baseline. Open items to verify
before relying on it:
- that slot save/restore works in router mode with multiple models;
- file sizes at 32k context;
- restore time versus prefill time on a given accelerator.

## 6.7 Failure cases (must be tested, doc 9)

| Case | Required behaviour |
|---|---|
| model OOM or crash mid-generation | turn resumes from the last step; the partial token stream of the failed step is discarded and regenerated |
| crash between checkpoint and unload | the checkpoint is complete, so the swap simply re-runs |
| crash between unload and load | the session is in state "no model"; the next request loads the model and resumes |
| corrupted checkpoint tail | roll back to the last valid step |
| incompatible KV file | discard it; baseline prefill |
| process restart during a tool call | outcome unknown; shown, never auto-re-run |
| browser disconnect | the turn continues server-side; the client re-attaches by turn id (this ends today's "never retry implicitly after a disconnect" limitation for chat) |

## 6.8 Scope

This is the prerequisite for mid-task switching (doc 12), for co-residency swaps (doc 5 §5.5), and
for surviving engine restarts. It is also valuable on its own, even if every System-One experiment
fails.
