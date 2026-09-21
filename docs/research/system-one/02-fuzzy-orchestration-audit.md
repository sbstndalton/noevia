# 2. Fuzzy-orchestration audit

Every place where noevia's code makes a *judgement* — a guess about intent, relevance, difficulty
or quality — as opposed to enforcing a rule. Counts are from the source on 2026-09-21
(non-comment lines; `if (` occurrences; numeric `const` thresholds).

## The inventory

| # | Decision | Where | Mechanism today | Size | Failure mode | Replaceable by System One? |
|---|---|---|---|---|---|---|
| D1 | **Model role** (fast / smart / code) | `auto-router.cjs` | 7 regex/length heuristics, then a **generative** classifier call to the fast model (up to 512 tokens, parse FAST/SMART/CODE from text or reasoning), fail-open to fast | 94 lines, 16 ifs, 2 prompts | Parsing a generated word; thinking models restate the prompt's own labels; measured 12–31 s on an iGPU before the no-thinking hint | **Yes — the clearest case.** One `choice` decision over the allowed roles |
| D2 | **Toolbox narrowing** | `chat-tool-routing.cjs` + `tool-router.cjs` | Embedding cosine, top-3, threshold **0.35**, only narrows the user's selection | 109 lines, 12 ifs, 2 thresholds | Cosine between a message and a box description is a weak proxy for "will need this tool"; threshold hand-picked | **Yes** — `rank`/multi-select over the already-allowed boxes |
| D3 | **Skill loading** | `chat-skill-routing.cjs` | Embedding cosine, threshold **0.5**, margin **0.03**, max 1 skill | 48 lines, 4 ifs, 3 consts | Same proxy problem; margin tuned by hand | **Yes** — `choice` over skills + "none" |
| D4 | **RAG relevance** | `rag.cjs` `searchProject` | Cosine top-**6**, floor **0.3**; small files (≤2,400 chars) always injected | inside 263 lines, 5 consts | No reranking: bi-encoder similarity only; fixed k regardless of question | **Yes** — rerank a larger candidate set (cross-encoder or decision model) |
| D5 | **Tool count cap** | `toolboxes.cjs` `toolCapFor` | Regex the parameter count out of the **model's file name** (`≤12B` → 12 tools) | ~10 lines, 2 consts | Wrong for any model whose name lacks `NB`; a proxy for "can this model handle many choices" | Partly — becomes unnecessary if D2 hands the model 1–3 boxes; keep a hard ceiling as policy |
| D6 | **Tool token budget** | `toolboxes.cjs` + `prefill.cjs` | 5,000 / 8,000 tokens, adjusted by measured prefill rate towards a 14 s target | ~60 lines, 4+3 consts | Latency heuristic; sound, measured | **No** — keep; it is a measured resource limit, not a judgement |
| D7 | **Compaction trigger and cut** | `chat-context.cjs` `prepareUnlocked` | Over `limit − reserve(≤4,096 or 25%) − safety(15%)`; keep last 2 exchanges; summary allowance ≤1,800 or 20%; batch budget 45% | 116 lines, 29 ifs | Keeps recency, not importance; resolved threads are summarised as carefully as live ones | **Partly** — utility scoring (KEEP / DROP / RESOLVED / SUMMARIZE) before summarising; the fit arithmetic stays |
| D8 | **Tool-result shaping** | `tool-result-reduce.cjs` | Structural reduction of JSON listings to fit 8,000 chars (300-char values, ≥2 rows) | 125 lines, 19 ifs, 3 consts | Keeps shape, not relevance to the question | Partly — select relevant rows (rank) before structural reduction |
| D9 | **Loop continuation** | `chat.cjs` | Hard stop at **3** tool rounds; no judgement of whether the task is done | a few lines | Small models either stop early or wander until the cap | **Yes, as advice only** — continue / finish / ask_user among allowed next steps; the cap stays |
| D10 | **Output adequacy** | nowhere | — | — | A bad local answer is shown as-is; no retry, no stronger model | **New capability** — evaluate → pass / retry / stronger local / ask |
| D11 | **Diary skip** | `services/diary/agent/pipeline.py` `classify` | Generative LOG/SKIP on the aux model, first-token parse, fail-open to LOG | ~20 lines + prompt template | Same generate-then-parse pattern as D1 | **Yes** — a `noul`/boolean decision. (Diary is live; do not touch without a decision.) |
| D12 | **Research stopping** | `research-runner.cjs` | Fixed budgets: web calls, deadline, sources per sub-question | 93 lines, 15 ifs | Stops on budget, never on "enough evidence" | **Yes, as advice** — "enough / search more" within the budget |
| D13 | **Architect prompt preparation** | `code-service.cjs` `PROMPT_PREPARATION` | Not offered (0/18 usable prompts from the local architect) | — | — | Out of scope for System One (it is generation) |

## What is deterministic and must stay so

These are rules, not judgements, and remain application code whatever the benchmark says:

- **Authentication and tenancy**: `auth.cjs`, sessions, CSRF, per-user workspaces.
- **Tool authority**: `toolPolicy` (Allow/Ask/Block), `isWriteTool`, the three approval actions,
  per-chat `approve_all`, and the absence of any global "never ask".
- **Code-mode action classes** (`code-actions.cjs`, 174 lines, 22 ifs): fail-closed classification
  of ACP tool calls into edit / run / network / install / delete. It *looks* fuzzy but it is a
  security classifier over structured input — it must stay deterministic and fail closed.
- **Egress, SSRF and filesystem boundaries**: `code-egress.cjs`, `ssrf.cjs`, `code-workspace.cjs`,
  the DAV protected set.
- **Resource limits**: the tool token budget (D6), context fit arithmetic (D7's measure/threshold),
  step caps (D9's 3 rounds), research budgets (D12's ceilings), result size caps.
- **Feature flags and project modes**: `features.cjs`, `project-modes.cjs`.
- **Schema validation** of tool arguments and of every decision a model returns.

## Size of the fuzzy surface

| | Lines (non-comment) | `if` branches | Hand-set thresholds | Classifier prompts |
|---|---|---|---|---|
| D1 model routing | 94 | 16 | 2 (600 chars, ≥3 numbers) + 7 regexes | 2 |
| D2 tool narrowing | 109 | 12 | 2 (top-3, 0.35) | 0 |
| D3 skill loading | 48 | 4 | 3 (0.5, 0.03, 1) | 0 |
| D4 RAG cut-off | ~25 of 263 | ~4 | 3 (6, 0.3, 2,400) | 0 |
| D5 tool count cap | ~10 | 1 | 2 (12, 24) + a name regex | 0 |
| D11 diary skip | ~20 | 2 | 0 | 1 template |
| **Replaceable total** | **~306** | **~39** | **~12 + 8 regexes** | **3** |
| D7/D8/D9/D12 (advisory additions, not removals) | 427 | 82 | many | 1 (compaction summary) |

The honest reading: noevia's fuzzy orchestration is **already small and well-isolated** — roughly
300 lines of replaceable judgement code, not thousands. H2 ("replace hundreds of lines") is
therefore bounded at the low hundreds. The larger prize is not deletion but **adding decisions
noevia does not make today** (D4 reranking, D9 continuation, D10 output evaluation) through one
primitive instead of three new bespoke mechanisms. See [10-complexity-reduction.md](10-complexity-reduction.md).
