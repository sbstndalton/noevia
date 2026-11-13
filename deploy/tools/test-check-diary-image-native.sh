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
# A fake docker with a tiny daemon: containers are registered in $STATE/c (name|label) when "created" and removed by
# --rm on a normal end, by kill, or by rm -f. Killing the CLIENT of a hung run leaves its container behind, as the
# real daemon does. CREATE_DELAY makes a container appear only after that many seconds (a create still pending).
printf '%s\n' "$*" >> "$CALL_LOG"
state="$STATE/c"; touch "$state"
reg() { printf '%s|%s\n' "$1" "$2" >> "$state"; }
unreg() { grep -v "^$1|" "$state" > "$state.n" || true; mv "$state.n" "$state"; }
case "$1" in
  ps)
    [ -z "${PS_HANG:-}" ] || exec sleep 30
    [ -z "${PS_FAIL:-}" ] || exit 1
    for a in "$@"; do case "$a" in label=*) lab=${a#label=} ;; esac; done
    grep "|$lab\$" "$state" | cut -d'|' -f1 || true; exit 0 ;;
  rm)
    [ -z "${RM_HANG:-}" ] || exec sleep 30
    [ -z "${RM_FAIL:-}" ] || exit 1
    unreg "${@: -1}"; exit 0 ;;
  kill)
    [ -z "${KILL_HANG:-}" ] || exec sleep 30
    [ -n "${KILL_NOOP:-}" ] || unreg "${@: -1}"; exit 0 ;;
  run) ;;
  *) echo "unexpected docker command: $*" >&2; exit 99 ;;
esac
name=; lab=; prev=
for a in "$@"; do
  [ "$prev" = --name ] && name=$a
  [ "$prev" = --label ] && lab=$a
  prev=$a
done
[ -n "$name" ] && [ -n "$lab" ] || { echo "run without --name and --label: $*" >&2; exit 98; }
create() { if [ -n "${CREATE_DELAY:-}" ] && [[ "$*" == *"--version" ]]; then ( sleep "$CREATE_DELAY"; reg "$name" "$lab" ) & else reg "$name" "$lab"; fi; }
create "$@"
done_run() { unreg "$name"; }   # --rm: the container goes away when it ends
case "$*" in
  *"--entrypoint sh "*" -c "*)
    [ -z "${LIST_FAIL:-}" ] || { done_run; exit 1; }
    printf '%s\n' ${MISSING:-}; done_run ;;
  *"--entrypoint /usr/local/bin/noevia-diary "*" --version")
    [ -z "${HANG:-}" ] || exec sleep 30
    if [ -n "${VERSION_FAIL:-}" ]; then echo "error: unexpected argument --version" >&2; done_run; exit 2; fi
    printf '%s\n' "${VERSION_OUT:-noevia-diary 0.1.0 noevia-rs $REF_PIN}"; done_run ;;
  *"--entrypoint /usr/local/bin/tenant-assertion "*" self-test") printf '%s\n' "${TA_OUT:-ok}"; done_run; [ -z "${TA_FAIL:-}" ] || exit 1 ;;
  *"--entrypoint /usr/local/bin/workspace-restore-verify "*" self-test") printf '%s\n' "${WRV_OUT:-ok}"; done_run ;;
  *) echo "unexpected docker call: $*" >&2; done_run; exit 99 ;;
esac
SHIM
chmod +x "$work/bin/docker"
# t <image> <ref> [ENV=value ...]: runs the check with the fake docker and a fresh fake daemon; sets rc, out, err, calls.
t() {
  local image=$1 ref=$2; shift 2
  : > "$work/calls"; rm -rf "$work/state"; mkdir -p "$work/state"
  env PATH="$work/bin:$PATH" TMPDIR="$work/tmp" CALL_LOG="$work/calls" STATE="$work/state" REF_PIN="$REF" \
    CHECK_DIARY_SWEEP_PAUSE=0.3 "$@" bash "$here/check-diary-image-native.sh" "$image" "$ref" >"$work/out" 2>"$work/err"; rc=$?
}
daemon_left() { cat "$work/state/c" 2>/dev/null | grep -c . || true; }
IMG=cowork-diary:abc1234-candidate
t $IMG $REF
check "all binaries present, the right ref and ok self-tests pass" '[ $rc -eq 0 ] && grep -q "diary image native provenance ok" "$work/out"'
check "four container runs: listing, --version and two self-tests" '[ "$(grep -c "^run " "$work/calls")" -eq 4 ]'
check "every container runs with --network none and a stop timeout" '[ "$(grep "^run " "$work/calls" | grep -c -- "--network none")" -eq 4 ] && [ "$(grep "^run " "$work/calls" | grep -c -- "--stop-timeout 5")" -eq 4 ]'
check "no container mounts a volume, passes env or reads an env file" '! grep -qE -- "(^| )(-v|--volume|--mount|-e|--env|--env-file|--privileged|--network host)( |=)" "$work/calls"'
check "docker is used only to run, kill, list (ps) and remove containers" '! grep -vE "^(run|kill|rm|ps) " "$work/calls" | grep -q .'
check "each container has its own diary-prov-<pid>-<n> name" '[ "$(grep "^run " "$work/calls" | sed -n "s/.*--name \(diary-prov-[0-9]*-[0-9]*\) .*/\1/p" | sort -u | wc -l | tr -d " ")" -eq 4 ]'
check "every container carries the same noevia.diary-prov=<run-id> label" '[ "$(grep "^run " "$work/calls" | sed -n "s/.*--label \(noevia.diary-prov=[^ ]*\) .*/\1/p" | sort -u | wc -l | tr -d " ")" -eq 1 ] && grep "^run " "$work/calls" | grep -qc -- "--label noevia.diary-prov="'
check "the run ends with a sweep by label: docker ps -aq --filter label=noevia.diary-prov=<run-id>" 'grep -q "^ps -aq --filter label=noevia.diary-prov=" "$work/calls"'
check "the fake daemon holds no container of the run afterwards" '[ "$(daemon_left)" -eq 0 ]'
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
check "the timed-out container is killed by name and swept by label" 'n=$(grep -- "--version" "$work/calls" | sed -n "s/.*--name \(diary-prov-[0-9]*-[0-9]*\) .*/\1/p"); [ -n "$n" ] && grep -q "^kill $n\$" "$work/calls" && [ "$(daemon_left)" -eq 0 ]'
check "no later container is started after a timeout" '[ "$(grep -c "^run " "$work/calls")" -eq 2 ]'
check "an abnormal end sweeps more than once" '[ "$(grep -c "^ps -aq" "$work/calls")" -ge 3 ]'
check "nothing is left in the temp directory after a timeout" '[ -z "$(ls -A "$work/tmp")" ]'
# the reviewer case: the create was still pending when the client was killed, so the first sweeps find nothing
t $IMG $REF HANG=1 CHECK_DIARY_TIMEOUT=1 CREATE_DELAY=1.6
check "a container whose create lands after the deadline is still removed by the repeated sweeps" '[ "$(daemon_left)" -eq 0 ] && ! grep -q "may remain" "$work/err" && grep -q "outlived" "$work/err"'
t $IMG $REF HANG=1 CHECK_DIARY_TIMEOUT=1 CREATE_DELAY=1.6 CHECK_DIARY_SWEEPS=1; sleep 1
check "with a single sweep that late container would survive (the repeated sweeps are what remove it)" '[ "$(daemon_left)" -ge 1 ]'
t $IMG $REF HANG=1 CHECK_DIARY_TIMEOUT=1 KILL_NOOP=1 RM_FAIL=1 CHECK_DIARY_SWEEPS=2
check "containers that cannot be removed fail the check and are named" '[ $rc -eq 1 ] && grep -q "may remain" "$work/err" && grep -q "diary-prov-" "$work/err" && grep -q "label=noevia.diary-prov=" "$work/err"'
start=$SECONDS
t $IMG $REF HANG=1 CHECK_DIARY_TIMEOUT=1 KILL_NOOP=1 RM_HANG=1 CHECK_DIARY_HOUSEKEEPING_TIMEOUT=1 CHECK_DIARY_SWEEPS=2
check "a hung docker rm is cut off by its own deadline and the leftover is named" '[ $rc -eq 1 ] && grep -q "may remain" "$work/err" && grep -q "diary-prov-" "$work/err" && [ $((SECONDS - start)) -lt 40 ]'
start=$SECONDS
t $IMG $REF HANG=1 CHECK_DIARY_TIMEOUT=1 KILL_HANG=1 CHECK_DIARY_HOUSEKEEPING_TIMEOUT=1
check "a hung docker kill is cut off by its own deadline and the sweep still removes the container" '[ "$(daemon_left)" -eq 0 ] && [ $((SECONDS - start)) -lt 40 ] && grep -q "outlived" "$work/err"'
start=$SECONDS
t $IMG $REF PS_HANG=1 CHECK_DIARY_HOUSEKEEPING_TIMEOUT=1 CHECK_DIARY_SWEEPS=2
check "a docker ps that never answers cannot be waited on forever and is reported" '[ $rc -eq 1 ] && grep -q "docker ps did not answer" "$work/err" && [ $((SECONDS - start)) -lt 60 ]'
t $IMG $REF PS_FAIL=1
check "a failing docker ps is reported, even after an otherwise passing run" '[ $rc -eq 1 ] && grep -q "docker ps did not answer" "$work/err"'
: > "$work/calls"; rm -rf "$work/state"; mkdir -p "$work/state"
env PATH="$work/bin:$PATH" TMPDIR="$work/tmp" CALL_LOG="$work/calls" STATE="$work/state" REF_PIN="$REF" HANG=1 CHECK_DIARY_SWEEP_PAUSE=0.3 bash "$here/check-diary-image-native.sh" $IMG $REF >"$work/out" 2>"$work/err" &
cpid=$!
for _ in $(seq 1 100); do grep -q -- "--version" "$work/calls" && break; sleep 0.1; done
kill -TERM "$cpid"; wait "$cpid"; rc=$?
check "a terminated check exits 143" '[ $rc -eq 143 ]'
check "a terminated check sweeps its label and leaves no container in the daemon" '[ "$(daemon_left)" -eq 0 ] && grep -q "^ps -aq" "$work/calls"'
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
