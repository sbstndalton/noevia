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

### Production shape — 2026-09-17 (gate holds; not enabled live yet)

`production-shape.cjs`, run inside the live web container (release 127b300). Real curated Nextcloud
boxes and schemas from `nextcloud-mcp` (`tools/list` only; **no tool was called**), the production
router (`chat-tool-routing.cjs`, top-3, threshold 0.35) and the production selection rule
(selection order, 12-tool cap, 5 000-token budget). A 10-box project (notes, calendar, tasks,
files, mail, contacts, deck, talk, cookbook, news; 744–5 367 schema tokens each), 13 realistic
requests × 2 repeats, alternating order. Chat model Qwen3.5-4B-Q5_K_M on the native engine;
embeddings from a temporary CPU-only `llama-server --device none` nomic (`-c 4096 -ub 2048`; with
`-c 2048 --parallel 2` each slot is 1 024 tokens and box texts up to 4 000 chars fail, which made the
first attempt silently fall back to the full selection). Rows in
`qwen35-4b-nextcloud-production-shape-2026-09-17.json`.

| Mode | Needed box reached the model | First tool call from the right box | No tool call | Median wall | Median input tokens | Router cost |
|---|---|---|---|---|---|---|
| baseline | 8/26 | 6/26 | 16 | 15.1 s | 2 261 | — |
| router | **16/26** | **15/26** | 9 | **13.4 s** | 3 748 | 17 ms (query embed 16 ms) |

The baseline's real failure is the budget, not latency: in selection order only Notes (744) fits
before Calendar (5 367) breaks the 5 000-token budget, so tasks, files, mail, contacts, deck, talk,
cookbook and news never reach the model. The router narrows to three boxes and gets files, mail,
contacts and cookbook through. Still failing in both: tasks, deck, talk and news (the needed box was
ranked below the top-3 or its box alone exceeds what fits after a larger box). Input tokens rise
because the narrowed set now includes the useful schemas.

Decision: the gate holds (completion well above baseline, latency better). **Enable
`features.toolRouter` only together with a CPU embedder and `EMBEDDING_BASE_URL`** (branch, not yet
deployed); on 127b300 every routed message would evict the chat model under `--models-max 1`.
Follow-ups: rank-then-fit (take boxes by score until the budget, instead of top-3 then budget), and
check the four boxes that still miss.
