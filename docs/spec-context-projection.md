# Context projection — spec

Status: **research/design**, 2026-09-16. Nothing here is implemented unless marked
*present*. Strengthens the existing metering and compaction in
`apps/web/server/chat-context.cjs`; it does not replace it. Roadmap: Research priority 1.

## 1. Three layers (architectural principle)

| Layer | What it is | Where it lives today |
|---|---|---|
| **Authoritative record** | What actually happened: every message, every tool call and its complete result, approvals, errors. | Chat history is sent by the client (`body.history`, last `HISTORY_CAP`=40 in `index.cjs`). Tool calls/results are *not* kept past the exchange; full tool results are kept nowhere (only Diary preparation jobs record tool events, `server/diary-jobs.cjs`). |
| **Model-facing projection** | The bounded request actually sent: system text, optional summary, protected recent messages, reduced tool results, tool schemas. | Built per turn in `handleChat`; summary applied by `applySummary`; results hard-cut at `TOOL_RESULT_CAP` (8000 chars). |
| **Human presentation** | What the user sees: chips, previews, disclosures. | Tool result events truncated to 300 chars for the UI. |

One system, three views — not three stores. The projection and presentation are derived
from the record and may be regenerated; the record is never rewritten to make a projection fit.

## 2. Current behaviour (verified in code)

- Request shape: `[system…, summary (as assistant, "reference only"), recent history…]` +
  `tools`. System text joins project name, goal, instructions, memories, RAG `filesBlock`,
  skills index and a stored-only note; vision notes add or append system text.
- `tokens()` estimates bytes/3 + 12 per value + 4096 per image. `measure()` gives
  `reserve = min(4096, 25% limit)`, `safety = 15% limit`, `threshold = limit − reserve − safety`.
  Tool schemas are also estimated separately for budgeting (`estimateToolTokens` in `index.cjs`).
- Limit: backend `ctx_size` from the model manager, else 8192.
- Compaction (`prepareUnlocked`): triggers on `force` or `used > threshold`; keeps the last
  two exchanges (cut moved back to a user message); rolling summary in batches (≤45% limit
  each, output ≤1536 tokens, ≤24 calls, ≤1000 messages); rejects empty/oversized summaries
  and non-shrinking results; state saved atomically with a prefix hash. *Present.*

### Gaps
1. **No protected-input preflight.** Summarizer calls start without checking whether the
   parts that can never be compacted already exceed the window.
2. **Commit before validation.** Lines ~85–90: `Object.assign(state, candidate)` and
   `save(...)` run before `if (meter.used > meter.threshold) throw`. A summary that shrinks
   but still doesn't fit is persisted, then the request fails. The rebuilt request's
   structure is not validated.
3. **No full tool results** in any authoritative store; truncation is lossy and generic.
4. **Tool groups** are only safe today because they are never persisted. Any future
   tool-history persistence makes grouping a live invariant.

## 3. Protected-input preflight

Before any summarizer call, compute the **protected envelope** with the existing
`tokens()`/`measure()` — no second calculator:

```
protected = system messages (instructions, required memory/sources)
          + tool schemas selected for this turn
          + summary allowance (the existing max summary size)
          + the newest protected groups (today: last two exchanges)
          + reserve + safety
```

If `protected > limit`, fail immediately with a typed, user-readable error naming the
largest part (sources, tools, recent messages) and spend **no** inference call. Deterministic
reduction (§5) may run first and the check repeats; summarization is attempted only when the
compactable remainder is what's over budget.

Reference: Row-Bot `src/row_bot/agent.py` `_prepare_with_compaction` counts the fixed prompt
+ tool envelope and fails permanently when it alone exceeds the usable limit (`e5803e3`).

## 4. Validate before commit

A compaction result becomes active only if the rebuilt projection:
1. is structurally valid (roles, ordering, no orphaned tool results, summary position);
2. keeps protected messages byte-identical;
3. keeps every tool-call group intact (§6);
4. fits `threshold` by `measure()`.

Otherwise keep the previous valid state untouched, keep the authoritative record, and return
a typed error. Write the new state only after all checks pass; guard the write so a
concurrent change (different prefix/revision) aborts instead of overwriting.

References: Row-Bot rebuilds with `next_state`, retries once with a tighter boundary, then
saves with compare-and-set (`threads.save_summary_state_cas`); stop requests discard the
result before the save (`tests/subsystem/agents/test_context_compaction.py`). DeepSeek
Harness `packages/compaction/compaction-basic/src/region.ts` rejects a summary that doesn't
shrink its span and aborts on `SurfaceChangedError` (`0d1f500`).

## 5. Deterministic tool-result reduction

Order (unchanged from the roadmap): **measure → trim deterministic waste → collapse recurring
sequences into task-shaped tools → answer mechanical work without the model → summarize only
where still needed.**

- The **complete** result goes to the authoritative record; the projection receives a reduced
  form with a pointer back (result id) so it can be re-expanded on request.
- Reducers are **tool-aware**, keyed from the toolbox manifest (`resultReducer`), with a generic
  fallback. Candidates, to be chosen by measurement, not assumption:

| Result kind | Keep | Drop |
|---|---|---|
| Directory listing | name, type, size, modified date | repeated formatting, irrelevant fields |
| Search | top-k ranked hits, matched passages, source identity | navigation boilerplate, duplicate snippets |
| File read | requested region + surrounding lines, path + line refs | unrelated sections |
| Web page | title, relevant passages, URL, useful metadata | markup, navigation, repeated chrome |
| Command output | head, warnings/errors, matched lines, tail + exit state | repetitive progress noise |

- Cross-cutting, from the references:
  - **Duplicate collapse** — hash large results; earlier identical copies become a reference.
    (Row-Bot `_collect_agent_complete_input`, results > 64 tokens.)
  - **Aged results** — once used and older than N turns, project a one-line stub with a
    pointer. (Row-Bot, > 128 tokens before `_TOOL_CLEANUP_RECENT_TURNS`.)
  - **Generic head/tail** only as fallback, never splitting Unicode. (DeepSeek
    `compaction-tool-result-pruner`: threshold 8192, head 4096, tail 1024; original kept via
    `sourceEventSeqs`.)
- Reduction runs before the preflight re-check and before any summarizer call; it can make an
  LLM compaction unnecessary.

**Measurement first.** Log per turn: input tokens by part (system, history, summary, each tool
schema, each tool result), tool sequence, and whether compaction ran. Rank tools/sequences by
context consumed; build reducers for the top of that list only.

**Acceptance.** Model-facing tokens drop on the measured fixtures; authoritative results are
byte-complete; task completion no worse (same fixtures as `experiments/tool-routing/`);
fewer or no LLM compaction calls where reduction creates room.

## 6. Atomic tool-call groups

An assistant message with `tool_calls` plus every matching `role:'tool'` result (same ids, in
order) is one unit.

- Never compact, age or drop half a group.
- **Never fabricate** a missing result and never replay a tool to repair structure. (Row-Bot
  `_repair_trimmed_tool_messages` inserts "[Result not available…]" — rejected for noevia.)
- Interrupted or pending calls get an explicit state instead of an `ERROR:` string:
  `not_started` / `outcome_unknown` / `denied` / `timed_out` / `cancelled` (after DeepSeek
  `packages/core/session/src/repair.ts` `TOOL_NOT_STARTED` / `TOOL_OUTCOME_UNKNOWN`).
- When aging old tool interactions out of the projection, age whole eligible groups; protect
  groups the newest exchanges depend on.
- Balanced cut points are computed, not assumed (DeepSeek `compaction/src/tool-pairing.ts`).

## 7. Non-goals

A second token estimator; rewriting canonical history; persisting hidden reasoning; changing
the three-round tool limit or approval behaviour; model-driven tool search (measured slower,
`spec-tool-routing-research.md`).


## R1 measurement log (added 2026-09-16)

Opt-in with `CONTEXT_LOG=1`. Each chat round appends one JSON line to the tenant's
`context-log.jsonl` (mode 0600, rotated at 2 MiB to `.1`): estimated tokens for system text,
history, summary, each tool schema and each tool result (by tool name), the round's tool
sequence, whether compaction ran this request, model, limit and a hashed chat id. No message
text, arguments or results are recorded. `node apps/web/server/context-log.cjs <files>` ranks
tools and recurring sequences by context consumed. Estimates use the same conservative
`tokens()` as the meter (sandbox check: 429 estimated vs 269 provider prompt tokens for a
tool-less first round), so compare them against each other, not against provider counts.
Sandbox-verified against the native engine with a per-run `diary-test` copy; nothing collected
from real accounts yet.
