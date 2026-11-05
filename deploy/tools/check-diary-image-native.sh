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
# real tenant, and no model is touched. Each container has a unique name, a deadline (CHECK_DIARY_TIMEOUT seconds,
# default 120, then it is killed) and is removed again on exit, interrupt or termination.
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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-diary-image-native.XXXXXX")
names=""; seq=0; client_pid=""; watchdog_pid=""
cleanup() {
  trap - EXIT INT TERM
  [ -z "$watchdog_pid" ] || kill "$watchdog_pid" 2>/dev/null || true
  [ -z "$client_pid" ] || kill "$client_pid" 2>/dev/null || true
  local name
  for name in $names; do docker rm -f "$name" >/dev/null 2>&1 || true; done
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# run <docker run args...>: one container, no network, a unique name, stdout in $tmp/out and stderr in $tmp/err. Returns
# docker's status, or 124 after killing the container when it outlives the deadline.
run() {
  seq=$((seq + 1)); local name="diary-prov-$$-$seq"; names="$names $name"
  rm -f "$tmp/timeout"
  docker run --rm --name "$name" --network none --stop-timeout 5 "$@" >"$tmp/out" 2>"$tmp/err" &
  client_pid=$!
  ( i=0; while [ "$i" -lt "$limit" ]; do sleep 1; i=$((i + 1)); done
    : > "$tmp/timeout"; docker kill "$name" >/dev/null 2>&1 || true; kill "$client_pid" 2>/dev/null || true ) &
  watchdog_pid=$!
  local rc=0
  wait "$client_pid" || rc=$?
  kill "$watchdog_pid" 2>/dev/null || true; wait "$watchdog_pid" 2>/dev/null || true
  client_pid=""; watchdog_pid=""
  docker rm -f "$name" >/dev/null 2>&1 || true
  if [ -e "$tmp/timeout" ]; then echo "check-diary-image-native: a container for $image outlived its ${limit}s deadline and was killed" >&2; return 124; fi
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
