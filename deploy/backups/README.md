# noevia backups on DaServer

Configured 2026-09-12 using the already-installed Appdata Backup plugin.
Persistent settings: `/boot/config/plugins/appdata.backup/config.json`.
Schedule: daily 04:10 in the server's configured timezone. The plugin installs
its own persistent cron through `scripts/checkCron.php`; this is not a Codex task.

Destination: `/mnt/disk3/noevia-backups`, mode 0700, outside SMB exports, on an
array disk separate from `/mnt/docker`'s single NVMe. Keep at least 7 backup
directories and retain newer-than-30-day backups. This is local recovery, not
an off-site copy or a claim of whole-server backup coverage.

Only `cowork-web-1` and `cowork-diary-1` are selected as a group. Both stop before
state archives are created/verified; Diary starts before web afterwards. Expect
a short nightly interruption (about 16 seconds for the first run). Other
containers are skipped; container updates are disabled. Future unconfigured
containers default to no stop/no backup/no update. Include paths cover noevia
config, Cowork Compose Manager configuration, SMB custom configuration and the
backup settings. The plugin also copies Docker templates. Flash/VM backups are off.

The allowed-source list includes current noevia state and the planned dedicated
Diary storage root; once the real Diary volume is mounted, verify it actually
appears in backup archives. The current remote Nextcloud corpus is **not** copied
by this job. Its verified migration originals are separately preserved on Mac;
Nextcloud-wide backup remains a separate service responsibility.

Initial backup: `ab_20260912_224418`, approximately 6.1 MB. Both archive comparisons
passed. An isolated restore under `restore-check-20260912` passed integrity checks
for 11 SQLite databases, exact encryption-key comparison, configuration presence,
and decryption of the restored storage connection. No private content was printed
or sent to an inference provider. Restored files have never replaced live state.

Manual run: `php /usr/local/emhttp/plugins/appdata.backup/scripts/backup.php`.
Check `/tmp/appdata.backup/ab.log` for completion/errors and verify both services
restart. Plugin notifications are set to errors. Never assume process exit code
alone proves the backup succeeded; inspect the backup log and expected archives.

Restore into a new, private directory first. Treat archives as sensitive and
extract with path protections. Load SQLite's sqlite-vec extension when checking
vector databases. Restore `secrets.key` with its matching database/provider files;
losing the key makes encrypted credentials unusable. Stop writers before restoring
live state and retain the displaced current state. Reconcile newer Diary writes
before rolling back to an older corpus. Preserve current tenant mappings, mount
identity markers and read-only SMB policy.

Follow-up: the restored web image starts with the restored accounts/configuration
and serves HTTP in a network-none container. This verifies web startup, not a full
end-to-end restored Diary/provider exchange. No restored state replaced production.


### Full synthetic workflow restore — 2026-09-13

`node apps/web/qa/restore-http.cjs` passed with real web and Diary processes and a
synthetic HTTP provider. It created disposable state, captured an entry, stopped
both writers, archived/extracted into a new directory, then verified restored
login, prior corpus, encrypted provider credential use, continued Diary capture,
and HTTP 409 for a stale file write. All temporary state was removed afterward.

This complements the production archive integrity/key/startup checks above. It
does not replay the real journal or send restored private data to a provider, and
is not a container-image or disaster-site recovery test. Off-site backup has no
chosen destination or budget; the user deferred that decision. Dedicated corpus
archive coverage still needs verification after SMB storage cutover.
