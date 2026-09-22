# noevia local-first System-One architecture — research and design

Status: **research complete, waiting for architectural review.** No production code has changed
for this work. Written 2026-09-21 from the source at `860316b` plus primary-source web research.
**No benchmark has been run yet**, so every quality claim below is a hypothesis with a plan to test
it (doc 9).

Current implementation follow-up: [adapter cutoff and conditional bounds](14-adapter-cutoff-and-bounds.md)
(local source verified; not deployed). Historical research status below predates implementation.

Current durability follow-up: [first internal durable-chat slice](15-durable-chat-slice.md)
(disabled by default; synthetic verification only).

Current experimental UI follow-up: [opt-in routing switch](16-experimental-routing.md)
(local source only; baseline, not a selected dedicated System-One model).

Current supervision follow-up: [provider-neutral step supervision](17-step-supervision.md)
(disabled; injected mocked providers only).

Current setup follow-up: [shared decision-service configuration](18-decision-service-settings.md)
(Laya routing and supervision share an editable endpoint).

## Deliverables

| # | Document |
|---|---|
| 1 | [Current noevia architecture map](01-architecture-map.md), including the target architecture |
| 2 | [Fuzzy-orchestration audit](02-fuzzy-orchestration-audit.md) |
| 3 | [System-One landscape](03-system-one-landscape.md) |
| 4 | [Decision-provider API specification](04-decision-provider-api.md) |
| 5 | [Local model residency specification](05-model-residency.md) |
| 6 | [Session checkpoint / resume specification](06-session-checkpoint.md) |
| 7 | [Provider / authentication architecture](07-provider-auth-architecture.md) |
| 8 | [OAuth / subscription support matrix](08-oauth-subscription-matrix.md) |
| 9 | [Benchmark specification](09-benchmark-spec.md) |
| 10 | [Complexity-reduction analysis](10-complexity-reduction.md) |
| 11–12 | [Migration and rollback plans](11-migration-and-rollback.md) |
| 13 | Recommended first prototype: §5 below |
| + | [Adaptive capability profiling and mid-task model switching](12-adaptive-model-switching.md) |
| + | [Model classes, and choosing the generic System-One model](13-model-classes-and-system-one-candidates.md) (correction, 2026-09-21) |

**Terminology (doc 13 §13.1), used throughout:**
- **A. Specialised discriminative model:** one narrow task, e.g. `Qwen3-Reranker` for RAG ranking (live since `67f336e`).
- **B. Generic System-One decision model:** bounded orchestration decisions through `decide()`. Candidates: Laya, SemIf-style option-logit readout, Jev (reference); floor: heuristics. **Unresolved.**
- **C. System-Two generative model:** Qwen, Gemma, gpt-oss.

The live reranker is a class-A component. It is not the generic System One, and its gains say nothing about class B.

## 1. Executive summary

1. **The best local System One today is a technique, not a product.** Reading option logits from
   an ordinary local model gets close to Jev on everyday decisions. The independent JevBench
   results show SemIf, zero-shot Qwen3.5-4B, at 74.7 against Jev at 75.4; the gap is on the hard
   tier. noevia can do this on the llama.cpp engine it already runs (`logprobs`), with a model it
   already has. For RAG, a purpose-built reranker (Qwen3-Reranker on llama.cpp's `/v1/rerank`)
   fits better still.
2. **noevia's fuzzy orchestration is small.** It is about 300 replaceable lines, 3 classifier
   prompts and about 12 hand-set thresholds, already injected and fail-open. The case for System
   One is **quality and uniformity**, not deleting large amounts of code; line count will rise.
   The real simplification: one decision mechanism replaces five styles, and new decisions become
   one-line wrappers.
3. **Subscriptions cannot legitimately power noevia's chat.**
   - Anthropic and Google forbid reusing subscription OAuth in third-party software.
   - OpenAI documents ChatGPT sign-in as being for Codex clients only.
   - DeepSeek has no subscription.
   - Z.ai and Alibaba plan keys are limited to listed interactive tools.

   The only legitimate subscription route is **Code mode running the vendor's unmodified CLI**,
   with the user signing in through the vendor's own flow. Chat escalation beyond local is
   metered.
4. **Session durability is the missing foundation.** Code tasks and research runs already survive
   a model or process death through `jobs.cjs`. Chat turns do not. Every model-swapping idea,
   including co-residency swaps and mid-task switching, depends on fixing that first. It is also
   worth doing on its own.
5. **Adaptive mid-task switching is designable today on noevia-owned state.** It uses safe
   boundaries, a handover note built from structured state, an empirical capability database keyed
   by exact model and runtime configuration, and a deterministic manager with hysteresis and a
   switch budget. Whether it beats choosing once is unknown. The prior expectation is: yes for
   long multi-phase tasks on hardware that holds two models, no for short chats. The design
   therefore falls back to choose-once whenever swapping costs more than it saves.

## 2. Answers to the critical questions

| # | Question | Answer now | Confidence / how it gets settled |
|---|---|---|---|
| 1 | What could a decision model replace? | Model-role routing (D1), toolbox narrowing (D2), skill loading (D3), the RAG cut-off (D4), the file-name tool cap (D5), the Diary skip classifier (D11); plus new decisions: output evaluation, loop control, context utility, residency, mid-task switching | High (from the code, doc 2) |
| 2 | What stays deterministic? | Auth, tenancy, tool policy and the three approval actions, Code-mode action classes, egress/SSRF/filesystem, budgets and caps, context-fit arithmetic, schema validation, cloud policy, secrets | High |
| 3 | Strongest local System One? | *Corrected in doc 13.*

- **RAG ranking (class A):** Qwen3-Reranker, measured and live.
- **Generic decisions (class B):** unresolved. The candidates are compared on quality **and** residency.
  - A 4B option-logit model is one candidate, not the answer.
  - Laya (421M, fine-tuned) is the leading always-resident prior. | Medium (independent benchmark + vendor numbers; not yet measured here) |
| 4 | Can it stay resident beside System Two? | On DaServer, CPU and iGPU share one 29 GB pool, and llama.cpp is capped at 14 GB. A dedicated 4B cannot stay beside gpt-oss-20B. Laya (≈0.5–2 GB, in process) or a 0.6–1.7B CPU logit model can (doc 13 §13.4) | Medium; doc 5 §5.8 |
| 5 | Does it improve task quality? | Unknown | Configurations C vs A/B (doc 9) |
| 6 | How much does RAG improve? | Unknown; reranking reliably helps in the literature and the current pipeline has no rerank stage at all | First prototype measures it |
| 7 | How much does tool reliability improve? | Unknown; the existing embedding router already cut input tokens 23% with no loss (14/14 vs 14/14, `experiments/tool-routing`) | Doc 9 tool family |
| 8 | Can output evaluation safely control retries? | Only with calibrated confidence, a hard retry cap, and "ask the user" or "best answer + notice" as the terminal state; unsafe before calibration | Evaluator false-PASS/false-FAIL rates |
| 9 | How much code disappears? | About 155 lines, 3 prompts, 12 thresholds, 8 regexes; net lines rise; the win is structural | High (doc 10) |
| 10 | What % of work stays local? | Unknown; target ≥ 95% of ordinary requests | Doc 9 "fully local / 100" |
| 11 | When does remote help? | Hard-tier reasoning and decisions (frontier ≈ 95% vs ≈ 60–75% local on JevBench hard), missing capabilities, very long context | Configuration D vs C |
| 12 | Can System Two die without losing the session? | Not today for chat. Yes after doc 6 (M4) | Failure-injection suite |
| 13 | Cold reload / resume latency? | Unmeasured; it will be load time plus rebuilt-context prefill | Doc 5 §5.8 |
| 14 | Is KV restoration practical? | llama.cpp supports slot save/restore; compatibility is strict (doc 6 §6.6); router-mode behaviour unverified | Measure; optimisation only |
| 15 | Which providers support useful OAuth? | OpenRouter (PKCE, metered); Google Gemini API (the user's own Cloud project) | High (primary docs) |
| 16 | Which subscriptions include third-party inference? | None, for third-party *apps*. Claude and ChatGPT subscriptions work only inside their own clients, which noevia can host unmodified in Code mode | High (primary docs) |
| 17 | Can subscriptions reduce metered spend? | Yes for **Code mode** via vendor CLIs; not for chat | High |
| 18 | Behaviour at subscription limits? | Show it, then offer the next tier that policy allows; never a silent switch to metered | Design (doc 7 §7.4) |
| 19 | When is paying for Jev justified? | As a benchmark reference, and possibly as an opt-in remote decision backend for the hard-tier decisions local models get wrong, if doc 9 shows a gain worth $0.04 per 1,000 decisions and the state may leave the machine | Configuration E (needs approval) |
| 20 | Can every remote provider vanish without breaking core functions? | Yes by design: the decision floor is the heuristic and the generation floor is local (doc 7 §7.6). True of today's noevia too, apart from web search and optional connectors | High |
| 21 | **Can noevia switch among local models mid-task, using System One and a capability database, for higher quality with the smallest suitable model per phase?** | Architecturally yes (docs 5, 6, 12); empirically unknown | Configurations H vs G |
| 22 | **Does adaptive switching beat choosing once at the start?** | Unknown. Expected: yes on long multi-phase tasks where two models fit; no on short chats or single-slot hardware. The design falls back to choose-once when a swap will not pay | H3 in doc 12 §12.9 |

### Added 2026-09-21 (doc 13)

| # | Question | Answer now | How it gets settled |
|---|---|---|---|
| 23 | One generic System-One model for all bounded decisions, or a hybrid (specialised discriminative models for narrow tasks such as RAG reranking, plus a tiny generic decision model for orchestration)? | Hybrid, unless one class-B backend matches the reranker **on the RAG set** at lower total residency | Doc 13 §13.5, including the RAG suite run through the winning class-B backend |
| 24 | Is the 4B option-logit approach better at system level once residency pressure and swap costs are counted? | Probably not as a *dedicated* model on DaServer; possibly yes as readout on the *already-loaded* System Two | Doc 13 §13.5 system-level run: Q4 and S2L vs Laya L1/L2 and Q06/Q17 |

## 3. Prototype order, and one change to it

Your order was:
1. model routing
2. RAG reranking
3. tool selection
4. output evaluation
5. loop control
6. context utility
7. lifecycle
8. escalation

**I recommend swapping 1 and 2**, and adding one foundation step in parallel:

- **RAG reranking first:**
  - **Quality lever:** it tests the central hypothesis that better context makes small local
    models much better, on the path every project question takes.
  - **Nothing to replace:** the pipeline has no rerank stage today (cosine top-6 ≥ 0.3), so
    there is nothing to regress against except "no rerank".
  - **Mature backend:** Qwen3-Reranker, Apache-2.0, on llama.cpp `/v1/rerank`. No new runtime,
    and no dependency on a week-old project.
  - **No residency question:** reranking works with one generation model, so it doesn't depend
    on the one-model-or-two question you've asked me to leave open.
  - **Fully offline to measure:** needs no maintenance window, no live data and no credits.
- **Model routing second:**
  - Today's router only runs for projects set to `routing: 'auto'`.
  - It needs two or more generation models to matter, so it depends on the residency and
    one-vs-two question you deferred.
  - It gets a shadow-mode rollout on the new `llama-logit` backend.
- **In parallel: session durability (doc 6, M4).** It's independent of every System-One result,
  valuable on its own, and the prerequisite for any swapping, including mid-task switching.

## 4. What could eventually be deleted or simplified

If each purpose wins its benchmark (doc 10):
- `auto-router.cjs` heuristics, both classifier prompts, verdict parsing and the retry path;
- the cosine, threshold and margin code in `chat-skill-routing.cjs`;
- the ranking half of `chat-tool-routing.cjs`/`tool-router.cjs`;
- `toolCapFor`'s file-name parse;
- the fixed RAG cut-off;
- later, the Diary skip classifier.

Every one stays as the fallback until two clean releases after its replacement goes live.

## 5. Recommended first prototype (smallest useful)

**"Decision layer v0 + RAG rerank", offline.**

1. `apps/web/server/decision/`:
   - `decide()` with output validation, deadline, fallback and logging;
   - a `heuristic` backend that wraps today's code unchanged;
   - an `llama-rerank` backend.

   About 250 lines plus tests. No call site changes behaviour.
2. `experiments/system-one/rag/`:
   - 45 RAG tasks (doc 9 families: project questions, needle, multi-hop, unanswerable) over
     synthetic corpora;
   - compared: today's pipeline (top-6 cosine) against retrieve-24 → rerank → top-n, on the
     **fast** model and the **smart** model;
   - measures: recall@k, answer factuality (gold spans), hallucination on the unanswerable set,
     prompt tokens, and added latency.
3. Runs on a developer machine with native llama.cpp: no production engine, no maintenance
   window, no credits, no Diary.
4. **Deliverable:**
   - a results table;
   - a go/no-go for wiring rerank into `rag.filesContext` behind a flag;
   - the first labelled data for calibrating the decision layer.

Stop point: after (4), for your review, before any production wiring.

## 6. Constraints honoured

- No production changes.
- No Diary data.
- No paid credits.
- No live-model benchmarking.
- Claude Code/Codex harness work not started.
- WebDAV sharing untouched.
- Residency and the one-vs-two question left open (now part of docs 5 and 12).
- Ornith and repository access untouched.

## Sources (primary unless marked)

- JevBench v1.2 (independent): https://github.com/fstandhartinger/jevbench and https://raw.githubusercontent.com/fstandhartinger/jevbench/main/RESULTS-v1.2.md
- TypeSafe Jev docs: https://docs.typesafe.ai/models
- SemIf: https://github.com/TheoLeeCJ/SemIf
- Bespoke Nimble: https://github.com/bespokelabsai/nimble
- Kev: https://github.com/jaredpalmer/kev and https://huggingface.co/jaredpalmer/kev-0.6b
- Laya: https://huggingface.co/convaiinnovations/laya ; Node/ONNX wrapper https://github.com/receptron/laya
- djev: https://github.com/mmastrac/djev-spark , https://github.com/Davipar/djev-dev
- llama.cpp server (logprobs, rerank, slots, sleep, router): https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- Qwen3-Reranker GGUF: https://huggingface.co/ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF
- Anthropic credential policy: https://code.claude.com/docs/en/legal-and-compliance
- OpenAI Codex auth: https://learn.chatgpt.com/docs/auth ; Codex for OSS: https://developers.openai.com/community/codex-for-oss
- Gemini API OAuth: https://ai.google.dev/gemini-api/docs/oauth ; Gemini CLI terms: https://geminicli.com/docs/resources/tos-privacy/
- Z.ai Coding Plan: https://docs.z.ai/devpack/quick-start
- Alibaba Coding Plan: https://www.alibabacloud.com/help/en/model-studio/coding-plan
- DeepSeek API: https://api-docs.deepseek.com/
- OpenRouter OAuth PKCE: https://openrouter.ai/docs/guides/overview/auth/oauth
- Secondary, used only where marked [C]: Qwen OAuth discontinuation (https://github.com/QwenLM/qwen-code/issues/3316), Anthropic enforcement dates (press).
