# Diary storage: server-local corpus and SMB access

Status: storage support deployed on 2026-09-12; restricted synthetic SMB pilot
created. Mac SMB authentication is pending. Real Diary cutover is not yet done.

## Implementation evidence — 2026-09-12

- Diary image `cowork-diary:ae39000-diary-smb-20260912` is healthy, zero restarts.
  Web/OCR remain `ae39000`. The live Compose override pins the separate Diary
  image and source directory; the main `current` release symlink remains unchanged.
- `DIARY_LOCAL_VOLUMES` provides an operator-owned tenant/root/prefix mapping,
  separate from the general Nextcloud connection. An identity marker is checked
  on every tenant request and backend operation; missing/wrong storage returns
  503. One dedicated state is reused across general-storage header changes.
- Optional `reader_uid` preserves SMB readability after atomic root-container
  saves. This grants file ownership to the reader while Samba remains read-only.
- 192 local Diary tests passed, 3 skipped; all 195 Linux candidate tests passed.
  A real-image synthetic bind/HTTP pilot verified sequential saves, stale 409,
  UID 1000 reading replacement files, missing-volume 503 and recovery. Embeddings
  were stubbed; no private Diary prompt or live inference was used.
- `Diary-Pilot` in `/boot/config/smb-extra.conf` exports only synthetic
  `/mnt/docker/appdata/cowork/diary-smb-pilot/corpus`. Existing `sebastian` account
  only, no guest access, read-only, private-network host restrictions, no symlinks.
  `testparm` passes and anonymous share access is denied. Port 445 is reachable
  from the Mac; macOS is waiting for the existing SMB password.
- The selected tenant has 80 files on both Mac and server, all matching by SHA-256
  excluding Finder metadata. Originals and comparison are retained at
  `~/.local/share/noevia/diary-migration/20260912/` on the Mac. SQLite backup-API
  snapshots (legacy and selected tenant) passed integrity checks and were also
  copied to that Mac backup. The selected journal had 16 applied/0 pending and
  0 dirty documents at preflight.
- Real corpus, general storage connection and Mac sync selection are unchanged.
  The dedicated mapping is not enabled yet. Finish authenticated Mac reopen and
  rename-visibility checks, recompare/drain/backup at cutover, then copy to the
  dedicated volume and enable the mapping. Do not delete either original.

See [operator setup](../deploy/diary/README.md). Arbitrary writable SMB editing
and external-edit indexing remain deferred; noevia/scoped API are the write path.

## User direction

Replace the Mac's Nextcloud-synced Diary working folder with a network-mounted
view of the authoritative server files. Preserve noevia capture/retrieval and
the ability for Claude and other clients to work with the same Diary. This
reopens SMB in Workstream 7; the older decision to exclude a share sidecar is
not the current plan for this deployment.

The reported symptom is stale local content after server-side updates. The
explanation that a same-named file cannot sync is unverified. The previous
Nextcloud push repair passed its server self-tests, but Mac synchronization and
pending local/cloud differences were not verified. Do not label that incident
fully diagnosed or resolved.

## Dedicated Diary scope

User clarification (2026-09-12): this is a dedicated Diary storage/share feature,
not a general noevia file server or a replacement for all Nextcloud storage.
Expose only this tenant's Entries, AI Memory and Raw Sources, with a dedicated
share identity, permissions and Mac mount. The share name `Diary` is a working
label to check for collisions during preflight. Keep non-Diary projects, uploads
and existing storage connections unchanged. Any future app controls belong under
Diary settings rather than a global storage migration flow.

A dedicated share does not require another Samba daemon: prefer Unraid's existing
SMB service with isolated configuration. If a separate service is later necessary,
it must receive only the same scoped corpus and its own explicit access policy.

## Intended topology

One dedicated, durable corpus directory on DaServer, outside Nextcloud's internal
managed data tree, provides the authoritative Markdown files:

- The Diary container accesses it through a local bind mount and the existing
  `local` backend. On the same host, mounting DaServer's own SMB share back into
  the container would add an unnecessary network dependency.
- Unraid's existing SMB service exports only this user's corpus. Prefer the
  host service over a second Samba container; inspect the existing configuration
  before selecting a share name, disk/pool path, identity or ACL.
- The Mac mounts that share under `/Volumes/...`, outside the Nextcloud desktop
  sync root. Client workflows must select this mount explicitly.
- SQLite journal/index files, authentication state, keys and other tenants'
  directories stay on local server storage, outside the SMB export.
- If Nextcloud access remains useful, connect the canonical corpus using its
  supported external-storage mechanism. Its view is secondary, with external
  change detection verified separately; do not maintain two authoritative copies.

The exact paths and account mapping are implementation preflight outputs, not
values to guess from the corpus name. Preserve Entries, AI Memory, Raw Sources,
existing date/layout settings and tenant isolation.

## Corrections to the pasted proposal

**SMB is not cache-free.** SMB leases allow client caching, and editors can keep
their own in-memory document. Removing desktop synchronization removes a separate
replication step; it does not guarantee an already-open editor refreshes instantly.
Test reopen/refresh and overwrite-by-rename behavior on the actual Mac clients.
[Samba lease documentation](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html#SMB2LEASES)

**Existing local conditional writes do not arbitrate external editors.**
`services/diary/agent/local_storage.py` uses a per-instance `threading.Lock`, checks
a content hash, then writes a temporary file and performs `os.replace`. A Samba
writer, another backend instance or another process does not acquire that Python
lock. An external save between the hash check and replace can be overwritten.
Atomic replacement prevents partial publication; it does not make the entire
read/check/write sequence a distributed compare-and-swap.

The SQLite journal supports the companion's recorded operations and recovery;
it does not journal or coordinate arbitrary SMB edits. Keep SQLite/WAL on the
server's local filesystem rather than exporting or opening it through SMB.
[SQLite network-filesystem guidance](https://www.sqlite.org/useovernet.html)

**An environment-variable-only migration is not established.**
`agent/app.py` resolves tenant storage: a supplied WebDAV/S3 storage header takes
precedence, and a non-legacy local tenant receives
`<retrieval-db-parent>/users/<user-id>/corpus`, overriding the generic
`CORPUS_LOCAL_ROOT`. Map the selected tenant, its stored connection settings,
effective path and mount first. A scoped bind mount may avoid a new backend;
if path configuration needs code, preserve tenant boundaries explicitly.

**Do not simply share Nextcloud's internal data directory.** Direct disk changes
can bypass its application bookkeeping. Even supported external storage can need
change detection/scanning before Nextcloud reflects external writes.
[Nextcloud external-storage documentation](https://docs.nextcloud.com/server/latest/admin_manual/configuration_files/external_storage_configuration_gui.html)

## Delivery sequence

1. **Inventory and preserve.** Inspect configuration/path metadata and client sync
   status. Reconcile pending Mac/server differences without automatically choosing
   either version; retain both originals and verified backups before cutover.
   Do not use private Diary content as synthetic test input.
2. **Synthetic pilot.** Use a disposable tenant/corpus and a restricted SMB share.
   Verify local bind access, Mac mounts, same-name updates and rename saves.
   Keep the real journal and live storage selection unchanged during this pilot.
3. **Choose the write contract.** Begin the pilot with SMB read access while
   noevia and the scoped Diary API perform guarded writes. For ordinary Mac/Claude
   filesystem editing, require either a tested single-writer editing handoff or
   coordinated locking/conflict preservation covering every writer and rename.
   Do not declare arbitrary simultaneous SMB/API edits safe because ETags exist.
   The existing Claude adapter remains useful on a local corpus.
4. **Implement gaps.** Confirm tenant path selection, failure when storage is
   unavailable (no silent empty replacement corpus), and reliable detection of
   external changes for retrieval/index invalidation. Direct SMB saves do not
   call the existing `workspace_files.py` dirty-index hook.
5. **Controlled migration.** Drain companion writes and outstanding journal work;
   copy/reconcile with hashes; set tenant storage and container mounts; verify
   permissions/layout; switch the Mac/Claude working path. Retire the old Diary
   sync selection only after reconciliation, without deleting the preserved copy.
6. **Verify and retain rollback.** Record the original settings and directories.
   If new writes occurred after switching, reconcile them before rollback; do not
   repoint clients at an older snapshot and lose those writes. Document the
   server change in the canonical DaServer changelog when implementation occurs.

## Acceptance criteria

- A server-acknowledged synthetic update is visible on Mac reopen; measure the
  latency for both in-place updates and atomic rename replacement.
- If client editing is enabled, stale saves and overlapping companion/client
  writes conflict or preserve both proposals; neither update silently vanishes.
- Mac disconnect/reconnect, server/container restart and missing storage produce
  explicit failure/recovery rather than a false successful save or empty corpus.
- Retrieval notices external edits, renames and deletions within a measured,
  documented interval; a fresh filesystem read alone is not index freshness.
- Only the intended user's corpus is visible. No guest write access, cross-tenant
  traversal, exposed journal/database, or public SMB port is introduced.
- Backup restore and rollback preserve changes made after cutover. All failure
  and concurrency tests use synthetic files.

Storage support and the synthetic share are deployed. The real migration, Mac
mount verification and arbitrary writable SMB workflow are still pending.
