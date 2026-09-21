# 4. Decision-provider API specification (draft for review)

One primitive, several thin wrappers, pluggable backends, and a fallback chain that always ends in
deterministic code. Written for noevia's Node server (`apps/web/server/`), so types are JSDoc.

## 4.1 Placement and the authority rule

```
request state
   ↓
POLICY (deterministic)          ← auth, tenancy, toolPolicy, project modes, cloud policy, budgets
   ↓  produces: allowed choices (never empty; "safe default" always present)
DECISION (System One)           ← picks among allowed choices, returns probabilities
   ↓  selected ∈ allowed, validated
EXECUTOR (deterministic)        ← runs the choice under the same policy again
```

- Policy runs first and hands the decision layer a **closed list**. The decision layer cannot add a
  choice, and its output is rejected if it is not in the list.
- The executor re-checks policy. A decision never carries authority: choosing `write_file` from an
  allowed list still goes through Ask/approval exactly as today.
- Every decision has a **safe default** chosen by policy. It is used on timeout, error, abstention
  or low confidence.

## 4.2 The primitive

```js
/**
 * @typedef {'choice'|'multi'|'rank'|'noul'|'score'} DecisionKind
 * @typedef {{ id: string, label: string, description?: string }} Option
 * @typedef {{
 *   kind: DecisionKind,
 *   purpose: string,              // registry key, e.g. 'route.model', 'rag.rerank' — selects prompt, calibration, logging
 *   state: string | object,       // what the decision is about (message, candidate passage, draft answer …); bounded
 *   question: string,             // natural-language question
 *   options?: Option[],           // choice/multi/rank: the ALLOWED set from policy
 *   items?: Option[],             // rank: things to score against the question (passages, boxes)
 *   scale?: { min: number, max: number, labels?: string[] }, // score
 *   constraints?: { maxSelected?: number, minConfidence?: number, deadlineMs: number },
 *   fallback: DecisionResult | (() => DecisionResult),     // REQUIRED: the deterministic answer
 *   context?: { userId: string, projectId?: string, cloud: 'never'|'allowed' }, // policy facts, never sent to a remote backend unless cloud==='allowed'
 * }} DecisionRequest
 *
 * @typedef {{
 *   selected: string | string[] | number | null,  // null = abstained
 *   scores: Record<string, number>,               // calibrated probabilities (choice/noul) or relevance (rank)
 *   confidence: number,                            // calibrated top probability, 0–1
 *   source: string,                                // backend id that answered: 'llama-logit', 'rerank', 'laya', 'jev', 'heuristic', 'default'
 *   metadata: { latencyMs: number, calibrated: boolean, fellBack?: string, model?: string, tokens?: number },
 * }} DecisionResult
 */
async function decide(request) → DecisionResult
```

Rules the primitive enforces, regardless of which backend runs:

1. **Validate the output.** `selected` must be a member of `options` (or within `scale`); `scores`
   keys must match the ids. Otherwise the result is discarded and the fallback is used.
2. **Deadline.** `constraints.deadlineMs` is required. The chat path uses about 150–400 ms. A
   decision that misses its deadline is treated as a failure.
3. **Minimum confidence.** Below `minConfidence` (from the purpose's calibration), return the
   fallback and mark `fellBack: 'low-confidence'`.
4. **Never throw into the caller.** Every failure resolves to the fallback.
5. **Log every decision** (purpose, backend, selected, confidence, latency, fallback reason; no
   raw state unless evidence logging is on) to the existing evidence path (`evidence.cjs`), so the
   benchmark and the calibration fits can be built from real traffic.

## 4.3 Wrappers (one line each over `decide`)

| Wrapper | Kind | Allowed set comes from | Safe default (= today's behaviour) |
|---|---|---|---|
| `routeModel(msg, roles)` | choice | configured roles + policy (cloud policy, budget) | today's heuristic → `fast` |
| `selectTools(msg, boxes)` | multi | the project's selected, offered boxes | today's cosine router → whole selection |
| `selectSkill(msg, skills)` | choice (+ `none`) | project skills that are enabled | today's cosine ≥ 0.5 |
| `rankContext(query, passages)` | rank | retrieved candidates (k = 24) | today's cosine order, top 6 |
| `evaluateOutput(req, draft, evidence)` | choice over PASS / RETRY_LOCAL / USE_STRONGER_LOCAL / RETRIEVE_MORE / ASK_USER / ESCALATE_REMOTE, **filtered by policy** | policy: which of those are possible now | `PASS` (today: always shown) |
| `shouldContinue(transcript, allowedNext)` | choice | the loop's allowed next steps within the step cap | today: continue while tool calls remain |
| `classifyContextUtility(blocks)` | rank / multi-label | blocks eligible for dropping (never pinned instructions) | today: keep recent, summarise older |
| `selectResidencyAction(plan)` | choice | actions the Model Manager says are feasible | Model Manager's deterministic rule |
| `shouldLogDiary(exchange)` (Diary, later) | noul | — | `LOG` (fail-open) |

`ESCALATE_REMOTE` appears in `evaluateOutput`'s allowed set **only** when policy says cloud is
allowed for this user/project *and* a remote provider is configured. The decision model cannot
make noevia leave the machine; it can only pick that exit when policy has already opened it.

## 4.4 Backends

```js
/** @typedef {{
 *   id: string,
 *   supports: (kind: DecisionKind, purpose: string) => boolean,
 *   available: () => Promise<boolean>,      // cheap, cached health
 *   locality: 'local'|'remote',
 *   decide: (request) => Promise<Omit<DecisionResult,'source'>>,
 * }} DecisionBackend */
```

| Backend id | What it is | Kinds | Notes |
|---|---|---|---|
| `heuristic` | today's code, moved behind the interface unchanged | all current purposes | always available; the permanent floor |
| `llama-logit` | option-logit readout on any local GGUF via llama.cpp | choice, multi, noul, score | see 4.5; uses a resident model, preferably the small one |
| `llama-rerank` | llama.cpp `/v1/rerank` with a reranker GGUF | rank | RAG, tool boxes, skills |
| `embed` | cosine on the existing embedding endpoint | rank | what D2/D3/D4 do today |
| `laya` | ONNX Runtime in-process (CPU) | choice, noul, score | only after fine-tuning on noevia's own decisions |
| `sidecar` | HTTP to a Python decision server (SemIf, Kev, Nimble) | per server | for candidates without a llama.cpp path |
| `jev` | TypeSafe API | choice, noul, score | remote; `context.cloud` must be `'allowed'`; API key; never default |
| `disabled` | always the fallback | — | the kill switch |

**Model classes (doc 13):**
- `llama-rerank` and `embed` serve **class A** purposes: specialised discriminative models such as the live `rag.rerank`.
- `heuristic`, `llama-logit`, `laya`, `sidecar` and `jev` are candidates for **class B**, the generic System-One decisions.
- A class-A backend is never placed in a class-B chain just because it can emit scores.

Configuration (per purpose, not global, because the best backend differs per task):

```ini
DECISION_PROVIDERS=route.model:llama-logit>heuristic, rag.rerank:llama-rerank>embed, tools.select:llama-rerank>embed, eval.output:llama-logit>default
DECISION_MODEL=<model id for llama-logit>          # empty = use whatever small model is resident
DECISION_REMOTE=off                                 # 'jev' to allow it as a last step, when policy allows cloud
DECISION_SHADOW=route.model,rag.rerank              # run, log, but act on the fallback's answer
```

A chain is tried left to right; the first backend that is available and answers before the
deadline wins. The last element is always the purpose's deterministic fallback, whether or not
it is written.

## 4.5 The `llama-logit` backend: how to read a decision out of llama.cpp

1. Build a prompt from a per-purpose template, with the state, the question, and options lettered
   `A`, `B`, `C` … (single tokens in every mainstream tokenizer). End it with `Answer: `.
2. Send the prompt to `/completion` with `n_predict: 1`, `n_probs: K` (K ≥ the option count),
   `temperature: 0`, `cache_prompt: true`, and a GBNF grammar restricting the one generated token
   to the letters in play. On chat-template models, disable thinking
   (`chat_template_kwargs.enable_thinking=false`, already used by `auto-router.cjs`).
3. Read `completion_probabilities[0].top_logprobs`. Map letters back to option ids and renormalise
   over the allowed letters. **Use pre-sampling probabilities** (`post_sampling_probs: false`),
   because the grammar-masked distribution after sampling is degenerate.
4. Apply the purpose's temperature `T`: `p_i ∝ exp(logit_i / T)`, fitted offline (4.7).
5. `multi`: one `noul` per option in a single request, batched through llama.cpp's parallel slots
   with a shared prompt prefix (SemIf's "shared-state" pattern).
6. `score`: options are the scale points; the reported score is the expected value, and confidence
   is the probability mass on the chosen point.

This needs no new runtime, no new download, and no Python. It is also exactly how the current
auto router *should* have worked. Today that router generates up to 512 tokens and parses a word
back out.

## 4.6 Fallback chain and failure behaviour

```
purpose's configured local backend(s)  ──fail/timeout/low-confidence──▶  heuristic (today's code)
        │                                                                        │
        └── optional remote (jev) only if policy.cloud==='allowed' AND DECISION_REMOTE ──▶ safe default
```

| Failure | Behaviour |
|---|---|
| Decision engine down | health cache marks the backend unavailable for 30 s; every call goes straight to the heuristic, with no per-request timeout cost |
| Slow | the deadline gives the fallback; a backend that misses 3 deadlines in a row is benched for 60 s |
| Malformed output | fallback; counted as `fellBack: 'invalid'` |
| Low confidence | fallback; counted |
| Remote unavailable / no key / cloud not allowed | skipped silently; never an error to the user |
| All fail | safe default, which is today's behaviour |

No new single point of failure: the worst case is exactly today's noevia.

## 4.7 Calibration

- Raw logits are not probabilities you can threshold. Per purpose and per backend/model, fit a
  temperature `T` (and optionally a bias per option) by minimising NLL on a labelled set. Report
  ECE and Brier before and after.
- Store fits in `ui-data/decision-calibration.json`, keyed by `{purpose, backend, model id + GGUF
  sha256 prefix}`. A new model file invalidates its fit: an uncalibrated purpose runs in **shadow
  mode** until refitted.
- `minConfidence` per purpose is chosen from the fitted curve to hit a target false-accept rate
  (for example 5% for `eval.output`, and more lenient for `rag.rerank`).

## 4.8 Shadow mode (how every rollout starts)

With `DECISION_SHADOW` set for a purpose, noevia runs the decision and logs it next to the
heuristic's answer, **then acts on the heuristic's answer**. That gives agreement rates, latency and
a disagreement sample for labelling on real traffic, with zero behaviour change. No purpose goes
live without a shadow period and a benchmark result.

## 4.9 What the interface deliberately does not do

- It does not generate text: summaries, arguments and answers stay with System Two.
- It does not decide permissions, budgets, egress, write approval or cloud use.
- It does not take free-form output schemas: flat, typed, bounded options only. Nested extraction
  is not a decision.
- It keeps no hidden state between calls: everything it needs is in the request.
