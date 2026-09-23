# Show bounded assistant output on Code tasks

Status: **plan only; implementation pending**. Tracks [#60](https://github.com/sbstndalton/noevia/issues/60). Baseline: `e925b0ca5c8b34ac7bc3cecd186952afaf075acd`.

## Problem and contract

Code task cards show status, approvals, tool counts, network use and metadata, but no visible assistant explanation. `code-harness.cjs` receives `agent_message_chunk` from ACP, including the active pi bridge's `text_delta`, yet retains only a chunk count. The pi bridge can emit text before a tool, after a tool, and after low-level `agent_end` before the whole turn settles. The card should show this ordered text under the honest heading **Assistant output**. It is a stream of visible assistant text, not a guaranteed final answer or a success verdict. The task badge, error and approval remain separate.

Only ACP `agent_message_chunk` text blocks with a string `content.text` may enter this field. Never persist `agent_thought_chunk`, tool summaries, raw events, file contents, permission arguments or metadata as assistant output. Keep React rendering text-only, with preserved line breaks and wrapped long paths. Empty output produces no section; truncated output gets an explicit note.

## Intended changes

- Extend the closed job-event vocabulary and derivation in `apps/web/server/jobs.cjs` with a Code assistant-output batch event and a derived `{ text, truncated } | null` field. Cap reconstructed text at **32 KiB UTF-8 per task**, cutting at a Unicode boundary. The event data and count also need fixed bounds, so a long stream cannot turn into one journal append per token.
- In `apps/web/server/code-harness.cjs`, collect adjacent visible deltas in order, flush bounded batches during the task and before the terminal event on completion, rejection or graceful cancellation, and mark truncation once. Flush at tool boundaries where needed for readable separation. Coalesce or rate-limit the current `progress` event emitted for every message/thought chunk; otherwise batching the new output would not reduce journal writes. Preserve the existing `messageChunks` statistic and `thinking`/`writing` stage semantics. Do not infer a distinct final assistant turn: this ACP client has no message ID on those chunks.
- Carry the derived field through `code-service.view`, `src/components/code/api.ts` and `CodePanel.TaskCard`; style it in `code.css` using existing semantic tokens. Show partial text with failed, cancelled or interrupted status when present. No change to the pi bridge, Code approval actions, sandbox policy, generic Chat transcript or task result counters.

The Code job journal is replayed after a process restart, so already flushed batches can reappear even when recovery marks the task interrupted. An abrupt process kill can lose the still-buffered sub-batch tail. The current Code store writes synchronously without the jobs primitive's `durable:true` fsync mode, so this change must not promise power-loss durability.

## Acceptance and verification

1. A scripted stream with multiple visible deltas, a tool round, thought deltas and a post-`agent_end` continuation yields ordered visible text only. No thought or tool output appears in the field. The existing fake pi RPC/ACP test should assert the exact sequence through `agent_settled`.
2. Hundreds of tiny chunks produce far fewer total job events than chunks, including coalesced progress events. The final text is byte-capped at 32 KiB without splitting a multibyte character; the truncation marker is persisted once. Malformed or non-text blocks are ignored. A pathological sequence of one-character tool rounds still has a fixed output-event ceiling.
3. Normal completion, prompt failure and graceful cancellation flush pending output before their terminal event. A fresh job-store instance recovers the flushed text; interruption retains it with an interrupted status. Code service list/get expose it only in the owning tenant workspace and project, with another task's output kept separate.
4. Extend `qa/code-mode.cjs` with synthetic running/completed/failed/interrupted cards, null and truncated output, malicious-looking inert text, long unbroken paths, two tasks/projects and a revisit. Verify 375/768/1440 in light/dark with no horizontal overflow, readable ordering and unchanged approval actions.
5. Run the web unit suite, typecheck, build, design lint and synthetic Code browser QA at the final implementation HEAD. Live model and production calls are outside this plan.

Likely implementation files are `apps/web/server/jobs.cjs`, `code-harness.cjs`, `code-service.cjs`, `apps/web/src/components/code/api.ts`, `CodePanel.tsx`, `code.css` and their focused tests/fixtures. The existing request/approval gates and all three approval actions must remain intact.
