#!/bin/bash
# backup-diary.sh : a verified stop-backup of the Diary data, the step before a Diary flip when the last backup no longer
# matches the data (#2635: manifest-compare.sh shows an UNEXPLAINED change, or the GO asks for a fresh one). Runs ON THE
# SERVER as root from the release kit directory (kit.conf beside it). Frozen with the kit: it prints its own sha256 so
# the LIVE file can name exactly what ran. Never a hot copy: SQLite files are only copied while the Diary is stopped.
# Steps: window and lock (shared with every flip and rollback), no release step running, Diary running and healthy,
# enough space, the Diary idle (lib.sh diary_idle, retried up to 10 minutes; never proceeds when busy), record the
# container identity (no environment), STOP the Diary, manifest of the data, copy, manifest of the copy, compare (files
# by type, mode, size and sha256; directories by type, mode and name), archive state/diary + config/.env, gzip test and
# listing check, SHA256SUMS, START the same container (no recreate), wait healthy, web -> Diary health, same image.
# An exit while the Diary is stopped starts it again. DRY=1 runs the checks and the idle gate and stops before the stop.
# Prints names, counts and paths only. Ends with `backup=verified B=<dir>`, which manifest-compare.sh <dir> then uses.
set -euo pipefail; umask 077; trap '' HUP PIPE
HERE=$(cd -- "$(dirname -- "$0")" && pwd); . "$HERE/lib.sh"; KIT_PREFIX=backup
kit_conf "${KIT_CONF:-$HERE/kit.conf}" || exit 1
A=${CONF_APPDATA:-/mnt/docker/appdata/cowork}; F=${CONF_FLIPS_DIR:-$A/release-prep/flips}; DF=${CONF_DIARY_FLIPS_DIR:-$F/diary}
DI=${CONF_DIARY:-cowork-diary-1}; WEB=${CONF_WEB:-cowork-web-1}; HEALTH=${CONF_DIARY_HEALTH_URL:-http://diary:8010/api/health}
state=${CONF_DIARY_STATE:-$A/state/diary}; root=${CONF_BACKUP_ROOT:-/mnt/disk3/noevia-backups}; prefix=${CONF_DIARY_BACKUP_PREFIX:-diary-backup}
config=$A/config/.env
die() { log "backup_error=$1"; exit 1; }
install -d -m 0700 "$F" "$DF"; exec </dev/null > >(tee -p -a "$DF/backup-diary-$(kit_stamp).log") 2>&1
log "backup-diary.sh sha256=$(sha256sum "$0" | cut -c1-64) dry=${DRY:-0} start $(kit_now)"
kit_clock forward || exit 1
exec 8>>"$F/.switch.lock"; flock -n 8 || die locked_by_a_flip
steps() { [ "$(kit_running cutover.sh cutover-diary.sh rollback-web.sh rollback-diary.sh)" = 0 ] || die release_step_running; }
steps
[ -d "$state" ] && [ -d "$root" ] && [ -f "$config" ] || die "state, backup root or .env missing"
IMG=$(docker inspect --format '{{.Image}}' "$DI"); RC0=$(docker inspect --format '{{.RestartCount}}' "$DI")
[ "$(docker inspect --format '{{.State.Status}}' "$DI")" = running ] || die diary_not_running
[ "$(docker inspect --format '{{.State.Health.Status}}' "$DI")" = healthy ] || die diary_not_healthy
need=$(du -sb "$state" | cut -f1); free=$(df -B1 --output=avail "$root" | tail -1 | tr -d ' ')
[ "$free" -gt $(( need * 10 + ${KIT_BACKUP_SPARE_BYTES:-1073741824} )) ] || die not_enough_free_space
log "preflight ok: data $need bytes, backup disk free $free bytes"
t0=$(kit_epoch); until diary_idle "$DI"; do [ $(( $(kit_epoch) - t0 )) -lt 600 ] || die not_idle_10min; sleep 5; done
kit_clock forward || exit 1; steps
[ "${DRY:-0}" != 1 ] || { log "DRY: checks and idle gate passed; the Diary was not stopped, nothing written $(kit_now)"; exit 0; }
B="$root/${prefix}_$(kit_stamp)"; mkdir -m 700 "$B" || die "backup dir exists: $B"
docker inspect "$DI" | jq '.[0] | {Id, Name, Image, Created, RestartCount, State: (.State | {Status, StartedAt, Health: .Health.Status}), Config: (.Config | {Image, Labels}), Mounts: [.Mounts[] | {Type, Source, Destination, RW}]}' >"$B/identity-before.json"
stopped=0
# The start comes first: nothing (a closed terminal, a failing log line) may stand between an exit and the start.
on_exit() { set +e; if [ "$stopped" = 1 ]; then docker start "$DI" >/dev/null 2>&1; r=$?; log "exit while the Diary was stopped: started $DI again (rc=$r)"; fi; }
trap on_exit EXIT
stopped=1; t_stop=$(kit_epoch)
docker stop --time 30 "$DI" >/dev/null; log "$DI stopped $(kit_now)"
diary_manifest "$state" "$B/manifest-stop"
cp -a "$state" "$B/state-diary"
diary_manifest "$B/state-diary" "$B/manifest-copy"
dls() { sed -E 's/^(d [0-7]+) [0-9]+ /\1 /' "$1"; }
cmp -s "$B/manifest-stop.sha" "$B/manifest-copy.sha" && cmp -s <(dls "$B/manifest-stop.ls") <(dls "$B/manifest-copy.ls") || die copy_differs_from_the_data_at_stop
# The archive is made from the verified copy (named as the data's path under APPDATA), not from the live directory.
(COPYFILE_DISABLE=1 tar -czf "$B/diary-appdata.tar.gz" -C "$B" --transform "s|^state-diary|${state#"$A"/}|" state-diary -C "$A" config/.env)
gzip -t "$B/diary-appdata.tar.gz"; tar -tzf "$B/diary-appdata.tar.gz" >"$B/listing.txt"
grep -qx 'config/.env' "$B/listing.txt" && grep -qE "^${state#"$A"/}(/|$)" "$B/listing.txt" || die archive_listing
(cd "$B" && sha256sum diary-appdata.tar.gz manifest-stop.sha manifest-stop.ls >SHA256SUMS)
docker start "$DI" >/dev/null; stopped=0
t=$(kit_epoch); until [ "$(docker inspect --format '{{.State.Health.Status}}' "$DI")" = healthy ]; do [ $(( $(kit_epoch) - t )) -lt 240 ] || die not_healthy_after_start; sleep 3; done
[ "$(docker inspect --format '{{.Image}}' "$DI")" = "$IMG" ] || die image_changed
rc1=$(docker inspect --format '{{.RestartCount}}' "$DI"); [ "$rc1" = 0 ] || [ "$rc1" = "$RC0" ] || die restarted   # a manual start may reset the count
docker exec "$WEB" node -e "fetch('$HEALTH',{headers:{Authorization:'Bearer '+process.env.DIARY_AUTH_TOKEN}}).then(r=>process.exit(r.ok?0:1),()=>process.exit(1))" || die web_to_diary
printf 'B=%s\nT=%s\n' "$B" "$(kit_now)" >"$DF/last-backup.txt"
log "backup=verified B=$B files=$(grep -c . "$B/manifest-stop.sha" || true) copy=identical archive=ok downtime_s=$(( $(kit_epoch) - t_stop )) $(kit_now)"
