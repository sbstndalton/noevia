#!/bin/bash
# rollback-diary.sh <backup-dir> [--keep-switches] [--restore|--restore-force] : rolls the Diary image back to the previous tag. Runs
# ON THE SERVER as root from the release kit directory (kit.conf beside it). Replaces the per-release
# release-prep/diary-<id>/rollback-diary.sh. <backup-dir> is the cutover's (or backup-diary.sh's) verified backup.
# .env: DIARY_VERSION goes back to DIARY_OLD_TAG and (#2636) every Diary switch line (DIARY_RUST_* and the native leaf
# *_IMPL keys) is removed in the same edit, together with its line in the override's diary environment, so no stale
# switch is left for the next cutover-diary.sh to refuse on and LIVE-SWITCHES.md can say "off". Their names are
# printed (no values). --keep-switches keeps them (only when the old image is known to read them). Every other .env line
# (web keys, web switches) is kept as it is. Then: untag cowork-diary:<DIARY_VERSION> (the candidate keeps its own tag),
# recreate only the Diary with the release's up.sh call, wait healthy on the old image, web -> Diary health, and compare
# the data with the backup's stop manifest (names only).
#   --restore        ONLY when that comparison shows an UNEXPLAINED file and no user data changed (exit 3): the backup's copy is staged beside the
#                    data and proved equal to the stop manifest first; only then the Diary stops, the current data is
#                    moved aside (kept, never deleted), the staged copy takes its place (a rename) and the Diary starts.
#   --restore-force  the same also when user data changed since the backup (exit 4 or 5): those saves stay only in the
#                    moved-aside directory. The owner's decision, never a default.
# DRY=1 prints what would change (key names) and changes nothing, never restores. Ignores HUP and logs to FLIPS_DIR.
# Refuses inside 04:00-04:30 America/New_York and while a flip or another release step runs. Times come from the clock.
set -euo pipefail; umask 077; trap '' HUP PIPE
HERE=$(cd -- "$(dirname -- "$0")" && pwd); . "$HERE/lib.sh"; KIT_PREFIX=rollback
B=${1:?backup dir}; shift; KEEP=0; RESTORE=0
for o in "$@"; do case "$o" in --keep-switches) KEEP=1 ;; --restore) RESTORE=1 ;; --restore-force) RESTORE=2 ;; *) echo rollback_error=unknown_option; exit 64 ;; esac; done
kit_conf "${KIT_CONF:-$HERE/kit.conf}" || exit 1
A=${CONF_APPDATA:-/mnt/docker/appdata/cowork}; C=${CONF_COMPOSE_DIR:-/boot/config/plugins/compose.manager/projects/Cowork}
F=${CONF_FLIPS_DIR:-$A/release-prep/flips}; DI=${CONF_DIARY:-cowork-diary-1}; WEB=${CONF_WEB:-cowork-web-1}
HEALTH=${CONF_DIARY_HEALTH_URL:-http://diary:8010/api/health}; state=${CONF_DIARY_STATE:-$A/state/diary}
V=${CONF_DIARY_VERSION:-}; OLD_TAG=${CONF_DIARY_OLD_TAG:-}; OLD_ID=${CONF_DIARY_OLD_IMAGE:-}
[[ "$V" =~ ^[0-9a-f]{7,40}$ && "$OLD_TAG" =~ ^[A-Za-z0-9_.-]{1,128}$ && "$OLD_ID" =~ ^sha256:[0-9a-f]{64}$ && "$OLD_TAG" != "$V" ]] || { echo rollback_error=conf_diary_binding; exit 64; }
config=$A/config/.env; BASE=$C/docker-compose.yml; OVR=$C/docker-compose.override.yml
die() { log "rollback_error=$1"; exit 1; }
install -d -m 0700 "$F"; exec </dev/null > >(tee -p -a "$F/rollback-diary-$(kit_stamp).log") 2>&1
log "rollback-diary ${V:0:7} -> $OLD_TAG dry=${DRY:-0} keep_switches=$KEEP restore=$RESTORE start $(kit_now)"
kit_clock rollback || exit 1
[ -f "$B/manifest-stop.sha" ] || die no_manifest-stop.sha_in_backup
exec 8>>"$F/.switch.lock"; flock -n 8 || die locked_by_a_flip
[ "$(kit_running cutover.sh cutover-diary.sh rollback-web.sh backup-diary.sh)" = 0 ] || die release_step_running
health_ok() { [ "$(docker inspect "$DI" --format '{{.Image}} {{.State.Health.Status}}' 2>/dev/null)" = "$OLD_ID healthy" ]; }
if [ "$(docker inspect "$DI" --format '{{.Image}}' 2>/dev/null)" != "$OLD_ID" ] || [ "$(env_get "$config" DIARY_VERSION)" != "$OLD_TAG" ]; then
  [ "$(grep -c '^DIARY_VERSION=' "$config")" = 1 ] || die env_needs_exactly_one_DIARY_VERSION_line
  [ "$(docker image inspect "cowork-diary:$OLD_TAG" --format '{{.Id}}' 2>/dev/null)" = "$OLD_ID" ] || die "old_tag_is_not_${OLD_ID:7:12}"
  [ -z "$(tail -c1 "$config")" ] && [ -z "$(tail -c1 "$OVR")" ] || die file_without_final_newline
  W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
  env_put "$config" DIARY_VERSION "$OLD_TAG" >"$W/env"; cp "$OVR" "$W/ovr"; dropped=
  if [ $KEEP = 0 ]; then
    for k in $(diary_switch_keys); do
      if [ "$(env_get "$W/env" "$k")" != - ]; then env_put "$W/env" "$k" - >"$W/e"; mv "$W/e" "$W/env"; dropped="$dropped$k "; fi
      if ovr_block "$W/ovr" diary | grep -qxF -- "$(ovr_line "$k")"; then ovr_drop "$W/ovr" diary "$k" >"$W/o"; mv "$W/o" "$W/ovr"; [[ " $dropped" == *" $k "* ]] || dropped="$dropped$k(override) "; fi
    done
  fi
  for k in $(env_keys_differing "$config" "$W/env"); do [ "$k" = DIARY_VERSION ] || [[ " $(diary_switch_keys) " == *" $k "* ]] || die "env_edit_beyond_diary_keys:$k"; done
  [ "$(diff "$OVR" "$W/ovr" | grep -c '^>' || true)" = 0 ] || die override_edit_adds_lines
  sw_kept=$(for k in $(diary_switch_keys); do [ "$(env_get "$W/env" "$k")" = - ] || printf '%s ' "$k"; done)
  if [ "${DRY:-0}" = 1 ]; then
    log "DRY: .env keys that would change: [$(env_keys_differing "$config" "$W/env" | tr '\n' ' ')]; switches removed: [$dropped]; kept: [$sw_kept]; override lines removed: $(diff "$OVR" "$W/ovr" | grep -c '^<' || true); nothing changed"
    exit 0
  fi
  log "ROLLING BACK to cowork-diary:$OLD_TAG (backup $B)"
  cp -p "$config" "$config.bak.before-diary-rollback-$(kit_stamp)"; cp -p "$OVR" "$B/override.before-diary-rollback-$(kit_stamp).yml"
  T=$(mktemp "$A/config/.rbd.XXXXXX"); cp "$W/env" "$T"; chmod --reference="$config" "$T"; chown --reference="$config" "$T"; mv -Tf "$T" "$config"
  if ! cmp -s "$OVR" "$W/ovr"; then TO=$(mktemp "$C/.rbd.XXXXXX"); cp "$W/ovr" "$TO"; chmod --reference="$OVR" "$TO"; chown --reference="$OVR" "$TO"; mv -Tf "$TO" "$OVR"; fi
  [ -z "$dropped" ] || log "switch lines removed with the image rollback: [$dropped] (update LIVE-SWITCHES.md: off)"
  [ -z "$sw_kept" ] || log "NOTE: switch keys kept (--keep-switches): [$sw_kept]"
  docker image rm "cowork-diary:$V" >/dev/null 2>&1 || true
  if ! (cd "$C" && timeout 300 bash "$A/tools/preflight/up.sh" --env-file "$config" --project-directory "$C" -f "$BASE" -f "$OVR" --profile code -- -d --no-build --pull never --no-deps --wait --wait-timeout 180 diary); then
    [ "$(docker inspect "$DI" --format '{{.Image}}' 2>/dev/null)" = "$OLD_ID" ] && docker start "$DI" >/dev/null \
      || die "up_failed_and_the_diary_is_not_on_the_old_image (.env already names $OLD_TAG: run this command again, or up.sh for diary by hand)"
  fi
elif [ "${DRY:-0}" = 1 ]; then log "DRY: the Diary already runs cowork-diary:$OLD_TAG; nothing to roll back"
fi
t0=$(kit_epoch); until health_ok; do [ $(( $(kit_epoch) - t0 )) -lt 240 ] || die old_image_not_healthy_240s; sleep 3; done
docker exec "$WEB" node -e "fetch('$HEALTH',{headers:{Authorization:'Bearer '+process.env.DIARY_AUTH_TOKEN}}).then(r=>process.exit(r.ok?0:1),()=>process.exit(1))" || log "web cannot reach the Diary"
log "running: $(docker inspect "$DI" --format 'image={{.Image}} health={{.State.Health.Status}} restarts={{.RestartCount}}')"
rc=0; bash "$HERE/manifest-compare.sh" "$B" || rc=$?
case "$rc" in 0 | 3 | 4 | 5) ;; *) die "manifest_compare_failed_rc_$rc (no conclusion about the data: run manifest-compare.sh again)" ;; esac
if [ "${DRY:-0}" = 1 ]; then log "DRY: manifest_rc=$rc; no restore in a DRY run $(kit_now)"; exit 0; fi
if [ $RESTORE != 0 ]; then
  if [ "$rc" = 0 ] || { [ "$rc" != 3 ] && [ $RESTORE = 1 ]; }; then
    [ "$rc" = 0 ] && log "no UNEXPLAINED file: restore refused (not needed)" || log "user data changed since the backup (saved): restore refused; it would lose those saves (--restore-force only on the owner's decision)"
    exit 0
  fi
  [ -d "$B/state-diary" ] || die "backup_has_no_state-diary_copy (nothing was stopped or moved)"
  stage="$state.restore-$(kit_stamp)"; aside="$state.before-restore-$(kit_stamp)"
  [ ! -e "$stage" ] && [ ! -e "$aside" ] || die "restore_paths_exist ($stage or $aside; nothing was stopped or moved)"
  log "staging the backup copy at $stage"
  cp -a "$B/state-diary" "$stage" || { rm -rf "$stage"; die "staging_copy_failed (nothing was stopped or moved)"; }
  (cd "$stage" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum) | cmp -s - "$B/manifest-stop.sha" \
    || { rm -rf "$stage"; die "staged_copy_differs_from_the_stop_manifest (nothing was stopped or moved)"; }
  moved=0
  # Whatever stops this run (an error, a signal), the data directory is never left missing and the Diary is started.
  undo() { set +e; if [ ! -e "$state" ] && [ -d "$aside" ]; then mv -T "$aside" "$state" && log "restore interrupted: current data put back"; fi
    docker start "$DI" >/dev/null 2>&1; [ -z "${W:-}" ] || rm -rf "$W"; }
  trap 'undo' EXIT
  kit_clock rollback || exit 1
  log "RESTORE from $B (staged copy verified); current data moved aside to $aside"
  docker stop --time 30 "$DI" >/dev/null
  mv -T "$state" "$aside"; moved=1; mv -T "$stage" "$state"; moved=2
  docker start "$DI" >/dev/null
  t0=$(kit_epoch); until health_ok; do [ $(( $(kit_epoch) - t0 )) -lt 240 ] || die not_healthy_after_restore; sleep 3; done
  trap - EXIT; [ -z "${W:-}" ] || rm -rf "$W"
  log "restored and healthy; data equals the stop manifest; previous data kept at $aside"
fi
log "rollback-diary=verified image=${OLD_ID:7:12} manifest_rc=$rc $(kit_now)"
exit 0
