# 3. System-One landscape (verified 2026-09-21)

"System One" in this sense is days old. TypeSafe launched **Jev** on 15 September 2026; within a
week there were a dozen open reproductions. Treat everything here as a snapshot that will age fast.

**Evidence labels:**
- **[P]** primary source: the repository, model card or vendor docs, read directly.
- **[V]** vendor claim, meaning the project's own number about itself.
- **[B]** independent benchmark: JevBench v1.2 ([repo](https://github.com/fstandhartinger/jevbench), [results](https://raw.githubusercontent.com/fstandhartinger/jevbench/main/RESULTS-v1.2.md), run by one operator, v1.2.3 cost-corrected 19 Sep 2026).
- **[C]** community or press claim, not verified.
- **[—]** unknown.

**None of the numbers below is a noevia measurement yet.**

## What they all are

A decision model takes a **state** (text, JSON) plus typed questions and returns a **probability
per allowed option** in one forward pass, without generating tokens. Three question types recur
across the ecosystem:

- `choice`: pick one from a list.
- `score`: an ordinal rating.
- `noul`: yes / no / unknown.

The technique that matters for noevia is **option-logit readout**: prefill the state and question,
then read the logits of the tokens that begin each allowed answer. This works on an ordinary
causal LM with no trained head (SemIf does it zero-shot on base weights [P]). It is therefore
available on any local GGUF model through llama.cpp's `logprobs` / `n_probs` output [P: llama.cpp
server README].

## JevBench v1.2 [B]

Composite score = geometric mean of Intelligence, Calibration, Speed and Cost, 25% each. 534
decisions across six task families: routing, adequacy judging, policy checks, intent, ordinal
scoring and extraction. Tiers: easy, standard, judge and hard.

| System | Open? | Score | Easy / Std / Judge / Hard | p50 raw | Ran on |
|---|---|---|---|---|---|
| Jev 1.13.0 | closed API | 75.4 | 100 / 99.0 / 94.5 / 74.1 | 0.65 s | vendor API |
| SemIf (Qwen3.5-4B) | MIT, zero-shot | 74.7 | 100 / 97.9 / 95.2 / 59.5 | 0.20 s | RunPod GPU |
| djev (DiffusionGemma) | Apache-2.0 | 74.3 | 100 / 97.9 / 93.2 / 69.5 | 0.24 s | vendor API |
| Qwen3-32B zero-shot ("jqv") | open | 70.1 | 100 / 95.8 / 92.5 / 64.5 | 0.75 s | H100 |
| Laya 421M | Apache-2.0 | 70.1 | 94.4 / 72.9 / 69.2 / 34.1 | 0.79 s | **CPU** |
| OpenDecision (ModernBERT-L) | open | 67.0 | 87.5 / 62.5 / 71.2 / 33.2 | 0.34 s | H100 |
| kev 0.6B | Apache-2.0 | 66.7 | 100 / 81.2 / 66.4 / 40.0 | 0.59 s | RTX 3090 |
| kev 4B | Apache-2.0 | 62.2 | 100 / 91.7 / 85.6 / 42.3 | 0.55 s | RTX 3090 |
| Bespoke Nimble 9B | open | 61.8 | 100 / 94.8 / 89.0 / 65.5 | 0.39 s | A40 |
| GPT-5.6 Luna (low) | API | 66.2 | 100 / 97.9 / 96.6 / 94.5 | 0.97 s | OpenAI API |
| DeepSeek V4.1 Flash | API | 57.8 | 98.6 / 99.0 / 93.2 / 95.0 | 1.42 s | DeepSeek API |
| GLiNER2 | open | 53.0 | 97.2 / 66.7 / 45.9 / 36.4 | 0.31 s | CPU |

How to read this for noevia:

- **Frontier APIs are the most accurate** on the hard tier (≈95%) but lose on speed and cost. The
  composite rewards cheapness, which is why a closed API does not top it.
- **Zero-shot logit readout on a 4B general model (SemIf) nearly matches Jev** on
  easy/standard/judge, and trails on hard (59.5 vs 74.1).
- **Encoder-sized models (Laya, OpenDecision) are much weaker** on hard decisions (≈34%). They are
  CPU-friendly, but they are bases to fine-tune, not drop-in engines.
- **Self-hosted latencies are doubled plus 0.15 s** by the benchmark "to approximate production
  load — an assumption, not a measurement" [B]. Raw numbers are on data-centre GPUs, not a laptop
  iGPU.

## Candidates in detail

### Jev (TypeSafe): reference, closed [P docs.typesafe.ai]
- API only: `POST https://api.typesafe.ai/v1/systemone`, model `jev-1.13.0`. State plus questions
  with optional instructions and criteria. Text only.
- Limits: 64k tokens per request, 32k for state plus the longest question. Rate limit 1,200
  requests/min.
- **Pricing: $0.042 per million input tokens, output free.** JevBench measures about **$0.04 per
  1,000 decisions** [B].
- No weights, no parameter count, no self-hosting [P]. "Not trained on customer requests"; zero
  data retention is enterprise-only [P].
- **Role for noevia:** a benchmark reference and an optional remote decision backend. It can never
  be the default, because it is network-dependent, sends state to a US vendor, and is
  single-vendor.

### SemIf (formerly OpenJev): the strongest open option on quality [P github.com/TheoLeeCJ/SemIf]
- MIT. Zero-shot option-logit readout. No trained head needed.
- Models: Qwen3-0.6B, MiniCPM5-2B, **Qwen3.5-4B**, Qwen3-Reranker-4B.
- Runtimes: PyTorch CUDA, MLX, MPS, and a **llama.cpp/GGUF build for the browser (WebGPU)**.
- Shared-state prefix reuse: prefill a long state once, branch across many questions.
- [V] on an RTX 3090: 21 criteria in 1.02 s median, versus 5.33 s for JSON generation. Qwen3.5-4B
  balanced accuracy 0.813; agreement with the TypeSafe subset 0.845 (Jev itself 0.883).
- **Why it matters most:** it shows that the technique, not a special model, carries most of the
  value. noevia can reproduce it on its existing llama.cpp engine with an already-downloaded model.

### djev (Maisa): diffusion-based [B; repos github.com/mmastrac/djev-spark, github.com/Davipar/djev-dev]
- DiffusionGemma denoising an answer canvas. Apache-2.0.
- Recipes target vLLM and a DGX Spark (NVFP4). [—] No llama.cpp path found.
- Strong on the benchmark (hard 69.5), but a heavy runtime dependency for a local-first app.

### Bespoke Nimble: fine-tuned 9B [P github.com/bespokelabsai/nimble]
- Qwen3.5-9B with LoRA r=16, about 18 GB unquantised. Logit readout over one token per option.
- Prompt limit **2,048 tokens**; enums and booleans only, up to 26 choices.
- Runtimes: MLX and CUDA. **No GGUF/llama.cpp** [P].
- [V] Latency: 106 ms on an H100, 444 ms on an M5 Pro. Agreement: 90.1% own holdout (base model
  66.4%, Jev 93.2%).
- Licence not stated in the README [P].
- Too big to sit permanently beside a System-Two model on modest hardware.

### Kev (Jared Palmer): small and permissive [P huggingface.co/jaredpalmer/kev-0.6b, github.com/jaredpalmer/kev]
- LoRA plus a pointer head on Qwen3 **0.6B / 4B / 8B** base. Apache-2.0 for both adapter and base.
- Block-causal mask: questions attend to the shared state but not to each other, so they are
  scored in parallel.
- [—] No GGUF; the pointer head needs its own runtime.
- [B] kev-0.6B scores 66.7; hard tier 40%.

### Laya (Convai): the CPU-resident candidate [P huggingface.co/convaiinnovations/laya]
- ModernBERT-large (395M) plus a 2-layer decision head, 421M total. Multilingual 322M
  (mmBERT-base). Apache-2.0.
- Input: 512 tokens for English, 1,024 for multilingual.
- [V] Latency: 33 ms on a T4 GPU, **193–464 ms on CPU**.
- **Zero-shot typed-decision accuracy 0.362**; 0.766 after fine-tuning.
- Over-confident until temperature-scaled: ECE 0.466 → 0.081.
- Accuracy collapses with many options (Banking77, 0.425).
- A community **Node.js / ONNX Runtime** wrapper exists ([receptron/laya](https://github.com/receptron/laya)). That fits noevia's Node server with no Python sidecar.
- **Role:** the only credible *permanently resident, CPU-only* decision model. It is weak
  zero-shot and needs fine-tuning on noevia's own decisions before it could be trusted.

### Cross-encoder rerankers (not "System One" by name, but the right tool for RAG) [P]
- **Qwen3-Reranker-0.6B / 4B** (Apache-2.0) run on llama.cpp's `/v1/rerank` with
  `--reranking --pooling rank`.
- Caveat: most community GGUFs produce near-zero scores. Use `ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF`
  or convert with the official `convert_hf_to_gguf.py`.
- These are purpose-trained query–passage scorers, and the obvious first backend for use case B.

### Named but not verified
- **NanoJev, mini-jev:** appear only in secondary articles, not in JevBench. Not assessed [C].
- **"Laya 33 ms beats Jev":** the GPU single-question figure versus Jev's network round-trip.
  Not like for like [C].

## Candidate matrix

| | Params | Licence | Offline | CPU-viable | llama.cpp | Context | Zero-shot usable | Calibrated | Maturity |
|---|---|---|---|---|---|---|---|---|---|
| Logit readout on the resident System-Two (SemIf technique) | whatever is loaded | model's | yes | as the model | **yes (`logprobs`)** | model's | yes (4B ≈ SemIf) | needs temperature fit | the technique is proven [P]; our code not written |
| Small dedicated logit model (e.g. Qwen3-0.6B/1.7B GGUF) | 0.6–2B | Apache-2.0 | yes | yes, slow | **yes** | 32k | weaker than 4B [B: kev-0.6B 66.7] | needs fit | [—] |
| Qwen3-Reranker-0.6B (RAG only) | 0.6B | Apache-2.0 | yes | yes | **yes (`/v1/rerank`)** | 32k | yes, for relevance | scores, not probabilities | mature |
| Laya | 421M | Apache-2.0 | yes | **yes (193–464 ms)** | no (ONNX) | 512 / 1k | **no (0.362)** | after temperature fit | 1 week old |
| Kev 0.6B | 0.6B | Apache-2.0 | yes | [—] | no | [—] | partly | [B] 51 | 1 week old |
| SemIf (as a Python sidecar) | 4B | MIT | yes | slow | browser GGUF only | model's | yes | [B] 72.6 | 1 week old |
| Nimble | 9B | [—] | yes | no | no | 2k | yes | [B] 65.3 | 1 week old |
| djev | [—] | Apache-2.0 | yes | no | no | [—] | yes | [B] 65.4 | 1 week old |
| Jev | [—] | closed | **no** | n/a | n/a | 64k | yes | [B] 82.7 | vendor-backed |

## Conclusion (for review)

1. **The strongest local option today is not a new model; it is a technique.** Option-logit
   readout, run through the llama.cpp engine noevia already operates, on a model noevia already
   has. SemIf's numbers [V, B] suggest a 4B model gets most of Jev's quality on everyday
   decisions. That is exactly the size noevia already runs as its fast model.
2. **For RAG, a purpose-built reranker beats a general decision model.** Qwen3-Reranker on
   `/v1/rerank` needs no new runtime.
3. **Laya is the only realistic "always resident on CPU" model**, and it needs fine-tuning.
   Revisit once noevia has a labelled set of its own decisions: the benchmark corpus in doc 9
   produces exactly that set.
4. **Jev is a yardstick and an opt-in fallback, never a dependency.**
5. Everything in this ecosystem is under a week old. Pin versions, keep the interface generic,
   and expect to swap backends.
