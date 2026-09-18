#!/bin/bash
# Mirror noevia's encrypted off-site store to Google Drive (or any rclone remote).
#
# noevia writes sealed, content-addressed objects into LOCAL (server/offsite-dir.cjs). This
# script copies them to REMOTE. It never sees plaintext, and noevia never sees the Google
# credential — that lives only in rclone's config, scoped to `drive.file`.
#
# Two rules, because a mirror is the one tool that can destroy a backup:
#
#   1. Refuse to run against a LOCAL that does not look like a healthy store. `rclone sync`
#      makes the remote match the local side; a wiped or unmounted local folder would therefore
#      delete everything on Drive — at exactly the moment the backup is needed.
#   2. Copy first, prune second, and cap the prune. Objects are immutable (chunk ids are
#      content hashes), so the copy can never overwrite a good remote file with a bad local one;
#      the prune only removes what noevia's own retention already removed, and never more than
#      MAX_DELETE objects in one run.
#
# Usage: rclone-sync.sh [--dry-run]
# Env:   LOCAL (default /mnt/user/noevia-backups/offsite)
#        REMOTE (default gdrive:noevia-offsite)
#        RCLONE_CONFIG (default /boot/config/rclone/rclone.conf — /root is RAM on Unraid)
#        MAX_DELETE (default 500), LOG (default next to LOCAL)
set -uo pipefail

LOCAL=${LOCAL:-/mnt/user/noevia-backups/offsite}
REMOTE=${REMOTE:-gdrive:noevia-offsite}
export RCLONE_CONFIG=${RCLONE_CONFIG:-/boot/config/rclone/rclone.conf}
MAX_DELETE=${MAX_DELETE:-500}
LOG=${LOG:-$(dirname "$LOCAL")/offsite-sync.log}
DRY=()
[ "${1:-}" = "--dry-run" ] && DRY=(--dry-run)

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

# Keep the log bounded; it lives on disk, not in RAM, so it survives the outage it may explain.
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || stat -f %z "$LOG")" -gt 1048576 ]; then
  tail -c 262144 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

# One run at a time: an overlapping sync can prune what the other is still copying.
exec 9>"${LOG}.lock"
if ! flock -n 9; then log "SKIP another sync is still running"; exit 0; fi

command -v rclone >/dev/null || { log "FAIL rclone is not installed"; exit 2; }
[ -f "$RCLONE_CONFIG" ] || { log "FAIL no rclone config at $RCLONE_CONFIG (run: rclone config — see deploy/offsite/README.md)"; exit 2; }
remote_name=${REMOTE%%:*}
rclone listremotes 2>/dev/null | grep -qx "${remote_name}:" \
  || { log "FAIL rclone has no remote named ${remote_name}: (see deploy/offsite/README.md)"; exit 2; }

# Rule 1: is this a healthy store? A real one has its encrypted `config` object and at least
# one snapshot. Anything else is a folder that was never initialised, was wiped, or is not
# mounted — and must not be mirrored.
if [ ! -f "$LOCAL/config" ]; then log "REFUSE $LOCAL has no config object: not a noevia store, or wiped"; exit 3; fi
snapshots=$(find "$LOCAL/snapshots" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')
if [ "${snapshots:-0}" -lt 1 ]; then log "REFUSE $LOCAL has no snapshots yet"; exit 3; fi

common=(--exclude '.tmp-*' --exclude '.*' --transfers 4 --checkers 8 --retries 5 --low-level-retries 10 --stats-one-line -v)

# Rule 2a: additive copy. --immutable refuses to replace an existing remote file whose content
# differs, which for content-addressed objects can only mean corruption on one side.
# --checksum makes "differs" mean content, not modification time: restoring this folder from a
# backup resets timestamps on identical files, and without it every later sync would refuse.
log "COPY $LOCAL -> $REMOTE (${snapshots} snapshots locally)"
if ! rclone copy "$LOCAL" "$REMOTE" --immutable --checksum "${common[@]}" "${DRY[@]}" >>"$LOG" 2>&1; then
  log "FAIL copy did not complete; nothing was pruned"; exit 4
fi

# Rule 2b: capped prune. Only reached after a complete copy, so the remote is never left with
# fewer snapshots than the local side.
log "PRUNE remote objects that noevia's retention removed (at most $MAX_DELETE)"
if ! rclone sync "$LOCAL" "$REMOTE" --max-delete "$MAX_DELETE" --checksum "${common[@]}" "${DRY[@]}" >>"$LOG" 2>&1; then
  log "FAIL prune stopped (over the delete cap, or an error); the remote keeps everything it had"; exit 5
fi

log "OK mirrored ${snapshots} snapshots to $REMOTE"
