# 13. Model classes, and choosing the generic System-One model (draft for review)

Written 2026-09-21, after the RAG reranker went live (release `67f336e`). This document corrects
how the earlier docs used "System One". **The live reranker is not the generic System-One
implementation**, and it does not answer any question about one. Evidence tags as in doc 3:
[P] primary source, [B] independent benchmark, [V] vendor figure, [M] measured by us,
[E] our estimate, [—] unknown.

## 13.1 Three model classes (terminology used in all System-One docs)

| Class | Name | Job | Examples | Interface in noevia |
|---|---|---|---|---|
| **A** | **Specialised discriminative model** | One narrow scoring task it was trained for | `Qwen3-Reranker-0.6B` (RAG ranking, live); the embedding model (`nomic-embed-text-v1`) | Its own purpose, e.g. `rag.rerank`, through `decisions.rank()` or a dedicated call |
| **B** | **Generic System-One decision model** | Bounded orchestration decisions: pick, judge, stop, escalate | Candidates: Laya, SemIf-style option-logit readout (4B or smaller), Jev (remote reference); floor: deterministic heuristics | `decide({ state, question, choices, constraints })`, provider-independent (doc 4) |
| **C** | **System-Two generative model** | Generation, reasoning, coding, synthesis | Qwen3.5-4B/9B, Gemma-4 E2B/E4B, gpt-oss-20B | Chat and Code paths |

```
noevia decision layer  (decide / rank; validation, deadline, fallback, logging: doc 4)
│
├── A. Specialised discriminative models
│   ├── rag.rerank      → Qwen3-Reranker-0.6B   (live, flag NOEVIA_FEATURE_RAG_RERANK)
│   └── embeddings      → nomic-embed-text-v1   (CPU embed container)
│
├── B. Generic System-One (UNRESOLVED; this doc)
│   └── model selection, mid-task switching, tool selection, retry/continue/stop,
│       output evaluation, escalation, context utility, residency
│       → backend: laya | llama-logit (SemIf-style) | jev | heuristic
│
└── C. System-Two generators
    └── Qwen / Gemma / gpt-oss …
```

Rules:
- **A is judged only on its own task.** The reranker stays because it measured better on RAG
  (80% → 86–91% correct on the synthetic set). A class-B model replaces it only if it beats it
  **on RAG ranking**, not to make the architecture uniform.
- **B is judged on noevia's bounded decisions.** A class-A score (reranking quality) is no
  evidence about B, and the reranker is never used as a class-B backend. It returns relevance
  logits for query–passage pairs, not calibrated answers to typed questions.
- **Callers do not know which backend answered.** Every class-B call goes through `decide()`.
  Specialised class-A purposes can have their own entry point, but they still sit behind the
  same validation, deadline and fallback.
- **Mixing is allowed.** Several class-A components plus one small class-B model is a legitimate
  end state (13.6).

## 13.2 What was verified about Laya (direct investigation, 2026-09-21)

Sources: the model repository file list and code (`rl_common.py`, `rl_agent_api.py`, configs,
`eval/results.md`) on Hugging Face [P], its model card [V], and the receptron Node/ONNX wrapper
[P]. **Nothing was downloaded or run.** Each weight file is 0.64–0.84 GB, and downloading needs
approval.

**Architecture [P, from code].**
- ModernBERT-large encoder (395M parameters, bidirectional, fully fine-tuned) plus a head trained
  from scratch; 421M in total.
- Each option gets a `[MASK]` marker. A scorer (LayerNorm → Linear → GELU → Linear) turns each
  marker into a logit, and a softmax runs over that question's options.
- **A separate act head** (`n_act=2`: answer or escalate) reads the pooled sequence plus a summary
  of its own answer distribution. It was trained with `escalate` costing 0.5 and a wrong act
  costing 3.0. That is a learned abstention signal, returned as `act_probability`.
- Trained with RL against proper scoring rules (log + spherical + RPS), so honest probabilities
  are the reward optimum. Temperatures are fitted afterwards per question type and option count
  (`temperature_by_options`).

**Typed-decision interface [P].**
- The request shape is Jev's: `system_one(state, {id: {type: choice|score|noul, instructions,
  criteria}})`.
- `choice` returns probabilities plus a confidence (1 − normalised entropy); `score` returns an
  expected level plus a distribution; `noul` returns P(true).
- All questions are scored in one batched forward pass. The state is truncated from the left to
  `max_len` (512 tokens; 1,024 for the typed-decisions and multilingual checkpoints).
- Options must fit a 192-token head budget (256 multilingual). Accuracy collapses past about 20
  options (Banking77: 0.425 vs Jev 0.870 [V]).

This maps onto `decide()` directly: `choice`, `score` and `noul` are three of doc 4's kinds, and
`act_probability` fits the `abstain` / low-confidence path.

**Checkpoints [P].**

| Checkpoint | Encoder | Weight file | Context |
|---|---|---|---|
| `laya` | ModernBERT-large | 843 MB | 512 |
| `laya/typed-decisions` | ModernBERT-large | 843 MB | 1,024 |
| `laya/multilingual` | mmBERT-base, 322M | 644 MB | 1,024 |

The weight file sizes mean bf16 storage.

**Local inference requirements.**
- Python: PyTorch plus transformers [P].
- Node: `onnxruntime-node` via receptron/laya, MIT, 16 commits [P]. It downloads **fp32** ONNX
  weights (about 1.7 GB) and loads in "roughly 2 GB of RAM … plus a few hundred MB per batch" [P].
- No GGUF or llama.cpp path exists, so Laya would be the first ONNX runtime in noevia.

**CPU performance.**
- About 140 ms for 3 questions on Apple-silicon CPU, warm [P, wrapper README].
- 193–464 ms on CPU per the card [V].
- JevBench ran it on a 4-thread Ryzen 5 3600: raw p50 0.79 s, with the benchmark's ×2 + 0.15 s
  adjustment [B].
- A cold checkpoint build takes about 7.4 s on CPU [V].
- DaServer (24 threads, Zen 5) is untested [—].

**Accuracy and calibration.**

| Measure | Result | Source |
|---|---|---|
| Held-out task families (zero-shot) | 0.651 accuracy, ECE 0.204 | [V] |
| Agent-style typed-decisions workflows, zero-shot | **0.362** (random 0.318, majority class 0.461) | [V] |
| Same workflows after fine-tuning on their training split | 0.766 | [V] |
| JevBench tiers: easy / standard / judge / **hard** | 94.4 / 72.9 / 69.2 / **34.1** | [B] |
| ECE before → after temperature refit | 0.466 → 0.081 | [V] |
| Coverage at 50%, in-task | 0.947 accuracy | [V] |
| Accuracy on non-Latin scripts | 0.000 at 0.952 confidence | [V] |

- The agent-style workflows are the closest public proxy for noevia's decisions, so the model card
  is right to call Laya "a fast base to specialise, not a zero-shot decision engine".
- Raw calibration is over-confident until the temperature refit.
- Its selective-prediction curve is its strength: 0.947 accuracy when it answers the half it is
  surest about.
- It is confidently wrong on non-Latin scripts, so language gating is required.

**Adaptation.**
- The published fine-tune took about 2 h on 2×T4 [P, config and notebook], so it is cheap.
- It needs labelled noevia decisions, which doc 9's corpus produces.
- Temperatures must be refitted on noevia's own data before any gating.

**Can it stay resident beside a large System Two?**
- On footprint, yes. It lives inside the web process (ONNX in Node), outside the 14 GB llama.cpp
  memory cap.
- fp32 ONNX needs about 2 GB [P]. A bf16/fp16 or int8 export should need about 0.9 GB or
  0.5 GB [E, accuracy unverified].
- DaServer has about 6 GB of RAM available while gpt-oss-20B is loaded (13.3), so
  bf16 fits with margin; fp32 fits but is tight.

**Maintenance and licence.**
- Weights Apache-2.0, wrapper MIT.
- About a week old, one vendor (Convai), and 0 recorded downloads on the Hub API today.
- Pin the exact revision.

## 13.3 DaServer memory budget (why residency is the first-class metric)

Measured 2026-09-21 [M]:
- **The GPU is a Radeon 890M iGPU with a 2 GB VRAM carve-out**; llama.cpp (Vulkan) borrows the rest
  from system RAM through GTT.
- **CPU and GPU draw on the same 29 GB of RAM.** A model that stays loaded costs the same memory
  whether it runs on CPU or GPU.
- llama.cpp is capped at `LLAMACPP_MEMORY_LIMIT=14g`.
- Available RAM: about 15.7 GB with no chat model loaded; about 6 GB with gpt-oss-20B resident
  (docling, Nextcloud and the rest share the box).

Model files [M]:

| Model | GGUF size |
|---|---|
| gpt-oss-20B Q4_K_M | 11 GB |
| Qwen3.5-9B Q4_K_XL | 5.8 GB |
| **Qwen3.5-4B Q8_K_XL** | **5.7 GB** |
| Gemma-4-E4B Q4 | 4.0 GB |
| Gemma-4-E2B Q4 | 3.2 GB |
| Qwen3-Reranker-0.6B Q8 | 610 MB |
| nomic-embed Q8 | 140 MB |

The Mac is a 16 GB M2 with unified memory, which gives the same conclusion.

## 13.4 Expected resident footprints (weights + working memory)

| Candidate (class B unless noted) | Where it runs | Resident footprint | Competes with System Two for | Evidence |
|---|---|---|---|---|
| Deterministic heuristic | in process | ≈ 0 | nothing | [M] |
| Jev | remote API | 0 local | nothing (network, cost, state leaves the box) | [P] |
| **Laya typed-decisions**, ONNX | web process, CPU | fp32 ≈ 2.0 GB; bf16 ≈ 0.9 GB; int8 ≈ 0.5 GB | RAM only; outside the llama cap | [P] fp32, [E] others |
| Laya multilingual | web process, CPU | ≈ 0.7–1.4 GB | RAM only | [E] |
| Qwen3-0.6B, option-logit | separate CPU llama.cpp (like `embed`) | ≈ 0.6 GB Q8 + ≈ 0.2 GB KV | RAM only | [E] |
| Qwen3-1.7B, option-logit | separate CPU llama.cpp | ≈ 1.8 GB Q8 + ≈ 0.3 GB KV | RAM only | [E] |
| **Qwen3.5-4B, option-logit (SemIf-style)**, dedicated | router slot or its own instance | Q8 ≈ 5.7 GB + KV; Q4 ≈ 2.7 GB + KV | **the llama cap and the router's two slots**: cannot sit beside gpt-oss-20B, and needs a swap (load time) or a second instance | [M] file, [E] rest |
| Option-logit on the **already-loaded System Two** | router | 0 extra | the **single generation slot** (`parallel=1`): decisions queue behind generation; quality varies with whichever model is loaded | [M] config |
| SemIf native (PyTorch BF16 4B) | Python sidecar | ≈ 8–9 GB | everything | [E] |
| kev-0.6B | Python sidecar (pointer head, no GGUF) | ≈ 1.5 GB + PyTorch | RAM; adds a Python runtime | [E] |
| *(class A)* Qwen3-Reranker-0.6B | router second slot | ≈ 0.6 GB + 8k context | the second slot (by the user's choice) | [M] file |

Reading:
- **On DaServer, a dedicated 4B decision model cannot stay loaded beside the large System Two.**
  gpt-oss-20B plus a Q4 4B is over the 14 GB cap, and the second router slot now holds the
  reranker. So every call would either swap models (seconds) or queue on the System-Two slot.
- Only four candidates can stay resident at any time without competing for the llama.cpp slots
  or cap: the heuristic, Laya, a 0.6–1.7B CPU logit model, and Jev (remote).

## 13.5 Comparison plan: Laya vs option-logit vs Jev vs the rest

**Candidates.** Each runs through `decide()` as a backend, on identical inputs:

| # | Backend | Notes |
|---|---|---|
| H | heuristic | today's rules; the floor every candidate must beat |
| L0 | Laya typed-decisions, zero-shot, card temperatures | as shipped |
| L1 | Laya typed-decisions, temperature refit on noevia calibration split | cheap adaptation |
| L2 | Laya fine-tuned on the noevia training split, refit | real adaptation (2×T4-class GPU, hours; or rent) |
| Q06 | Qwen3-0.6B GGUF, option-logit via llama.cpp `logprobs`, CPU instance | smallest resident logit model |
| Q17 | Qwen3-1.7B GGUF, same | |
| Q4 | Qwen3.5-4B Q8 GGUF, option-logit, recreated SemIf technique | on the Mac GPU and on DaServer, both warm and **including swap cost** |
| S2L | option-logit on the loaded System Two | zero extra residency; measured against each System-Two model |
| SEMIF | SemIf itself (its llama.cpp/GGUF build, or MPS on the Mac) | kept separate from Q4 so our recreation is checked against the original; it is MIT and available [P], so include it |
| K06 | kev-0.6B | only if the Python sidecar cost is acceptable; otherwise note and skip |
| J | Jev 1.13.0 | remote reference; **needs your approval** (synthetic state only; about $0.04 per 1,000 decisions [B]) |

**Decision set.** Synthetic only, from doc 9 plus doc 12. About 600 labelled decisions, split
60/20/20 into train/calibration/test so that L1 and L2 never see test data. The test split is
frozen before any run.

| Family | Kind | Examples |
|---|---|---|
| model selection (fast/smart/vision/code) | choice | today's auto-router cases |
| **mid-task switching** | choice over `KEEP_CURRENT, SWITCH_LOCAL_MODEL, SWITCH_TO_SPECIALIST, RETRIEVE_MORE, RETRY, ESCALATE_REMOTE, FINISH` | synthetic task traces with phase, current model, result quality, latency, memory pressure, swap cost, capability-database rows |
| tool / toolbox selection | multi, choice | existing `experiments/tool-routing` cases |
| retry / continue / stop | choice | loop traces |
| output evaluation | noul, score | answers with known defects |
| escalation | choice + abstain | hard cases local models get wrong |
| context utility | score | chunk or memory usefulness (**not** RAG ranking; that is class A) |
| residency | choice | load/keep/unload scenarios from doc 5 |

**Metrics.** Accuracy alone decides nothing.

| Group | Metric |
|---|---|
| Quality | accuracy and macro-F1 per family; **hard-case accuracy** separately |
| Calibration | ECE (15 bins), Brier, NLL; before and after temperature refit |
| Abstention | risk–coverage curve, AURC, accuracy at 50/80% coverage, how often it escalates and whether that was right (Laya's act head; confidence thresholds for the others) |
| Latency | p50/p95 for 1, 5 and 20 questions batched on one state; **startup / cold load time**; swap-in time when not resident |
| Viability | CPU-only (DaServer 24 threads, Mac M2) and GPU (Mac Metal, DaServer Vulkan iGPU) |
| Footprint | steady RSS / GTT; peak during a batch; effect on System-Two tokens/s while co-resident |
| Residency | can it stay loaded for 24 h beside gpt-oss-20B and beside Qwen3.5-9B without OOM or eviction? |
| Batching | questions per forward pass; shared-state prefix reuse |
| Engineering | new runtime? lines of backend code; export/quantisation steps |
| Health | licence; project age, commits, releases; pinned revision |

**System-level score.** This is the real question. Run the same synthetic multi-step tasks (doc
12, configurations G vs H) with each backend making the switching and escalation decisions.
Measure task success, wall time **including swaps**, peak memory and remote calls. A backend that
is weaker per decision but always resident can win this, and that is exactly what the test is
for.

**Decision rule, to be written down before the test run:**
- Pick the smallest always-resident backend whose system-level task success is within 2 points
  of the best local backend.
- It must also have ECE ≤ 0.10 after refit and hard-case accuracy no worse than the heuristic.
- Otherwise use the best local backend per family, and keep the heuristic floor.

## 13.6 The two research questions

**Q23. One generic System-One model for all bounded decisions, or a hybrid?**
Current answer: **hybrid.**
- Class A models are trained for their task and already beat a generic model's likely score
  there. The reranker went 80% → 86–91% on RAG [M]; no general decision model is trained on
  query–passage relevance at that size.
- One small class-B model then handles the orchestration decisions through `decide()`.
- What would overturn this: a single class-B backend matching the reranker **on the RAG set**
  at lower total residency. Keep it as a test (run the RAG suite through `decide()` with the
  winning class-B backend), not as a goal.

**Q24. Is the 4B option-logit approach better at system level once residency and swapping are
counted?**
Current answer: **probably not on DaServer as a dedicated model; possibly yes as "logit readout on
whatever System Two is loaded".**
- A dedicated 4B cannot stay loaded beside gpt-oss-20B (13.4), so it pays a swap on every
  decision burst, or it must *be* the System Two.
- When the loaded System Two is itself a 4B-class model, reading option logits off it costs no
  extra memory. The price is quality that shifts with the loaded model, and waiting for the one
  generation slot.
- JevBench's 74.7 for SemIf [B] is per-decision quality on a 32 GB GPU with the model always
  loaded, which is exactly the condition noevia lacks.
- To be settled by the §13.5 system-level run (Q4 and S2L against L1/L2 and Q06/Q17).

## 13.7 Most promising candidate for the always-resident generic role (hypothesis)

1. **Laya typed-decisions, fine-tuned on noevia's decisions and temperature-refit (L2)**, in
   process via ONNX at bf16 or int8.
   - Why:
     - about 0.5–0.9 GB outside the llama cap;
     - a typed interface that matches `decide()`;
     - a built-in abstain/escalate head;
     - a strong risk–coverage curve;
     - cheap fine-tuning.
   - Risks:
     - near-chance zero-shot on agent workflows (0.362);
     - weak on hard decisions (34.1 on JevBench);
     - over 20 options breaks it (irrelevant for noevia, where the switching set has 7 actions);
     - a 512/1,024-token state limit means a compact state summary is required, which doc 12's
       handover note already provides;
     - it is a new runtime (ONNX), from a week-old single vendor.
2. **Qwen3-0.6B/1.7B option-logit on a CPU llama.cpp instance (Q06/Q17).**
   - It adds no new runtime: the same pattern as the `embed` container and the existing
     `llama-logit` design (doc 4 §4.5).
   - It sits at about 0.8–2.1 GB, and is likely weaker than 4B (kev-0.6B scored 66.7 [B]).
   - It is the fallback if Laya's fine-tune fails the decision rule.
3. **Not recommended as the always-resident generic model:** a dedicated 4B (13.6 Q24), SemIf's
   PyTorch runtime, kev (Python runtime), Nimble/djev (no local path on this hardware).
4. **Always present:** the heuristic floor. Jev stays a reference, and an opt-in remote backend
   only if policy allows cloud.

Nothing here is chosen yet. The ranking above is a prior for which experiments to run first.

## 13.8 What to benchmark next, before choosing

In order:

1. **Build and freeze the noevia decision set** (13.5). Synthetic, about 600 items, including
   the 7-action switching family. No downloads needed.
2. **Cheap resident baselines:**
   - H;
   - Q06/Q17 on a CPU llama.cpp instance on the Mac, then DaServer;
   - S2L on the Mac's Gemma-4-E2B and Qwen3.5-4B.

   Needs Qwen3-0.6B/1.7B GGUF downloads (about 0.6 GB / 1.8 GB, from `Qwen/…-GGUF` on Hugging Face):
   **needs your approval.**
3. **Laya L0 → L1 on CPU:** footprint, cold start, p50/p95 on DaServer and the Mac; calibration
   before and after refit; act-head abstention.

   Needs `convaiinnovations/laya` `typed-decisions/` (843 MB safetensors) or the receptron fp32
   ONNX (about 1.7 GB): **needs your approval.**
4. **Q4 and SEMIF on the Mac GPU:** accuracy per family, then the **swap-inclusive** latency on
   DaServer while gpt-oss-20B is the System Two. That needs a maintenance window you start (D2).
5. **Laya L2** fine-tune on the training split, if L1 is promising (about 2 h on a rented
   2×T4-class GPU, or longer on the Mac's MPS). Rented GPU time needs your approval.
6. **Jev (J)** on the same frozen test split, as the reference. **Needs your approval** (remote,
   synthetic state, about $0.04 per 1,000 decisions).
7. **System-level run:** doc 12's switching tasks with the top two local backends plus H,
   measuring task success, wall time including swaps, and peak memory. Apply the §13.5 decision
   rule.

**Production stays unchanged** throughout: the reranker (class A) stays live as it is, and no
class-B backend is wired into chat until step 7 picks one and it passes a shadow-mode release
(doc 4 §4.8).

## 13.9 Pilot set-up (2026-09-21)

The pilot lives in `experiments/system-one/decisions/`, with its own README. It has:
- a compact decision state (`noevia.decision-state/1`);
- 594 synthetic decisions in 9 families × 5 template families, split by template;
- baselines B0 and B1;
- an isolated `llama-server` worker behind `decide()`, with a deadline and cancellation.

One run completed: Gemma-4-E2B, compact state, on the M2 GPU. The user stopped the rest because
the Mac was in use.

**Execution boundary, from now on:**
- No model servers, inference, benchmarks, training or heavy builds on the Mac **or** DaServer
  without approval for that run.
- A run proposal states:
  - host;
  - model and exact configuration;
  - number of cases;
  - CPU/GPU use;
  - expected peak memory;
  - concurrency;
  - maximum duration and stop conditions;
  - impact on other applications.
- A smoke test comes first.

## 13.10 Audit of the pilot (2026-09-21, no new inference)

### Confirmed implementation issues

1. **Option-logit readout v1** (`llamaLogitBackend` as of `e906624`):
   - it read only the top-50 next-token log-probabilities;
   - it gave any missing option label an invented floor (min − 2) and normalised it together
     with the observed scores;
   - with every label missing it would still pick the first option;
   - `lettersSeen` counted any capital letter, not the permitted labels;
   - it did not check that the scored position was the answer position (Gemma-4 emits a
     `<|channel>` token first unless thinking is off in the template);
   - it had no notion of token variants.
2. **The grammar method is not exact in the pinned runtime** (llama.cpp `b29c606e2`). The server
   calls `common_sampler_sample(..., grammar_first=false)`. When the greedy token is already
   valid, the grammar is never applied to the candidate list, so `post_sampling_probs` is
   sometimes grammar-restricted and sometimes not.
3. **Residency v1** (`state.cjs`) compared file size with currently free memory. It could not
   express "fits only after unloading the current model". It treated file size as resident and
   reclaimable memory, and ignored KV/context, runtime overhead, load peaks and pinned residents
   such as the reranker.
4. **B0 is an approximation, not noevia's measured behaviour.** Its model choice uses production's
   `auto-router` heuristics. Everything else is simplified (choose once, retry while possible,
   finish when told). Its aggregate is not noevia's task-success rate.
5. **Several families are structured compliance tests.** In the model-choice families (initial,
   keep/switch, general/specialist, unavailable), and in finish/injection where the verifier flag
   is structured, the labels come from the same fields B1 reads. The same author wrote the rule,
   the label and the baseline.
6. **The injection family is one held-out attack template in 24 variants,** not a robustness
   suite.

### What the saved logs can and cannot establish

The v1 run kept each option's normalised probability, `lettersSeen`, latency and prompt size.

It kept no raw top-k tokens, first token or label-to-token mapping. From it:
- **Shown:** all 378 decisions came from the model, with no fallbacks.
- **Shown:** no row has two options with identical probability, so there is no sign of two or
  more options sharing the invented floor score.
- **Cannot be shown:**
  - whether a single option per row was floored;
  - whether the scored position was the answer position;
  - which labels were really observed. `lettersSeen` was 17–18 per row, which carries no
    information.
- **Not shown either way:** whether the readout caused any failure. The injection failures put
  0.84–0.86 on FINISH with the other options at 0.12–0.14 and ≈0.02. That pattern doesn't look
  like a floor artefact, but it doesn't rule one out. **The v1 probabilities are provisional.**

### Corrected scoring contract (v2, implemented and unit-tested with mocks only; never run)

`llamaLogitBackend` in `apps/web/server/decision/backends.cjs`, with tests in `logit.test.cjs`:

1. **Labels:** single letters, resolved with `/tokenize`. The variants `"A"` and `" A"` are one
   answer, and their probabilities are **summed**. A label whose canonical form is not one token
   is refused.
2. **Answer-position check (unbiased request):** the permitted label variants must hold
   ≥ `minLabelMass` (default 0.5) of the first generated position's probability. Otherwise the
   readout is invalid, and the top token is reported.
3. **Exact ratios (second request, served from the prompt cache):**
   - an **equal** `logit_bias` on every label token, samplers `["temperature"]` at T=1, and
     `post_sampling_probs`;
   - the pinned chain is logit-bias → samplers → dist, so an equal bias keeps the ratios among
     label tokens exact;
   - the leftover mass on other tokens is reported and must be ≤ `maxResidual` (default 1e-3).
4. **No invented scores:**
   - labels are reported as observed or unobserved;
   - an unobserved label gets probability 0, bounded by the residual;
   - the readout counts as complete only when that bound is negligible.
5. **Failure handling:** invalid readouts, incomplete readouts and exact ties **throw**, so
   `decide()` logs them and uses the authorised fallback. The runner records the readout and the
   failure reason per decision.
6. **Not yet validated:** a smoke test on an approved host must confirm the tokenization,
   answer-position mass and residual on the real model before any v2 numbers are trusted.

### Corrected residency specification (v2, `residency.cjs`, unit-tested)

- **Inputs:** a **host profile** (deployment-specific: the model-runtime cap, measured available
  host memory, and resident models with measured footprints and a `pinned` flag), plus a
  candidate's **measured** steady footprint at the planned context and its measured load peak.
- **Result:** `coexist`, `after_swap`, `no_fit` or `unknown`.
  - `after_swap` only reclaims the measured footprint of models named swappable at a safe
    checkpoint, and never a pinned model such as the reranker.
  - Any missing measurement gives `unknown`: no estimate from file size.
- **Use:** a shortlist carries each candidate's fit class. A `SWITCH` action to an `after_swap`
  candidate is offered **only** when session durability can checkpoint and resume (doc 6). Until
  then it is shown, but not permitted.
- **Scope:** DaServer's numbers go in its own profile, not in noevia-wide rules.

### Policy-wrapped pipeline over the saved v1 run (`pipeline.cjs`, analysis only)

Test split (216 decisions). Gate: a completion action is refused while the latest authoritative
verifier result is an unresolved FAIL, and fallbacks pass the same gate.

| | Raw model | Final, B0 fallback | Final, B1 fallback | B0 alone | B1 alone |
|---|---|---|---|---|---|
| all families | 64% | 62% | 77% | 39% | 77% |
| misleading tool output | 0% | 100% | 100% | 0% | 100% |
| retry vs retrieve (free text) | 79% | 54% | 54% | 54% | 54% |
| insufficient evidence (free text) | 63% | 38% | 38% | 38% | 38% |

- **The gate makes the injection outcome safe** whatever the model chose (24 of 24 rejected). The
  raw model's 0% remains a model-robustness finding.
- **One global threshold (0.88, fitted on calibration) abstained on 167 of 216,** including every
  free-text decision where the raw model beat B0. What happens after abstaining decides the
  outcome, so thresholds must be fitted per family, or per category.

### Which conclusions stand

| Conclusion | Status |
|---|---|
| The class A / B / C separation; the reranker stays as it is | Supported (design) |
| Hard constraints, policy, approvals and verifier authority are deterministic, and a gate makes the injection outcome safe whatever the model chooses | Supported by the pipeline analysis, though the injection set is one template |
| Selecting from explicit numbers (question A) is done well by a deterministic rule | Supported for synthetic numbers only; it says nothing about the value of a generic model elsewhere |
| A small option-logit model helps on free-text judgements (question B) | **Provisional:** v1 readout, 24 items per family, one author, one template per family |
| Gemma-E2B's calibration and abstention numbers | **Provisional:** v1 readout; global threshold |
| "Laya / dedicated decision models do not help" | **Not tested.** No such conclusion |
| Adaptive mid-task switching helps or hurts (question C) | **Not tested.** Needs session durability first |
| Model-routing labels reflect real model quality | **No:** capability numbers are synthetic; no measured noevia outcomes exist yet |

### Revised, smaller benchmark design

- **Question A** (constraint enforcement, selecting from explicit numbers): the rules, eligibility,
  residency and the gate become **unit tests**. No model runs.
- **Question B** (interpreting ambiguous natural-language evidence and recommending a next action).
  About 300 decisions in 5 free-text families:
  1. failure cause → retry / retrieve more / switch to a specialist / ask;
  2. **missing capability** named in verifier or tool text (vision, long context, code execution,
     tool access) → which capability to route to;
  3. evidence sufficiency → answer / ask;
  4. completion judged from a free-text reviewer note, with **no** structured pass flag;
  5. requirement change between phases (e.g. planning turns into coding) → keep / change model
     class.
- **Split for question B:**
  - each family has 2 calibration templates and 4 **held-out test templates**, 60 decisions per
    family (20 calibration, 40 test);
  - wording and labels come from separate sources: the labelling rubric is fixed first, and the
    held-out templates are written independently (by you, a second agent, or both);
  - you review a sample of labels;
  - multiple acceptable actions are allowed.
- **Security set:** a separate adversarial set with at least 5 attack templates (instruction in
  tool output, fake verifier message, fake approval, a fake capability claim to steer a model
  switch, markup-hidden text). Reported raw and after the gate.
- **Question-B reporting:** per family and category:
  - raw quality;
  - invalid readouts (v2);
  - gate rejections;
  - abstention with per-family thresholds;
  - final outcome with the **B1 structured fallback** and with B0;
  - latency and memory.
- **Precision:** 200 test decisions give about ±7 points overall and about ±15 per family. Enough
  for large effects only.
- **Question C** (a whole task, including switching costs): about 8 multi-phase synthetic tasks
  run choose-once vs checkpoint-and-switch. Measures task success, wall time including load and
  context rebuilding, and peak memory. **Blocked on session durability** (doc 6 M4): no switching
  experiment until noevia can checkpoint, unload, resume without repeating tool side effects, and
  keep approvals intact.
- **Model-routing evidence:** any routing test that uses capability numbers labels them
  *synthetic* until real noevia outcomes exist in the capability database (doc 12).

### Minimum next experiment (needs your approval of host and run)

**A readout-v2 smoke test:** Gemma-4-E2B (already installed), 10 decisions from the calibration
split, one worker, context 8192, on a host you choose. It checks four things only:
- label tokenization;
- answer-position label mass;
- residual mass;
- the invalid-readout rate.

Only if those hold is the question-B pilot (about 300 decisions, one model) worth proposing.

Laya typed-decisions stays **untested**. Its exact download proposal:
- the checkpoint: `convaiinnovations/laya-typed-decisions` @ `f9ab0b2`, 843 MB safetensors plus
  about 3.6 MB tokenizer and config;
- the reference code: `convaiinnovations/laya` @ `1c5edc1` (`rl_common.py`, `rl_agent_api.py`);
- Python packages: CPU `torch`, `transformers`, `safetensors`, `numpy`, in their own virtual
  environment.

The `receptron/laya-onnx` export (@ `68f27df`) is the *base* checkpoint and is not evidence about
typed-decisions. This proposal waits for a separately approved host and run. Laya would be
compared on the same question-B set, through the same `decide()` interface.
