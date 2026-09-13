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
