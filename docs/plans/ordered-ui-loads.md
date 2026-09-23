# Plan: keep asynchronous UI loads ordered

Issues: #23 and #25

Status: implemented and verified with synthetic fixtures (2026-09-23).

## Problem

Diary storage and workspace loads can overlap. Each resolved request currently writes component state, so an older response that arrives last can replace a newer saved connection or workspace list.

## Intended changes

- Give the Diary storage-loading effect an abort or monotonically increasing request identity. Only the current request may update storage or report an error. Keep the `StoragePicker` result authoritative while its confirmation request is pending.
- Give `App.refreshProjects` the same latest-request-wins guarantee for projects, free chats, and `workspaceLoaded`, while retaining the existing pending-project-patch merge.
- Keep the ordering mechanism local and explicit unless a small shared helper has a clear typed contract for both call sites. Do not introduce a general request framework.
- Preserve existing workspace-change, retry, migration, and save triggers.

## Acceptance criteria

- A delayed pre-save storage response cannot replace the newly saved connection.
- A superseded storage-load failure does not replace current state with an error; the current request can still show a retryable error.
- A delayed workspace response cannot replace lists returned by a newer refresh or set load state after that newer refresh.
- Pending project patches continue to apply to current project rows.

## Verification

- Add focused deferred-promise component tests for both orderings.
- Cover an ordinary storage retry, a workspace-change-triggered refresh, and a save-triggered refresh.
- Run the web unit tests, typecheck, and build.
- Verify the affected Diary picker and workspace flows in Chromium with synthetic API fixtures. Do not use private Diary data or production APIs.

## Compatibility constraints

Keep existing API contracts, event names, storage modes, and optimistic project patches. Avoid visual redesign and production mutation.

## Implementation verification

`npm test` passed all 1,247 tests; `npm run typecheck` and `npm run build` passed. `qa/ordered-ui-loads.cjs` drives the real React components in installed Chrome with intercepted synthetic APIs. Checked relevant failure/recovery states at 375, 768 and 1440 pixels in light/dark, keyboard focus and document overflow. Impeccable detector returned no findings. No production APIs, private Diary corpus, physical devices or screen readers were used.
