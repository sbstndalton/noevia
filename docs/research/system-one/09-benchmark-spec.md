# 9. Benchmark specification (draft for review)

Measures final-task quality, decision quality, system cost and complexity, on noevia's own kinds
of work, under the user's standing constraints:
- no real Diary data;
- no paid credits without approval;
- live-model benchmarking only in a maintenance window the user starts (D2).

## 9.1 Where it runs

- **Development (default):** llama.cpp built natively on the developer's machine (Metal on Apple
  Silicon, CPU elsewhere), with the same GGUF files.
  - Portable by design, and never touches production.
  - The harness takes an engine URL, so the same suite runs anywhere.
- **Reference deployment:** only inside a user-started maintenance window. Results are keyed by
  capability profile (doc 5 §5.6), so numbers from different machines are never mixed.

## 9.2 Corpus (target 150 tasks, then 200)

| Family | n | Source | Automatic grading |
|---|---|---|---|
| Normal chat (facts, how-to, small talk) | 15 | written for the suite | rubric + local judge, 20% human spot-check |
| Project questions over files | 20 | synthetic projects (reuse `qa/` fixtures, public docs, a synthetic tax-like PDF set) | gold answer spans; citation check |
| RAG needle / multi-hop / "not in the sources" | 25 | same corpora; 5 deliberately unanswerable | exact span; abstention scored |
| Coding (write / fix) | 15 | `scratch`-style fixture repos with tests | **unit tests pass** |
| Repository analysis / debugging | 10 | fixture repos with a planted bug | test passes + root cause named |
| Tool use (read, search, calendar-like, file) | 20 | synthetic MCP tools (`experiments/tool-routing` harness) | correct tool, valid args, final answer exact |
| Research (bounded, offline) | 10 | Kiwix-only questions (no paid search) | gold facts present, sources cited |
| Multi-step agent tasks | 10 | combinations of the above | end state checked |
| Context-heavy (long chat, compaction) | 10 | scripted 40–80-turn conversations | a late question needs an early fact |
| Ambiguous requests | 5 | written | correct behaviour = ask a clarifying question |
| Known local failure cases | 10 | harvested from earlier noevia runs (the classifier truncation, the 0/18 architect prompts, tool loops) | as the family |

- **Decision-level labels** are collected alongside: for every task, the gold model role per
  phase, the gold tools, the gold relevant passages and the gold evaluator verdict for a set of
  planted good and bad drafts. These become the labelled set for calibration (doc 4 §4.7) and,
  later, for fine-tuning Laya/Kev-class models.
- **Real usage:** the corpus is *modelled on* real noevia use. Nothing is copied from the user's
  chats without an explicit, per-item opt-in export. Diary content is never used.
- Hidden split: 30% of the tasks are held out and never used for tuning thresholds or prompts.

## 9.3 Configurations

| Id | Description |
|---|---|
| **A** | current noevia (production orchestration, as deployed) |
| **B** | local System Two only: one model, all tools offered, no routing, plain top-k RAG |
| **C** | local System One + local System Two (all decision purposes on local backends) |
| **D** | C + remote escalation (metered, only after local attempts; **needs user approval of spend**) |
| **E** | C with Jev as the decision backend (**needs approval**; cost ≈ $0.04 per 1,000 decisions [B]) |
| **F** | frontier-heavy reference (quality ceiling; **needs approval**) |
| **G** | *choose once*: System One picks the best single local model at the start, no switching |
| **H** | *adaptive*: G + mid-task re-evaluation and switching (doc 12), with the capability database |
| H−db | H using public priors only (isolates the capability database's contribution, H4) |

Each decision purpose is also ablated alone (C with only rerank on, only tool selection on, and so
on) to attribute gains.

## 9.4 Metrics

**Quality (per task):** correctness, completeness, evidence fidelity, tool correctness,
instruction following, relevance, hallucination (unsupported claims), task completion, and whether
a user correction was needed (scripted follow-up).

**Decision:**
- top-1 / top-k accuracy against the labels;
- Brier, ECE (10 bins) and reliability diagram per purpose;
- false positives and false negatives (especially evaluator false-PASS and false-FAIL);
- abstention rate;
- p50 / p95 latency;
- RAM, VRAM and CPU use;
- startup time.

**System (per 100 tasks):**
- successful tasks;
- fully local tasks;
- metered escalations (and subscription escalations, in Code mode);
- local generations;
- tool failures;
- retries;
- average agent steps;
- average and p95 end-to-end latency;
- **model swaps, swap time, context-restoration time, KV-restore versus prefill time**;
- preload hit rate;
- API cost;
- **cost per successful task**;
- **large-model occupancy**: seconds the largest model was hot, per task.

**RAG-specific:**
- recall@k of gold passages before and after rerank;
- prompt tokens spent on context;
- answer factuality;
- performance of the *small* model with reranked context versus the large model with plain
  context (the "better context makes small models good" hypothesis).

**Complexity:** doc 10's counts before and after, for each purpose that is switched over.

## 9.5 Failure injection (all must degrade gracefully)

The following are injected by the harness:

- wrong confident route and wrong confident tool (a forced decision);
- a useful passage rejected, or an irrelevant one ranked first (a forced rerank);
- a bad draft passed, or a good draft failed (forced evaluator);
- a retry loop (the evaluator always says RETRY);
- an unnecessary cloud escalation attempt with the policy closed;
- an unnecessary unload;
- a checkpoint write failure;
- a crash between checkpoint and unload;
- a corrupted checkpoint tail;
- an incompatible KV file;
- the decision backend unavailable, or slow past its deadline;
- local inference unavailable;
- OAuth expired (OpenRouter key revoked);
- the remote provider unavailable.

Pass criterion: the task either completes, or ends with a correct, explicit message. It must never
hang, loop past the caps, lose the session, re-run a side-effecting tool, or spend money that
policy did not allow.

## 9.6 Statistics

- Paired comparisons on the same tasks, with 3 repeats for stochastic runs (temperature > 0).
- Report success-rate differences with a 95% bootstrap interval, and latency medians with an
  interval.
- A difference is claimed only when the interval excludes zero.
- H3 (adaptive beats choose-once) is judged on success rate first, then on total time at equal
  success.

## 9.7 Artefacts

- `experiments/system-one/`: the runner, fixtures, labels, raw rows (JSONL) and a summary table
  per run, keyed by capability profile and configuration key.
- Results feed the capability database (doc 12), as `bench_results`, and the calibration fits
  (doc 4).
