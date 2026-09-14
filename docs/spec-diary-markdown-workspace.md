# Diary Markdown workspace

Status: first editor increment implemented locally, 2026-09-14. Not deployed; no migration.

## Direction

Keep ordinary Markdown files as the portable content format. Build on noevia's
existing tenant-scoped storage and guarded editor rather than add a second diary
backend. “Obsidian-style” means a folder of readable Markdown, navigation, links
and editing ergonomics; it does not promise Obsidian plugin or vault compatibility.

Moodiary reference: https://docs.moodiary.net/guide/ describes offline entry editing,
search/categories, trash, export and optional encrypted sync. These are product
references, not imported implementation. Its Flutter/Rust stack and SQLite-first
content model are not a drop-in replacement for noevia's storage architecture.

## Existing foundation — implemented, not reverified in this documentation pass

- `services/diary/agent/workspace_files.py`: bounded Markdown listing/reading,
  tenant-relative paths, content hashes, storage ETags, conflict rejection and
  index-dirty marking on edits.
- `apps/web/src/components/DiaryView.tsx`: Markdown edit/preview, explicit Save,
  local-folder and configured server-storage workflows.
- Diary capture and entry-edit paths already distinguish original material from
  derived content. Preserve their integrity and approval contracts.

## Reviewable increments

1. **Editor workspace:** replace cramped modal editing with a responsive file list,
   source editor and preview. Show file path, dirty state, saving/saved/error status;
   keyboard save uses the same guarded route. Preserve unsaved text on failures.
   On conflict, show current stored version beside the draft, with explicit reload
   or manually reconciled save; never silently overwrite. Keep existing explicit
   save until durable draft policy is chosen.
2. **Revision backend:** save tenant-owned prior versions before overwriting;
   define an atomic commit/recovery strategy for each storage backend. Restore
   creates a new version. Bound retention and expose failed history writes.
   Test concurrent editor/capture writes, interrupted writes and restore conflicts.
3. **Markdown navigation:** headings/outline, relative Markdown links, tags and
   backlinks. Derived link/search indexes must be rebuildable from source files.
   Start with standard Markdown; specify wiki-link/frontmatter behavior separately.
   Renames need reference-update previews, conflict detection and recovery before
   being exposed. Never follow links outside authorized tenant roots.
4. **Search and calendar:** combine existing diary retrieval with explicit lexical
   search, date/tag filters and result snippets. Verify index updates after edits,
   tenant filtering, missing/corrupt documents and reindex retry. Do not infer mood
   metadata or add model calls as part of ordinary editing.
5. **Portable export and recovery:** Markdown plus attachments and a manifest,
   followed by reversible trash and restore. Preview import changes and duplicates
   before writing; test path traversal, collisions and interrupted imports.

## Decisions needed before their dependent increments

- Revision retention limits and placement on each supported storage backend.
- Whether “offline” should include persistent browser copies of private diary text.
  Current in-memory/local-folder modes must not silently become browser storage.
- Which optional Markdown dialect features need round-trip compatibility with
  external editors. Preserve unknown frontmatter and source formatting.
- Rich-text/live-preview editor choice after testing Markdown round-trip fidelity,
  accessibility, dependency/license fit and large-file responsiveness.
- Encryption is a separate design: key recovery, server-side inference and search
  access must be reconciled before any end-to-end encryption claim.

## Safety and validation

No real diary prompts, corpus edits, vault imports or storage reconfiguration for
QA. Use synthetic tenant-separated fixtures. Keep original/raw capture integrity,
existing three tool-write approval actions and explicit human editor saves.
Test stored Markdown round trips, conflict preservation, safe preview links/HTML,
attachment authorization, keyboard navigation and responsive editor layouts.

## Delivery status

First editor increment implemented locally: expanded responsive workspace dialog,
folder browsing, source/preview split, explicit keyboard save, retained editor after
save, dirty/saving/error feedback and server stored-version comparison. Accepting
a reviewed base retains the draft; a later competing write still encounters the
existing hash/ETag guard. Discard/reload asks explicitly. Markdown source is kept
verbatim; the existing limited preview renderer is unchanged.

Verified: 390 web tests, typecheck/build, 21 relevant Diary workspace tests;
synthetic browser save, failed-save draft preservation, conflict comparison,
manual reconciliation, keyboard save and 375/768/1440 light/dark layouts.

Remaining in increment 1: local-folder conflict reconciliation (existing pending
save/sync recovery remains), richer file-loading feedback, replacing the expanded
dialog with an integrated page workspace, and wider keyboard/accessibility QA.
No revisions, backlinks, new offline cache, trash or encryption implemented.
Production remains fca1f19; no deployment performed.
