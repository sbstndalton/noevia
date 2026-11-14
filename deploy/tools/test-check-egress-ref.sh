#!/usr/bin/env bash
# Tests deploy/tools/check-egress-ref.sh against a synthetic git repository in a temporary directory (no network).
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/check-egress-ref.XXXXXX")"; trap 'rm -rf "$work"' EXIT
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; printf '%s\n' "$out" | sed 's/^/    | /'; fi; }
g() { git -C "$work/r" -c user.name=t -c user.email=t@example.invalid "$@"; }
mkdir -p "$work/r/deploy/egress-proxy"; git init -q "$work/r"
df() { printf 'FROM rust AS build\nARG NOEVIA_RS_REF=%s\nARG NOEVIA_RS_SHA256=%s\n' "$1" "$2" >"$work/r/deploy/egress-proxy/Dockerfile"; g add -A; g commit -qm "$3"; g rev-parse HEAD; }
R1=$(printf '1%.0s' {1..40}); R2=$(printf '2%.0s' {1..40}); S1=$(printf 'a%.0s' {1..64}); S2=$(printf 'b%.0s' {1..64})
c1=$(df "$R1" "$S1" one); echo x >"$work/r/other"; g add -A; g commit -qm two; c2=$(g rev-parse HEAD); c3=$(df "$R2" "$S2" three)
run() { out=$(CHECK_EGRESS_REPO="$work/r" bash "$here/check-egress-ref.sh" "$@" 2>&1); rc=$?; }
run "$c1" "$c2"; check "same rs ref: no rebuild (exit 0)" '[ $rc = 0 ] && grep -q "egress_ref=unchanged" <<<"$out"'
run "${c1:0:8}" "$c3"; check "moved rs ref: rebuild required (exit 3), names both refs" '[ $rc = 3 ] && grep -q "egress_ref=moved rs 111111111111 -> 222222222222" <<<"$out"'
c4=$(df "$R1" "$S2" four); run "$c1" "$c4"; check "same ref with another tarball sha256 counts as moved" '[ $rc = 3 ]'
run deadbeef "$c1"; check "an unknown commit is an error (exit 1)" '[ $rc = 1 ] && grep -q "no deploy/egress-proxy/Dockerfile at deadbeef" <<<"$out"'
printf 'FROM rust\nARG NOEVIA_RS_REF=${X}\n' >"$work/r/deploy/egress-proxy/Dockerfile"; g add -A; g commit -qm five; c5=$(g rev-parse HEAD)
run "$c1" "$c5"; check "an unreadable ARG line is an error, never a pass" '[ $rc = 1 ] && grep -q "no single NOEVIA_RS_REF" <<<"$out"'
echo "check-egress-ref: $passes passed, $fails failed"
[ "$fails" = 0 ]
