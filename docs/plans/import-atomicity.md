# Plan: make conversation imports recoverable across partial commits

Issue: #29

Status: plan only; implementation pending.

## Problem

Conversation import writes every transcript before it persists free-chat and project-chat metadata. A later workspace-save failure can return an error with new transcript files that no chat list references, or with part of a new project already committed. Retrying has no durable record of what this attempt wrote.

## Intended changes

- Give one import attempt a durable, tenant-scoped identity and recovery record before applying its plan. Record only the new chat IDs and metadata this attempt owns; never snapshot or replace the whole workspace.
- Stage newly imported transcripts under that attempt and promote them at a defined metadata commit point, or use an equivalent journal that can safely finish or remove only definitely unreferenced files after interruption.
- Define explicit partial-commit semantics for free chats, existing projects, and newly created projects. A retry with the same export must resume/reconcile the attempt rather than create duplicate chats.
- Treat storage-backed project-folder allocation as an external side effect. Do not promise deletion or rollback of an externally created folder; retain or surface it safely if project persistence fails.
- Preserve unrelated and concurrent workspace changes. Cleanup may remove only files proven to have been created by this import and still unreferenced.
- Emit the existing success audit only after reconciliation reaches a completed state. Add bounded diagnostics for recovery failures without logging transcript content.

## Acceptance criteria

- Failure while persisting a new project or adding chats to an existing project leaves no permanently unreachable imported transcript.
- A retry after every supported failure point converges on one visible copy of each imported chat.
- Recovery never deletes a pre-existing transcript, chat, project, or external storage folder.
- Tenant isolation, tombstones, add-only behavior, input limits, history sanitization, and successful response shape remain intact.
- The implementation documents any failure window that cannot be made atomic and how the next request/startup recovers it.

## Verification

- Add route/store tests with real filesystem transcript writes and injected workspace-save failures at free-chat, new-project, and existing-project-chat boundaries.
- Cover a multi-chat attempt that fails after one commit, then retry and assert exactly one visible copy plus no unreferenced new transcript files.
- Cover process-restart recovery from each durable marker/staging state.
- Assert cleanup leaves unrelated concurrent records and pre-existing transcript paths untouched.
- Run the web unit tests, typecheck, and production build using synthetic conversations only.

## Compatibility constraints

Keep the current import/export format, endpoint, audit privacy, per-user workspace layout, tombstone behavior, and project-folder contract. Do not read private Diary data, call production APIs, delete external storage folders, or introduce a whole-workspace rollback snapshot.
