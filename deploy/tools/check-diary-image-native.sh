#!/usr/bin/env bash
# Image-level provenance of the native Diary binaries (noevia#2391). Run against a BUILT candidate Diary image during
# release qualification (diary-overlay.sh runs it on cowork-diary:<sha>-candidate before anything is stopped; run it by
# hand on an image built from services/diary/Dockerfile). The static Dockerfile guard (assemble-release.sh) proves what
# the Dockerfile says; this proves what the image holds:
#   1. every native binary is present and executable at /usr/local/bin;
#   2. `noevia-diary --version` prints exactly ONE line, `noevia-diary <version> noevia-rs <pinned 40-hex ref>`, and
#      nothing else (the binary embeds the ref it was built from: its crate reads NOEVIA_RS_REF at build time, which the
#      Dockerfile passes as an ARG);
#   3. the binaries with a self-test answer it (tenant-assertion, workspace-restore-verify).
# Every container runs with --network none and no volumes, env files or data: nothing is read from or written to a
# real tenant, and no model is touched. Each container has a unique name and a run label, a deadline
# (CHECK_DIARY_TIMEOUT seconds, default 120, then it is killed), and every docker call has its own deadline
# (CHECK_DIARY_HOUSEKEEPING_TIMEOUT, default 10 s). On exit, after a deadline or on a signal the script sweeps every
# container of its run label (docker ps -aq --filter label=..., docker rm -f), repeating a few times over about 10 s
# after an abnormal end so a create that was still pending is caught; if anything remains it exits non-zero naming it.
#
# Usage: check-diary-image-native.sh <image> <noevia-rs-ref>      (ref: the 40-hex NOEVIA_RS_REF of the release pin)
# Exit 0 only when all checks pass; any docker failure, timeout, missing binary or ref mismatch exits non-zero.
set -euo pipefail
image=${1:-}; ref=${2:-}
limit=${CHECK_DIARY_TIMEOUT:-120}
[[ $image =~ ^[A-Za-z0-9][A-Za-z0-9._:/@-]*$ ]] || { echo "check-diary-image-native: invalid image name" >&2; exit 2; }
[[ $ref =~ ^[0-9a-f]{40}$ ]] || { echo "check-diary-image-native: the noevia-rs ref must be 40 lowercase hex" >&2; exit 2; }
[[ $limit =~ ^[1-9][0-9]{0,3}$ ]] || { echo "check-diary-image-native: CHECK_DIARY_TIMEOUT must be a whole number of seconds" >&2; exit 2; }
# The same list diary-overlay.sh removes and rebuilds (native_bin_names); deploy/tests/test_overlay_scripts.py keeps them equal.
native_bins="tenant-assertion workspace-restore-verify diary-corpus-write-cli diary-corpus-parse diary-score-gap diary-temporal-cli diary-workspace-export diary-workspace-import-apply diary-entity-focus diary-index-transform diary-storage-backoff diary-workspace-rules diary-backup-format diary-backup-run noevia-diary"

runid="$$-$(date +%s)-$RANDOM"
label="noevia.diary-prov=$runid"
housekeeping=${CHECK_DIARY_HOUSEKEEPING_TIMEOUT:-10}   # seconds allowed to each docker kill / rm / ps
sweeps=${CHECK_DIARY_SWEEPS:-5}                        # sweeps after an abnormal end, so that a pending create settles
pause=${CHECK_DIARY_SWEEP_PAUSE:-2}
[[ $housekeeping =~ ^[1-9][0-9]{0,2}$ && $sweeps =~ ^[1-9][0-9]?$ && $pause =~ ^[0-9]+(\.[0-9]+)?$ ]] \
  || { echo "check-diary-image-native: CHECK_DIARY_HOUSEKEEPING_TIMEOUT, CHECK_DIARY_SWEEPS and CHECK_DIARY_SWEEP_PAUSE must be numbers" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-diary-image-native.XXXXXX")
seq=0; unsettled=0; dk_pid=""; dk_wd=""
# dk <deadline-seconds> <stdout-file> <docker args...>: one docker CLI call under a bash watchdog (macOS has no
# timeout). Returns docker's status, or 124 when the call outlived its deadline and was killed.
dk() {
  local deadline=$1 outfile=$2; shift 2
  rm -f "$tmp/dk.timeout"
  docker "$@" >"$outfile" 2>"$tmp/dk.err" &
  dk_pid=$!
  ( i=0; while [ "$i" -lt "$deadline" ]; do sleep 1; i=$((i + 1)); done
    : > "$tmp/dk.timeout"; kill "$dk_pid" 2>/dev/null || true ) &
  dk_wd=$!
  local rc=0
  wait "$dk_pid" || rc=$?
  kill "$dk_wd" 2>/dev/null || true; wait "$dk_wd" 2>/dev/null || true
  dk_pid=""; dk_wd=""
  if [ -e "$tmp/dk.timeout" ]; then rm -f "$tmp/dk.timeout"; unsettled=1; return 124; fi
  return "$rc"
}
# sweep: remove every container carrying this run label. After an abnormal end (a deadline, a signal, a hung docker
# call) it repeats a few times so a container whose create was still pending when the client was killed is found and
# removed once the daemon has made it. Returns 1 and leaves the names in $tmp/left when any container may remain.
sweep() {
  local i=0 rounds=1 id
  [ "$unsettled" = 0 ] || rounds=$sweeps
  while [ "$i" -lt "$rounds" ]; do
    i=$((i + 1))
    if dk "$housekeeping" "$tmp/ps" ps -aq --filter "label=$label"; then
      for id in $(cat "$tmp/ps"); do dk "$housekeeping" /dev/null rm -f "$id" || true; done
    fi
    [ "$i" -ge "$rounds" ] || sleep "$pause"
  done
  # the verdict is one fresh listing: empty means this run left nothing behind
  if dk "$housekeeping" "$tmp/ps" ps -aq --filter "label=$label"; then
    [ -s "$tmp/ps" ] || return 0
    cp "$tmp/ps" "$tmp/left"
  else
    echo "(docker ps did not answer)" > "$tmp/left"
  fi
  return 1
}
finish() {   # finish <status>: stop what is running, sweep, report anything left, exit
  local status=$1
  trap - EXIT; trap ':' INT TERM   # a signal during the sweep does not cut it short (a no-op handler, so subshells still die on TERM)
  [ -z "$dk_wd" ] || kill "$dk_wd" 2>/dev/null || true
  [ -z "$dk_pid" ] || { kill "$dk_pid" 2>/dev/null || true; unsettled=1; }
  if ! sweep; then
    echo "check-diary-image-native: containers of run $runid may remain and need removing by hand: $(tr '\n' ' ' < "$tmp/left")(docker ps -aq --filter label=$label)" >&2
    rm -rf "$tmp"; exit 1
  fi
  rm -rf "$tmp"; exit "$status"
}
trap 'finish $?' EXIT
trap 'unsettled=1; finish 130' INT
trap 'unsettled=1; finish 143' TERM

# run <docker run args...>: one labelled container, no network, a unique name, stdout in $tmp/out and stderr in
# $tmp/err. Returns docker's status, or 124 after killing the container when it outlives the deadline.
run() {
  seq=$((seq + 1)); local name="diary-prov-$$-$seq" rc=0
  dk "$limit" "$tmp/out" run --rm --name "$name" --label "$label" --network none --stop-timeout 5 "$@" || rc=$?
  cp "$tmp/dk.err" "$tmp/err" 2>/dev/null || true
  if [ "$rc" = 124 ]; then
    dk "$housekeeping" /dev/null kill "$name" || true
    echo "check-diary-image-native: a container for $image outlived its ${limit}s deadline and was killed" >&2
  fi
  return "$rc"
}
fail() { echo "check-diary-image-native: $*" >&2; exit 1; }
shown() { head -c 200 "$tmp/out" | tr -c '[:print:]' '?'; }

run --entrypoint sh "$image" -c \
  "for b in $native_bins; do if [ ! -f \"/usr/local/bin/\$b\" ] || [ ! -x \"/usr/local/bin/\$b\" ]; then echo \"\$b\"; fi; done" \
  || fail "could not list the native binaries in $image"
missing=$(cat "$tmp/out")
[ -z "$missing" ] || fail "$image lacks (or cannot execute): $(printf '%s ' $missing)"

run --entrypoint /usr/local/bin/noevia-diary "$image" --version \
  || fail "noevia-diary --version failed in $image (a binary built before it embeds its noevia-rs ref cannot be qualified)"
version=$(cat "$tmp/out")
expected="^noevia-diary [0-9][0-9A-Za-z.+_-]* noevia-rs ${ref}\$"
if [ "$(wc -l < "$tmp/out" | tr -d ' ')" -gt 1 ] || ! [[ $version =~ $expected ]]; then
  fail "noevia-diary --version in $image is not exactly one line 'noevia-diary <version> noevia-rs $ref' (got: $(shown))"
fi

for b in tenant-assertion workspace-restore-verify; do
  run --entrypoint "/usr/local/bin/$b" "$image" self-test || fail "$b self-test failed in $image"
  [ "$(cat "$tmp/out")" = ok ] || fail "$b self-test did not answer ok in $image"
done
echo "diary image native provenance ok: $image noevia-rs $ref"
