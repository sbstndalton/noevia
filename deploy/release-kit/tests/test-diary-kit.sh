#!/usr/bin/env bash
# Tests deploy/release-kit/{diary-switch.sh,diary-rollback-switch.sh,rollback-diary.sh,backup-diary.sh,
# manifest-compare.sh} against fixtures in a temporary directory (synthetic QA data; fake docker/curl/up.sh/date/sleep in
# tests/fake/). No host, no container, no Diary data.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"; kit="$(dirname "$here")"
work="$(mktemp -d "${TMPDIR:-/tmp}/release-kit-diary.XXXXXX")"; trap 'chmod -R u+rwX "$work" 2>/dev/null; rm -rf "$work"' EXIT
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; printf '%s\n' "${out:-}" | sed 's/^/    | /' | tail -25; fi; }
export PATH="$here/fake:$PATH" KIT_SETTLE_S=0 KIT_BACKUP_SPARE_BYTES=0
V=3333333333333333333333333333333333333333; OLD_TAG=4444444; WV=1111111111111111111111111111111111111111
CAND=sha256:$(printf 'c%.0s' {1..64}); OLD=sha256:$(printf 'd%.0s' {1..64}); WID=sha256:$(printf 'a%.0s' {1..64})
SECRET=qa-secret-value-never-printed; U1=0f0f0f0f-0000-4000-8000-000000000a01
T0=$(/usr/bin/date -u -d 2026-11-20T12:00:00Z +%s)
setup() {
  S=$work/$1; A=$S/appdata; C=$S/compose; F=$A/release-prep/flips; K=$S/kit; BR=$S/backups; export FAKE=$S/fake
  mkdir -p "$A/config" "$A/tools/preflight" "$A/state/diary/users/$U1" "$C" "$F" "$K" "$BR" "$FAKE/c" "$FAKE/img"
  cp "$kit"/*.sh "$kit"/*.txt "$K/"; cp "$here/fake/up.sh" "$A/tools/preflight/up.sh"; echo "$T0" >"$FAKE/now"
  printf 'qa index\n' >"$A/state/diary/users/$U1/managed-index.db"; printf 'qa diary\n' >"$A/state/diary/users/$U1/managed-diary.db"
  printf '# QA synthetic entry\n' >"$A/state/diary/users/$U1/2026-11-20.md"
  printf 'COWORK_VERSION=%s\nQA_TOKEN=%s\nDIARY_VERSION=%s\nNOEVIA_CODE_EXECUTOR=rust\n' "$WV" "$SECRET" "$V" >"$A/config/.env"
  cat >"$C/docker-compose.yml" <<'YML'
services:
  web:
    environment:
      COWORK_VERSION: ${COWORK_VERSION}
  diary:
    environment:
      DIARY_VERSION: ${DIARY_VERSION}
      WORKSPACE_RESTORE_VERIFY_IMPL: ${WORKSPACE_RESTORE_VERIFY_IMPL:-}
YML
  cat >"$C/docker-compose.override.yml" <<'YML'
services:
  web:
    environment:
      NOEVIA_RUST_STATS: ${NOEVIA_RUST_STATS:-0}
      NOEVIA_CODE_EXECUTOR: ${NOEVIA_CODE_EXECUTOR:-}
  diary:
    environment:
      LLM_EMBED_BASE_URL: ${LLM_EMBED_BASE_URL:-}
YML
  printf '%s\n' "$CAND" >"$FAKE/img/cowork-diary_$V"; printf '%s\n' "$OLD" >"$FAKE/img/cowork-diary_$OLD_TAG"; printf '%s\n' "$WID" >"$FAKE/img/cowork-web_$WV"
  cat >"$K/kit.conf" <<CONF
APPDATA=$A
COMPOSE_DIR=$C
FLIPS_DIR=$F
DIARY_VERSION=$V
DIARY_IMAGE=$CAND
DIARY_OLD_TAG=$OLD_TAG
DIARY_OLD_IMAGE=$OLD
BACKUP_ROOT=$BR
CONF
  up web; up diary
}
up() { (cd "$C" && bash "$A/tools/preflight/up.sh" --env-file "$A/config/.env" -f "$C/docker-compose.yml" -f "$C/docker-compose.override.yml" -- "$1") >/dev/null; }
tick() { echo $(( $(cat "$FAKE/now") + $1 )) >"$FAKE/now"; }
run() { out=$("$@" 2>&1); rc=$?; }
cval() { awk -v k="$1" 'index($0,k"=")==1{print substr($0,length(k)+2);f=1} END{if(!f)print "-"}' "$FAKE/c/cowork-diary-1/Env"; }
h() { sha256sum "$@" | cut -c1-64 | tr '\n' ' '; }
dg() { sed -n 's/.*CONFIRM_DRY=\([0-9a-f]\{12\}\).*/\1/p' <<<"$out"; }
flip() { run env DRY=1 bash "$K/diary-switch.sh" "$@"; local d; d=$(dg); tick 75; run env CONFIRM_DRY="$d" bash "$K/diary-switch.sh" "$@"; }
envh() { h "$A/config/.env" "$C/docker-compose.override.yml"; }

# ---------------- diary-switch.sh ----------------
setup d1; before=$(envh)
run bash "$K/diary-switch.sh" DIARY_RUST_ANSWER shadow -
check "a Diary flip without a DRY run is refused (#2632)" '[ $rc != 0 ] && grep -q dry_run_first <<<"$out" && [ "$(envh)" = "$before" ]'
run env DRY=1 bash "$K/diary-switch.sh" DIARY_RUST_ANSWER shadow -; d=$(dg)
run env CONFIRM_DRY="$d" bash "$K/diary-switch.sh" DIARY_RUST_ANSWER shadow -
check "a Diary flip chained right after its DRY is refused" '[ $rc != 0 ] && grep -q dry_run_too_recent <<<"$out" && [ "$(envh)" = "$before" ]'
tick 61; run env CONFIRM_DRY="$d" bash "$K/diary-switch.sh" DIARY_RUST_ANSWER shadow -
check "the confirmed flip verifies with the Rust process running" '[ $rc = 0 ] && grep -q "^switch=verified DIARY_RUST_ANSWER=\[shadow\].*rust_process=1" <<<"$out" && [ "$(cval DIARY_RUST_ANSWER)" = shadow ]'
check "the flip wrote one .env line and one line in the override diary block" 'grep -qx "DIARY_RUST_ANSWER=shadow" "$A/config/.env" && grep -A1 "LLM_EMBED_BASE_URL:" "$C/docker-compose.override.yml" | grep -qxF "      DIARY_RUST_ANSWER: \${DIARY_RUST_ANSWER:-}"'
check "no .env value but the switch's own is printed" '! grep -qF "$SECRET" <<<"$out"'
run bash "$K/diary-rollback-switch.sh" DIARY_RUST_ANSWER
check "diary-rollback-switch.sh puts both files back byte for byte" '[ $rc = 0 ] && [ "$(envh)" = "$before" ] && [ "$(cval DIARY_RUST_ANSWER)" = - ]'
flip DIARY_RUST_INDEX on -
check "a forward flip that skips a step is refused" '[ $rc = 64 ] && grep -q value_refused <<<"$out"'
flip DIARY_RUST_WRITES "$U1,$U1" -
check "DIARY_RUST_WRITES refuses a list of tenants" '[ $rc = 64 ] && grep -q value_refused <<<"$out"'
flip DIARY_RUST_ROUTES /api/health,/api/secret -
check "DIARY_RUST_ROUTES refuses a route outside the Rust-served set" '[ $rc = 64 ]'
flip DIARY_BACKUP_IMPL rust python
check "a leaf flip from python checks the live value first" '[ $rc != 0 ] && grep -q container_value_not_old <<<"$out"'
flip DIARY_BACKUP_IMPL rust -
check "a leaf flip verifies" '[ $rc = 0 ] && [ "$(cval DIARY_BACKUP_IMPL)" = rust ] && [ "$(cat "$F/diary/state/DIARY_BACKUP_IMPL.before")" = - ]'
flip WORKSPACE_RESTORE_VERIFY_IMPL rust -
check "a key the base Compose file maps is edited in .env only" '[ $rc = 0 ] && ! grep -q WORKSPACE_RESTORE_VERIFY_IMPL "$C/docker-compose.override.yml" && [ "$(cval WORKSPACE_RESTORE_VERIFY_IMPL)" = rust ]'
printf '%s\n' '2026-11-20T11:59:00Z "POST /api/day HTTP/1.1" 200' >"$FAKE/c/cowork-diary-1/logs"
run env DRY=1 bash "$K/diary-switch.sh" DIARY_RUST_INDEX shadow -
check "a forward flip waits for an idle Diary and gives up after 5 minutes" '[ $rc != 0 ] && grep -q not_idle_5min <<<"$out"'
run bash "$K/diary-rollback-switch.sh" DIARY_BACKUP_IMPL
check "a rollback proceeds while the Diary is busy" '[ $rc = 0 ] && grep -q gate_not_idle_rollback_proceeds <<<"$out" && [ "$(cval DIARY_BACKUP_IMPL)" = - ]'

# #2636: flips, then a Diary image rollback that keeps the switch lines: the switch rollbacks still run on the old image.
setup d2; before=$(envh); flip DIARY_RUST_ANSWER shadow -; flip DIARY_RUST_INDEX shadow -
mkdir -p "$S/b"; diary_bk() { (cd "$A/state/diary" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum) >"$S/b/manifest-stop.sha"; cp -a "$A/state/diary" "$S/b/state-diary"; }; diary_bk
run bash "$K/rollback-diary.sh" "$S/b" --keep-switches
check "rollback-diary.sh --keep-switches leaves the switch lines (old behaviour, on request)" '[ $rc = 0 ] && grep -q "^DIARY_RUST_ANSWER=shadow" "$A/config/.env" && [ "$(cat "$FAKE/c/cowork-diary-1/Image")" = "$OLD" ]'
flip DIARY_RUST_ROUTES /api/health -
check "forward flips refuse on the previous image" '[ $rc != 0 ] && grep -q live_image_not_release_3333333 <<<"$out"'
run bash "$K/diary-rollback-switch.sh" DIARY_RUST_INDEX
check "after an image rollback the switch rollback runs and skips the image checks (#2636)" '[ $rc = 0 ] && grep -q "image, version and Rust-process checks skipped" <<<"$out" && grep -q "^switch=verified DIARY_RUST_INDEX=\[-\]" <<<"$out"'
run bash "$K/diary-rollback-switch.sh" DIARY_RUST_ANSWER
check "both switch lines can be removed on the previous image; no stale line is left" '[ $rc = 0 ] && ! grep -q DIARY_RUST "$A/config/.env" "$C/docker-compose.override.yml"'

# ---------------- rollback-diary.sh ----------------
setup r1; flip DIARY_RUST_ANSWER shadow -; flip DIARY_BACKUP_IMPL rust -; flip WORKSPACE_RESTORE_VERIFY_IMPL rust -
mkdir -p "$S/b"; diary_bk; eh=$(envh); : >"$FAKE/events"
run env DRY=1 bash "$K/rollback-diary.sh" "$S/b"
check "rollback-diary.sh DRY names the keys and changes nothing" '[ $rc = 0 ] && grep -qF "switches removed: [DIARY_RUST_ANSWER DIARY_BACKUP_IMPL WORKSPACE_RESTORE_VERIFY_IMPL ]" <<<"$out" && [ "$(envh)" = "$eh" ] && ! grep -q "^up" "$FAKE/events"'
run bash "$K/rollback-diary.sh" "$S/b"
check "the image rollback removes every Diary switch line with DIARY_VERSION (#2636)" '[ $rc = 0 ] && ! grep -qE "^(DIARY_RUST_|DIARY_BACKUP_IMPL|WORKSPACE_RESTORE)" "$A/config/.env" && ! grep -qE "DIARY_RUST_ANSWER|DIARY_BACKUP_IMPL" "$C/docker-compose.override.yml" && grep -qx "DIARY_VERSION=$OLD_TAG" "$A/config/.env"'
check "web keys and web switches stay as they are" 'grep -qx "NOEVIA_CODE_EXECUTOR=rust" "$A/config/.env" && grep -qF "NOEVIA_CODE_EXECUTOR: \${NOEVIA_CODE_EXECUTOR:-}" "$C/docker-compose.override.yml" && grep -qx "QA_TOKEN=$SECRET" "$A/config/.env"'
check "the Diary runs the old image and the data matches the backup" '[ "$(cat "$FAKE/c/cowork-diary-1/Image")" = "$OLD" ] && grep -q "rollback-diary=verified" <<<"$out" && grep -q "unexplained=0" <<<"$out" && ! grep -qF "$SECRET" <<<"$out"'
echo 'qa extra' >"$A/state/diary/users/$U1/qa-unexpected.txt"; run bash "$K/rollback-diary.sh" "$S/b" --restore
check "--restore puts the backup back after an unexplained change and keeps the moved-aside data" '[ $rc = 0 ] && grep -q "restored and healthy" <<<"$out" && [ ! -e "$A/state/diary/users/$U1/qa-unexpected.txt" ] && ls -d "$A/state/diary.before-restore-"* >/dev/null'

# ---------------- backup-diary.sh and manifest-compare.sh ----------------
setup b1; : >"$FAKE/events"; run env DRY=1 bash "$K/backup-diary.sh"
check "backup-diary.sh DRY passes the gate and never stops the Diary" '[ $rc = 0 ] && grep -q "DRY: checks and idle gate passed" <<<"$out" && ! grep -q "^stop" "$FAKE/events" && [ -z "$(ls "$BR")" ]'
run bash "$K/backup-diary.sh"; BD=$(sed -n 's/.*backup=verified B=\([^ ]*\).*/\1/p' <<<"$out")
check "backup-diary.sh stops, copies, compares, archives and starts the Diary (#2635)" '[ $rc = 0 ] && [ -n "$BD" ] && [ "$(grep -c . "$FAKE/events")" = 2 ] && head -1 "$FAKE/events" | grep -q "^stop cowork-diary-1" && tail -1 "$FAKE/events" | grep -q "^start cowork-diary-1" && [ "$(cat "$FAKE/c/cowork-diary-1/Status")" = running ]'
check "the backup holds the stop manifest, an identical copy and a tested archive" '(cd "$BD" && sha256sum -c --quiet SHA256SUMS) && cmp -s "$BD/manifest-stop.sha" "$BD/manifest-copy.sha" && grep -qx config/.env "$BD/listing.txt" && [ "$(grep -c . "$BD/manifest-stop.sha")" = 3 ]'
check "backup-diary.sh prints its own hash and the clock time" 'grep -q "backup-diary.sh sha256=$(sha256sum "$K/backup-diary.sh" | cut -c1-64)" <<<"$out" && grep -q "start 2026-11-20T12:00:00Z" <<<"$out" && ! grep -qF "$SECRET" <<<"$out"'
run bash "$K/manifest-compare.sh" "$BD"
check "manifest-compare.sh: the data still matches the fresh backup" '[ $rc = 0 ] && grep -q "changed=0 added=0 removed=0 unexplained=0" <<<"$out"'
echo 'qa reindex' >"$A/state/diary/users/$U1/managed-index.db"; : >"$A/state/diary/storage-gates.db"; run bash "$K/manifest-compare.sh" "$BD"
check "manifest-compare.sh accepts the expected live changes (index, gate)" '[ $rc = 0 ] && grep -q "^rehearsed   changed users/$U1/managed-index.db" <<<"$out" && grep -q "^rehearsed   added storage-gates.db" <<<"$out"'
echo '# QA edit' >>"$A/state/diary/users/$U1/2026-11-20.md"; run bash "$K/manifest-compare.sh" "$BD"
check "manifest-compare.sh names any other change UNEXPLAINED (exit 3): take a new backup" '[ $rc = 3 ] && grep -q "^UNEXPLAINED changed users/$U1/2026-11-20.md" <<<"$out"'
setup b2; printf '%s\n' '2026-11-20T11:59:00Z "PUT /api/day HTTP/1.1" 200' >"$FAKE/c/cowork-diary-1/logs"; : >"$FAKE/events"; run bash "$K/backup-diary.sh"
check "backup-diary.sh never stops a busy Diary" '[ $rc != 0 ] && grep -q not_idle_10min <<<"$out" && ! grep -q "^stop" "$FAKE/events" && [ -z "$(ls "$BR")" ]'
setup b3; printf 'qa\n' >"$A/state/diary/users/$U1/unreadable.db"; chmod 000 "$A/state/diary/users/$U1/unreadable.db"; : >"$FAKE/events"; run bash "$K/backup-diary.sh"
check "a failure while stopped starts the Diary again" '[ $rc != 0 ] && grep -q "starting cowork-diary-1 again" <<<"$out" && tail -1 "$FAKE/events" | grep -q "^start cowork-diary-1" && [ "$(cat "$FAKE/c/cowork-diary-1/Status")" = running ]'
setup b4; /usr/bin/date -u -d 2026-11-20T08:15:00Z +%s >"$FAKE/now"; run bash "$K/backup-diary.sh"
check "backup-diary.sh refuses 08:00-09:30Z" '[ $rc != 0 ] && grep -q window_utc_0815 <<<"$out"'
setup b5; ( exec 9>>"$F/.switch.lock"; flock 9; bash "$K/backup-diary.sh" >"$S/l.out" 2>&1 ); out=$(cat "$S/l.out")
check "backup-diary.sh refuses while a flip holds the shared lock" 'grep -q locked_by_a_flip <<<"$out"'

echo "release-kit diary: $passes passed, $fails failed"
[ "$fails" = 0 ]
