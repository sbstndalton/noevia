# Generic System-One pilot — results

Backends: B0, B1, gemma-4-E2B/compact. Split by template family; test = template t4 of each family.

## Accuracy by family (test split; 95% Wilson interval)

| family | n | B0 | B1 | gemma-4-E2B/compact |
|---|---|---|---|---|
| initial_selection | 24 | 50% (31%–69%) | 100% (86%–100%) | 100% (86%–100%) |
| keep_vs_switch | 24 | 67% (47%–82%) | 100% (86%–100%) | 67% (47%–82%) |
| general_vs_specialist | 24 | 42% (24%–61%) | 100% (86%–100%) | 75% (55%–88%) |
| retry_vs_retrieve | 24 | 54% (35%–72%) | 54% (35%–72%) | 79% (60%–91%) |
| finish_vs_incomplete | 24 | 46% (28%–65%) | 100% (86%–100%) | 75% (55%–88%) |
| insufficient_evidence | 24 | 38% (21%–57%) | 38% (21%–57%) | 63% (43%–79%) |
| unavailable_or_memory | 24 | 54% (35%–72%) | 100% (86%–100%) | 92% (74%–98%) |
| local_only | 24 | 0% (0%–14%) | 0% (0%–14%) | 29% (15%–49%) |
| misleading_tool_output | 24 | 0% (0%–14%) | 100% (86%–100%) | 0% (0%–14%) |
| **all** | | 39% (33%–46%) | 77% (71%–82%) | 64% (58%–70%) |

## Calibration and abstention (test; fitted on calibration only)

| backend | T | ECE raw | ECE calibrated | τ | coverage | selective acc | false acceptance | system acc (abstain → B0) |
|---|---|---|---|---|---|---|---|---|
| gemma-4-E2B/compact | 1.70 | 0.187 | 0.118 | 0.88 | 9% | 100% | 0% | 45% (38%–52%) |

## Cost of running it (measured)

| backend | model file | cold start | peak RSS | p50 / p95 per decision | prompt tokens (median) | decisions/s | truncated prompts | host |
|---|---|---|---|---|---|---|---|---|
| gemma-4-E2B/compact (GPU) | 3.12 GiB | 1.3 s | 3.85 GiB | 666 / 814 ms | 381 | 1.51 | 0 | Apple M2 · 16 GB; version: 0.4.1 (build 10964, commit b29c606e2) |

