# Dedicated Diary volume

The companion accepts `DIARY_LOCAL_VOLUMES`, an operator-only JSON object keyed by
an exact tenant UUID. Each entry has an absolute container `root` and a corpus
`prefix`. This overrides that tenant's general WebDAV/S3 connection for Diary
only. Other users and project storage retain their existing configuration.

The root must already contain `.noevia-diary-volume` with that tenant UUID.
Missing/mismatched volumes return HTTP 503, including cached tenant requests;
backend operations check again. The service never creates a dedicated root.
Mount the host directory using Compose long syntax with `create_host_path: false`.
Keep the identity marker, SQLite state and backups outside the SMB export.
Set an optional numeric `reader_uid` to the existing server SMB account's UID
when the companion runs as root. Atomic saves then give that reader ownership
of the replacement file (mode 0600); otherwise new root-owned files would become
unreadable over SMB. This does not grant SMB write access.

Preserve the previous corpus prefix inside the volume during migration. This
keeps journal and retrieval document keys valid without rewriting private text
or historical journal records. Drain pending writes, take SQLite backup-API
snapshots, compare hashes of both clients, copy without deleting originals, and
recheck hashes while writes are stopped before changing the storage mapping.

SMB is read-only in this implementation. All edits use noevia or the scoped Diary
connector, whose version checks and dirty-index hooks remain active. Do not enable
Samba writes: arbitrary external editors do not participate in those guards.
SMB caching still exists; verify fresh-open visibility using synthetic files.

Example override (replace placeholder UUID and paths with verified values):

```yaml
services:
  diary:
    environment:
      DIARY_LOCAL_VOLUMES: '{"11111111-1111-4111-8111-111111111111":{"root":"/app/diary-volume","prefix":"Documents/Diary"}}'
    volumes:
      - type: bind
        source: /srv/diary-volume
        target: /app/diary-volume
        bind:
          create_host_path: false
```

Export only `/srv/diary-volume/Documents/Diary`, with `guest ok = no`,
`valid users = <existing-user>`, `read only = yes`, an empty `write list`,
`wide links = no`, `follow symlinks = no`, and private-network host restrictions.
Do not export the parent or Nextcloud's managed internal directory.

To roll back after new writes, stop writers and reconcile the current corpus into
the original backend through its supported API before restoring the previous
container/configuration. Simply switching back to an old snapshot loses updates.
