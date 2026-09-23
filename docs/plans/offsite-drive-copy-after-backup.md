# Copy completed backups to Google Drive

Fixes [#56](https://github.com/sbstndalton/noevia/issues/56). Audited against `e19e5f619a987b4be3953ee7582d55ae164e1b1c`.

`runNow` previously queued its Drive copy inside the `exclusive('backup')` callback. That microtask ran while `busy` still held the backup lock, so it skipped the copy after both scheduled and manual backups. The encrypted local snapshot completed but its Google Drive mirror could become stale.

`runNow` now waits for the backup and retention lock to release, starts one background mirror when idle, and returns the completed backup without waiting for the upload. Backup failure never starts a mirror. The existing copy helper still checks the directory destination, Drive connection and copy setting, records success or failure, and keeps manual `copyNow` available. An active copy blocks a simultaneous backup or manual copy.

Synthetic service tests cover a deferred upload that does not delay the backup response, one mirror call and its success status, failure status, manual copy, overlap rejection, and no mirror after a failed backup or with copy disabled, Drive disconnected, or a non-directory destination. The scheduler calls this same `runNow` method; its existing cadence test remains in place. Required checks: `npm --prefix apps/web run test`, `typecheck`, `build`, and `lint:design`, plus `git diff --check`. No live Google Drive, production backup, or private data is used.
