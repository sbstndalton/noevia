#!/bin/bash
# manifest-compare.sh <backup dir B> : compares the Diary data now with B/manifest-stop.sha (taken right after the Diary
# stopped for that backup: cutover-diary.sh or backup-diary.sh). Prints file NAMES only, classified:
#   rehearsed   changed users/<id>/managed-index.db: every managed tenant's first request after a start marks its
#               Markdown files dirty and reindexes them
#               changed users/<id>/managed-diary.db: a save, or a storage-backup that really uploads (backups row)
#               changed users/<id>/index.db: a remote-storage tenant's journal/index after one of its writes
#               added or changed storage-gates.db: the shared storage back-off gate (created by the first remote-storage
#               request, its row replaced on every one)
#               added users/<id>/managed-backup.lock: an empty lock file, only when a backup really uploads
#   code        added SQLite -journal/-wal/-shm files (transient)
#   UNEXPLAINED anything else changed, added or removed
# Exit 0 when nothing is UNEXPLAINED, 3 otherwise. This is the check that decides whether an earlier backup still
# counts before a Diary flip (#2635); when it does not, take a new one with backup-diary.sh.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "$0")" && pwd); . "$HERE/lib.sh"
B=${1:?backup dir}
kit_conf "${KIT_CONF:-$HERE/kit.conf}" || exit 1
state=${CONF_DIARY_STATE:-${CONF_APPDATA:-/mnt/docker/appdata/cowork}/state/diary}
[ -f "$B/manifest-stop.sha" ] || { echo "manifest_error=no_manifest-stop.sha_in_backup"; exit 1; }
now=$(mktemp -d); trap 'rm -rf "$now"' EXIT
(cd "$state" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum) >"$now/sha"
names() { sed -E 's/^[0-9a-f]{64}  \.\///' "$1" | LC_ALL=C sort; }
names "$B/manifest-stop.sha" >"$now/before.names"; names "$now/sha" >"$now/after.names"
sum_of() { awk -v n="./$2" 'substr($0, 67) == n { print substr($0, 1, 64) }' "$1"; }
changed=$(LC_ALL=C comm -12 "$now/before.names" "$now/after.names" | while IFS= read -r n; do
  [ "$(sum_of "$B/manifest-stop.sha" "$n")" = "$(sum_of "$now/sha" "$n")" ] || echo "$n"; done)
added=$(LC_ALL=C comm -13 "$now/before.names" "$now/after.names")
removed=$(LC_ALL=C comm -23 "$now/before.names" "$now/after.names")
unexplained=0
cls() {  # cls <kind> <name>
  local k=$1 n=$2
  if [ "$k" = changed ] && [[ $n =~ ^users/[0-9a-f-]{36}/(managed-diary|managed-index|index)\.db$ ]]; then echo "rehearsed   $k $n"
  elif [ "$k" = added ] && { [ "$n" = storage-gates.db ] || [[ $n =~ ^users/[0-9a-f-]{36}/managed-backup\.lock$ ]]; }; then echo "rehearsed   $k $n"
  elif [ "$k" = changed ] && [ "$n" = storage-gates.db ]; then echo "rehearsed   $k $n"
  elif [ "$k" = added ] && [[ $n =~ \.db-(journal|wal|shm)$ ]]; then echo "code        $k $n"
  else echo "UNEXPLAINED $k $n"; unexplained=$((unexplained + 1)); fi
}
while IFS= read -r n; do [ -z "$n" ] || cls changed "$n"; done <<<"$changed"
while IFS= read -r n; do [ -z "$n" ] || cls added "$n"; done <<<"$added"
while IFS= read -r n; do [ -z "$n" ] || cls removed "$n"; done <<<"$removed"
echo "manifest compare: files before=$(grep -c . "$now/before.names" || true) now=$(grep -c . "$now/after.names" || true) changed=$(grep -c . <<<"$changed" || true) added=$(grep -c . <<<"$added" || true) removed=$(grep -c . <<<"$removed" || true) unexplained=$unexplained $(kit_now)"
[ "$unexplained" = 0 ] || exit 3
