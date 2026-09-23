# Scripted contract results

Run on 2026-09-23 with Node v26.8.2. No live model, MCP candidate or skill script was called. All three modes used the same 16 snapshots, repeated three times: 144 records.

Fixture set SHA-256: `9b0a7e8598da23d33689304f0af444c219109e11c46bc716472a3cd17e2daa06`.

| Mode | Runs | Mean schema bytes | Mean estimated schema tokens | Mean body bytes | Forbidden schema exposures |
| --- | ---: | ---: | ---: | ---: | ---: |
| baseline | 48 | 676.50 | 429.88 | 0.00 | 0 |
| embedding | 48 | 436.75 | 362.44 | 29.19 | 0 |
| decision | 48 | 516.00 | 384.75 | 29.19 | 0 |

These costs describe deliberately small synthetic schemas under the common experimental loader. Decision answers are scripted, including rejected answers; the embedding vectors are keyword stubs. The apparent cost differences do not demonstrate model accuracy, instruction adherence, task completion, total-token savings or production latency. Harness latency is recorded per run but is not a useful model-performance metric.

Live model quality, actual token use and end-to-end completion are **unmeasured**. Unauthorized actions are **not measured by the selection runner**, which executes none. The separate execution contract tests count synthetic calls and verify approval/denial/block/cancellation boundaries. Production adoption remains **deferred**.

Reproduce with the commands in [README](README.md). Full JSONL is generated locally rather than committing repetitive run records. The fixture split is a protocol scaffold, not an unseen model benchmark.

Verification: 43 offline contract/execution tests pass; the existing application suite passes 1,247/1,247; `npm run typecheck` and `npm run build` pass. No UI or production module changed. Independent review found and fixed eligibility leakage in the embedding proposal and raw catalogue identifiers in telemetry, plus a missing dependency check in the exposure metric. Each has a regression test.
