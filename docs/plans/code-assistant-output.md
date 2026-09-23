# Show bounded assistant output on Code tasks

Status: **implemented in draft PR #61**. Tracks [#60](https://github.com/sbstndalton/noevia/issues/60). Implementation base: `1c3ab0e5c21f11d69380e720a9730cb8ea63f361`.

## Problem and contract

Code task cards show status, approvals, tool counts, network use and metadata, but no visible assistant explanation. `code-harness.cjs` receives `agent_message_chunk` from ACP, including the active pi bridge's `text_delta`, yet retains only a chunk count. The pi bridge can emit text before a tool, after a tool, and after low-level `agent_end` before the whole turn settles. The card should show this ordered text under the honest heading **Assistant output**. It is a stream of visible assistant text, not a guaranteed final answer or a success verdict. The task badge, error and approval remain separate.

Only ACP `agent_message_chunk` text blocks with a string `content.text` enter this field. It does not directly copy thought chunks, tool summaries, raw events, file reads, permission arguments or metadata. Visible assistant prose may itself quote those sources; this feature does not redact what the assistant says. React renders the field as inert text, with preserved line breaks and wrapped long paths. Empty output produces no section; truncated output gets an explicit note.

## Implemented changes

- `jobs.cjs` journals Code-only `assistant.output` events, each at most 1 KiB and at most 64 per task. Replay derives `{ text, truncated } | null`, caps the ordered prefix at **32 KiB UTF-8**, cuts only at a Unicode boundary, and never appends after truncation.
- `code-harness.cjs` buffers visible text in 1 KiB batches, permits up to 30 early tool-boundary flushes, and flushes its tail before a normal, failed or gracefully cancelled terminal event. It carries a split surrogate across adjacent deltas and replaces an unmatched surrogate predictably. Thought chunks and tool content never enter output. The `thinking`/`writing` progress stage is coalesced; `messageChunks` still counts the raw chunks. No distinct final answer is inferred: this ACP client has no message ID on those chunks.
- `code-service.view`, the TypeScript API and Code task card expose the derived text. Approval, error and cancel controls remain ahead of a bounded, keyboard-scrollable plain-text region; partial text stays visible on failed, cancelled or interrupted cards. The pi bridge, approval policy, sandbox policy, Chat transcript and task counters are unchanged.

The Code job journal is replayed after a process restart, so already flushed batches can reappear even when recovery marks the task interrupted. An abrupt process kill can lose the still-buffered sub-batch tail. The current Code store writes synchronously without the jobs primitive's `durable:true` fsync mode, so this change must not promise power-loss durability.

## Acceptance and verification

1. Fake pi RPC/ACP test asserts the exact pre-tool, post-tool and post-`agent_end` visible sequence through `agent_settled`; its separate thought updates remain excluded in harness tests.
2. Harness and jobs tests cover malformed blocks, real tool summaries, hundreds of tiny chunks, split emoji, cap crossing, fixed event count, coalesced progress and sticky Unicode-prefix truncation.
3. Tests cover completion, prompt failure, graceful cancellation, journal replay and interruption, plus Code service tenant, project and task isolation.
4. Synthetic Code browser QA covers running and terminal output, null and 32 KiB truncated fields, inert markup-like text, long paths, project revisit, approval priority, keyboard focus/scroll, and 375/768/1440 light/dark overflow.
5. Final-HEAD verification: web unit suite, typecheck, build, design lint and synthetic browser QA. Live model and production calls are outside this change.

The existing request and approval gates and all three approval actions remain intact.
