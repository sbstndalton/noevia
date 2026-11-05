#!/usr/bin/env bash
# Tests deploy/tools/check-diary-image-native.sh with a fake docker on PATH (no daemon, no image).
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/check-diary-image-native-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; fi; }
REF=$(printf 'a%.0s' $(seq 1 40)); OTHER=$(printf 'b%.0s' $(seq 1 40))
mkdir -p "$work/bin" "$work/tmp"
cat > "$work/bin/docker" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALL_LOG"
case "$1" in
  rm|kill) exit 0 ;;
  run) ;;
  *) echo "unexpected docker command: $*" >&2; exit 99 ;;
esac
case "$*" in
  *"--entrypoint sh "*" -c "*)
    [ -z "${LIST_FAIL:-}" ] || exit 1
    printf '%s\n' ${MISSING:-} ;;
  *"--entrypoint /usr/local/bin/noevia-diary "*" --version")
    [ -z "${HANG:-}" ] || exec sleep 30
    [ -z "${VERSION_FAIL:-}" ] || { echo "error: unexpected argument --version" >&2; exit 2; }
    printf '%s\n' "${VERSION_OUT:-noevia-diary 0.1.0 noevia-rs $REF_PIN}" ;;
  *"--entrypoint /usr/local/bin/tenant-assertion "*" self-test") printf '%s\n' "${TA_OUT:-ok}"; [ -z "${TA_FAIL:-}" ] || exit 1 ;;
  *"--entrypoint /usr/local/bin/workspace-restore-verify "*" self-test") printf '%s\n' "${WRV_OUT:-ok}" ;;
  *) echo "unexpected docker call: $*" >&2; exit 99 ;;
esac
SHIM
chmod +x "$work/bin/docker"
# t <name> <ref> [ENV=value ...]: runs the check with the fake docker; sets rc, out, err, calls.
t() {
  local image=$1 ref=$2; shift 2
  : > "$work/calls"
  env PATH="$work/bin:$PATH" TMPDIR="$work/tmp" CALL_LOG="$work/calls" REF_PIN="$REF" "$@" bash "$here/check-diary-image-native.sh" "$image" "$ref" >"$work/out" 2>"$work/err"; rc=$?
}
IMG=cowork-diary:abc1234-candidate
t $IMG $REF
check "all binaries present, the right ref and ok self-tests pass" '[ $rc -eq 0 ] && grep -q "diary image native provenance ok" "$work/out"'
check "four container runs: listing, --version and two self-tests" '[ "$(grep -c "^run " "$work/calls")" -eq 4 ]'
check "every container runs with --network none and a stop timeout" '[ "$(grep "^run " "$work/calls" | grep -c -- "--network none")" -eq 4 ] && [ "$(grep "^run " "$work/calls" | grep -c -- "--stop-timeout 5")" -eq 4 ]'
check "no container mounts a volume, passes env or reads an env file" '! grep -qE -- "(^| )(-v|--volume|--mount|-e|--env|--env-file|--privileged|--network host)( |=)" "$work/calls"'
check "docker is used only to run, kill and remove containers" '! grep -vE "^(run|kill|rm) " "$work/calls" | grep -q .'
check "each container has its own diary-prov-<pid>-<n> name" '[ "$(grep "^run " "$work/calls" | sed -n "s/.*--name \(diary-prov-[0-9]*-[0-9]*\) .*/\1/p" | sort -u | wc -l | tr -d " ")" -eq 4 ]'
check "every named container is removed again (rm -f)" 'for n in $(grep "^run " "$work/calls" | sed -n "s/.*--name \(diary-prov-[0-9]*-[0-9]*\) .*/\1/p"); do grep -q "^rm -f $n\$" "$work/calls" || exit 1; done'
check "nothing is left in the temp directory" '[ -z "$(ls -A "$work/tmp")" ]'
check "the listing names noevia-diary and the other native binaries at /usr/local/bin" 'head -1 "$work/calls" | grep -q "noevia-diary" && head -1 "$work/calls" | grep -q "diary-workspace-export" && head -1 "$work/calls" | grep -q "/usr/local/bin/"'
for b in noevia-diary tenant-assertion diary-workspace-export workspace-restore-verify; do
  t $IMG $REF MISSING="$b"
  check "a missing or non-executable $b fails and is named" '[ $rc -ne 0 ] && grep -q "$b" "$work/err"'
done
t $IMG $REF MISSING="diary-score-gap diary-backup-run"
check "several missing binaries are all named" '[ $rc -ne 0 ] && grep -q "diary-score-gap" "$work/err" && grep -q "diary-backup-run" "$work/err"'
t $IMG $REF LIST_FAIL=1
check "an unlistable image fails" '[ $rc -ne 0 ] && grep -q "could not list" "$work/err"'
t $IMG $REF VERSION_FAIL=1
check "a binary without --version (built before it embeds its ref) fails" '[ $rc -ne 0 ] && grep -q "built before it embeds" "$work/err"'
t $IMG $REF VERSION_OUT="noevia-diary 0.1.0 noevia-rs $OTHER"
check "a different noevia-rs ref fails and is shown" '[ $rc -ne 0 ] && grep -q "$OTHER" "$work/err" && grep -q "not exactly one line" "$work/err"'
t $IMG $REF VERSION_OUT="noevia-diary 0.1.0"
check "a version line with no ref fails" '[ $rc -ne 0 ] && grep -q "not exactly one line" "$work/err"'
vneg() { t $IMG $REF VERSION_OUT="$2"; check "version output $1 fails" '[ $rc -ne 0 ] && grep -q "not exactly one line" "$work/err"'; }
vneg "with the pinned ref and a conflicting ref on one line" "noevia-diary 0.1.0 noevia-rs $REF noevia-rs $OTHER"
vneg "with the pinned ref, a comma and another ref" "noevia-diary 0.1.0 noevia-rs $REF,$OTHER"
vneg "with a conflicting ref then the pinned one after a comma" "noevia-diary 0.1.0 noevia-rs $OTHER,$REF"
vneg "with a trailing comma" "noevia-diary 0.1.0 noevia-rs $REF,"
vneg "with a comma after the version" "noevia-diary 0.1.0, noevia-rs $REF"
vneg "with the ref embedded in a longer word" "noevia-diary 0.1.0 noevia-rs x$REF"
vneg "with the ref followed by more characters" "noevia-diary 0.1.0 noevia-rs ${REF}0"
vneg "with the ref as a prefix-suffixed token" "noevia-diary 0.1.0 noevia-rs built-from-$REF-extra"
vneg "with the ref in a longer sentence" "noevia-diary 0.1.0 noevia-rs $REF is the build"
vneg "with extra words after the ref" "noevia-diary 0.1.0 noevia-rs $REF extra"
vneg "with extra words before" "banner noevia-diary 0.1.0 noevia-rs $REF"
vneg "with a leading space" " noevia-diary 0.1.0 noevia-rs $REF"
vneg "with a trailing space" "noevia-diary 0.1.0 noevia-rs $REF "
vneg "with two spaces" "noevia-diary  0.1.0 noevia-rs $REF"
vneg "with an uppercase ref" "noevia-diary 0.1.0 noevia-rs $(printf 'A%.0s' $(seq 1 40))"
vneg "with a truncated ref" "noevia-diary 0.1.0 noevia-rs ${REF:0:39}"
vneg "with a version that does not start with a digit" "noevia-diary v0.1.0 noevia-rs $REF"
vneg "with a second line carrying a conflicting ref" "noevia-diary 0.1.0 noevia-rs $REF
noevia-diary 0.1.0 noevia-rs $OTHER"
vneg "with a banner line before the version line" "starting
noevia-diary 0.1.0 noevia-rs $REF"
vneg "with a carriage return" "noevia-diary 0.1.0 noevia-rs $REF$(printf '\r')"
t $IMG $REF VERSION_OUT="noevia-diary 0.1.0-rc.1+build_5 noevia-rs $REF"
check "a semver-looking version with pre-release and build parts is accepted" '[ $rc -eq 0 ]'
t $IMG $REF TA_OUT="not ok"
check "a self-test that does not answer ok fails" '[ $rc -ne 0 ] && grep -q "tenant-assertion self-test did not answer ok" "$work/err"'
t $IMG $REF TA_FAIL=1
check "a failing self-test fails" '[ $rc -ne 0 ] && grep -q "self-test failed" "$work/err"'
t $IMG $REF WRV_OUT="nope"
check "workspace-restore-verify must answer ok too" '[ $rc -ne 0 ]'
t $IMG $REF HANG=1 CHECK_DIARY_TIMEOUT=1
check "a container that outlives its deadline is killed and the check fails" '[ $rc -ne 0 ] && grep -q "outlived its 1s deadline" "$work/err"'
check "the timed-out container is killed and removed by name" 'n=$(grep -- "--version" "$work/calls" | sed -n "s/.*--name \(diary-prov-[0-9]*-[0-9]*\) .*/\1/p"); [ -n "$n" ] && grep -q "^kill $n\$" "$work/calls" && grep -q "^rm -f $n\$" "$work/calls"'
check "no later container is started after a timeout" '[ "$(grep -c "^run " "$work/calls")" -eq 2 ]'
check "nothing is left in the temp directory after a timeout" '[ -z "$(ls -A "$work/tmp")" ]'
: > "$work/calls"
env PATH="$work/bin:$PATH" TMPDIR="$work/tmp" CALL_LOG="$work/calls" REF_PIN="$REF" HANG=1 bash "$here/check-diary-image-native.sh" $IMG $REF >"$work/out" 2>"$work/err" &
cpid=$!
for _ in $(seq 1 100); do grep -q -- "--version" "$work/calls" && break; sleep 0.1; done
kill -TERM "$cpid"; wait "$cpid"; rc=$?
check "a terminated check exits 143" '[ $rc -eq 143 ]'
check "a terminated check removes the container that was running" 'n=$(grep -- "--version" "$work/calls" | sed -n "s/.*--name \(diary-prov-[0-9]*-[0-9]*\) .*/\1/p"); [ -n "$n" ] && grep -q "^rm -f $n\$" "$work/calls"'
check "a terminated check leaves nothing in the temp directory" '[ -z "$(ls -A "$work/tmp")" ]'
check "a terminated check starts no further container" '[ "$(grep -c "^run " "$work/calls")" -eq 2 ]'
t $IMG $REF CHECK_DIARY_TIMEOUT=0
check "a zero or non-numeric deadline is refused before docker runs" '[ $rc -eq 2 ] && [ ! -s "$work/calls" ]'
t $IMG $REF CHECK_DIARY_TIMEOUT=abc
check "a non-numeric deadline is refused" '[ $rc -eq 2 ]'
t 'bad image;id' $REF
check "an image name with shell characters is refused before docker runs" '[ $rc -eq 2 ] && [ ! -s "$work/calls" ]'
t $IMG "${REF:0:39}"
check "a non-40-hex pin is refused before docker runs" '[ $rc -eq 2 ] && [ ! -s "$work/calls" ]'
t $IMG "$(printf 'A%.0s' $(seq 1 40))"
check "an uppercase pin is refused" '[ $rc -eq 2 ]'
check "the binary list is the overlay's native_bin_names list" \
  '[ "$(sed -n "s/^native_bins=\"\(.*\)\"$/\1/p" "$here/check-diary-image-native.sh" | tr " " "\n" | sort | tr "\n" " ")" = "$(bash -c ". <(sed -n \"/^# BEGIN rust-leaves/,/^# END rust-leaves/p\" \"$here/../examples/diary-overlay.sh\"); native_bin_names" | sort | tr "\n" " ")" ]'
echo "passed $passes, failed $fails"
[ "$fails" -eq 0 ]
