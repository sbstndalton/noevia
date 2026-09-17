# Synthetic tool-routing experiment — 2026-09-13

Decision: retain current production routing. This bounded experiment found no
latency or total-token benefit from deferred disclosure or a planning pass.

Seven fixtures, two repeats, rotated mode order; Gemma-4-E4B-it-GGUF through the
existing Lemonade endpoint, Vulkan, ctx_size 32768, K cache q5_0 / V cache q4_0.
Planner and executor used the **same model**. No production setting changed.
All tools and approval decisions were simulated; no real tool writes or Diary data.
The standalone baseline approximates the current approach; it is not a benchmark
of the complete production HTTP handler.

| Mode | Exact answers | Median elapsed | Input tokens | Output tokens |
| --- | --- | --- | --- | --- |
| baseline | 14/14 | 8.64s | 6420 | 2736 |
| deferred | 14/14 | 12.91s | 12382 | 3813 |
| planner | 13/14 | 26.97s | 8894 | 8625 |

The planner's one exact-answer failure was formatting: it returned the correct
BLUE-17 code in a sentence. This is not evidence of a factual accuracy regression.
Each mode performed six expected simulated writes and six approvals, including
zero writes on declined cases. Eight scripted tests separately cover selection
ceilings, schema-disclosure timing, duplicate writes, approval decisions,
deselection, round limits and provider failure.

For the large catalogue, cumulative schema bytes fell from 7,026 to 1,420 with
deferred disclosure, but provider input tokens rose from 1,522 to 1,648 per case.
The catalogue and extra search round offset the schema saving. Byte-derived token
estimates exclude messages/results/catalogue and are labelled estimates.

Only two repeats on one shared backend: timing is indicative, not a controlled
hardware qualification or broad accuracy benchmark. A distinct Smart/Fast pair,
cancellation in the production handler, and browser approvals remain adoption
gates if a future experiment shows a useful tradeoff.

Run tests with `python3 -m unittest discover -s experiments/tool-routing -p 'test_*.py'`.
See `python3 experiments/tool-routing/run.py --help` for explicit endpoint/model
arguments. API credentials, if needed, come from TOOL_EXPERIMENT_API_KEY.
Full synthetic answers and measurements are in gemma-e4b-results.json.

## Router variant (prepared 2026-09-16, not yet measured)

`--modes baseline router --embedding-model <id>` adds task-conditional loading: one
embedding call before the first model call ranks the fixture's selected tools against
the request, loads the top `--router-top-k` above `--router-threshold` once for the
case, and never widens the selection. If embeddings fail it falls back to the full
selection and records `router_fallback`. Rows add `router_ms` and `routed_tools`.
The ranking mirrors `apps/web/server/tool-router.cjs`, whose unit tests cover the
production policy (deployment ceiling, `autoLoad: never`, `requires` closure,
whole-box cap, tool-name collisions, user selection, fallback).

Gate from the roadmap: adopt only if completion ≥ baseline and median latency is no
worse than baseline plus a stated margin, on this deployment's models.

### Measured 2026-09-17 — gate passed

Qwen3.5-4B-Q5_K_M on native llama.cpp (Vulkan, ctx 24 576, `--models-max 2`), embeddings from
`nomic-embed-text-v1` (Q8_0) on the same engine, run from inside the Diary container against the
internal engine. Seven fixtures × two repeats × two modes, rotated order, synthetic tools only.
Full rows in `qwen35-4b-router-results.json`.

| Mode | Exact answers | Median elapsed | Input tokens | Output tokens | Writes / approvals |
| --- | --- | --- | --- | --- | --- |
| baseline | 14/14 | 10.59 s | 12 872 | 2 234 | 6 / 6 |
| router | 14/14 | 9.72 s | 9 872 | 2 238 | 6 / 6 |

Router overhead was 16–1 270 ms (the first call loads the embedding model; later ones are
~15–85 ms). Input tokens fell 23 %, the large-catalogue case from 2 476 to 976 per case, with no
fallback and no lost writes or approvals. Per-fixture medians differ by at most ±2 s either way,
within run-to-run noise at n = 2. Decision: adopt behind `features.toolRouter` (off by default).

Production applies the same policy at **toolbox** granularity rather than single tools: it only
narrows the project's own selection (never adds a box, so it cannot offer an unapproved write)
and keeps the whole selection when embeddings fail or no box clears the threshold
(`apps/web/server/chat-tool-routing.cjs`).
