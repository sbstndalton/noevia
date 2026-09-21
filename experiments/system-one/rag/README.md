# RAG rerank prototype

First prototype of the local-first System-One design ([docs/research/system-one](../../../docs/research/system-one/README.md) §5):
does a local reranker, placed between today's embedding retrieval and the chat model, improve
answers, and in particular answers from *small* local models?

## What it compares

| Mode | Excerpts sent to the model |
|---|---|
| `baseline` | production today (`rag.cjs`): cosine top 6, score ≥ 0.3 |
| `rerank6` | cosine top 24 → Qwen3-Reranker-0.6B (llama.cpp `/v1/rerank`) → top 6 |
| `rerank3` | the same, top 3: less context, if it is the right context |

Everything else is held fixed: production's chunker (`rag.chunkText`), production's prompt shape
(manifest, coverage note, `[from file]` excerpts), temperature 0, thinking off. Reranking goes
through the decision layer (`apps/web/server/decision/`), so a reranker failure falls back to the
cosine order, exactly as it would in production.

## Corpus

`corpus.cjs` builds four synthetic documents (124 chunks) and 44 tasks. The documents are dense
with near-identical records, which is the case bi-encoders get wrong:
- 7 years of four vendors' bills;
- 40 homelab hosts;
- 60 weekly meeting notes;
- 120 appliance error codes.

Task families:
- needle (24);
- project (10);
- multi-hop (4);
- unanswerable (6), where the right answer is "not found".

Grading: the gold values must all appear in the answer; unanswerable tasks must refuse. Evidence
recall checks that the chunk holding the fact was among those sent. It is seeded, and contains no
real data.

## Run

```bash
experiments/system-one/rag/serve.sh gemma-4-E2B_q4_0-it.gguf
CHAT_MODEL=gemma-4-E2B node experiments/system-one/rag/run.cjs
pkill -f 'llama-server.*1808[123]'
```

Results land in `results/` (JSONL rows plus a Markdown summary per run).

## Results so far (2026-09-21)

**Gemma-4-E2B (fast model), Apple M2 16 GB, full run, 44 tasks × 4 modes** (`results/2026-09-21T19-30-37-530Z-gemma-4-E2B.md`):

| Mode | Correct | Evidence recall | Median prompt tokens | Median rerank |
|---|---|---|---|---|
| baseline (production) | 80% (35/44) | 84% | 2,185 | — |
| rerank6 (24 → 6) | 86% (38/44) | 95% | 2,404 | 8.4 s |
| rerank3 (24 → 3) | **91% (40/44)** | 92% | **1,278** | 11.4 s |
| rerank6p12 (12 → 6) | 89% (39/44) | 89% | 2,402 | 4.1 s |

Caveats and findings:
- Two of the four multi-hop tasks were ambiguous in this run (a budget figure appeared in two
  weeks). The corpus is fixed (unique figures, all other records identical), but multi-hop has not
  been rerun.
- When cosine ranks the gold chunk outside the pool (rank 29 > 24), reranking cannot recover it.
- Reranking can **demote** a gold chunk when the question hinges on an exact number (`mtg-m2`).
- On an unanswerable question (`E177`), reranking surfaced the near-miss E17/E117 entries, and the
  model then invented an answer. rerank3 refused `fin-u1` correctly where baseline and rerank6
  hallucinated.
- Latency: reranking 24 chunks (~12k tokens) runs at about 1,600 tok/s on the M2 (GPU, shared with
  chat). On **DaServer's CPU** it is **~21 s** (3 runs: 22.3, 21.4, 21.1 s; llama.cpp server image,
  `--device none`, `-t 8`). CPU placement is too slow for the chat path.

**Qwen3.5-4B Q8:** partial only (56/176 rows, all four modes 11/14 correct; recall 9/12 baseline
vs 11/12 reranked). Stopped: the 16 GB Mac was swapping (prefill ~3 tok/s), so timings are
invalid. The user decided the evidence is enough to adopt reranking.
