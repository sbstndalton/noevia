# App-owned Diary with delayed WebDAV backup

Implementation candidate, 2026-09-14. Not deployed; no real Diary imported.
This replaces the proposed dedicated SMB working corpus as the current direction.
The existing production release and all original corpora remain in place.

## Behavior

A fresh account with no existing Diary index, local corpus, dedicated mapping, or
saved remote connection starts with app storage. Saved Markdown and binary corpus
bytes live in a tenant-local SQLite database. Capture, the guarded Markdown
editor, and the scoped Diary API use that same primary. The browser folder mode
remains an explicitly selected advanced workflow.

WebDAV/Nextcloud is a delayed backup destination. Each save commits both bytes and
an updated backup deadline in one SQLite transaction (`synchronous=FULL`). After
three quiet seconds, a server worker checks eligible accounts every three seconds;
network and queue time can add delay. No browser or model call is required. Saves
continue during backup network I/O. A snapshot acknowledges only its own generation,
so edits made during upload remain pending for the next snapshot.

The UI separates saved app changes from pending/complete/failed backups and shows
the last successful backup time. These labels do not claim an unsaved editor or
composer draft has been saved. Failed uploads retain app data and retry after 5,
10, 20, 40, 80, 160, then 300 seconds. Progress and retry state survive restarts.
A rejected backup origin blocks outgoing requests but leaves an already-active
app Diary available. Legacy remote storage still fails closed.

## Storage and access boundaries

Under the existing persistent Diary DB parent:

- `users/<UUID>/managed-diary.db`: primary corpus, settings, generations and backup
  progress. This is irreplaceable state, not a disposable search index.
- `managed-diary.active`: fsynced tenant activation marker. A missing database,
  wrong identity, or interrupted activation fails closed. Never delete the marker
  to dismiss an error or let the service create a replacement empty Diary.
- `managed-index.db`: separate retrieval cache and write journal. Keep it in full
  application backups, particularly while writes are pending.
- `managed-diary.lock` / `managed-backup.lock`: process-shared cutover/worker locks.

The existing persistent DB-parent mount must be writable and reliably backed up.
Do not put SQLite on a network/SMB filesystem or treat only the old loose corpus
folder as sufficient state. Whole-app cold backups must include the full Diary
state directory, web account database and encryption key. For online snapshots,
use SQLite's backup API; do not copy a live database file in isolation.

Credentials remain in the existing encrypted account store. The shared account
storage connection also serves Projects; the Diary connection picker explicitly
says so. S3 remains a legacy corpus/Projects option, but is not a managed Diary
backup destination. The worker obeys Diary opt-in, tenant scoping and approved
outbound-origin rules. Sidecar routes retain the existing shared-token/internal
network trust model; do not expose the sidecar publicly. Tool approval actions
(Allow once, Decline, Allow for this chat) are unchanged.

## Immutable backup layout

Relative to the WebDAV base URL:

```
<corpusRoot>/noevia-backups/<tenant UUID>/
  objects/<SHA-256>/<original basename>
  manifests/<SHA-256 of manifest JSON>.json
```

Objects and manifests are create-only and read back for byte verification. A
manifest is published only after every referenced object verifies. It records the
format, tenant, generation, saved timestamp, corpus layout settings, explicit
empty folders, and each file's relative path, checksum and object location.
No existing remote Diary file is overwritten or deleted. Remote edits never flow
back into the app automatically. A conflicting immutable object causes a visible
backup failure; both the remote bytes and app bytes are preserved.

This release has no retention deletion policy. Backup history grows indefinitely;
monitor destination capacity. Identical content objects are reused, but each
changed generation rechecks the complete snapshot. Large corpora or slow WebDAV
servers may take longer than the debounce interval. Completed generations are not
periodically re-audited until another change requires a backup. This is backup,
not two-way sync or a replacement for independent whole-server disaster recovery.

## Safe import

Existing local, dedicated-volume, WebDAV and S3 corpora stay on their original
backend until the user chooses **Preview import into noevia**, reviews the files,
then chooses **Copy verified files & use app storage**. Close other Diary sessions
and pause external editors before committing an import.

The preview fingerprints file bytes and directory names. Commit reads the source
again, compares the approved fingerprint, then takes a second matching snapshot.
The source is never changed. The app activates the complete copy transactionally,
preserving layout settings and empty directories. A process-shared reentrant lock
and the legacy write guard stop queued old writers from writing after cutover.
Pending journal writes must be drained before import. In-flight capture that reaches
the retired backend after cutover fails instead of silently saving to it; review
its existing recovery record before retrying.

Limits: 5,000 files, approximately 5,000 visited directories, 64 MiB per file and
256 MiB total. Local, WebDAV and S3 import reads enforce byte budgets while reading.
Malformed, duplicated or escaping listings and changed snapshots are refused.
Top-level `noevia-backups` history is excluded. Empty sources are rejected so a
wrong or missing remote folder cannot be mistaken for an intentional blank Diary.
An account that saved a remote connection before its first Diary request therefore
stays on the conservative legacy/import path; no automatic empty-remote cutover.

After activation, changing general storage cannot replace the app corpus. Existing
original files, dedicated mappings and historical journals are retained. Do not
switch back to the originals after new app saves without an explicit reconciled
export: they are now a historical copy.

## Restore procedure

For full service recovery, use the existing cold-state archive procedure. The
synthetic whole-stack check covers login, encrypted provider credentials, Diary
content, continued capture and guarded edits after that restore.

For a portable corpus restore from WebDAV:

1. Download the `noevia-backups` tree, retaining its path relative to the WebDAV
   base (including `corpusRoot`). Select a complete manifest by its `savedAt` and
   generation for the intended tenant; filenames themselves are content hashes.
2. From `services/diary`, use the service's Python environment:

   ```sh
   .venv/bin/python -m agent.backup_restore /path/to/downloaded-webdav-tree /path/to/manifest-hash.json /path/to/new-restored-directory
   ```

3. The command checks the manifest filename hash, format, tenant object scope,
   paths, namespace and every file checksum before creating the destination.
   Existing destinations are refused. It restores Markdown, binary bytes and empty
   folders, and reports the corpus layout settings. It neither chooses a latest
   manifest nor replaces a live database. Restore is bounded to 50,000 files/1 GiB.
4. Inspect that new directory and preserve the report/settings. A live replacement
   is a separate operator recovery: stop writes, preserve the failed state, prepare
   an isolated tenant with matching layout settings, perform the verified import,
   and validate before a deliberate switch. Never remove the activation marker on
   a running service or merge a restored tree into live state blindly.

The portable backup contains the corpus and layout, not account credentials, model
configuration, conversation recovery records, or pending journal operations.

## Validation

Verified locally: 405 web tests; full Diary suite 216 passed / 3 skipped with
two existing dependency warnings; the final bounded-read/path guards pass all
21 managed storage/API tests. Typecheck and production build pass.

Reproducible synthetic checks, no real Diary prompts/corpus changes:

- Full Diary pytest suite (set `DB_PATH` to an isolated `/tmp` directory).
- Web tests, TypeScript check and production build.
- `apps/web/qa/restore-http.cjs`: real web/Diary services, synthetic HTTP inference
  and WebDAV, cold restore, no-browser backup, portable restore, offline saves,
  restart/retry, immutable remote conflict, stale-write rejection and DAV access.
- `apps/web/qa/managed-diary.cjs`: pending/failure/completion, draft preservation,
  reviewed import, long filenames, keyboard focus, 375/768/1440 light/dark layouts.
- Managed storage tests include separate-process cutover, transactional CAS,
  concurrent backup/save, missing database, retained originals, bounded reads,
  empty-folder preservation and corrupt-backup restore refusal.

## Rollout boundary

This is a reviewable implementation, not authorization to deploy or import the
real Diary. Before any approved rollout, follow `deployment.md`, retain a verified
whole-state backup and previous release, verify the persistent DB-parent mount,
and validate the candidate image with synthetic data. Existing users should see
legacy storage until a separately reviewed import. Deployment and real import are
separate decisions; neither happened while implementing this candidate.
