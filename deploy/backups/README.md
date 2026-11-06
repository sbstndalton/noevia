# Application backup and restore

This guide describes backup coverage and verification. Configure schedules, destinations,
retention, selected services, and recovery receipts in the installation's local operator
runbook, excluded from Git. It is not a record of a running backup job.

## Coverage

- Include application state, configuration, tenant mappings, encryption keys, and the effective
  Compose inputs required to restore the same release. Match each key with the databases and
  provider files it encrypts.
- Include the `preset-authority` named volume (`authority.sqlite`) when native presets are enabled.
  It records outstanding operations and recovery incidents; retain it across restarts and image rollback.
  Snapshot it with `deploy/tools/preset-authority-backup.sh backup <volume-mount>/authority.sqlite <private-snapshot>`;
  SQLite's backup API includes committed WAL records. Do not copy only the main SQLite file while writers run.
- Coordinate writers before taking a consistent snapshot. Record service shutdown/startup
  dependencies and the expected interruption locally.
- Verify that each configured Diary storage backend is actually covered. A remote corpus is
  not backed up merely because the application's local configuration is included.
- Keep the destination outside application writable roots and file-sharing exports. A backup
  on the same machine is local recovery; it is not an independent off-site copy.

An operator may use a host backup plugin or another qualified mechanism. Inspect the selected
tool's current configuration and logs rather than assuming a historical schedule still runs.
Check archive completeness and writer recovery; a successful process exit is insufficient.

## Restore verification

Restore into a new private directory first and validate extraction paths. Check SQLite integrity,
configuration presence, encryption-key compatibility, and readable restored credentials without
printing their values. Load any required database extensions when checking vector databases.
Never send restored private content to an inference provider for verification.

Use synthetic state to test login, prior entries, continued writes, and stale-write conflicts.
The historical `qa/restore-http.cjs` workflow exercised these behaviors with real web/Diary
processes and a synthetic HTTP provider. A synthetic workflow does not prove a particular
production archive is complete, nor a disaster-site or container-image restore.

Before an authorized live restore, stop writers, preserve displaced state, and reconcile writes
newer than the backup. Preserve tenant boundaries and storage identity markers. An image rollback
does not authorize replacing application databases or a Diary corpus.

## Off-site copies

Store encryption recovery material separately from the encrypted backup. Verify the off-site
copy and restore process independently. Provider selection, account configuration, cost, and
retention are operator decisions; see [the off-site guide](../offsite/README.md).

## Native preset authority rollback

An image rollback keeps `preset-authority` mounted and unchanged. Old images ignore its journal and
fence metadata; never remove it with `docker compose down -v`. A new image initializes an empty or
older journal and turns unfinished old-incarnation operations into recovery incidents before admission.
For a data restore, stop web, loader and gate first, preserve displaced state, then use
`preset-authority-backup.sh restore <snapshot> <volume-mount>/authority.sqlite --services-stopped`.
Restart all three after the restore so Gate reopens its read-only journal snapshot.
Verify a fresh covered preset reread before opening admission. A code rollback alone never restores
an older authority snapshot or clears an incident.
