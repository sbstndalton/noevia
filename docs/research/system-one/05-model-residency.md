# 5. Local model residency specification (draft for review)

A `ModelManager` that application code asks for capabilities ("I need `local-smart` loaded"), and
that owns every lifecycle action. System One may *recommend* a lifecycle action; only this
deterministic component performs one. It is the executor for adaptive mid-task switching
([12-adaptive-model-switching.md](12-adaptive-model-switching.md)).

## 5.1 What exists today

| Piece | Where | Does |
|---|---|---|
| Load / unload a model | `llamacpp-manager.cjs` `load`, `/models/unload` | router-mode llama.cpp; `load` waits for readiness |
| Make room | `makeRoomFor(model, keep)` | unloads every other model except `keepAlongside()` (the embedding model) |
| Concurrency ceiling | engine flag `--models-max N` (deployment config) | how many models the router keeps resident |
| Sizing | `llamacpp-autoconfig.cjs`, `gguf-meta.cjs`, calibration, auto-tune | context / offload proposals from GGUF headers and host memory, measured |
| Maintenance gate | `maintenance.enter()` inside `mutate` | serialises lifecycle mutations |
| Idle sleep | llama.cpp `--sleep-idle-seconds` [P: llama.cpp server README] | not used by noevia |
| KV save/restore | llama.cpp `/slots/{id}?action=save|restore` with `--slot-save-path` [P] | not used |

Missing pieces:
- a notion of *roles/capabilities* separate from file names;
- a residency plan;
- a pre-swap checkpoint hook;
- System One co-residency;
- a capability profile that is not specific to this machine.

## 5.2 Interface

```js
/** @typedef {'hot'|'warm'|'cold'|'absent'} Residency
 *  hot  = loaded on the primary accelerator, ready
 *  warm = loaded but sleeping (llama.cpp sleep) or on a secondary device (CPU/NPU)
 *  cold = weights on disk only
 */
class ModelManager {
  capabilities()                          // → CapabilityProfile (5.6), cached, refreshed on change
  residency()                             // → [{ model, role?, device, residency, bytes, loadedAt, lastUsedAt, pinned }]
  memoryPressure()                        // → { accelBytesFree, ramBytesFree, swapRisk: 'low'|'medium'|'high' }

  async ensureLoaded(ref, { reason, deadlineMs, allowEvict }) // ref = role ('local-smart') or exact model id
  async preload(ref, { priority })        // best-effort, never evicts a pinned or in-use model
  async hibernate(model)                  // sleep / move to warm tier if the runtime supports it, else unload
  async unload(model)

  async checkpointSession(sessionId)      // delegates to the Session Store (doc 6); returns a checkpoint id
  async restoreSession(sessionId, cpId)

  plan(target)                            // PURE: → { feasible, actions: [...], estMs, evicts: [...] } — used by System One
  async apply(plan, { lease })            // performs the planned actions under the lifecycle lock
}
```

Rules:

1. **Roles, not names.** Application code asks for `local-fast`, `local-smart`, `local-code`,
   `local-large`, `decision`, `embed` or `rerank`. The mapping from role to model, per installation,
   lives in configuration and in the capability database (doc 12). An exact id is allowed for
   user-pinned models.
2. **Leases.** A request that is generating holds a lease on its model. `apply` never unloads a
   leased model. It waits for the lease, up to the deadline, then reports "not feasible now".
3. **One lifecycle lock** (today's `maintenance` gate), so two requests cannot thrash the engine.
4. **Checkpoint before evict.** Any action that evicts a model some session is using first calls
   `checkpointSession` for that session (doc 6). If the checkpoint fails, the swap is aborted.
5. **Pinned residents.** `decision`, `embed` and `rerank` are pinned by default when the capability
   profile shows they fit beside a useful System-Two model (5.4). Pinned models are evicted only by
   explicit user action or a failed-load recovery.
6. **Hysteresis.** A model loaded less than `minResidencyMs` ago (default 60 s, or 3× its measured
   load time, whichever is larger) is not evicted for a *preference*, only for a *requirement*
   (for example, a model that does not fit). This prevents ping-pong between two models on
   alternating steps.

## 5.3 Lifecycle actions and who decides

| Action | Meaning | May be *recommended* by System One | *Performed* by |
|---|---|---|---|
| `KEEP_CURRENT` | no change | yes | — |
| `LOAD_ALONGSIDE` | load the target without evicting (fits) | yes | `ensureLoaded` |
| `CHECKPOINT_AND_SWAP` | checkpoint → unload current → load target → restore | yes | `plan` + `apply` |
| `PRELOAD_NEXT` | start loading the likely next model while the current one works | yes | `preload` (only when it fits without eviction) |
| `HIBERNATE_CURRENT` | sleep or demote the current model after its phase ends | yes | `hibernate` |
| `RESTORE_PREVIOUS` | bring back the model a paused phase was using | yes | `ensureLoaded` + `restoreSession` |

System One sees only the actions `plan()` marks feasible. The action set it chooses from is
therefore computed by deterministic code from real memory figures, never assumed.

## 5.4 Co-residency (System One beside System Two)

The goal is for the decision model to be always available and never cost a swap. Options, in order
of preference, chosen by capability detection rather than hard-coded:

1. **Decision model = the resident fast System-Two model.** The `llama-logit` backend (doc 4)
   reads decisions from whatever small model is loaded. That costs zero extra memory, but
   decisions stop when the small model is swapped out.
2. **A small dedicated decision model beside System Two on the same accelerator** (0.6–2B GGUF at
   Q8 ≈ 0.7–2.2 GB of weights plus a small KV cache). Needs `--models-max ≥ 2`; the reference
   deployment already runs two models.
3. **Decision model on CPU or NPU** (a llama.cpp CPU instance, or Laya/ONNX in-process at 193–464 ms
   per decision [V]), leaving the accelerator entirely to System Two.
4. **No co-residency:** swap to decide, then swap back (5.5). Almost certainly too slow for per-step
   decisions; acceptable only for rare, high-value decisions.

**Measured constraint (doc 13 §13.3):**
- On DaServer the iGPU borrows system RAM, so options (2) and (3) draw on the same 29 GB pool; option (3) only avoids the 14 GB llama.cpp cap.
- The second router slot is now the class-A RAG reranker.
- Doc 13 §13.4 lists each candidate's resident footprint.

Open question for the benchmark: whether (1) is good enough. If it is, the one-vs-two System-Two
question partly dissolves, because the second slot is then worth more as the *decision* or
*rerank* resident than as a second chat model.

## 5.5 When co-residency is impossible

```
S2 active → checkpoint → unload S2 → load S1 → decide (batched) → unload S1 → load S2 → restore → continue
```

Two loads per decision point. Recommendation, pending measurement:
- only for decisions batched at phase boundaries;
- never inside a tool round;
- fall back to the heuristic whenever the estimated swap cost exceeds the purpose's budget.

## 5.6 Capability profile (portable, detected, never assumed)

```js
{ host: { os, arch, cpu: { model, cores, avx2, avx512, neon }, ramBytes, freeDiskBytes: { models, state } },
  accelerators: [ { kind: 'cuda'|'rocm'|'vulkan'|'metal'|'npu'|'none', name, memBytes, unified: bool, driver } ],
  engines: [ { id: 'llama.cpp', version, backends: ['vulkan','cpu'], routerMode: bool, modelsMax, slotSave: bool, sleep: bool, rerank: bool, logprobs: bool } ],
  resident: [ ...residency() ],
  measured: { [modelSha]: { loadMs, prefillTokPerSec, decodeTokPerSec, peakBytes } } }   // from calibration / auto-tune
```

- Engine features are **probed** (`/props`, a dry `/slots` call, a 1-token `n_probs` request), not
  inferred from a version string.
- The profile feeds `plan()`, the capability database (doc 12) and the admin Models page. It
  replaces the scattered memory guesses in `llamacpp-autoconfig.cjs` over time.
- Paths such as the model directory, the state directory and `--slot-save-path` come from
  configuration.

## 5.7 Memory hierarchy

| Tier | Holds | Owner |
|---|---|---|
| Accelerator | hot model weights and live KV | engine |
| RAM | warm models (CPU residents, sleeping), prompt cache | engine |
| SSD (configured path) | model files, **session checkpoints** (doc 6), optional KV files, retrieval indexes | noevia (checkpoints, indexes), engine (KV files) |

## 5.8 What to measure (feeds doc 9)

- Load time per model: cold from disk, and warm from the page cache.
- Unload time.
- Time to first token after a swap, both with full prefill and with KV restore.
- Swaps per 100 tasks, and the share of total task time spent swapping.
- Preload hit rate: how often the preloaded model was the next one needed.
- Co-residency cost: System-Two decode speed with the decision model resident versus absent.
- Failure injection: a crash during unload, a load failure (OOM), and a restore with a missing
  checkpoint.
