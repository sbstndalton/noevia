# Chat metadata save recovery — plan only

Issue: #51. Base: `59f38d0bbc497aeb0bf234535f6cb3df97c2d3f6`.

`App.handlePatchChat` optimistically changes free or project chat metadata, then silently discards a failed list POST. In a synthetic Chrome fixture, a 500 from either endpoint left a failed Pin visible and a failed Archive hidden, with no alert. Rename and row actions use the same handler.

## Intended change

Keep the change local to chat metadata handling in `App.tsx` and focused browser QA. Surface a concise dismissible save error through the existing alert. On failure, reconcile the affected chat fields from the last confirmed state without depending solely on a workspace fetch, and leave unrelated chats and fields intact. Order rapid writes to the same list and protect newer optimistic actions from earlier completions or refreshes; free and project lists must remain independent. Preserve the server's merge/tombstone behavior and existing tenant boundaries. Do not alter chat history or project configuration saves.

## Acceptance and verification

- Failed Pin, Rename, and Archive recover accurately for free and project chats, including when the follow-up workspace GET fails.
- Repeated/rapid actions on one list converge on the latest successful action; a failed earlier operation cannot undo a newer one. Concurrent updates to unrelated chat fields such as preview and `updatedAt` survive reconciliation.
- A synthetic browser regression uses the actual Sidebar menu and save routes with forced failures and delayed responses. No live inference, Diary, or private data.
- From `apps/web`: `npm test`, `npm run typecheck`, `npm run build`, `npm run lint:design`, plus the synthetic browser regression. Use external dependency and build directories.

This PR contains the plan only. Cross-device simultaneous writes are not established by the synthetic browser fixture; reassess if implementation changes their contract.
