#!/usr/bin/env bash
# Tests deploy/tools/check-diary-image-native.sh with a fake docker on PATH (no daemon, no image).
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/check-diary-image-native-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; fi; }
REF=$(printf 'a%.0s' $(seq 1 40)); OTHER=$(printf 'b%.0s' $(seq 1 40))
mkdir -p "$work/bin"
cat > "$work/bin/docker" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALL_LOG"
[ "$1" = run ] || { echo "unexpected docker command: $*" >&2; exit 99; }
case "$*" in
  *"--entrypoint sh "*" -c "*)
    [ -z "${LIST_FAIL:-}" ] || exit 1
    printf '%s\n' ${MISSING:-} ;;
  *"--entrypoint /usr/local/bin/noevia-diary "*" --version")
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
  env PATH="$work/bin:$PATH" CALL_LOG="$work/calls" REF_PIN="$REF" "$@" bash "$here/check-diary-image-native.sh" "$image" "$ref" >"$work/out" 2>"$work/err"; rc=$?
}
IMG=cowork-diary:abc1234-candidate
t $IMG $REF
check "all binaries present, the right ref and ok self-tests pass" '[ $rc -eq 0 ] && grep -q "diary image native provenance ok" "$work/out"'
check "four container runs: listing, --version and two self-tests" '[ "$(wc -l < "$work/calls")" -eq 4 ]'
check "every container runs with --network none" '[ "$(grep -c -- "--network none" "$work/calls")" -eq 4 ]'
check "no container mounts a volume, passes env or reads an env file" '! grep -qE -- "(^| )(-v|--volume|--mount|-e|--env|--env-file|--privileged|--network host)( |=)" "$work/calls"'
check "no command other than docker run is used" '! grep -v "^run " "$work/calls" | grep -q .'
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
check "a different noevia-rs ref fails and is shown" '[ $rc -ne 0 ] && grep -q "$OTHER" "$work/err" && grep -q "not the pinned" "$work/err"'
t $IMG $REF VERSION_OUT="noevia-diary 0.1.0"
check "a version line with no ref fails" '[ $rc -ne 0 ] && grep -q "none" "$work/err"'
t $IMG $REF VERSION_OUT="noevia-diary 0.1.0 noevia-rs $REF built-from $OTHER"
check "the pinned ref next to another ref fails" '[ $rc -ne 0 ]'
t $IMG $REF VERSION_OUT="noevia-diary 0.1.0 noevia-rs ${REF}0"
check "a longer hex run containing the pin is not the pin" '[ $rc -ne 0 ]'
t $IMG $REF VERSION_OUT="noevia-diary 0.1.0 noevia-rs ${REF:0:39}"
check "a truncated ref fails" '[ $rc -ne 0 ]'
t $IMG $REF TA_OUT="not ok"
check "a self-test that does not answer ok fails" '[ $rc -ne 0 ] && grep -q "tenant-assertion self-test did not answer ok" "$work/err"'
t $IMG $REF TA_FAIL=1
check "a failing self-test fails" '[ $rc -ne 0 ] && grep -q "self-test failed" "$work/err"'
t $IMG $REF WRV_OUT="nope"
check "workspace-restore-verify must answer ok too" '[ $rc -ne 0 ]'
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
