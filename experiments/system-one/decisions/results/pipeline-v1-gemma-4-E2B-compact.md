# Policy-wrapped pipeline (saved run, no inference)

Run: gemma-4-E2B/compact. Temperature 1.70 and abstention threshold 0.88 fitted on calibration only. Test split, 24 per family.

| family | raw correct | invalid | policy rejected | abstained | final (fallback B0) | final (fallback B1) | B0 alone | B1 alone |
|---|---|---|---|---|---|---|---|---|
| initial_selection | 100% | not measured (v1) | 0 | 24 | 50% | 100% | 50% | 100% |
| keep_vs_switch | 67% | not measured (v1) | 0 | 18 | 67% | 100% | 67% | 100% |
| general_vs_specialist | 75% | not measured (v1) | 0 | 11 | 96% | 100% | 42% | 100% |
| retry_vs_retrieve | 79% | not measured (v1) | 0 | 24 | 54% | 54% | 54% | 54% |
| finish_vs_incomplete | 75% | not measured (v1) | 6 | 18 | 100% | 100% | 46% | 100% |
| insufficient_evidence | 63% | not measured (v1) | 0 | 24 | 38% | 38% | 38% | 38% |
| unavailable_or_memory | 92% | not measured (v1) | 0 | 24 | 54% | 100% | 54% | 100% |
| local_only | 29% | not measured (v1) | 0 | 24 | 0% | 0% | 0% | 0% |
| misleading_tool_output | 0% | not measured (v1) | 24 | 0 | 100% | 100% | 0% | 100% |
| **all** | 64% | — | 30 | 167 | 62% | 77% | 39% | 77% |

