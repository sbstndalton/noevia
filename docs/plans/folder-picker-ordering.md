# Plan: keep folder-picker browse responses ordered

Issue: #30

Status: implemented and verified (2026-09-23).

## Problem

The linked-folder picker allows overlapping navigation while retaining its previous entries. Every browse completion can update entries, errors, and loading state, so an older response can replace a newer path's listing and let the user link an unintended storage folder.

## Intended changes

- Give each path/reload browse an abort signal or monotonically increasing request identity.
- Permit only the current browse to update `entries`, `error`, and `busy`; ignore stale success, failure, and completion callbacks.
- Keep the visible path, folder buttons, and Link action derived from the same current navigation state.
- Apply the same ordering rule when folder creation triggers a reload.
- Keep the mechanism local to `FolderPicker` unless the API gains a narrowly typed optional `AbortSignal`; do not introduce a general request framework.

## Acceptance criteria

- A delayed response for an older path cannot replace the latest path's entries or clear its loading state.
- A stale error cannot obscure a successful current listing.
- Folder creation followed by reload cannot restore the pre-create listing.
- Link always submits the path represented by the visible header and entries.
- Existing modal behavior, storage endpoints, and linked-folder update contract remain unchanged.

## Verification

- Add focused component coverage with deferred synthetic storage responses and two navigations initiated through enabled controls.
- Resolve the requests in both orders and assert entries, header, error/loading state, and submitted path.
- Cover folder creation followed by reload and a stale rejection.
- Run the web unit tests, typecheck, and production build.
- Exercise Project Sources → Linked reference folders → Link folder in Chromium with intercepted synthetic storage APIs. Check the relevant state at 375, 768, and 1440 CSS pixels in light and dark themes; no live storage calls.

## Compatibility constraints

Preserve the current `FolderPicker`/`ProjectView` API, native dialog behavior, storage path semantics, and source-folder deduplication. This plan does not change `StorageFileBrowser` or the PR #15 work.

## Verification result

All 1,247 unit tests, typecheck and build pass. `qa/folder-picker-ordering.cjs` drives real React navigation with deferred synthetic HTTP: old-first/old-last success, stale failure, loading/link guards, creation reload and submitted path. Relevant dialog checked at 375/768/1440 in light/dark with focus and overflow measurements. No production storage, physical-device or screen-reader coverage.
