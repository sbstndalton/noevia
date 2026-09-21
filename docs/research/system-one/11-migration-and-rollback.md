# 11. Migration plan and rollback plan

## 11.1 Principles

- **Behind flags, in shadow first, one purpose at a time.** Nothing is replaced until its
  benchmark result is in and the user has reviewed it.
- The old implementation *is* the fallback. Deleting it is a separate, final step per purpose,
  taken only after at least two releases of the new path running as default with no regression.
- Every step stays within the standing constraints:
  - no live Diary data;
  - no paid credits without approval;
  - no live-engine benchmarking outside a maintenance window;
  - the three approval actions untouched;
  - tenant isolation untouched.

## 11.2 Phases

| Phase | Work | Behaviour change | Exit gate |
|---|---|---|---|
| **M0** (now) | this research; review | none | the user's architectural review |
| **M1** | `server/decision/`: primitive, validation, fallback, logging; `heuristic` backend wrapping today's code **unchanged**; call sites switched to the wrapper | none (byte-identical decisions; tests prove it) | all existing tests plus equivalence tests green |
| **M2** | first prototype, **RAG rerank** (doc 0 §5): `llama-rerank` backend, k = 24 → rerank → top-n; offline benchmark on the RAG family | none live (offline only) | recall@k and answer factuality improve on the held-out set; latency within budget |
| **M3** | `llama-logit` backend + calibration tooling; **model routing in shadow** on live traffic; decisions logged next to the heuristic | none (shadow) | agreement/disagreement report; the benchmark shows C ≥ A on routing |
| **M4** | server-owned chat turn on `jobs.cjs` + checkpoints (doc 6), independent of System One | a chat survives engine/process restarts and browser disconnects | failure-injection suite (doc 9 §9.5) passes |
| **M5** | ModelManager (doc 5) over `llamacpp-manager.cjs`: roles, leases, `plan()`, hysteresis, capability profile | Models page shows residency and profile | swap and restore measurements recorded |
| **M6** | capability database (doc 12), fed by the benchmark and by real outcomes (labels only) | none | populated for the installed models |
| **M7** | output evaluation + loop control in shadow; then choose-once (G) vs adaptive (H) on the benchmark | none until the gate | H3 decided; if H loses, keep G |
| **M8** | provider/auth refactor (doc 7): adapters, cost classes, user policy, OpenRouter PKCE | new settings; metered spend visible | no regression in existing providers |
| **M9** | per-purpose go-live, then deletion of the replaced heuristics (doc 10 §10.1) | yes, one purpose per release | two releases clean per purpose |

M4 (session durability) can run in parallel with M2–M3. It has independent value and is the
prerequisite for anything that swaps models.

## 11.3 Rollback

| Level | How | Time |
|---|---|---|
| One purpose | set its chain to `heuristic` (`DECISION_PROVIDERS`), or remove it from the live list; no redeploy needed | seconds (config + web restart) |
| Whole decision layer | `DECISION_PROVIDERS=*:heuristic`; the wrappers then run today's code | seconds |
| Switching (doc 12) | `ADAPTIVE_SWITCHING=off` → choose-once; hysteresis and switch budget make a runaway impossible even when on | seconds |
| Server-owned chat turn | flag back to browser-saved transcripts; the journal is additive, so nothing to migrate back | seconds |
| A release | the existing overlay rollback (retain the previous release; restore compose and `.env` backups) | minutes, as today |
| Data | the capability database, calibration fits and checkpoints are new files; deleting them returns to priors and baseline behaviour; they are never the source of truth for user data | — |

No migration rewrites existing user data. Every new store is additive and can be discarded.
