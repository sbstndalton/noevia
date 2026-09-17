# Deep research mode — spec

Status: steps 1–5 built behind `features.deepResearch` (admin-only, off) as of 2026-09-17; step 6 (the §8 gate on real models) is not run. Originally: **spec, not built** (2026-09-16). Roadmap item I. Build only after the durable-work
primitive exists ([spec-agent-execution.md §4](spec-agent-execution.md)) and the measurement
gate below has been run on this deployment's models.

Inspiration: Gemini Deep Research and NotebookLM — a question the user deliberately hands off,
answered as a cited report saved to the project. Reference points only; nothing is adopted
wholesale.

## 1. What it is, and what it is not

- A **chosen, long-running job** started from a project, not a chat turn. It plans an
  investigation, reads web results and the project's own selected sources, and produces a
  Markdown report with numbered citations, saved into the project.
- Not an automatic escalation of normal chat. Chat keeps its current single-model path with
  the three-round tool ceiling (`handleChat`, `round < 3`).
- Not a crawler. `web-crawl` (`tavily_crawl`, `tavily_map`) stays out of the default budget:
  one call can spend a month of credits.
- No writes outside the project: the only persisted outputs are the report and its source
  list. External accounts are never written to.

## 2. Why a planning step is allowed here when chat rejected it

`spec-tool-routing-research.md` (42 runs, 2026-09-13) measured a planner/executor split for
**chat turns**: median 26.97 s against 8.64 s baseline, with more tokens and no accuracy gain.
That finding stands for chat, where time to answer is the product.

Deep research differs on the axis that decided that result: the user has already chosen to
wait, and the output is judged on coverage and citation correctness, not seconds. So a plan
step is *permitted* but **not assumed useful** — it must beat a no-plan pipeline on the
metrics in §8, on the same fixtures, or it is removed. The chat finding is not overturned.

## 3. Flow

1. **Start.** User picks *Deep research* in a project composer, writes the question, sees the
   budget (max web calls, max wall time, sources in scope) and starts. Starting is the
   job-level consent to run reads and to save the report into this project.
2. **Plan (optional, measured).** The configured Smart model (or the project model) proposes
   3–7 sub-questions as structured JSON. The plan is shown; the user can edit, delete or add
   sub-questions, or skip planning. The plan is task context, never authorization: it cannot
   add tools, raise budgets or reach other projects.
3. **Gather, per sub-question.** Up to *k* `tavily_search` calls, then `tavily_extract` on the
   top results; plus retrieval over the project's own sources through the existing RAG path.
   Each fetched item is registered as a source (§5) and reduced to notes **before** it enters
   model context (§6).
4. **Synthesize, per section.** One section per sub-question from its notes only, then a short
   overall summary from the section drafts. Claims carry `[n]` markers pointing at source ids.
5. **Verify citations** (deterministic, §5). Unsupported markers are dropped and the claim is
   flagged in the report rather than silently kept.
6. **Save.** `Research/<date> <slug>.md` and `Research/<date> <slug>.sources.json` into the
   project folder through `uploads.ingest`, so they appear as project sources and are indexed.
7. **Notify** in the app (and later through notifications, when built).

## 4. Job model (on the durable-work primitive)

Built on §4 of the agent-execution spec, not a bespoke queue:

- Job owned by tenant + project; `mode: 'deep_research'`; records question, budget, model(s),
  architect mode, plan revision.
- Append-only events: `job.created`, `plan.proposed|edited|skipped`, `step.started|completed`
  per sub-question, `tool.started|completed|failed` (reads), `source.registered`,
  `section.drafted`, `citations.verified`, `artifact.created`, `job.completed|failed|cancelled`.
  State is derived from events.
- **Checkpoints** after each completed sub-question (its notes and sources). A restart resumes
  from the last checkpoint; a sub-question that was mid-flight is re-run from its start (all of
  its calls are reads, so re-running is safe; the metered credit cost is shown in the job log).
- **Cancel** stops new calls immediately, keeps completed sections, and offers "Save partial
  report" — never saves automatically after a cancel.
- Progress survives navigation; one completion owner writes the artifacts.

## 5. Sources and citations

Source registry per job:

```json
{ "id": 3, "kind": "web" | "project", "url": "https://…" | null, "file": "notes.md" | null,
  "title": "…", "retrievedAt": 1760000000000, "excerpts": [{ "sha256": "…", "text": "…" }] }
```

- Excerpts are the exact reduced spans shown to the model (bounded, see §6).
- **Citation check:** every `[n]` must name a registered source used by that section; each
  sentence carrying `[n]` must share a quoted span or a normalised key phrase with one of that
  source's excerpts. Failing markers are removed and the sentence is marked "unsupported" in a
  footnote list. No model call is used for verification.
- Report footer lists sources in id order with title, URL or project file, and retrieval date.

## 6. Context limits (local models)

Assume 8K–32K usable context. Never place a full page in context:

- Extracted pages are reduced deterministically first (boilerplate strip, heading-aware
  chunking, top chunks by the sub-question's embedding similarity via the existing embeddings
  call), capped per source (e.g. 1,200 tokens) and per sub-question (e.g. 6,000 tokens).
- Notes are written per source by the model within that cap; sections are drafted from notes,
  the summary from section drafts — a bounded map-reduce with the same `tokens()`/`measure()`
  accounting and protected-envelope preflight used by chat compaction
  ([spec-context-projection.md](spec-context-projection.md)).
- If a step's protected input already exceeds the window, the step fails with a readable
  reason and no inference call, exactly like chat compaction.

## 7. Security and cost

- Web content, extracted pages, tool output and project files are **data, never instructions**.
  Planner and writer prompts state this; the runner enforces it structurally (no tool lists
  derived from content, no URLs fetched that a page asked for unless they were search results).
- Only read tools from `web-search` plus internal RAG. Any other tool, including every write,
  is outside the job's capability set, which is fixed at creation.
- Budgets are hard limits enforced by the runner: web calls, wall time, tokens per step. The
  default budget is shown before start; raising it is an explicit user action.
- `tavily_research` (Tavily's hosted research endpoint) sends the whole question to a third
  party and returns their synthesis. It is not used by the pipeline by default; it is a
  **comparison baseline** in §8 and needs a clear disclosure if ever offered.
- Members use the deployment's configured Tavily key only if the administrator offers the
  `web-search` toolbox; tenant isolation of projects and artifacts is unchanged.
- Prompt Architect may prepare the plan prompt only if D4's benchmark shows a gain for this
  task class; otherwise Direct.

## 8. Measurement gate

Fixtures (synthetic, offline where possible):

- 12 questions over a **local static fixture site** served by the test runner (so results are
  reproducible and cost nothing), each with an answer key of required facts and the pages that
  contain them; 4 questions that also need the project's own synthetic sources; 2 adversarial
  pages containing instructions aimed at the model.
- A small live set (≤5 questions, run once, credits recorded) only with the user's go-ahead.

Variants on the same fixtures and models:

| Variant | Description |
|---|---|
| A | Current chat with `web-search` enabled (three-round ceiling) |
| B | Pipeline without the plan step (question used as the only sub-question) |
| C | Pipeline with plan step |
| D | `tavily_research` result, reformatted (live set only, baseline) |

Record per run: required facts covered, citation validity rate (§5 check), unsupported
sentences (manual sample of 20%), adversarial-instruction compliance (must be zero), web calls,
credits, input/output tokens, wall time, cancellations/resumes exercised.

Adopt the mode if B or C covers materially more required facts than A with ≥95% citation
validity and zero adversarial compliance. Keep the plan step only if C beats B on coverage
without lower citation validity. Record results here with the date and model configuration.

### Gate result — 2026-09-17 (failed; feature turned off)

Ornith-1.5-9B-Q5_K_M (ctx 16 384) on DaServer, llama.cpp b10920, `--models-max 1`, harness run
from inside the web container against `http://llama:8080/v1`, 12 + 4 + 2 fixtures, variants A/B/C.
Questions 9–12 of the run hit `Model HTTP 500` in every variant because a Nextcloud Assistant test
evicted the 9B mid-run (single model slot), so only questions 1–8 are clean. They already decide it:

| Variant | Completed (Q1–8) | Required facts | Citation validity | Adversarial compliance | Median time |
|---|---|---|---|---|---|
| A chat + search | 8/8 | 15/22 | — | **2** | 11.8 s |
| B pipeline, no plan | 8/8 | 15/22 | **0.65** | 0 | 51.1 s |
| C pipeline + plan | 7/8 | 13/22 | **0.675** | 0 | 225.6 s |

(Facts are counted over all 12 questions; the failed 4 contributed none to any variant.)
B and C miss the ≥ 0.95 citation-validity bar, B covers no more facts than A, and C is worse than
B at four times the time. The pipeline's one clear win is adversarial resistance (0 vs 2).
**Decision:** not adopted. `NOEVIA_FEATURE_DEEP_RESEARCH` set to `"false"` in the live override
(copy `.bak.before-deep-research-off`), web recreated. Before a re-run: find why a third of cited
sentences fail the §5 check on a 9B (claim extraction vs. citation format), and run the gate with
nothing else using the engine.

## 9. Build order

1. Durable-work primitive (R6) with event log, checkpoints, cancel, restart recovery.
2. Source registry, deterministic reducers and citation verifier, with unit tests.
3. Runner B (no plan) behind an admin flag; fixture site and measurement script.
4. Plan step (C) and plan editing UI; measure B vs C.
5. Report save via `uploads.ingest`, progress panel, cancel/partial save, report view.
6. Enable per deployment only after §8 passes.

## 10. Open decisions for the user

- Default budget (web calls per job, maximum wall time) and whether members may start jobs.
- Whether a live-credit measurement run is acceptable, and its credit ceiling.
- Where reports live: `Research/` inside the project folder (proposed) or a separate section.
