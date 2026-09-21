# Saved results

| File | Readout contract | Notes |
|---|---|---|
| `2026-09-21T22-12-41-585Z-baselines-baselines.jsonl` | n/a | B0/B1 on calibration + test |
| `2026-09-21T22-13-16-284Z-gemma-4-E2B-compact.jsonl` | **v1** (top-50 next-token log-probs; a missing option label got an invented floor of min−2; `lettersSeen` counted any capital letter) | Kept unchanged. Its probabilities are not a verified option distribution; see doc 13 §13.10 |
| `summary.md` | v1 | analyze.cjs output over the two files above |
| `pipeline-v1-gemma-4-E2B-compact.md` | v1 | pipeline.cjs (policy gate, abstention, fallbacks), computed from the saved v1 run; no inference |

Runs stopped by the user before finishing (no files): Gemma-4-E2B full-state, Qwen3.5-4B compact, Gemma-4-E2B CPU.
