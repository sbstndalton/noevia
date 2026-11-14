#!/usr/bin/env bash
# Tests deploy/release-kit/{switch.sh,rollback-switch.sh,rollback-web.sh,stamp.sh} against fixtures in a temporary
# directory: a fake docker/curl/up.sh/date (tests/fake/) keeps container state in files. No host, no container.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"; kit="$(dirname "$here")"
work="$(mktemp -d "${TMPDIR:-/tmp}/release-kit-web.XXXXXX")"; trap 'rm -rf "$work"' EXIT
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; printf '%s\n' "${out:-}" | sed 's/^/    | /' | tail -25; fi; }
export PATH="$here/fake:$PATH"
V=1111111111111111111111111111111111111111; OV=2222222222222222222222222222222222222222
NID=sha256:$(printf 'a%.0s' {1..64}); OID=sha256:$(printf 'b%.0s' {1..64}); SECRET=qa-secret-value-never-printed
T0=$(/usr/bin/date -u -d 2026-11-20T12:00:00Z +%s)

# setup <name>: a fresh server layout under $work/<name> (appdata A, Compose dir C, flips dir F, kit copy K, FAKE state).
setup() {
  S=$work/$1; A=$S/appdata; C=$S/compose; F=$A/release-prep/flips; K=$S/kit; export FAKE=$S/fake
  mkdir -p "$A/config" "$A/tools/preflight" "$A/egress-control/issuer" "$C" "$F" "$K" "$FAKE/c" "$FAKE/img" "$A/releases/$OV" "$A/releases/$V"
  cp "$kit"/*.sh "$kit"/*.txt "$K/"; cp "$here/fake/up.sh" "$A/tools/preflight/up.sh"
  printf 'echo check\n' >"$A/tools/preflight/check.php"; printf 'echo dmc\n' >"$A/tools/preflight/diary-models-check.sh"
  echo "$T0" >"$FAKE/now"
  printf 'key-bytes\n' >"$A/egress-control/current.key"; chmod 440 "$A/egress-control/current.key"; echo '{}' >"$A/egress-control/issuer/code-egress-issuer.json"
  printf 'COWORK_VERSION=%s\nQA_TOKEN=%s\nDIARY_VERSION=qa-diary\n' "$V" "$SECRET" >"$A/config/.env"
  cat >"$C/docker-compose.yml" <<'YML'
services:
  web:
    image: cowork-web:${COWORK_VERSION}
    environment:
      COWORK_VERSION: ${COWORK_VERSION}
      QA_TOKEN: ${QA_TOKEN}
  diary:
    environment:
      DIARY_VERSION: ${DIARY_VERSION}
YML
  cat >"$C/docker-compose.override.yml" <<'YML'
services:
  web:
    environment:
      NOEVIA_RUST_STATS: ${NOEVIA_RUST_STATS:-0}
  diary:
    environment:
      LLM_EMBED_BASE_URL: ${LLM_EMBED_BASE_URL:-}
YML
  printf '%s\n' "$NID" >"$FAKE/img/cowork-web_$V"; printf '%s\n' "$OID" >"$FAKE/img/cowork-web_$OV"
  printf '#!/bin/bash\nexit "$(cat %s/gate_rc 2>/dev/null || echo 0)"\n' "$FAKE" >"$K/gate.sh"
  cat >"$K/kit.conf" <<CONF
# kit.conf of the fixture release
APPDATA=$A
COMPOSE_DIR=$C
WEB_VERSION=$V
WEB_IMAGE=$NID
GATE=$K/gate.sh
FLIPS_DIR=$F
RELEASE_ID=${V:0:7}
RELEASE_VERSION=$V
ROLLBACK_VERSION=$OV
ROLLBACK_IMAGE=$OID
CONF
  mkdir -p "$FAKE/c/cowork-egress-rs-1"; echo cowork >"$FAKE/c/cowork-egress-rs-1/Project"; echo "sha256:egress" >"$FAKE/c/cowork-egress-rs-1/Image"
  up web
}
up() { (cd "$C" && bash "$A/tools/preflight/up.sh" --env-file "$A/config/.env" -f "$C/docker-compose.yml" -f "$C/docker-compose.override.yml" -- "$1") >/dev/null; }
tick() { echo $(( $(cat "$FAKE/now") + $1 )) >"$FAKE/now"; }
at() { /usr/bin/date -u -d "$1" +%s >"$FAKE/now"; }
run() { out=$("$@" 2>&1); rc=$?; }
cenv() { awk -v k="$1" 'index($0,k"=")==1{print substr($0,length(k)+2);f=1} END{if(!f)print "-"}' "$FAKE/c/cowork-web-1/Env"; }
h() { sha256sum "$@" | cut -c1-64 | tr '\n' ' '; }
sw() { KIT_SETTLE_S=0 bash "$K/switch.sh" "$@"; }

# ---------------- switch.sh ----------------
setup s1; before=$(h "$A/config/.env" "$C/docker-compose.override.yml")
run sw NOEVIA_RUST_RETRIEVAL shadow -
check "forward flip without a DRY run is refused" '[ $rc != 0 ] && grep -q "switch_error=dry_run_first" <<<"$out" && [ "$(h "$A/config/.env" "$C/docker-compose.override.yml")" = "$before" ]'
run env DRY=1 KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_RUST_RETRIEVAL shadow -
dg=$(sed -n 's/.*CONFIRM_DRY=\([0-9a-f]\{12\}\).*/\1/p' <<<"$out")
check "DRY prints both diffs, records a digest and changes nothing" '[ $rc = 0 ] && grep -q "^> NOEVIA_RUST_RETRIEVAL=shadow" <<<"$out" && grep -qF "NOEVIA_RUST_RETRIEVAL: \${NOEVIA_RUST_RETRIEVAL:-}" <<<"$out" && [ -n "$dg" ] && [ "$(h "$A/config/.env" "$C/docker-compose.override.yml")" = "$before" ]'
check "DRY output carries the clock time, not a typed one" 'grep -q "start 2026-11-20T12:00:00Z" <<<"$out"'
run env CONFIRM_DRY=$dg KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_RUST_RETRIEVAL shadow -
check "a real run chained right after its DRY is refused (#2632)" '[ $rc != 0 ] && grep -q "dry_run_too_recent_0s" <<<"$out" && [ "$(h "$A/config/.env" "$C/docker-compose.override.yml")" = "$before" ]'
tick 61; run env CONFIRM_DRY=000000000000 KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_RUST_RETRIEVAL shadow -
check "a wrong confirmation digest is refused" '[ $rc != 0 ] && grep -q "dry_run_digest_differs" <<<"$out"'
run env CONFIRM_DRY=$dg KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_RUST_RETRIEVAL shadow -
check "the confirmed run 61 s after the DRY flips and verifies" '[ $rc = 0 ] && grep -q "^switch=verified NOEVIA_RUST_RETRIEVAL=\[shadow\]" <<<"$out" && [ "$(cenv NOEVIA_RUST_RETRIEVAL)" = shadow ]'
check "the flip wrote one .env line and one override line after the anchor" '[ "$(grep -c "^NOEVIA_RUST_RETRIEVAL=shadow$" "$A/config/.env")" = 1 ] && grep -A1 "NOEVIA_RUST_STATS:" "$C/docker-compose.override.yml" | grep -qxF "      NOEVIA_RUST_RETRIEVAL: \${NOEVIA_RUST_RETRIEVAL:-}"'
check "no .env value but the switch's own is ever printed" '! grep -qF "$SECRET" <<<"$out" && ! grep -qF "$SECRET" "$F"/switch-*.log'
run env CONFIRM_DRY=$dg KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_RUST_RETRIEVAL shadow -
check "a used confirmation cannot be replayed" '[ $rc != 0 ] && grep -qE "no_dry_run_recorded|container_value_not_old" <<<"$out"'
run bash "$K/rollback-switch.sh" NOEVIA_RUST_RETRIEVAL
check "rollback-switch.sh reads the live value and needs no DRY" '[ $rc = 0 ] && grep -q "switch NOEVIA_RUST_RETRIEVAL: \[shadow\] -> \[-\] dry=0 rollback=1" <<<"$out" && grep -q "^switch=verified NOEVIA_RUST_RETRIEVAL=\[-\]" <<<"$out"'
check "after the rollback both files are byte-identical to before the flip" '[ "$(h "$A/config/.env" "$C/docker-compose.override.yml")" = "$before" ] && [ "$(cenv NOEVIA_RUST_RETRIEVAL)" = - ]'
run bash "$K/rollback-switch.sh" NOEVIA_RUST_RETRIEVAL
check "rolling back an absent switch is refused" '[ $rc = 64 ] && grep -q "NOEVIA_RUST_RETRIEVAL_not_set" <<<"$out"'
run sw NOEVIA_UNKNOWN_SWITCH 1 -
check "a key outside web-switches.txt is refused" '[ $rc = 64 ] && grep -q key_refused <<<"$out"'
run sw NOEVIA_CHAT_EXECUTOR native:a,b -
check "a value outside the key's pattern is refused (no account lists)" '[ $rc = 64 ] && grep -q value_refused <<<"$out"'
run sw NOEVIA_RUST_MCP_CALLS - 1
check "a forward run never removes a key" '[ $rc = 64 ] && grep -q removal_needs_rollback <<<"$out"'

setup s2; at 2026-11-20T08:30:00Z
run env DRY=1 KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_RUST_MCP_CALLS 1 -
check "forward runs refuse 08:00-09:30Z" '[ $rc != 0 ] && grep -q window_utc_0830 <<<"$out"'
at 2026-11-20T09:10:00Z
run env DRY=1 ROLLBACK=1 KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_RUST_MCP_CALLS - 1
check "every step refuses inside the 04:00-04:30 New York backup window" '[ $rc != 0 ] && grep -q window_new_york_0410 <<<"$out"'

# Flip, then a web image rollback onto the old release: the switch's rollback still runs (#2636's web twin).
setup s3; run env DRY=1 KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_RUST_MCP_CALLS 1 -; dg=$(sed -n 's/.*CONFIRM_DRY=\([0-9a-f]\{12\}\).*/\1/p' <<<"$out"); tick 90
run env CONFIRM_DRY=$dg KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_RUST_MCP_CALLS 1 -
check "flip for the image-rollback case" '[ $rc = 0 ] && [ "$(cenv NOEVIA_RUST_MCP_CALLS)" = 1 ]'
sed -i "s/^COWORK_VERSION=.*/COWORK_VERSION=$OV/" "$A/config/.env"; up web
run env DRY=1 KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_RUST_DRIVE_TOOLS 1 -
check "forward flips refuse on an image that is not the kit's release" '[ $rc != 0 ] && grep -q "live_image_not_1111111" <<<"$out"'
run bash "$K/rollback-switch.sh" NOEVIA_RUST_MCP_CALLS
check "a switch rollback works on the old image and verifies its ready version" '[ $rc = 0 ] && grep -q "rollback on the live image" <<<"$out" && grep -q "ready=$OV" <<<"$out" && ! grep -q "^NOEVIA_RUST_MCP_CALLS=" "$A/config/.env" && ! grep -q NOEVIA_RUST_MCP_CALLS "$C/docker-compose.override.yml"'

# A failed recreate after the edit puts both files back and recreates web again.
setup s4; before=$(h "$A/config/.env" "$C/docker-compose.override.yml")
run env DRY=1 KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_CODE_EXECUTOR rust -; dg=$(sed -n 's/.*CONFIRM_DRY=\([0-9a-f]\{12\}\).*/\1/p' <<<"$out"); tick 70
touch "$FAKE/up_fail"; run env CONFIRM_DRY=$dg KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_CODE_EXECUTOR rust -
check "a failed recreate restores both files automatically" '[ $rc = 1 ] && grep -q "RESTORE reason=web_up_failed" <<<"$out" && grep -q "automatic_restore=complete" <<<"$out" && [ "$(h "$A/config/.env" "$C/docker-compose.override.yml")" = "$before" ]'
echo 3 >"$FAKE/gate_rc"; run env DRY=1 KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_CODE_EXECUTOR rust -
check "a forward run refuses when the idle gate is not idle" '[ $rc != 0 ] && grep -q idle_gate <<<"$out"'
rm -f "$FAKE/gate_rc"; ( exec 9>>"$F/.switch.lock"; flock 9; KIT_SETTLE_S=0 DRY=1 bash "$K/switch.sh" NOEVIA_CODE_EXECUTOR rust - >"$S/locked.out" 2>&1 ); out=$(cat "$S/locked.out")
check "a second flip while one holds the lock is refused" 'grep -q switch_error=locked <<<"$out"'
printf 'COWORK_VERSION=x\nWEB_VERSION=%s\n' "$V" >>"$K/kit.conf"; run sw NOEVIA_CODE_EXECUTOR rust -
check "a kit.conf with a repeated or unknown key is refused" '[ $rc != 0 ] && grep -qE "conf_key_unknown:COWORK_VERSION|conf_key_repeated" <<<"$out"'
printf 'GATE=$(id)\n' >"$K/kit2.conf"; run env KIT_CONF="$K/kit2.conf" KIT_SETTLE_S=0 bash "$K/switch.sh" NOEVIA_CODE_EXECUTOR rust -
check "a kit.conf value can never carry a command" '[ $rc != 0 ] && grep -q conf_line_unreadable <<<"$out"'

run bash -c ". '$kit/lib.sh'; kit_conf '$kit/kit.conf.example' && echo \$CONF_ROLLBACK_VERSION"
check "kit.conf.example parses" '[ $rc = 0 ] && [ "$out" = fedcba9876543210fedcba9876543210fedcba98 ]'

# ---------------- rollback-web.sh ----------------
# cutover <name>: the state right after release V's cutover from OV (the cutover changed COWORK_VERSION only).
cutover() {
  setup "$1"; B=$S/backup; mkdir -p "$B" "$A/tools/preflight.bak.before-${V:0:7}"
  cp "$A/tools/preflight/"{check.php,diary-models-check.sh} "$A/tools/preflight.bak.before-${V:0:7}/"
  printf 'COWORK_VERSION=%s\nQA_TOKEN=%s\nDIARY_VERSION=qa-diary\nNOEVIA_RUST_RETRIEVAL=on\n' "$OV" "$SECRET" >"$B/.env"
  cp -p "$B/.env" "$A/config/.env.bak.before-${V:0:7}"; sha256sum "$A/egress-control/current.key" | cut -d' ' -f1 >"$B/key-before.sha256"
  (cd "$B" && sha256sum .env key-before.sha256 >SHA256SUMS)
  sed "s/^COWORK_VERSION=.*/COWORK_VERSION=$V/" "$B/.env" >"$A/config/.env"
  awk '{print} /NOEVIA_RUST_STATS:/{print "      NOEVIA_RUST_RETRIEVAL: ${NOEVIA_RUST_RETRIEVAL:-}"}' "$C/docker-compose.override.yml" >"$C/o" && mv "$C/o" "$C/docker-compose.override.yml"
  printf 'echo new\n' >"$A/tools/preflight/check.php"
  # The target release tree: its front reads retrieval and MCP calls; no Code executor unless asked.
  mkdir -p "$A/releases/$OV/rs/bins/noevia-server/src" "$A/releases/$OV/rs/crates" "$A/releases/$OV/core/server"
  printf 'const A: &str = "NOEVIA_RUST_RETRIEVAL";\nconst B: &str = "NOEVIA_RUST_MCP_CALLS";\n' >"$A/releases/$OV/rs/bins/noevia-server/src/config.rs"
  up web; ln -sfn "$A/releases/$V" "$A/current"
}
later() { printf '%s=%s\n' "$1" "$2" >>"$A/config/.env"; [ "${3:-}" = web ] && awk -v l="      $1: \${$1:-}" '{print} /NOEVIA_RUST_STATS:/{print l}' "$C/docker-compose.override.yml" >"$C/o" && mv "$C/o" "$C/docker-compose.override.yml"; up web; }
rbw() { run bash "$K/rollback-web.sh" "$@"; }

cutover r1; rbw "$B"
check "rollback with no later change: verified, old image, old ready version" '[ $rc = 0 ] && grep -q "^rollback=verified" <<<"$out" && [ "$(cat "$FAKE/c/cowork-web-1/Image")" = "$OID" ]'
check "with no later change the .env is byte-identical to the pre-cutover backup" 'cmp -s "$A/config/.env" "$B/.env"'
check "preflight files and current come back" '[ "$(cat "$A/tools/preflight/check.php")" = "echo check" ] && [ "$(readlink "$A/current")" = "$A/releases/$OV" ]'
check "the rollback output carries the clock time and no .env value" 'grep -q "2026-11-20T12:00:00Z" <<<"$out" && ! grep -qF "$SECRET" <<<"$out"'

cutover r2; later NOEVIA_RUST_MCP_CALLS 1 web; later DIARY_RUST_ANSWER shadow; rbw "$B"
check "later flips survive the release rollback and are named (#2633)" '[ $rc = 0 ] && grep -qF "rollback_env_keeps_later_changes=[DIARY_RUST_ANSWER NOEVIA_RUST_MCP_CALLS ]" <<<"$out" && grep -qx "NOEVIA_RUST_MCP_CALLS=1" "$A/config/.env" && grep -qx "DIARY_RUST_ANSWER=shadow" "$A/config/.env"'
check "only COWORK_VERSION went back" '[ "$(diff <(grep -v "^COWORK_VERSION=" "$A/config/.env.bak.before-${V:0:7}") <(grep -v "^COWORK_VERSION=" "$A/config/.env") | grep -c "^>")" = 2 ] && grep -qx "COWORK_VERSION=$OV" "$A/config/.env" && [ "$(cenv NOEVIA_RUST_MCP_CALLS)" = 1 ]'

cutover r3; later NOEVIA_CODE_EXECUTOR rust web; envh=$(h "$A/config/.env" "$C/docker-compose.override.yml"); : >"$FAKE/events"; rbw "$B"
check "a rollback onto a front without the Code executor refuses while NOEVIA_CODE_EXECUTOR=rust (#2638)" '[ $rc != 0 ] && grep -qF "target_cannot_run_switches=[NOEVIA_CODE_EXECUTOR ]" <<<"$out" && [ "$(h "$A/config/.env" "$C/docker-compose.override.yml")" = "$envh" ] && ! grep -q "^up" "$FAKE/events"'
DRY=1 rbw "$B" --drop-unsupported
check "DRY with --drop-unsupported names the change and changes nothing" '[ $rc = 0 ] && grep -q "DRY: .env keys that would change: \[COWORK_VERSION NOEVIA_CODE_EXECUTOR \]; override lines removed: 1" <<<"$out" && [ "$(h "$A/config/.env" "$C/docker-compose.override.yml")" = "$envh" ]'
rbw "$B" --drop-unsupported
check "--drop-unsupported removes the switch's .env and override lines, then verifies" '[ $rc = 0 ] && grep -q "dropped_switches=\[NOEVIA_CODE_EXECUTOR \]" <<<"$out" && ! grep -q NOEVIA_CODE_EXECUTOR "$A/config/.env" "$C/docker-compose.override.yml" && [ "$(cenv NOEVIA_CODE_EXECUTOR)" = - ] && grep -qx "NOEVIA_RUST_RETRIEVAL=on" "$A/config/.env"'

cutover r4; later NOEVIA_CODE_EXECUTOR rust web
printf 'fn x() { let s = Some("rust"); }\n' >"$A/releases/$OV/rs/bins/noevia-server/src/code_routes.rs"
printf 'const s = "NOEVIA_CODE_EXECUTOR";\n' >"$A/releases/$OV/rs/bins/noevia-server/src/lib.rs"; printf "x === 'NOEVIA_CODE_EXECUTOR'\n" >"$A/releases/$OV/core/server/rust-code-executor.cjs"
rbw "$B"
check "a target code_routes.rs without the switch constant still refuses (#2639: exact marker)" '[ $rc != 0 ] && grep -qF "target_cannot_run_switches=[NOEVIA_CODE_EXECUTOR ]" <<<"$out"'
printf 'pub const SWITCH: &str = "NOEVIA_CODE_EXECUTOR";\n' >"$A/releases/$OV/rs/bins/noevia-server/src/code_routes.rs"; rbw "$B"
check "a target that runs the Code executor keeps the switch" '[ $rc = 0 ] && grep -qx "NOEVIA_CODE_EXECUTOR=rust" "$A/config/.env" && grep -qF "kept_later_keys=[NOEVIA_CODE_EXECUTOR ]" <<<"$out"'

cutover r5; later NOEVIA_RUST_DRIVE_TOOLS 1 web; rbw "$B"
check "a later switch the target's front does not name is refused too (a stale line)" '[ $rc != 0 ] && grep -qF "target_cannot_run_switches=[NOEVIA_RUST_DRIVE_TOOLS ]" <<<"$out"'
sed -i '/^NOEVIA_RUST_DRIVE_TOOLS=/d' "$A/config/.env"; rbw "$B"
check "an override line without its .env line is named as stale" '[ $rc = 0 ] && grep -qF "stale_override_lines=[NOEVIA_RUST_DRIVE_TOOLS ]" <<<"$out"'

cutover r6; sed -i "s/^COWORK_VERSION=.*/COWORK_VERSION=$OV/" "$A/config/.env"; rbw "$B"
check "a live .env that does not name the release is refused" '[ $rc != 0 ] && grep -q "live_env_not_release_1111111" <<<"$out"'
cutover r7; echo tampered >>"$B/.env"; rbw "$B"
check "a backup that fails its checksums is refused" '[ $rc != 0 ] && grep -q backup_checksums <<<"$out"'
cutover r8; ( exec 9>>"$F/.switch.lock"; flock 9; bash "$K/rollback-web.sh" "$B" >"$S/locked.out" 2>&1 ); out=$(cat "$S/locked.out")
check "rollback-web.sh waits for no flip: it refuses while a flip holds the lock" 'grep -q rollback_error=locked_by_a_flip <<<"$out"'
cutover r9; rm -rf "$A/releases/$OV/rs"; rbw "$B"
check "an unreadable target tree is refused" '[ $rc != 0 ] && grep -q target_tree_unreadable <<<"$out"'

# ---------------- stamp.sh ----------------
setup t1; run bash -c "echo 'body line' | bash '$K/stamp.sh' '$S/x.GATE' GATE"
check "stamp.sh writes the clock time on the first line" '[ $rc = 0 ] && [ "$(head -1 "$S/x.GATE")" = "GATE written 2026-11-20T12:00:00Z on testhost" ] && grep -qx "body line" "$S/x.GATE"'
run bash -c "echo again | bash '$K/stamp.sh' '$S/x.GATE' GATE"
check "stamp.sh never overwrites a record" '[ $rc != 0 ] && grep -q stamp_error=exists <<<"$out"'
tick 300; run bash -c "echo more | bash '$K/stamp.sh' '$S/x.GATE' AMEND1 --append"
check "stamp.sh --append adds a clock-stamped section" '[ $rc = 0 ] && grep -qx -- "---- AMEND1 appended 2026-11-20T12:05:00Z on testhost ----" "$S/x.GATE"'
printf 'GO from the root, 2026-11-20T04:50Z\n' >"$S/y.GO"; touch -d 2026-11-20T04:38:05Z "$S/y.GO"; run bash "$K/stamp.sh" --check "$S/y.GO"
check "stamp.sh --check names a hand-written time 12 minutes off its write time" '[ $rc = 3 ] && grep -q "04:50Z is 715 s" <<<"$out"'
touch -d 2026-11-20T04:50:30Z "$S/y.GO"; run bash "$K/stamp.sh" --check "$S/y.GO"
check "stamp.sh --check passes a time within two minutes" '[ $rc = 0 ]'

echo "release-kit web: $passes passed, $fails failed"
[ "$fails" = 0 ]
