#!/bin/bash
# manifest-compare.sh <backup dir B> : compares the Diary data now with B/manifest-stop.sha (taken right after the Diary
# stopped for that backup: cutover-diary.sh or backup-diary.sh). Prints file NAMES only (never content), classified:
#   expected    changed users/<id>/managed-index.db: every managed tenant's first request after a start marks its
#               Markdown files dirty and reindexes them (an index, rebuilt from the diary)
#               changed users/<id>/managed-diary.db whose rows differ from the backup's copy ONLY in the `backups`
#               table (a storage-backup that really uploads), compared row by row with `sqlite3 -readonly .dump`
#               added or changed storage-gates.db: the shared storage back-off gate
#               added users/<id>/managed-backup.lock: an empty lock file, only when a backup really uploads
#               added SQLite -journal/-wal/-shm files (transient)
#   saved       changed users/<id>/managed-diary.db with any other row change (a user's save, an import, ...), or one
#               that cannot be compared row by row (no copy in B/state-diary, no sqlite3); changed users/<id>/index.db
#               (a remote-storage tenant's journal after one of its writes). User data the backup does not hold.
#   UNEXPLAINED anything else changed, added or removed
# Exit 0: only expected changes: the backup still counts before a Diary flip (#2635).
# Exit 4: user data changed since the backup, nothing unexplained: the backup is stale for a flip (take a new one with
#         backup-diary.sh); restoring it would lose those saves (rollback-diary.sh --restore refuses; --restore-force).
# Exit 3: something UNEXPLAINED (it wins over 4). Exit 1: the comparison itself failed (never read as "fine").
set -euo pipefail
HERE=$(cd -- "$(dirname -- "$0")" && pwd); . "$HERE/lib.sh"
B=${1:?backup dir}
kit_conf "${KIT_CONF:-$HERE/kit.conf}" || exit 1
state=${CONF_DIARY_STATE:-${CONF_APPDATA:-/mnt/docker/appdata/cowork}/state/diary}
[ -f "$B/manifest-stop.sha" ] || { echo "manifest_error=no_manifest-stop.sha_in_backup"; exit 1; }
now=$(mktemp -d); trap 'rm -rf "$now"' EXIT
[ -d "$state" ] || { echo "manifest_error=no_state_dir"; exit 1; }
(cd "$state" && find . -type f ! -name '*.db-journal' ! -name '*.db-wal' ! -name '*.db-shm' -print0 | LC_ALL=C sort -z | xargs -0r sha256sum) >"$now/sha" \
  || { echo "manifest_error=hashing_failed (a file vanished or is unreadable: run it again)"; exit 1; }
names() { sed -E 's/^[0-9a-f]{64}  \.\///' "$1" | LC_ALL=C sort; }
names "$B/manifest-stop.sha" >"$now/before.names"; names "$now/sha" >"$now/after.names"
sum_of() { awk -v n="./$2" 'substr($0, 67) == n { print substr($0, 1, 64) }' "$1"; }
changed=$(LC_ALL=C comm -12 "$now/before.names" "$now/after.names" | while IFS= read -r n; do
  [ "$(sum_of "$B/manifest-stop.sha" "$n")" = "$(sum_of "$now/sha" "$n")" ] || echo "$n"; done)
added=$(LC_ALL=C comm -13 "$now/before.names" "$now/after.names")
removed=$(LC_ALL=C comm -23 "$now/before.names" "$now/after.names")
unexplained=0; saved=0
# rows_only_backups <name>: true when the live database and the backup's copy dump to the same rows outside `backups`.
rows_only_backups() {
  local live="$state/$1" copy="$B/state-diary/$1" a b
  [ -f "$copy" ] && command -v sqlite3 >/dev/null 2>&1 || return 1
  a=$(sqlite3 -readonly "$copy" .dump | grep -vE '^INSERT INTO "?backups"? ' | sha256sum) || return 1
  b=$(sqlite3 -readonly "$live" .dump | grep -vE '^INSERT INTO "?backups"? ' | sha256sum) || return 1
  [ "$a" = "$b" ]
}
cls() {  # cls <kind> <name>
  local k=$1 n=$2
  if [ "$k" = changed ] && [[ $n =~ ^users/[0-9a-f-]{36}/managed-index\.db$ ]]; then echo "expected    $k $n"
  elif [ "$k" = changed ] && [[ $n =~ ^users/[0-9a-f-]{36}/managed-diary\.db$ ]]; then
    if rows_only_backups "$n"; then echo "expected    $k $n (backups rows only)"; else echo "saved       $k $n"; saved=$((saved + 1)); fi
  elif [ "$k" = changed ] && [[ $n =~ ^users/[0-9a-f-]{36}/index\.db$ ]]; then echo "saved       $k $n"; saved=$((saved + 1))
  elif [ "$k" = added ] && { [ "$n" = storage-gates.db ] || [[ $n =~ ^users/[0-9a-f-]{36}/managed-backup\.lock$ ]]; }; then echo "expected    $k $n"
  elif [ "$k" = changed ] && [ "$n" = storage-gates.db ]; then echo "expected    $k $n"
  elif [ "$k" = added ] && [[ $n =~ \.db-(journal|wal|shm)$ ]]; then echo "expected    $k $n"
  else echo "UNEXPLAINED $k $n"; unexplained=$((unexplained + 1)); fi
}
while IFS= read -r n; do [ -z "$n" ] || cls changed "$n"; done <<<"$changed"
while IFS= read -r n; do [ -z "$n" ] || cls added "$n"; done <<<"$added"
while IFS= read -r n; do [ -z "$n" ] || cls removed "$n"; done <<<"$removed"
echo "manifest compare: files before=$(grep -c . "$now/before.names" || true) now=$(grep -c . "$now/after.names" || true) changed=$(grep -c . <<<"$changed" || true) added=$(grep -c . <<<"$added" || true) removed=$(grep -c . <<<"$removed" || true) saved=$saved unexplained=$unexplained $(kit_now)"
[ "$unexplained" = 0 ] || exit 3
[ "$saved" = 0 ] || exit 4
