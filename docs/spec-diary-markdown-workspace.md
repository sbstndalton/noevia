# Diary Markdown workspace

Status: integrated editor/navigation/search, including date/tag filters, are deployed
as 48432fe and verified on 2026-09-14. No migration.

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

## Delivery status — 2026-09-14 continuation

Implemented locally:

- A page workspace replaces the modal editor. One file rail moves below the
  writing area at narrow widths; folder filtering, explicit refresh, loading,
  failure/retry and valid empty states are distinct. The original Diary view and
  its draft remain mounted while editing. Returning to it confirms unsaved edits.
- Source, preview and split modes; bounded heading outline; explicit Cmd/Ctrl+S;
  dirty/saving/saved/error feedback. Source formatting/frontmatter stays verbatim.
  Rendering is deferred while typing; no rich-text conversion was introduced.
- Server conflicts automatically attempt a comparison, preserving the draft.
  Local-folder conflicts now support the same explicit comparison/rebase/reload
  controls. Server saves still use hash/ETag guards. Browser-folder saves retain
  the existing read-before-write check; this is not atomic compare-and-swap
  against unrelated applications writing through the OS.
- Editor local writes are separate from capture pending-save records. A successful
  local write advances the editor baseline even if online sync fails. Existing
  pending sync keeps its original remote base across subsequent edits. Pending
  capture writes to the same path must be resolved before an editor save.
- Ordinary inline relative `.md` links stay inside the tenant root. Anchors,
  wiki links and unsupported syntax remain plain text. Raw HTML is not executed.
- Explicit literal search includes the selected folder and its descendants;
  backlinks scan from the Diary root. Both use current source, with no durable
  derived index or model calls. Bounds: 50 files, 50 folders, eight levels, 4 MiB,
  30 results and a 15-second browser deadline. Partial/unreadable results are
  labelled. A local folder is scanned once into a bounded transient snapshot.
- Download Markdown exports the current source, including unsaved changes, without
  saving it to the corpus. This is single-file export, not whole-vault backup.

Verified across the local change set: 404 web tests, typecheck/build; 196 Diary
passed, three skipped (two existing dependency warnings). Synthetic browser checks
cover server/local failures, competing edits, rebase and reload, original-base
sync retry, guarded navigation, file-list failure/retry, search/backlinks, safe
relative links, exact unsaved-source download, keyboard save and 375/768/1440
light/dark layouts. No production Diary prompts or corpus access used.

Next: revision history after retention/placement policy is settled; date/tag
filters; broader Markdown fidelity and large-corpus qualification; full portable
export with attachments/manifest, reversible trash/restore and previewed import.
The revision-retention question is pending: proposed 50 revisions/file for 90 days
with a total cap. This is a proposal, not an enabled policy. New persistent browser
caching, rich text and encryption remain separate decisions.

Production remains fca1f19; no deployment performed. Synthetic review server:
`node apps/web/qa/workspace-preview.cjs` (default localhost:31329, process memory).


## Date and tag filters — 2026-09-14

The existing transient search now combines optional text, inclusive from/through
dates and one whole hashtag, or accepts filters without a text query. Dates match
valid ISO dates at the start of Markdown filenames (YYYY-MM-DD.md or a dated name
with a space, underscore or dash suffix). Undated/monthly files do not match date
filters. It does not infer dates from prose, timestamps or frontmatter.

Tags are case-insensitive #hashtags in prose, with Unicode letters/numbers,
underscores, hyphens and slash-separated names. Frontmatter, fenced and inline
code are excluded; YAML tag arrays and wiki syntax are not claimed. Unknown source
formatting stays unchanged. Backlinks retain their independent unfiltered scan.
Changed input cancels an outstanding search and clears old results. Invalid dates,
reversed ranges and malformed tags are rejected. Existing 50-file/4-MiB bounds,
partial-result labels, tenant scoping and stored-source-only behavior remain.

426 web tests, typecheck/build, existing server/local editor failure/conflict/save
browser regressions, and new date/tag filtering checks at six mobile/landscape/
tablet/desktop sizes in both themes passed. Unsaved drafts remain unchanged and
all fixture writes/inference counts are zero. `qa/workspace-filters.cjs` is the
reproducible browser check. No real Diary corpus was read for these tests.

## Portable workspace export and isolated recovery — 2026-09-14

The workspace's Export section downloads stored Markdown, binary attachments and
empty folders as a ZIP. `workspace/` holds unchanged source paths and bytes;
`manifest.json` holds file sizes, SHA-256 checksums, directories and corpus layout
settings. It includes no credentials, retrieval databases, unsaved drafts or
optional chat attachments stored outside the corpus. Browser-folder mode explains
that the existing folder can be copied with the file manager; it does not silently
export the different server corpus.

Bounds: 5,000 files, 5,000 directories, 64 MiB per file, 256 MiB total source bytes,
8 MiB manifest. Export is an explicit authenticated, tenant-scoped read. Pending
Diary writes block export. Cold tenant initialization defers replay/indexing until
ordinary Diary access. Managed files/directories use one SQLite read transaction;
legacy storage uses two matching bounded snapshots and excludes its separate
`noevia-backups` history. External legacy writers cannot be atomically locked: two
matching scans detect observed changes, not a filesystem-wide atomic snapshot.
No new archive is retained server-side. The browser downloads private plain files.

Operator recovery is available from `services/diary`:

```sh
python -m agent.workspace_restore /path/to/noevia-workspace.zip
python -m agent.workspace_restore /path/to/noevia-workspace.zip --destination /path/to/new-folder --fingerprint REVIEWED_SHA256
```

The first command verifies and previews all paths without writing. The second
rechecks the exact reviewed archive and restores only into a new directory.
Traversal, links/special entries, duplicates, overlapping paths, unlisted content,
checksum failures and size violations are rejected before writes. Existing folders
are never merged or overwritten. Handled write failures remove only the newly
created destination; a hard process/host failure can leave that new folder partial.
Review/remove a partial isolated folder before retrying. This does not activate a
Diary corpus, rewrite raw capture, or update the retrieval index. In-app import
preview, conflict choices and reversible trash remain future work; revision
retention still requires a policy decision.

Synthetic tests cover exact binary/Markdown round trips, metadata-name collisions,
empty folders, source changes, tenant boundaries, pending writes, deferred
recovery, proxy errors, preview/restore failure safety and malformed ZIP paths.
Download failure/retry and draft preservation pass six viewport sizes in both
themes. Visual QA exposed telemetry overlapping the phone export button; workspace
scroll clearance now keeps it reachable and a center hit-test guards the fix.
