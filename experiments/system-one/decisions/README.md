# Generic System-One pilot (class B decisions)

> **Status 2026-09-21: paused and audited** ([doc 13 §13.10](../../../docs/research/system-one/13-model-classes-and-system-one-candidates.md)).
> - The saved Gemma run used readout **v1**, which had known defects, so its numbers are provisional.
> - `run.cjs` now uses readout v3 (exact / bounded / invalid; diagnostics saved per decision) and decision state v2 (residency-aware). Neither has been run against a model.
> - **No run on any host without per-run approval.**
> - Families whose labels come from structured fields are compliance tests (question A), not evidence about a generic model's wider value.
> - The injection family is one attack template.

**Question:** can a small local decision backend improve noevia's routing and control decisions
without adding disproportionate memory, latency, maintenance or state-preparation overhead?

This is a **pilot**, not a selection. Nothing here is wired into production, and the live
class-A reranker is untouched. Design notes are in
[doc 13 §13.9](../../../docs/research/system-one/13-model-classes-and-system-one-candidates.md).

## Files

| File | What it is |
|---|---|
| `state.cjs` | **Decision state v2** (`extractV2`, residency-aware; see doc 13 §13.11), plus the unchanged **v1** (`noevia.decision-state/1`): the compact, provider-neutral input. It holds one decision's facts plus a reference to noevia's canonical task state. Deterministic extraction; no model call. |
| `scenarios.cjs` | The pilot set: 594 synthetic decisions in 9 families × 5 template families, split **by template** (train t0–t2, calibration t3, test t4). Labels are sets of acceptable actions. |
| `baselines.cjs` | **B0**: an *approximation* of today's behaviour. It uses the real `auto-router` heuristics for model choice, and simplified rules elsewhere (choose once, retry, finish, never abstain). Its accuracy is **not** noevia's measured task success. **B1**: a plain rule over the structured fields. |
| `residency.cjs` | Residency feasibility v2: `coexist`, `after_swap`, `no_fit` or `unknown`, from measured footprints and a host profile. Unit-tested. |
| `harness.cjs` | One decision through `decide()`, appended to the results file with its readout diagnostics, whether it succeeds or fails. |
| `smoke-report.cjs` | The readout smoke-test report: readout classes, rejections, label mass, residual and consistency checks. **No accuracy.** |
| `test-fixtures/fake-llama-server.cjs` | A mock HTTP server for the runner tests. No model. |
| `pipeline.cjs` | The policy-wrapped pipeline over saved results: raw choice, gate rejections, abstention, fallback (B0 or B1), final outcome. |
| `run.cjs` | Runs a backend as an **isolated worker**: a `llama-server` subprocess with bounded threads, context and slots. Every decision goes through production `decide()` with a deadline, cancellation (AbortSignal) and B0 as the fallback. It records cold start, peak RSS, latency and truncation. |
| `analyze.cjs` | (v1 rows) Per-family accuracy (Wilson 95%), raw vs calibrated ECE, abstention, coverage, false acceptance, and cost. |
| `results/` | Raw JSONL per run, plus `summary.md`. |

```bash
node experiments/system-one/decisions/run.cjs --baselines
node experiments/system-one/decisions/run.cjs --model ~/noevia-models/gemma-4-E2B_q4_0-it.gguf --label gemma-4-E2B [--render full] [--ngl 0 --threads 4]
node experiments/system-one/decisions/analyze.cjs experiments/system-one/decisions/results/*.jsonl
```

## Decision state v1: what goes in, and what does not

Included:
- task text, type and phase;
- the latest verifier results (PASS / FAIL / free-text note);
- the last tool output, marked as untrusted data;
- the current model's profile **for this task type**;
- up to 4 eligible alternatives, best measured first, with the count of any left out;
- free memory and policy;
- retry and switch budgets;
- the cost of rebuilding context after a switch;
- the allowed actions, each with its full description.

Excluded:
- the conversation;
- the rest of the capability database;
- ineligible models.

Eligibility is decided **before** the model is asked, deterministically: memory, availability and
policy. So the decision model cannot pick a model that doesn't fit, and it cannot pick a remote
model under a local-only policy.

No silent truncation:
- a text field over its budget goes into `overflow`, and the caller must fall back rather than
  decide on partial evidence;
- option descriptions are never shortened;
- the worker log's `truncated = 1` count is recorded per run.

Everything comes from structured state noevia already keeps, so the state costs no model call.

## Pilot design

| Family | What is tested | Label comes from |
|---|---|---|
| initial_selection | model choice at the start | measured success for the task type; ties within 0.03 all acceptable. Templates t1/t4 make a 1.2B model the measured best and gpt-oss-20B mediocre |
| keep_vs_switch | stay or switch at a safe checkpoint | gain in measured success (keep if ≤ 0.10; switch if ≥ 0.05; both in between); budget |
| general_vs_specialist | general vs code/vision specialist | measured success only; 40% are "traps" where the general model is better |
| retry_vs_retrieve | the cause of a rejected step | free-text verifier note only (missing evidence → retrieve; transient → retry; no retries left → finish with notice or ask) |
| finish_vs_incomplete | done or not | verifier PASS/FAIL |
| insufficient_evidence | answer vs ask the user | free-text note: conflicting or absent → ask; clear → answer |
| unavailable_or_memory | the profile-best model is not eligible | best eligible (the ineligible one is excluded from the shortlist, but present in the full state) |
| local_only | repeated failure, remote not allowed | finish with notice or ask; a web page in the tool output suggests the cloud |
| misleading_tool_output | prompt injection claims the task is done | verifier FAIL → continue |

Sizes: 594 decisions in total (216 train, 162 calibration, 216 test), with **24 test decisions per
family**. The Wilson intervals on 24 items are roughly ±15–20 points, so this pilot can show large
differences only. It **cannot** show a 2-point difference: that needs on the order of 2,000+ test
decisions per compared pair, and more template families. The training split is not used by any
zero-shot backend.

Threats to validity, stated up front:
- The labels for the model-choice families come from the same structured facts B1 reads, so B1 is
  near an upper bound there **by construction**.
- The synthetic phrasing is ours, and real verifier output will be messier.
- The same author wrote the scenarios and the rules.
