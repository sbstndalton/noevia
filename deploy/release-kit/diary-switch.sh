#!/bin/bash
# diary-switch.sh KEY NEW OLD : one Diary switch on the live Diary. Runs ON THE SERVER as root from the release kit
# directory (kit.conf beside it; see README.md). Replaces the per-release flips/diary-switch.sh and diary-switch-v2.sh
# with their flip-*.sh wrappers; rollbacks go through diary-rollback-switch.sh. NEW/OLD: a value, or '-' for absent.
# Allowed (anything else is refused):
#   DIARY_RUST_ANSWER  forward - -> shadow, shadow -> on        rollback on -> shadow, on|shadow -> -
#   DIARY_RUST_INDEX   forward - -> shadow, shadow -> on (only with DIARY_RUST_WRITES set)   rollback on -> shadow, on|shadow -> -
#   DIARY_RUST_ROUTES  forward - -> a comma list of the Rust-served GET routes (ROUTESET)      rollback <list> -> -
#   DIARY_RUST_WRITES  forward - -> exactly ONE tenant UUID (never a list, never all)            rollback <uuid> -> -
#   leaf *_IMPL keys   forward -|python -> rust                     rollback rust -> -|python (back to what it was)
# Mechanics: one .env line, plus one line `KEY: ${KEY:-}` in the override's diary environment when the key goes
# absent<->set (a key the base Compose file maps itself edits .env only); Compose must resolve exactly the new value and
# nothing else; Diary-only recreate through the release's up.sh call; verify; automatic restore on any failed check.
# Forward runs are bound to the live Diary release (DIARY_VERSION/DIARY_IMAGE) and need a read DRY run (#2632).
# #2636: with ROLLBACK=1 the image, DIARY_VERSION and Rust-process checks are skipped, so a switch line can always be
# removed, after a Diary image rollback too; the image must stay the one that ran before. Prints no env value except
# KEY's own (a tenant UUID is not a secret). Every time it prints comes from the clock.
set -Eeuo pipefail; umask 077; trap '' HUP PIPE
HERE=$(cd -- "$(dirname -- "$0")" && pwd); . "$HERE/lib.sh"; KIT_PREFIX=switch
KEY=${1:?KEY}; NEW=${2:?NEW or -}; OLD=${3:?OLD or -}; R=${ROLLBACK:-0}
kit_conf "${KIT_CONF:-$HERE/kit.conf}" || exit 1
A=${CONF_APPDATA:-/mnt/docker/appdata/cowork}; C=${CONF_COMPOSE_DIR:-/boot/config/plugins/compose.manager/projects/Cowork}
F=${CONF_FLIPS_DIR:-$A/release-prep/flips}; DF=${CONF_DIARY_FLIPS_DIR:-$F/diary}
DI=${CONF_DIARY:-cowork-diary-1}; WEB=${CONF_WEB:-cowork-web-1}; URL=${CONF_WEB_URL:-http://127.0.0.1:8021}
V=${CONF_DIARY_VERSION:-}; CAND_ID=${CONF_DIARY_IMAGE:-}; HEALTH=${CONF_DIARY_HEALTH_URL:-http://diary:8010/api/health}
[[ "$V" =~ ^[0-9a-f]{7,40}$ && "$CAND_ID" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo switch_error=conf_diary_binding; exit 64; }
ENV=$A/config/.env; UP=$A/tools/preflight/up.sh; BASE=$C/docker-compose.yml; OVR=$C/docker-compose.override.yml
ANCHOR_RE='^      LLM_EMBED_BASE_URL: '; CLINE=$(ovr_line "$KEY")
ROUTESET=" /api/health /api/months /api/day /api/files /api/storage-status /api/workspace-export /api/external-sources "
refuse() { echo "switch_error=value_refused ($KEY $OLD -> $NEW, rollback=$R)"; exit 64; }
routes_ok() { local r n=0; [[ "$1" =~ ^[a-z/,-]{4,200}$ ]] || return 1
  for r in ${1//,/ }; do [[ "$ROUTESET" == *" $r "* ]] || return 1; n=$((n+1)); done; [ $n -ge 1 ]; }
uuid_ok() { [[ "$1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; }
case "$KEY" in
  DIARY_RUST_ANSWER | DIARY_RUST_INDEX) case "$R:$OLD/$NEW" in 0:-/shadow | 0:shadow/on | 1:on/shadow | 1:on/- | 1:shadow/-) ;; *) refuse ;; esac ;;
  DIARY_RUST_ROUTES) if [ "$R" = 0 ]; then [ "$OLD" = - ] && routes_ok "$NEW" || refuse; else [ "$NEW" = - ] && routes_ok "$OLD" || refuse; fi ;;
  DIARY_RUST_WRITES) if [ "$R" = 0 ]; then [ "$OLD" = - ] && uuid_ok "$NEW" || refuse; else [ "$NEW" = - ] && [ "$OLD" != - ] || refuse; fi ;;
  *) [[ " $(diary_leaves) " == *" $KEY "* ]] || { echo switch_error=key_refused; exit 64; }
     case "$R:$OLD/$NEW" in 0:-/rust | 0:python/rust | 1:rust/- | 1:rust/python) ;; *) refuse ;; esac ;;
esac
STAMP=$(kit_stamp); B=$DF/bak/$KEY-$STAMP
mkdir -p -m 0700 "$DF/bak" "$DF/state"; exec </dev/null > >(tee -p -a "$DF/switch-$KEY-$STAMP.log") 2>&1
install -d -m 0700 "$F"; exec 8>>"$F/.switch.lock"; flock -n 8 || { echo switch_error=locked; exit 1; }
die() { echo "switch_error=$1"; exit 1; }; insp() { timeout 15 docker inspect --format "$2" "$1"; }
# The "no other container changed" check is scoped to the Diary's own Compose project.
PROJ=$(timeout 15 docker inspect --format '{{with index .Config.Labels "com.docker.compose.project"}}{{.}}{{end}}' "$DI")
[ -n "$PROJ" ] || die diary_not_compose_managed
ids() { { docker ps -aq --filter "label=com.docker.compose.project=$PROJ" | xargs -r docker inspect --format '{{.Name}} {{.Id}} {{.Image}} {{.State.StartedAt}} {{.State.Status}} {{.RestartCount}}' 2>/dev/null || true; } | sort; }
idcmp() { awk -v d="/$DI" 'NR==FNR{if($1!=d)b[$1]=$2" "$3" "$4" "$5" "$6;next} $1!=d{a[$1]=$2" "$3" "$4" "$5" "$6} END{for(k in b)if(!(k in a))print "removed:"k; else if(a[k]!=b[k])print "changed:"k; for(k in a)if(!(k in b))print "added:"k}' "$1" "$2"; }
cval() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$DI" | awk -v k="$1" 'index($0,k"=")==1{v=substr($0,length(k)+2);f=1} END{if(!f||v=="")print "-"; else print v}'; }
# The Rust process runs when DIARY_RUST_ANSWER is shadow|on, DIARY_RUST_INDEX is shadow|on, or ROUTES/WRITES is set.
want_rust() { local a i; a=$(cval DIARY_RUST_ANSWER); i=$(cval DIARY_RUST_INDEX)
  { [ "$a" != - ] || [ "$i" != - ] || [ "$(cval DIARY_RUST_ROUTES)" != - ] || [ "$(cval DIARY_RUST_WRITES)" != - ]; } && echo 1 || echo 0; }
rust_procs() { docker top "$DI" -eo pid,args 2>/dev/null | grep -c '[n]oevia-diary' || true; }
echo "diary switch $KEY: [$OLD] -> [$NEW] dry=${DRY:-0} rollback=$R start $(kit_now)"
kit_clock "$([ "$R" = 1 ] && echo rollback || echo forward)" || exit 1
steps() { [ "$(kit_running cutover.sh cutover-diary.sh rollback-web.sh rollback-diary.sh backup-diary.sh)" = 0 ] || die release_step_running; }
steps
IMG0=$(insp "$DI" '{{.Image}}'); DV=$(env_get "$ENV" DIARY_VERSION)
if [ "$R" != 1 ]; then
  [ "$IMG0" = "$CAND_ID" ] || die "live_image_not_release_${V:0:7}"
  [ "$DV" = "$V" ] || die env_diary_version
  [ "$(insp "$DI" '{{.State.Status}}')" = running ] || die diary_not_running
  [ "$(insp "$DI" '{{.State.Health.Status}}')" = healthy ] || die diary_not_healthy
else
  [ "$IMG0" = "$CAND_ID" ] && [ "$DV" = "$V" ] || echo "rollback on the live Diary image ${IMG0:7:12} (not this kit's release ${V:0:7}): image, version and Rust-process checks skipped (#2636)"
fi
[ -z "$(tail -c1 "$ENV")" ] && [ -z "$(tail -c1 "$OVR")" ] || die file_without_final_newline
# A rollback reads the .env line (the previous image may not hand the key to the process it runs); a flip reads both.
[ "$R" = 1 ] || [ "$(cval "$KEY")" = "$OLD" ] || die container_value_not_old
[ "$(env_get "$ENV" "$KEY")" = "$OLD" ] || die env_value_not_old
# DIARY_RUST_INDEX=on hands writer tenants' re-index to the Rust process: it needs a DIARY_RUST_WRITES tenant
[ "$KEY:$NEW" != DIARY_RUST_INDEX:on ] || [ "$(env_get "$ENV" DIARY_RUST_WRITES)" != - ] || die index_on_needs_writes
# DIARY_RUST_WRITES may not be removed while DIARY_RUST_INDEX=on (roll INDEX back to shadow first)
[ "$KEY:$NEW" != DIARY_RUST_WRITES:- ] || [ "$(env_get "$ENV" DIARY_RUST_INDEX)" != on ] || die writes_needed_by_index_on
[ "$(ovr_block "$OVR" diary | grep -cE -- "$ANCHOR_RE" || true)" = 1 ] || die override_anchor
# a key the base Compose file maps itself (`KEY: ${KEY...}` in its diary block) is edited in .env only
INBASE=$(ovr_block "$BASE" diary | BK="      $KEY: \${$KEY" awk 'index($0,ENVIRON["BK"])==1 && substr($0,length($0))=="}"{n++} END{print (n==1)?1:0}')
[ "$INBASE" = 1 ] || [ "$(grep -c -- "$KEY" "$BASE" || true)" = 0 ] || die key_in_base_compose_unexpected_form
oc=$(ovr_block "$OVR" diary | grep -cxF -- "$CLINE" || true)
if [ "$INBASE" = 1 ]; then [ "$oc" = 0 ] || die override_line_for_base_key
elif [ "$OLD" = - ]; then [ "$oc" = 0 ] || die override_line_present
else [ "$oc" = 1 ] || die override_line_missing; fi
[ "$(grep -cxF -- "$CLINE" "$OVR" || true)" = "$oc" ] || die override_line_outside_diary
# Diary idle (lib.sh diary_idle), retried up to 5 minutes; a rollback proceeds when not idle. The window and the
# release-step check are repeated after the wait.
t0=$(kit_epoch); until diary_idle "$DI"; do
  if [ "$R" = 1 ]; then echo gate_not_idle_rollback_proceeds; break; fi
  [ $(( $(kit_epoch) - t0 )) -lt 300 ] || die not_idle_5min; sleep 10; done
kit_clock "$([ "$R" = 1 ] && echo rollback || echo forward)" || exit 1; steps
install -d -m 0700 "$B"; cp -p "$ENV" "$B/.env"; cp -p "$OVR" "$B/override.yml"; cp "$BASE" "$B/base.yml"; ids >"$B/identity-before.txt"
insp "$DI" '{{.Id}} restarts={{.RestartCount}} started={{.State.StartedAt}}' >"$B/diary-before.txt"
(cd "$B" && sha256sum .env override.yml base.yml >SHA256SUMS); echo "backup=$B"
# ---- edits (temp files beside the targets, then mv) ----
T=$(mktemp "$A/config/.dsw.XXXXXX"); env_put "$B/.env" "$KEY" "$NEW" >"$T"; chmod --reference="$ENV" "$T"; chown --reference="$ENV" "$T"
dl=$(diff "$B/.env" "$T" | grep '^[<>]' || true); [ -z "$(grep -v "^[<>] $KEY=" <<<"$dl")" ] && [ -n "$dl" ] || { rm -f "$T"; die env_edit_not_one_key; }
TO=$(mktemp "$C/.dsw.XXXXXX")
had=$([ "$oc" = 1 ] && echo 1 || echo 0); need=$([ "$INBASE" = 0 ] && [ "$NEW" != - ] && echo 1 || echo 0)
if [ "$had" = 0 ] && [ "$need" = 1 ]; then awk -v re="$ANCHOR_RE" -v l="$CLINE" '/^  [A-Za-z0-9_-]+:/{s=$1} {print} s=="diary:" && $0~re{print l}' "$OVR" >"$TO"
elif [ "$had" = 1 ] && [ "$need" = 0 ]; then ovr_drop "$OVR" diary "$KEY" >"$TO"
else cp -p "$OVR" "$TO"; fi
chmod --reference="$OVR" "$TO"; chown --reference="$OVR" "$TO"
ol=$(diff "$B/override.yml" "$TO" | grep -c '^[<>]' || true); [ "$had" != "$need" ] && want=1 || want=0
[ "$ol" = "$want" ] || { rm -f "$T" "$TO"; die override_edit_not_one_line; }
cfg() { (cd "$C" && docker compose --env-file "$1" -f "$BASE" -f "$2" --profile code config --format json 2>/dev/null); }
cv=$(cfg "$T" "$TO" | jq -r --arg k "$KEY" '.services.diary.environment[$k] // "" | if .=="" then "-" else . end') || cv=ERR
[ "$cv" = "$NEW" ] || { rm -f "$T" "$TO"; die "compose_config_value_$cv"; }
cmp -s <(cfg "$ENV" "$OVR" | jq -S --arg k "$KEY" 'del(.services.diary.environment[$k])') <(cfg "$T" "$TO" | jq -S --arg k "$KEY" 'del(.services.diary.environment[$k])') \
  || { rm -f "$T" "$TO"; die compose_config_changes_beyond_key; }
DG=$(printf '%s\n' "diary-switch $KEY $NEW $OLD $R" | cat - "$B/.env" "$B/override.yml" "$T" "$TO" | kit_digest)
if [ "${DRY:-0}" = 1 ]; then
  echo "DRY: env diff:"; diff "$B/.env" "$T" | grep '^[<>]' || true; echo "DRY: override diff:"; diff "$B/override.yml" "$TO" || true
  echo "DRY: compose resolves diary $KEY=[$cv], everything else identical; nothing committed, Diary not recreated"
  rm -f "$T" "$TO"; rm -rf "$B"; [ "$R" = 1 ] || kit_dry_record "$DF" "diary-$KEY" "$DG"; exit 0
fi
if [ "$R" != 1 ]; then kit_dry_check "$DF" "diary-$KEY" "$DG" || { rm -f "$T" "$TO"; rm -rf "$B"; exit 1; }; fi
UPC=(--env-file "$ENV" --project-directory "$C" -f "$BASE" -f "$OVR" --profile code -- -d --no-build --pull never --no-deps --wait --wait-timeout 180 diary)
restore() { local why=$1; trap - ERR; set +e; echo "RESTORE reason=$why"; docker logs --tail 300 "$DI" >"$B/diary-failed.log" 2>&1
  cp -p "$B/.env" "$ENV"; cp -p "$B/override.yml" "$OVR"; cmp -s "$B/.env" "$ENV" && cmp -s "$B/override.yml" "$OVR" && echo files_restored=1
  (cd "$C" && timeout 300 bash "$UP" "${UPC[@]}") >"$B/up-restore.out" 2>&1
  echo "restore_up_rc=$? image=$(insp "$DI" '{{.Image}}' | cut -c8-19) health=$(insp "$DI" '{{.State.Health.Status}}')"
  [ "$(env_get "$ENV" "$KEY")" = "$OLD" ] && [ "$(insp "$DI" '{{.State.Health.Status}}')" = healthy ] && echo automatic_restore=complete || echo "automatic_restore=FAILED manual_recovery_required=1"; exit 1; }
trap 'restore err_line_$LINENO' ERR; trap 'restore signal_TERM' TERM; trap 'restore signal_INT' INT
mv -Tf "$T" "$ENV"; mv -Tf "$TO" "$OVR"
echo "files committed (env 1 line, override $want line); compose resolved [$cv]; diary up $(kit_now)"
t_up0=$(kit_epoch)
(cd "$C" && timeout 300 bash "$UP" "${UPC[@]}") >"$B/up-diary.out" 2>&1 || restore diary_up_failed
[ "$(insp "$DI" '{{.Image}}')" = "$IMG0" ] || restore image_changed
[ "$(insp "$DI" '{{.State.Health.Status}}')" = healthy ] || restore not_healthy
[ "$(cval "$KEY")" = "$NEW" ] || restore container_value
docker exec "$WEB" node -e "fetch('$HEALTH',{headers:{Authorization:'Bearer '+process.env.DIARY_AUTH_TOKEN}}).then(r=>process.exit(r.ok?0:1),()=>process.exit(1))" || restore web_to_diary
[ "$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "$URL/api/diary/source")" = 401 ] || restore signed_out_not_401
sleep "${KIT_SETTLE_S:-15}"; [ "$(insp "$DI" '{{.RestartCount}}')" = 0 ] && [ "$(insp "$DI" '{{.State.Status}}')" = running ] || restore restarting
if [ "$IMG0" = "$CAND_ID" ]; then
  wr=$(want_rust); n=0; ok=0; rp=x
  while [ $n -lt 20 ]; do rp=$(rust_procs)
    if [ "$wr" = 1 ] && [ "$rp" -ge 1 ]; then ok=1; break; fi
    if [ "$wr" = 0 ] && [ "$rp" = 0 ]; then ok=1; break; fi
    n=$((n+1)); sleep 3; done
  [ $ok = 1 ] || restore "rust_process_expected_${wr}_found_${rp}"
fi
DL=$(docker logs --since "$(insp "$DI" '{{.State.StartedAt}}')" "$DI" 2>&1) || DL=
[ "$(grep -cE 'DIARY_RUST_[A-Z]+: .* is not one of' <<<"$DL" || true)" = 0 ] || restore switch_value_refused_by_diary
[ "$(grep -c 'Traceback' <<<"$DL" || true)" = 0 ] || restore traceback_in_diary_log
ids >"$B/identity-after.txt"; ch=$(idcmp "$B/identity-before.txt" "$B/identity-after.txt" | tr '\n' ' '); [ -z "$ch" ] || restore "other_container_changed:$ch"
trap - ERR TERM INT
# A leaf's value before its flip, for diary-rollback-switch.sh (back to what it was).
if [[ "$KEY" == *_IMPL ]]; then if [ "$R" = 1 ]; then rm -f "$DF/state/$KEY.before"; else printf '%s\n' "$OLD" >"$DF/state/$KEY.before"; fi; fi
echo "switch=verified $KEY=[$NEW] diary=$(insp "$DI" '{{.Id}}' | cut -c1-12) image=${IMG0:7:12} restarts=0 healthy rust_process=$(rust_procs) recreate_s=$(( $(kit_epoch) - t_up0 )) backup=$B $(kit_now)"
