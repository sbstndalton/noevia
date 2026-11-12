#!/usr/bin/env bash
# check-services-rs-pins.sh: lock with and without the optional services rs keys.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
chk="$here/check-services-rs-pins.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/services-rs-pins-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
A=$(printf 'a%.0s' $(seq 40)); B=$(printf 'b%.0s' $(seq 40)); C=$(printf 'c%.0s' $(seq 40))
SA=$(printf '1%.0s' $(seq 64)); SB=$(printf '2%.0s' $(seq 64)); SC=$(printf '3%.0s' $(seq 64))
S1=$(printf 'd%.0s' $(seq 40)); S2=$(printf 'e%.0s' $(seq 40))

tree() { # <ref> <sha>
  rm -rf "$work/tree"
  for s in model-manager ocr diary docling laya; do
    mkdir -p "$work/tree/services/$s"
    printf 'FROM rust\nARG NOEVIA_RS_REF=%s\nARG NOEVIA_RS_SHA256=%s\n' "$1" "$2" > "$work/tree/services/$s/Dockerfile"
  done
}
lock() { # <file> <services-ref> [<services-rs-ref> <services-rs-sha>]
  printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_SERVICES_REF=%s\n' "$B" "$SB" "$2" > "$1"
  if [ $# -ge 4 ]; then printf 'NOEVIA_SERVICES_RS_REF=%s\nNOEVIA_SERVICES_RS_SHA256=%s\n' "$3" "$4" >> "$1"; fi
}
lock "$work/base" "$S1"

fails=0; passes=0
check() { # <name> <want-rc> <msg-grep|-> <args...>
  local name="$1" want="$2" msg="$3"; shift 3
  out=$(bash "$chk" "$@" 2>&1); rc=$?
  if { [ "$want" = 0 ] && [ $rc -eq 0 ]; } || { [ "$want" = 1 ] && [ $rc -ne 0 ] && echo "$out" | grep -q -- "$msg"; }; then
    passes=$((passes+1)); echo "ok - $name"
  else fails=$((fails+1)); echo "FAIL - $name (rc=$rc): $out"; fi
}

tree "$B" "$SB"; lock "$work/l" "$S2"
check "no services keys, Dockerfiles at the main rs pin pass (base not needed)" 0 - "$work/tree" "$work/l"
check "no services keys, Dockerfiles at an older rs fail" 1 "NOEVIA_RS_REF != release/versions.lock NOEVIA_RS_REF" "$(tree "$A" "$SA"; echo "$work/tree")" "$work/l"
tree "$B" "$SC"
check "no services keys, wrong sha256 fails" 1 "NOEVIA_RS_SHA256 !=" "$work/tree" "$work/l"

tree "$A" "$SA"; lock "$work/l" "$S1" "$A" "$SA"
check "drift declared, Services pin unchanged, Dockerfiles at the services rs pass" 0 - "$work/tree" "$work/l" "$work/base"
check "drift declared, Dockerfiles at the main rs fail" 1 "NOEVIA_SERVICES_RS_REF" "$(tree "$B" "$SB"; echo "$work/tree")" "$work/l" "$work/base"
check "drift declared, Dockerfiles at a third revision fail" 1 "NOEVIA_SERVICES_RS_REF" "$(tree "$C" "$SC"; echo "$work/tree")" "$work/l" "$work/base"
tree "$A" "$SC"
check "drift declared, ref right but sha256 differs fails" 1 "NOEVIA_RS_SHA256" "$work/tree" "$work/l" "$work/base"
tree "$A" "$SA"
check "drift declared without a base lock fails" 1 "base branch lock is unavailable" "$work/tree" "$work/l"
lock "$work/l" "$S2" "$A" "$SA"
check "drift declared and the Services pin moved fails" 1 "NOEVIA_SERVICES_REF moved" "$work/tree" "$work/l" "$work/base"
lock "$work/l" "$S1" "$B" "$SB"; tree "$B" "$SB"
check "redundant services keys fail" 1 "remove the redundant services rs keys" "$work/tree" "$work/l" "$work/base"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_SERVICES_REF=%s\nNOEVIA_SERVICES_RS_REF=%s\n' "$B" "$SB" "$S1" "$A" > "$work/l"
check "only one services key fails" 1 "must both be set" "$work/tree" "$work/l" "$work/base"

echo "$passes passed, $fails failed"; [ "$fails" = 0 ]
