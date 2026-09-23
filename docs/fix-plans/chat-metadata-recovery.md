# Chat metadata save recovery

Fixes #51. Audited baseline: `59f38d0bbc497aeb0bf234535f6cb3df97c2d3f6`.

A rejected Pin or Archive previously remained as an optimistic sidebar change with no error; Rename used the same handler. The free-chat and project-chat endpoints receive a whole list and merge incoming records by ID.

`App.handlePatchChat` now keeps the displayed metadata at its last confirmed state until the save succeeds. Saves are queued per list, so rapid actions on the same list use the state left by the preceding result. A failed request reports a dismissible error and leaves the chat available to retry, even when `/api/workspace` is also unavailable. On success only the action's fields are applied to the latest local record; unrelated chats and newer preview/title/time fields survive. The client applies the server's 120-character title limit and ignores workspace GETs started before a confirmed save. Free and project lists remain independent. Chat history, the server's merge/tombstone rules, tenant boundaries, and project configuration saves are unchanged.

Synthetic Chrome QA drives the actual Sidebar menu through rejected Pin, Rename and Archive for both scopes; delayed consecutive saves; independent project/free requests; a workspace refresh carrying newer unrelated fields; a stale GET; title normalization; and 375/1440 light/dark alert layout. No live inference, private Diary, or production data is used. Cross-device simultaneous writes are outside this fixture and retain the existing whole-record server behavior.

Required checks from `apps/web`: `npm test`, `npm run typecheck`, `npm run build`, `npm run lint:design`, `node qa/chat-metadata-recovery.cjs` with Playwright Chrome, plus branch `git diff --check`.
