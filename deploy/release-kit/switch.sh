#!/bin/bash
# switch.sh KEY NEW OLD : one web port switch on the live web unit. Runs ON THE SERVER as root, from the release kit
# directory (deploy/release-kit/ copied beside its kit.conf; see README.md). Replaces the hand-made per-release
# flips-pb*/switch.sh (switch-v3 rebound by sed) and its rollback-<KEY>.sh files (rollback-switch.sh KEY).
#   Flip:      switch.sh NOEVIA_RUST_RETRIEVAL shadow -        (DRY=1 first, then CONFIRM_DRY=<digest> after reading it)
#   Rollback:  ROLLBACK=1 switch.sh NOEVIA_RUST_RETRIEVAL - shadow   (or rollback-switch.sh NOEVIA_RUST_RETRIEVAL)
#   Step back to an earlier value (on -> shadow): a forward run, with its DRY: switch.sh NOEVIA_RUST_RETRIEVAL shadow on
# NEW/OLD: a value, or '-' for absent; allowed keys and values are in web-switches.txt.
# The web environment is an explicit Compose list (no env_file), so a key in .env alone never reaches the container:
# this edits exactly ONE .env line (temp file, same owner/mode, mv) and, only when the key goes absent<->set, exactly ONE
# line `KEY: ${KEY:-}` in the override's web environment (after the anchor line). Back to '-' leaves both files
# byte-identical to before the flip. Recreates web only with the release's up.sh call (same image; --no-build --pull
# never --no-deps), verifies, and on any failed check after the edit puts both files back and recreates web again.
# Forward runs are bound to the live release (WEB_VERSION/WEB_IMAGE in kit.conf) and need a read DRY run (#2632).
# A rollback only removes a switch (NEW must be '-'): it runs on whatever image and version are live (after a web image
# rollback too, so a switch line can always be removed), needs no DRY and verifies that the image did not change. Never touches SQLite, other containers, the key directory or
# models. Prints no env value except KEY's own. Every time it prints comes from the clock.
# No `set -E`: a failure inside a $(...) check must not run the restore in that subshell (it runs once, from the check).
set -euo pipefail; umask 077; trap '' HUP PIPE
HERE=$(cd -- "$(dirname -- "$0")" && pwd); . "$HERE/lib.sh"; KIT_PREFIX=switch
KEY=${1:?KEY}; NEW=${2:?NEW or -}; OLD=${3:?OLD or -}; R=${ROLLBACK:-0}
kit_conf "${KIT_CONF:-$HERE/kit.conf}" || exit 1
A=${CONF_APPDATA:-/mnt/docker/appdata/cowork}; C=${CONF_COMPOSE_DIR:-/boot/config/plugins/compose.manager/projects/Cowork}
V=${CONF_WEB_VERSION:-}; NID=${CONF_WEB_IMAGE:-}; GATE=${CONF_GATE:-}; F=${CONF_FLIPS_DIR:-$A/release-prep/flips}
WEB=${CONF_WEB:-cowork-web-1}; EG=${CONF_EGRESS:-cowork-egress-rs-1}; URL=${CONF_WEB_URL:-http://127.0.0.1:8021}; PROJ=${CONF_PROJECT:-cowork}
[[ "$V" =~ ^[0-9a-f]{40}$ && "$NID" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo switch_error=conf_release_binding; exit 64; }
[ -n "$GATE" ] && [ -f "$GATE" ] || { echo switch_error=conf_gate_missing; exit 64; }
ENV=$A/config/.env; UP=$A/tools/preflight/up.sh; KD=$A/egress-control; BASE=$C/docker-compose.yml; OVR=$C/docker-compose.override.yml
AK=${CONF_WEB_ANCHOR_KEY:-NOEVIA_RUST_STATS}; ANCHOR_RE="^      $AK: "; CLINE=$(ovr_line "$KEY")
re=$(awk -v k="$KEY" '$1 == k { print $2; exit }' "$HERE/web-switches.txt")
[ -n "$re" ] || { echo switch_error=key_refused; exit 64; }
valid() { [ "$1" = - ] || [[ "$1" =~ $re ]]; }
valid "$NEW" && valid "$OLD" && [ "$NEW" != "$OLD" ] || { echo switch_error=value_refused; exit 64; }
# A forward run never removes a key; a rollback only removes one (it skips the DRY, the 08:00-09:30Z window and the
# release binding, so it may never set or change a value).
if [ "$R" = 1 ]; then [ "$NEW" = - ] || { echo "switch_error=rollback_only_removes (to step back to a value run a forward flip with its DRY)"; exit 64; }
else [ "$NEW" != - ] || { echo switch_error=removal_needs_rollback; exit 64; }; fi
STAMP=$(kit_stamp); B=$F/bak/$KEY-$STAMP
mkdir -p -m 0700 "$F/bak"; exec </dev/null > >(tee -p -a "$F/switch-$KEY-$STAMP.log") 2>&1
# One lock for every web flip, web rollback and Diary flip: .env and override edits never overlap.
exec 8>>"$F/.switch.lock"; flock -n 8 || { echo switch_error=locked; exit 1; }
die() { echo "switch_error=$1"; exit 1; }; insp() { timeout 15 docker inspect --format "$2" "$1"; }
# Identity of the release's Compose project only (label, or a /cowork-* name): disposable sandboxes elsewhere on the
# host start and stop at any time. A container removed between ps and inspect does not fail the listing.
ids() { { docker ps -aq | xargs -r docker inspect --format '{{.Name}} {{.Id}} {{.Image}} {{.State.StartedAt}} {{.State.Status}} {{.RestartCount}} {{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || true; } | awk -v p="$PROJ" '$7 == p || $1 ~ "^/" p "-"' | cut -d' ' -f1-6 | sort; }
idcmp() { awk -v w="/$WEB" 'NR==FNR{if($1!=w)b[$1]=$2" "$3" "$4" "$5" "$6;next} $1!=w{a[$1]=$2" "$3" "$4" "$5" "$6} END{for(k in b)if(!(k in a))print "removed:"k; else if(a[k]!=b[k])print "changed:"k; for(k in a)if(!(k in b))print "added:"k}' "$1" "$2"; }
khash() { sha256sum "$KD/current.key" | cut -d' ' -f1; }
cenv() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$WEB" | awk -v k="$KEY" 'index($0,k"=")==1{v=substr($0,length(k)+2);f=1} END{if(!f||v=="")print "-"; else print v}'; }
echo "switch $KEY: [$OLD] -> [$NEW] dry=${DRY:-0} rollback=$R start $(kit_now)"
kit_clock "$([ "$R" = 1 ] && echo rollback || echo forward)" || exit 1
[ "$(kit_running cutover.sh cutover-diary.sh rollback-web.sh rollback-diary.sh backup-diary.sh)" = 0 ] || die release_step_running
IMG0=$(insp "$WEB" '{{.Image}}'); EV=$(env_get "$ENV" COWORK_VERSION)
if [ "$R" != 1 ]; then
  [ "$IMG0" = "$NID" ] || die "live_image_not_${V:0:7}"
  [ "$EV" = "$V" ] || die env_version
else
  [ "$IMG0" = "$NID" ] && [ "$EV" = "$V" ] || echo "rollback on the live image ${IMG0:7:12} (not this kit's release ${V:0:7}): allowed for a rollback"
fi
[ "$(insp "$WEB" '{{.State.Status}}')" = running ] || die web_not_running
[ -z "$(tail -c1 "$ENV")" ] && [ -z "$(tail -c1 "$OVR")" ] || die file_without_final_newline
[ "$(cenv)" = "$OLD" ] || die container_value_not_old
[ "$(env_get "$ENV" "$KEY")" = "$OLD" ] || die env_value_not_old
[ "$(ovr_block "$OVR" web | grep -cE -- "$ANCHOR_RE" || true)" = 1 ] || die override_anchor
oc=$(ovr_block "$OVR" web | grep -cxF -- "$CLINE" || true)
[ "$(grep -cxF -- "$CLINE" "$OVR" || true)" = "$oc" ] || die override_line_outside_web
if [ "$OLD" = - ]; then [ "$oc" = 0 ] || die override_line_present; else [ "$oc" = 1 ] || die override_line_missing; fi
[ "$(grep -c -- "$KEY" "$BASE" || true)" = 0 ] || die key_in_base_compose
if [ "$R" != 1 ]; then GATE_SKIP_SWITCHES=1 timeout 90 bash "$GATE" || die idle_gate
else GATE_SKIP_SWITCHES=1 timeout 90 bash "$GATE" || echo gate_not_idle_rollback_proceeds; fi
install -d -m 0700 "$B"; cp -p "$ENV" "$B/.env"; cp -p "$OVR" "$B/override.yml"; cp "$BASE" "$B/base.yml"; ids >"$B/identity-before.txt"
khash >"$B/key-before.sha256"; insp "$WEB" '{{.Id}} restarts={{.RestartCount}} started={{.State.StartedAt}}' >"$B/web-before.txt"
(cd "$B" && sha256sum .env override.yml base.yml >SHA256SUMS); echo "backup=$B"
# ---- edits (temp files beside the targets, then mv) ----
T=$(mktemp "$A/config/.sw.XXXXXX"); env_put "$B/.env" "$KEY" "$NEW" >"$T"
chmod --reference="$ENV" "$T"; chown --reference="$ENV" "$T"
dl=$(diff "$B/.env" "$T" | grep '^[<>]' || true); [ -z "$(grep -v "^[<>] $KEY=" <<<"$dl")" ] && [ -n "$dl" ] || { rm -f "$T"; die env_edit_not_one_key; }
TO=$(mktemp "$C/.sw.XXXXXX")
if [ "$OLD" = - ]; then awk -v re="$ANCHOR_RE" -v l="$CLINE" '/^  [A-Za-z0-9_-]+:/{s=$1} {print} s=="web:" && $0~re{print l}' "$OVR" >"$TO"
elif [ "$NEW" = - ]; then ovr_drop "$OVR" web "$KEY" >"$TO"
else cp -p "$OVR" "$TO"; fi
chmod --reference="$OVR" "$TO"; chown --reference="$OVR" "$TO"
ol=$(diff "$B/override.yml" "$TO" | grep -c '^[<>]' || true); { [ "$OLD" != - ] && [ "$NEW" != - ]; } && want=0 || want=1
[ "$ol" = "$want" ] || { rm -f "$T" "$TO"; die override_edit_not_one_line; }
# The edited pair must resolve to exactly the new value for web, and nothing else may change in any service.
cfg() { (cd "$C" && docker compose --env-file "$1" -f "$BASE" -f "$2" --profile code config --format json 2>/dev/null); }
cv=$(cfg "$T" "$TO" | jq -r --arg k "$KEY" '.services.web.environment[$k] // "" | if . == "" then "-" else . end') || cv=ERR
[ "$cv" = "$NEW" ] || { rm -f "$T" "$TO"; die "compose_config_value_$cv"; }
cmp -s <(cfg "$ENV" "$OVR" | jq -S --arg k "$KEY" 'del(.services.web.environment[$k])') <(cfg "$T" "$TO" | jq -S --arg k "$KEY" 'del(.services.web.environment[$k])') \
  || { rm -f "$T" "$TO"; die compose_config_changes_beyond_key; }
DG=$(printf '%s\n' "switch $KEY $NEW $OLD $R" | cat - "$B/.env" "$B/override.yml" "$T" "$TO" | kit_digest)
if [ "${DRY:-0}" = 1 ]; then
  echo "DRY: env diff:"; diff "$B/.env" "$T" | grep '^[<>]' || true; echo "DRY: override diff:"; diff "$B/override.yml" "$TO" || true
  echo "DRY: would-be sha256 env=$(sha256sum <"$T" | cut -c1-16) override=$(sha256sum <"$TO" | cut -c1-16) (live now env=$(sha256sum <"$ENV" | cut -c1-16) override=$(sha256sum <"$OVR" | cut -c1-16))"
  echo "DRY: compose resolves web $KEY=[$cv], everything else identical; nothing committed, web not recreated"
  rm -f "$T" "$TO"; rm -rf "$B"; [ "$R" = 1 ] || kit_dry_record "$F" "switch-$KEY" "$DG"; exit 0
fi
if [ "$R" != 1 ]; then kit_dry_check "$F" "switch-$KEY" "$DG" || { rm -f "$T" "$TO"; rm -rf "$B"; exit 1; }; fi
UPC=(--env-file "$ENV" --project-directory "$C" -f "$BASE" -f "$OVR" --profile code -- -d --no-build --pull never --no-deps --wait --wait-timeout 150 web)
restore() { local why=$1; trap - ERR; set +e; echo "RESTORE reason=$why"; docker logs --tail 300 "$WEB" >"$B/web-failed.log" 2>&1
  cp -p "$B/.env" "$ENV"; cp -p "$B/override.yml" "$OVR"; cmp -s "$B/.env" "$ENV" && cmp -s "$B/override.yml" "$OVR" && echo files_restored=1
  timeout 300 bash "$UP" "${UPC[@]}" >"$B/up-restore.out" 2>&1
  echo "restore_up_rc=$? image=$(insp "$WEB" '{{.Image}}' | cut -c8-19) health=$(insp "$WEB" '{{.State.Health.Status}}') value=[$(cenv)]"
  [ "$(cenv)" = "$OLD" ] && [ "$(insp "$WEB" '{{.State.Health.Status}}')" = healthy ] && echo automatic_restore=complete || echo "automatic_restore=FAILED manual_recovery_required=1"; exit 1; }
trap 'restore err_line_$LINENO' ERR; trap 'restore signal_TERM' TERM; trap 'restore signal_INT' INT
mv -Tf "$T" "$ENV"; mv -Tf "$TO" "$OVR"
echo "files committed (env 1 line, override $want line); compose resolved [$cv]; web up $(kit_now)"
timeout 300 bash "$UP" "${UPC[@]}" >"$B/up-web.out" 2>&1 || restore web_up_failed
[ "$(insp "$WEB" '{{.Image}}')" = "$IMG0" ] || restore image_changed
[ "$(insp "$WEB" '{{.State.Health.Status}}')" = healthy ] || restore not_healthy
[ "$(cenv)" = "$NEW" ] || restore container_value
sleep 15; for n in "$WEB" "$EG"; do [ "$(insp "$n" '{{.RestartCount}}')" = 0 ] && [ "$(insp "$n" '{{.State.Status}}')" = running ] || restore "restarting_$n"; done
ok=0; for _ in $(seq 1 45); do L=$(docker logs -t "$WEB" 2>&1) || L=; read -r ta tb < <(awk '/"event":"egress.issuer_started"/{a=$1;b=""} /"event":"egress.control_ready"/&&a!=""&&b==""{b=$1} END{print a" "b}' <<<"$L"); [ -n "${tb:-}" ] && { ok=1; break; }; sleep 2; done; [ $ok = 1 ] || restore no_control_ready
DL=$(docker logs "$WEB" 2>&1) || DL=
[ "$(awk '/"event":"egress.issuer_started"/{n++; k=/"key":"kept"/} END{print n+0":"k+0}' <<<"$DL")" = 1:1 ] || restore issuer_not_kept_once
[ "$(grep -cE '"event":"egress\.(control_rekeyed|issuer_unavailable|key_superseded|control_rekey_refused)"' <<<"$DL" || true)" = 0 ] || restore issuer_refusal_or_rekey
[ "$(khash)" = "$(cat "$B/key-before.sha256")" ] || restore key_changed
[ "$R" = 1 ] && rv=$EV || rv=$V
jq -e --arg v "$rv" '.ready==true and .version==$v' <<<"$(curl -sS --max-time 5 "$URL/api/ready")" >/dev/null || restore ready_version
[ "$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "$URL/api/projects")" = 401 ] || restore auth_not_denied
ref=$(grep -cE 'must be (off, shadow or on|node, native)|needs account ids|switch.*refus' <<<"$DL" || true); [ "$ref" = 0 ] || restore switch_refused
ids >"$B/identity-after.txt"; ch=$(idcmp "$B/identity-before.txt" "$B/identity-after.txt" | tr '\n' ' '); [ -z "$ch" ] || restore "other_container_changed:$ch"
trap - ERR TERM INT
echo "switch=verified $KEY=[$NEW] web=$(insp "$WEB" '{{.Id}}' | cut -c1-12) image=${IMG0:7:12} restarts=0 healthy key=kept_no_rotation ready=$rv backup=$B $(kit_now)"
