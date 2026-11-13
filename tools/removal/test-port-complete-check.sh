#!/usr/bin/env bash
# Self-test for port-complete-check.sh on synthetic git repos (no network, no real data).
# Usage: tools/removal/test-port-complete-check.sh   (exit 0 when every assertion holds)
set -u
here=$(cd "$(dirname "$0")" && pwd)
check="$here/port-complete-check.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/r10-check-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=$((fail+1)); }

mkrepo() {  # mkrepo DIR : empty git repo with a committed main
  mkdir -p "$1" && git -C "$1" init -q -b main && git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
}
commit() {  # commit DIR PATH CONTENT : write one file and commit it
  mkdir -p "$1/$(dirname "$2")" && printf '%s\n' "$3" > "$1/$2" && git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q -m "add $2"
}

# A clean synthetic port: every check that can run on fixtures passes.
clean() {
  local d=$1
  mkrepo "$d/noevia"; mkrepo "$d/noevia-core"; mkrepo "$d/noevia-rs"; mkrepo "$d/noevia-services"
  commit "$d/noevia-rs" contracts/http/routes.toml $'[[route]]\npath = "/api/x"\nowner = "rust"'
  commit "$d/noevia-core" server/index.test.cjs "'use strict';"
  commit "$d/noevia-core" code-sandbox/Dockerfile $'FROM alpine:3.20\nCMD ["true"]'
  commit "$d/noevia-services" diary/Dockerfile $'FROM debian:bookworm-slim\nCMD ["true"]'
  commit "$d/noevia" build/web.Dockerfile $'FROM rust:1.99-slim-bookworm AS front\nFROM debian:bookworm-slim\nHEALTHCHECK CMD curl -f http://127.0.0.1:8021/ || exit 1'
}
run() {  # run DIR [extra args] : prints output to $tmp/out and returns the check's exit code
  local d=$1; shift
  "$check" --core "$d/noevia-core" --rs "$d/noevia-rs" --services "$d/noevia-services" --noevia "$d/noevia" \
    --ref HEAD "$@" > "$tmp/out" 2>&1
}

# Case 1: clean fixtures, partial read (skips allowed) -> exit 0, no FAIL lines.
clean "$tmp/clean"
run "$tmp/clean" --allow-skip; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^FAIL' "$tmp/out"; then ok "clean fixtures pass with --allow-skip"; else bad "clean fixtures: rc=$rc"; cat "$tmp/out"; fi

# Case 2: the same read without --allow-skip is not complete (skips count) -> exit 1.
run "$tmp/clean"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'not complete' "$tmp/out"; then ok "skips are not a pass without --allow-skip"; else bad "strict skip: rc=$rc"; fi

# Case 3: a Node server file added -> check 2 fails with the count.
commit "$tmp/clean/noevia-core" server/extra.cjs "module.exports = 1;"
run "$tmp/clean" --allow-skip; rc=$?
if [ "$rc" -eq 1 ] && grep -q '^FAIL  2 ' "$tmp/out"; then ok "a Node server file fails check 2"; else bad "node file: rc=$rc"; fi

# Case 4: a node owner row and a legacy proxy file fail check 1.
commit "$tmp/clean/noevia-rs" contracts/http/routes.toml $'[[route]]\npath = "/api/x"\nowner = "node"'
commit "$tmp/clean/noevia-rs" bins/noevia-server/src/legacy_proxy.rs "// temp"
run "$tmp/clean" --allow-skip; rc=$?
if [ "$rc" -eq 1 ] && grep -q '^FAIL  1a' "$tmp/out" && grep -q '^FAIL  1b' "$tmp/out"; then ok "node owner and legacy_proxy.rs fail check 1"; else bad "check 1: rc=$rc"; fi

# Case 5: a Node base in the sandbox image is allowed only as the declared exception (it passes here).
mkrepo "$tmp/img"; commit "$tmp/img" build/web.Dockerfile $'FROM node:22-bookworm\nHEALTHCHECK CMD node -e "process.exit(0)"'
"$check" --core "$tmp/clean/noevia-core" --rs "$tmp/clean/noevia-rs" --services "$tmp/clean/noevia-services" \
  --noevia "$tmp/img" --ref HEAD --allow-skip > "$tmp/out" 2>&1
if grep -q '^FAIL  4  web final base' "$tmp/out" && grep -q '^FAIL  4b' "$tmp/out"; then ok "a Node web base and HEALTHCHECK fail check 4"; else bad "check 4"; cat "$tmp/out"; fi

# Case 6: a captured process list with node outside declared engines fails check 5.
printf '%s\n' "root 1234 node /app/server/index.cjs" > "$tmp/ps.txt"
run "$tmp/clean" --allow-skip --ps-file "$tmp/ps.txt"; rc=$?
if [ "$rc" -eq 1 ] && grep -q '^FAIL  5' "$tmp/out"; then ok "node process fails check 5"; else bad "check 5: rc=$rc"; fi

echo "---"
[ "$fail" -eq 0 ] && echo "all self-test cases passed" || echo "self-test failures: $fail"
[ "$fail" -eq 0 ]
