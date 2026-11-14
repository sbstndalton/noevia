#!/bin/bash
# rollback-web.sh <backup-dir> [--drop-unsupported] : rolls the web release back to the previous version. Runs ON THE
# SERVER as root from the release kit directory (kit.conf beside it; see README.md). Replaces the per-release
# release-prep/<id>/rollback-web.sh. Recreates ONLY web on the old image; never touches SQLite, egress, the published
# key (current.key) or the issuer state.
#
# .env (#2633): only the keys the release changed (RELEASE_KEYS in kit.conf, default COWORK_VERSION) go back to their
# pre-cutover values from <backup-dir>/.env (= .env.bak.before-<RELEASE_ID>). Every other difference from that backup (a
# switch flipped or a Diary key set after the cutover) is KEPT and its key name printed, never a value. With no other
# difference the result is byte-identical to the backup (asserted).
# Switches (#2638, #2639): every web switch (web-switches.txt) still set after that must be one the target release can
# run: its Rust front names the key and switch-code.txt's files are there. Otherwise the rollback refuses and names the
# key; with --drop-unsupported it removes that key's .env line and its web override line in the same edit (the switch is
# then off on the old image: say so in LIVE-SWITCHES.md). A web override line whose .env line is gone is named as stale.
# The preflight files listed in PREFLIGHT_FILES come back from <tools/preflight>.bak.before-<RELEASE_ID>; `current` points
# at the old release. DRY=1 prints what it would change (key names only) and changes nothing.
# Refuses inside 04:00-04:30 America/New_York, while a flip, cutover or Diary step runs (shared lock), or when the live
# .env does not name the release. Resumable: once the files are committed it records that in FLIPS_DIR; if anything
# after that fails (the recreate, a check, a dropped session: HUP is ignored and the run is logged in FLIPS_DIR), the
# same command run again finds the committed files unchanged and finishes the recreate and the checks.
# Every time it prints comes from the clock.
set -euo pipefail; umask 077; trap '' HUP PIPE
HERE=$(cd -- "$(dirname -- "$0")" && pwd); . "$HERE/lib.sh"; KIT_PREFIX=rollback
B=${1:?backup dir}; DROP=0; [ "${2:-}" = --drop-unsupported ] && DROP=1; [ -z "${2:-}" ] || [ $DROP = 1 ] || { echo "rollback_error=unknown_option"; exit 64; }
kit_conf "${KIT_CONF:-$HERE/kit.conf}" || exit 1
A=${CONF_APPDATA:-/mnt/docker/appdata/cowork}; C=${CONF_COMPOSE_DIR:-/boot/config/plugins/compose.manager/projects/Cowork}
F=${CONF_FLIPS_DIR:-$A/release-prep/flips}; WEB=${CONF_WEB:-cowork-web-1}; EG=${CONF_EGRESS:-cowork-egress-rs-1}
KID=${CONF_RELEASE_ID:-}; V=${CONF_RELEASE_VERSION:-}; OV=${CONF_ROLLBACK_VERSION:-}; OID=${CONF_ROLLBACK_IMAGE:-}
[[ "$KID" =~ ^[0-9a-f]{7,40}$ && "$V" =~ ^[0-9a-f]{40}$ && "$OV" =~ ^[0-9a-f]{40}$ && "$OID" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo rollback_error=conf_release_binding; exit 64; }
RKEYS=${CONF_RELEASE_KEYS:-COWORK_VERSION}; PFILES=${CONF_PREFLIGHT_FILES-check.php,diary-models-check.sh}; TT=${CONF_TARGET_TREE:-$A/releases/$OV}
[[ ",$RKEYS," == *,COWORK_VERSION,* ]] || { echo rollback_error=release_keys_without_cowork_version; exit 64; }
ENV=$A/config/.env; PF=$A/tools/preflight; KD=$A/egress-control; BASE=$C/docker-compose.yml; OVR=$C/docker-compose.override.yml
die() { echo "rollback_error=$1"; exit 1; }
install -d -m 0700 "$F"; exec </dev/null > >(tee -p -a "$F/rollback-web-$KID-$(kit_stamp).log") 2>&1
echo "rollback-web $KID -> ${OV:0:7} dry=${DRY:-0} drop_unsupported=$DROP start $(kit_now)"
kit_clock rollback || exit 1
exec 8>>"$F/.switch.lock"; flock -n 8 || die locked_by_a_flip
MARK=$F/rollback-web-$KID.committed; committed=0
after_commit() { local rc=$?; [ "$committed" = 1 ] && [ "$rc" != 0 ] && echo "rollback_error=after_commit (the files are committed, see $MARK; run the same command again: it resumes with the recreate and the checks; after a recovery by hand delete $MARK*)"; return 0; }
trap 'after_commit; [ -z "${W:-}" ] || rm -rf "$W"' EXIT
[ "$(kit_running cutover.sh cutover-diary.sh rollback-diary.sh backup-diary.sh)" = 0 ] || die release_step_running
[ "$(docker image inspect --format '{{.Id}}' "cowork-web:$OV")" = "$OID" ] || die old_image
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || die backup_checksums
[ -f "$ENV.bak.before-$KID" ] || die missing_bak; cmp -s "$ENV.bak.before-$KID" "$B/.env" || die env_bak_mismatch
for f in ${PFILES//,/ }; do [[ "$f" =~ ^[A-Za-z0-9_.-]+$ ]] && [ -f "$PF.bak.before-$KID/$f" ] || die "missing_pf_bak:$f"; done
# A run that committed its files and then stopped: the same command resumes when the files are still the committed ones.
RESUME=0
if [ -f "$MARK" ] && [ "$(env_get "$ENV" COWORK_VERSION)" = "$OV" ]; then
  [ "$(sed -n 1p "$MARK")" = "$(kit_digest "$ENV")" ] || die "committed_env_changed_since_the_interrupted_run (compare with $B/.env.pre-rollback by hand; after a recovery by hand delete $MARK*)"
  if [ "$(sed -n 2p "$MARK")" != "$(kit_digest "$OVR")" ]; then
    # Interrupted between the two moves: the override is still the pre-rollback one; its move is finished below.
    cmp -s "$OVR" "$B/override.pre-rollback.yml" && [ -f "$MARK.ovr" ] && [ "$(kit_digest "$MARK.ovr")" = "$(sed -n 2p "$MARK")" ] \
      || die "committed_override_changed_since_the_interrupted_run (compare with $B/override.pre-rollback.yml by hand)"
    RESUME=2
  else RESUME=1; fi
  if [ "${DRY:-0}" = 1 ]; then echo "DRY: would resume the rollback committed earlier ($MARK): $([ $RESUME = 2 ] && echo "finish the override edit, ")preflight files, current, recreate and checks; nothing changed $(kit_now)"; exit 0; fi
  echo "resuming the rollback committed earlier ($MARK): $([ $RESUME = 2 ] && echo "finishing the override edit, ")recreate and checks"
fi
[ $RESUME != 0 ] || [ "$(env_get "$ENV" COWORK_VERSION)" = "$V" ] || die live_env_not_release_${V:0:7}
[ -d "$TT/rs" ] && [ -d "$TT/core/server" ] || die "target_tree_unreadable:$TT"
[ -z "$(tail -c1 "$ENV")" ] && [ -z "$(tail -c1 "$OVR")" ] || die file_without_final_newline

if [ $RESUME = 0 ]; then
# ---- the new .env: the live one with the release keys put back ----
W=$(mktemp -d)
cp "$ENV" "$W/env"
for k in ${RKEYS//,/ }; do [[ "$k" =~ ^[A-Z][A-Z0-9_]*$ ]] || die release_key_unreadable; env_put "$W/env" "$k" "$(env_get "$B/.env" "$k")" >"$W/env.n"; mv "$W/env.n" "$W/env"; done
later=$(env_keys_differing "$B/.env" "$W/env" | tr '\n' ' ')
[ -z "$later" ] || echo "rollback_env_keeps_later_changes=[$later] (set or changed after the cutover; kept as live)"
[ -n "$later" ] || cmp -s "$W/env" "$B/.env" || die env_differs_from_backup

# ---- switches the target cannot run ----
# The key as a whole word in the front's source (bins/*/src, crates/*/src; never tests/).
names_in_front() { local f; while IFS= read -r f; do grep -qswF -- "$1" "$f" && return 0; done < <({ find "$TT"/rs/bins/*/src "$TT"/rs/crates/*/src -type f -name '*.rs' 2>/dev/null || true; } | LC_ALL=C sort); return 1; }
rows_hold() { local k p s
  while read -r k p s; do
    case "$k" in '' | '#'*) continue ;; esac; [ "$k" = "$1" ] || continue
    [ -f "$TT/$p" ] || return 1; [ -z "$s" ] || grep -qF -- "$s" "$TT/$p" || return 1
  done <"$HERE/switch-code.txt"; return 0; }
unsup=; stale=
cp "$OVR" "$W/ovr"
while read -r k _; do
  case "$k" in '' | '#'*) continue ;; esac
  v=$(env_get "$W/env" "$k")
  if [ "$v" = - ] || [ -z "$v" ]; then
    ovr_block "$OVR" web | grep -qxF -- "$(ovr_line "$k")" && stale="$stale$k "
    continue
  fi
  names_in_front "$k" && rows_hold "$k" && continue
  unsup="$unsup$k "
  if [ $DROP = 1 ]; then env_put "$W/env" "$k" - >"$W/env.n"; mv "$W/env.n" "$W/env"; ovr_drop "$W/ovr" web "$k" >"$W/ovr.n"; mv "$W/ovr.n" "$W/ovr"; fi
done <"$HERE/web-switches.txt"
[ -z "$stale" ] || echo "stale_override_lines=[$stale] (no .env line: they resolve to empty = off; rollback-switch.sh cannot remove them, edit by hand only with the owner)"
if [ -n "$unsup" ]; then
  if [ $DROP = 1 ]; then echo "rollback_drops_unsupported_switches=[$unsup] (.env line and web override line removed: off on ${OV:0:7}; update LIVE-SWITCHES.md)"
  else die "target_cannot_run_switches=[$unsup] (the target ${OV:0:7} has no code for them: roll them back first with rollback-switch.sh, or pass --drop-unsupported)"; fi
fi
# Only the release keys and the dropped switches may differ from the live .env; the override only by the dropped lines.
for k in $(env_keys_differing "$ENV" "$W/env"); do [[ ",$RKEYS," == *",$k,"* || " $unsup" == *" $k "* ]] || die "env_edit_beyond_release_keys:$k"; done
[ "$(diff "$OVR" "$W/ovr" | grep -c '^[<>]' || true)" = "$(diff "$OVR" "$W/ovr" | grep -c '^< ' || true)" ] || die override_edit_adds_lines
if [ "${DRY:-0}" = 1 ]; then
  echo "DRY: .env keys that would change: [$(env_keys_differing "$ENV" "$W/env" | tr '\n' ' ')]; override lines removed: $(diff "$OVR" "$W/ovr" | grep -c '^< ' || true); preflight files: [${PFILES//,/ }]; current -> releases/$OV"
  echo "DRY: nothing changed, web not recreated $(kit_now)"; exit 0
fi

# ---- commit (the marker first, with the bytes about to be written, so an interrupted run can be resumed) ----
cp -p "$ENV" "$B/.env.pre-rollback"; cp -p "$OVR" "$B/override.pre-rollback.yml"
docker inspect --format '{{.Id}} {{.State.StartedAt}}' "$EG" >"$MARK.egress" 2>/dev/null || : >"$MARK.egress"
printf '%s\n' "$later" >"$MARK.later"; [ $DROP = 1 ] && printf '%s\n' "$unsup" >"$MARK.dropped" || : >"$MARK.dropped"; cp "$W/ovr" "$MARK.ovr"
{ kit_digest "$W/env"; kit_digest "$W/ovr"; } >"$MARK"
T=$(mktemp "$A/config/.rb.XXXXXX"); cp "$W/env" "$T"; chmod --reference="$ENV" "$T"; chown --reference="$ENV" "$T"; mv -Tf "$T" "$ENV"; committed=1
if ! cmp -s "$OVR" "$W/ovr"; then TO=$(mktemp "$C/.rb.XXXXXX"); cp "$W/ovr" "$TO"; chmod --reference="$OVR" "$TO"; chown --reference="$OVR" "$TO"; mv -Tf "$TO" "$OVR"; fi
eg_before=$(cat "$MARK.egress")
else
  committed=1; later=$(cat "$MARK.later" 2>/dev/null || true); unsup=$(cat "$MARK.dropped" 2>/dev/null || true)
  if [ $RESUME = 2 ]; then TO=$(mktemp "$C/.rb.XXXXXX"); cp "$MARK.ovr" "$TO"; chmod --reference="$OVR" "$TO"; chown --reference="$OVR" "$TO"; mv -Tf "$TO" "$OVR"; echo "override edit finished"; fi
  # The egress container may have restarted since the interruption (a host reboot): name it, and check from now on.
  eg_before=$(docker inspect --format '{{.Id}} {{.State.StartedAt}}' "$EG" 2>/dev/null || true)
  [ "$eg_before" = "$(cat "$MARK.egress" 2>/dev/null)" ] || echo "NOTE: $EG restarted or changed since the interrupted run (before this resume; not by it)"
fi
for f in ${PFILES//,/ }; do cp -p "$PF.bak.before-$KID/$f" "$PF/$f"; done
ln -sfnT "$A/releases/$OV" "$A/current.new.$$"; mv -Tf "$A/current.new.$$" "$A/current"
echo "files committed $(kit_now); web up"
timeout 300 bash "$PF/up.sh" --env-file "$ENV" --project-directory "$C" -f "$BASE" -f "$OVR" --profile code -- -d --no-build --pull never --no-deps --wait --wait-timeout 150 web
[ "$(docker inspect --format '{{.Image}}' "$WEB")" = "$OID" ] || die not_old_image
[ "$(docker inspect --format '{{.State.Health.Status}}' "$WEB")" = healthy ] || die not_healthy
rd=$(docker exec "$WEB" node -e 'fetch("http://127.0.0.1:8021/api/ready",{signal:AbortSignal.timeout(5000)}).then(r=>r.text()).then(t=>console.log(t))') || rd=
grep -qF "\"version\":\"$OV\"" <<<"$rd" || die ready_version
[ "$(docker inspect --format '{{.Id}} {{.State.StartedAt}}' "$EG" 2>/dev/null || true)" = "$eg_before" ] || die egress_changed
# The old image over the same key directory: its native issuer kept the state and reached the proxy.
ok=0; for _ in $(seq 1 45); do L=$(docker logs "$WEB" 2>&1) || L=; grep -qF '"event":"egress.control_ready"' <<<"$L" && { ok=1; break; }; sleep 2; done; [ $ok = 1 ] || die old_image_no_control_ready
[ "$(stat -c '%u:%g:%a:%h:%F' "$KD/current.key")" = "$(stat -c '%u:%g' "$KD"):440:1:regular file" ] || die key_shape_after_old_image
[ -d "$KD/issuer" ] && [ -f "$KD/issuer/code-egress-issuer.json" ] || die issuer_state_missing
OL=$(docker logs "$WEB" 2>&1) || OL=
[ "$(grep -F '"event":"egress.issuer_started"' <<<"$OL" | grep -c '"key":"kept"')" = 1 ] || die old_issuer_not_kept
[ "$(grep -cE '"event":"egress\.(issuer_unavailable|key_superseded|control_rekey_refused|control_rekeyed)"' <<<"$OL" || true)" = 0 ] || die old_issuer_refusal_or_rekey
if [ -s "$B/key-before.sha256" ]; then [ "$(sha256sum "$KD/current.key" | cut -d' ' -f1)" = "$(cat "$B/key-before.sha256")" ] || die key_changed; fi
dropped=$(cat "$MARK.dropped" 2>/dev/null || true)
kept=$(for k in $later; do [ " $dropped" == *" $k "* ] || printf '%s ' "$k"; done)
committed=0; rm -f "$MARK" "$MARK.later" "$MARK.dropped" "$MARK.egress" "$MARK.ovr"
echo "rollback=verified image=${OID:7:12} egress_untouched=$EG old_control_ready=yes issuer=kept sqlite_restore=not_performed kept_later_keys=[$kept] dropped_switches=[$(echo $dropped)${dropped:+ }] $(kit_now)"
