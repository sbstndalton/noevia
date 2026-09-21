# 12. Adaptive model capability profiling and mid-task model switching (draft for review)

Model routing is not a one-time decision at the start of a request. At safe, noevia-owned
boundaries, System One re-evaluates whether the active System-Two model is still the best one for
the **current phase** of the task, and the deterministic Model Manager (doc 5) performs any change.
Continuity comes from noevia-owned state (doc 6). No hidden reasoning ever moves between models.

## 12.1 Research questions

- **RQ-A.** Can noevia dynamically choose and switch among local models during a single task, using
  System-One decisions and an empirical capability database, so that it reaches higher task
  quality while using the smallest or cheapest suitable model for each phase?
- **RQ-B.** Does adaptive switching outperform the simpler strategy of choosing one model once, at
  the start?

Neither can be answered from the literature for noevia's setup. Both are measured in doc 9
(configurations G and H). The hypotheses and falsification criteria are in 12.9.

## 12.2 Phases and safe boundaries

A task moves through phases. System One (or a deterministic rule, when the phase is obvious)
labels the phase at each boundary:

```
classify → plan → retrieve → implement/code → tool work → verify → explain
```

**Switching is allowed only at these boundaries:**
- after a generation step;
- after a tool result;
- after a planning step;
- after a failed attempt;
- after retrieval;
- before the next agent step.

It never happens mid-stream, and never between a tool call and its result.

What crosses a switch is only the doc-6 checkpoint: conversation, task state, plan, working memory,
tool history and results, retrieval references, structured intermediate outputs and retry history.
The incoming model receives it as an ordinary prompt: rebuilt messages plus a short, noevia-written
**handover note** (phase, plan, open items, what has been tried). The handover note is generated
deterministically from structured state, not written by the outgoing model.

## 12.3 When to re-evaluate (so decisions do not cost more than they save)

Re-evaluation is **event-triggered**, not run every step:

| Trigger | Typical recommendation |
|---|---|
| phase change detected (plan finished, first code edit, verification started, final answer due) | specialise (general → code) or de-escalate (code → fast for the explanation) |
| evaluator verdict `RETRY_LOCAL` twice, or `USE_STRONGER_LOCAL` | escalate |
| tool failure streak ≥ 2 (bad arguments, schema errors) | a model with better measured tool accuracy |
| context headroom below the next step's estimate | a model with a longer context, or compact first |
| sustained low decode speed / memory pressure (Model Manager signal) | a smaller model |
| user-pinned model | **no switching** (the user's choice overrides) |

Each re-evaluation is one bounded `choice` decision (doc 4). Its allowed set is computed
deterministically from:

- models whose role fits the phase;
- that the Model Manager can `plan()` as feasible now;
- that policy allows: cloud off means no remote models; user pins; budget.

## 12.4 The decision

Inputs, given to System One as structured state:
- the phase;
- the last evaluator verdict and its confidence;
- recent tool outcomes;
- context used and remaining;
- for each candidate, a capability-database summary for this phase: success rate with
  uncertainty, median latency, load cost now (0 if hot), memory fit, cost class;
- the current model and its time since load.

Output: one of the allowed `{ model, action }` pairs. Actions are `KEEP_CURRENT`,
`LOAD_ALONGSIDE`, `CHECKPOINT_AND_SWAP`, `PRELOAD_NEXT`, `HIBERNATE_CURRENT` or `RESTORE_PREVIOUS`
(doc 5 §5.3).

**The objective is not hard-coded.** The design keeps two routers side by side and lets the
benchmark decide:

- **R-score:** a transparent deterministic baseline.
  `score = P(success | model, phase) − λ_t·latency − λ_s·swapCost − λ_m·memoryPressure − λ_c·cost`,
  with λ fitted on the benchmark. It is also the fallback when System One is unavailable.
- **R-S1:** System One picks among the same feasible options, given the same evidence.

Whichever wins on doc-9 metrics becomes the default. The loser stays as the fallback.

Guards that stay deterministic whatever the router says:
- **hysteresis** (doc 5 §5.2): no preference-driven swap within the minimum residency time;
- **switch budget:** at most N swaps per turn (start at 2), after which the current model finishes;
- **no oscillation:** A → B → A within one turn is refused unless forced by a hard requirement;
- **user pin:** always wins;
- **cloud:** only if policy has already opened it.

## 12.5 Bidirectional by design

| Direction | Example | Why it pays |
|---|---|---|
| small → large | repeated failed attempts on a hard reasoning step | quality |
| large → small | the code change is done and verified; the explanation goes to the fast model | latency, and frees the accelerator |
| general → specialist | the plan says "edit these files" → coding model | quality per token |
| specialist → general | back from code to a prose summary | the specialist is often worse at prose |
| local → remote | only when policy allows, the local tiers are exhausted, and the evaluator says the answer is not good enough | last resort (doc 7 cost classes) |
| remote → local | the remote model produced the plan; local models execute the steps | cost; keeps data local for execution |

De-escalation is as important as escalation. The largest model should not stay hot just because
an earlier phase needed it: `HIBERNATE_CURRENT` after a phase ends is a first-class action.

## 12.6 Model capability database

**Key: an exact configuration, not a family name.**

```
configKey = sha256(model file) + quant + engine@version + backend + ctx + kvType + flashAttn + key sampling settings
```

"Qwen3.5-9B" is not a key. `Qwen3.5-9B-Q5_K_M.gguf @ llama.cpp b6xxx / Vulkan / ctx 24576 / f16 KV`
is. When anything in the key changes, a new profile starts, seeded from the old one as a weak prior.

**Schema (sqlite, per installation, in `ui-data/`):**

```sql
configs(config_key PK, model_id, file_sha, quant, engine, engine_version, backend, ctx, kv_type, params_b, created_at)
static_priors(config_key, dimension, value, source_url, source_kind /* 'vendor'|'independent'|'community' */, retrieved_at)
bench_results(config_key, suite, task_id, dimension, success, score, latency_ms, tokens_in, tokens_out, run_at)
task_outcomes(config_key, phase, dimension, success, evaluator_verdict, retries, tool_calls, tool_errors,
              user_correction /* bool */, latency_ms, prefill_ms, swap_in_ms, at)   -- no content, no prompts
resource_profile(config_key, load_ms_cold, load_ms_warm, unload_ms, peak_bytes, prefill_tok_s, decode_tok_s, measured_at)
```

**Dimensions:**
- coding, debugging, reasoning, planning, research;
- summarisation, RAG synthesis, instruction following;
- tool calling (correct tool, valid arguments);
- long-context use, vision;
- plus latency, memory footprint, load time, prefill time and cost from `resource_profile`.

**Where evidence comes from, and how it is combined:**

| Source | Weight | Notes |
|---|---|---|
| Public benchmarks / model cards | weak prior | stored with its URL and kind; never overrides local evidence |
| Local benchmark suite (doc 9) | medium | controlled, repeatable; run by the admin in a maintenance window (D2) |
| Real noevia outcomes | strongest once n is large | success = evaluator PASS without user correction; failure signals = retries, tool errors, user corrections, "regenerate", abandoned turns |

Per `(config, dimension)`, estimate the success rate as a **Beta posterior**. The prior comes from
public or benchmark evidence, scaled to an effective n of about 10. Real outcomes update it. The
decision gets the mean *and* the interval, so it can see "84% ± 3 over 400 tasks" is different from
"90% ± 25 over 4 tasks". Local evidence dominates automatically as it accumulates, and that is the
"prefer locally observed performance" requirement expressed as arithmetic rather than as a rule.

**Output you can read** (admin Models page, later):

```
Qwen3.5-4B Q5_K_M / Vulkan:  repo debugging 71% (±6, n=212)  median 2.1 s   load 4.8 s
Qwen3.5-9B Q5_K_M / Vulkan:  repo debugging 84% (±5, n=180)  median 5.4 s   load 9.6 s
```

**Privacy:** outcomes store labels, counts and timings, never prompt or answer content. The
database is per installation and is not shared.

**Honest limits:**
- Outcome labels from real traffic are noisy (a user who does not correct is not necessarily
  satisfied).
- Phases are imperfectly labelled.
- Selection bias: models only get data on the tasks they were routed to. Mitigation: a small
  exploration rate (for example 5% of eligible, low-risk steps route to the second-best candidate),
  **off by default** and never used for write-capable steps.

## 12.7 Interaction with the Model Manager

```
boundary reached
  → Session Store: checkpoint (doc 6)                                    [deterministic]
  → ModelManager.plan(candidates) → feasible actions + estimated cost    [deterministic]
  → System One: choose {model, action} from the feasible set              [decision]
  → validate (hysteresis, switch budget, pins, policy)                    [deterministic]
  → ModelManager.apply(plan)                                              [deterministic]
  → rebuild prompt + handover note → continue                             [deterministic]
  → record outcome to the capability database                             [deterministic]
```

**Predictive preloading:**
- When the plan names a likely next phase (for example "implement" after "plan") and the target
  fits without eviction, `PRELOAD_NEXT` starts the load while the current model is still working.
- Measure the hit rate and the wasted loads.

## 12.8 Costs that can make switching a loss

- **Swap cost:** load time plus the rebuilt-context prefill. On an iGPU this is seconds to tens of
  seconds.
- **Handover loss:** the new model lacks the old model's implicit understanding; only the explicit
  state crosses.
- **Style discontinuity** in the final answer. Mitigation: the explanation phase is written by one
  model, from the structured results.
- **Thrash:** mitigated by hysteresis, the switch budget and the no-oscillation rule.

On hardware that holds only one System-Two model at a time, switching probably pays only at phase
boundaries separated by long work (for example plan → a long code phase), not per step. The
benchmark measures where the break-even lies. The design must degrade to "choose once" when
switching does not pay.

## 12.9 Hypotheses and falsification

- **H3 (adaptive switching beats choose-once):**
  - Claim: task success at least as high as the best single-model choice, with lower total task
    time or lower large-model time.
  - Falsified if: configuration H loses to configuration G on success rate, *or* on total task
    time at equal success.
- **H4 (the capability database improves routing):**
  - Claim: routing with local evidence beats routing with public priors alone.
  - Falsified if: after N ≥ 200 real or benchmark outcomes per candidate, database routing is not
    better on success per unit of time.
- **H5 (de-escalation is free):**
  - Claim: handing the explanation phase to the fast model does not lower rated answer quality.
  - Falsified if: a blind comparison shows a significant drop in quality.

## 12.10 Answers so far (to be replaced by measurements)

- **RQ-A:** Architecturally yes. Every requirement maps onto components designed here (the doc-6
  checkpoint, the doc-5 manager, the doc-4 decision). Whether it *raises quality while shrinking
  models* is unknown until configuration H runs.
- **RQ-B:** Unknown. The prior expectation is that on single-accelerator machines it beats
  choose-once only on long multi-phase tasks (code, research), and loses or ties on short chats,
  where the router should choose once and never switch. The design therefore makes "never switch"
  the automatic outcome whenever the estimated swap cost exceeds the expected gain.
