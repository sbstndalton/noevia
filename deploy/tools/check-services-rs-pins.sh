#!/usr/bin/env bash
# Release lock vs the assembled sidecar Dockerfiles' Rust pins (CI "Assembled release").
#
#   check-services-rs-pins.sh <assembled-tree> <lock> [<base-lock>]
#
# Every services/{model-manager,ocr,diary,docling,laya}/Dockerfile in the assembled tree carries
# ARG NOEVIA_RS_REF / NOEVIA_RS_SHA256. They must equal the lock's NOEVIA_SERVICES_RS_REF /
# NOEVIA_SERVICES_RS_SHA256 when those optional keys are present, else NOEVIA_RS_REF /
# NOEVIA_RS_SHA256. The keys declare "the pinned Services tree was built against an older Rust
# revision than the web image": allowed only while NOEVIA_SERVICES_REF is unchanged against
# <base-lock> (the lock on the PR's base), and refused when they merely repeat the main rs keys.
# deploy/egress-proxy/Dockerfile and the web image always follow NOEVIA_RS_REF (checked in CI's egress job).
set -euo pipefail

tree="${1:?assembled tree}"; lock="${2:?lock file}"; base="${3:-}"
val() { sed -n "s/^$1=//p" "$2" | tail -1; }
fail() { echo "::error::$*"; exit 1; }

rs_ref=$(val NOEVIA_RS_REF "$lock"); rs_sum=$(val NOEVIA_RS_SHA256 "$lock")
s_ref=$(val NOEVIA_SERVICES_RS_REF "$lock"); s_sum=$(val NOEVIA_SERVICES_RS_SHA256 "$lock")

want_ref="$rs_ref"; want_sum="$rs_sum"; src=NOEVIA_RS
if [ -n "$s_ref$s_sum" ]; then
  [[ "$s_ref" =~ ^[0-9a-f]{40}$ && "$s_sum" =~ ^[0-9a-f]{64}$ ]] \
    || fail "NOEVIA_SERVICES_RS_REF and NOEVIA_SERVICES_RS_SHA256 must both be set (40-hex ref, 64-hex sha256) or both absent"
  [ "$s_ref" != "$rs_ref" ] || [ "$s_sum" != "$rs_sum" ] \
    || fail "NOEVIA_SERVICES_RS_REF/SHA256 equal NOEVIA_RS_REF/SHA256: remove the redundant services rs keys"
  [ -n "$base" ] && [ -f "$base" ] \
    || fail "services rs keys declared drift but the base branch lock is unavailable, so an unchanged NOEVIA_SERVICES_REF cannot be shown"
  cur=$(val NOEVIA_SERVICES_REF "$lock"); old=$(val NOEVIA_SERVICES_REF "$base")
  { [ -n "$cur" ] && [ "$cur" = "$old" ]; } \
    || fail "services rs keys declare drift, which is only for releases that leave the Services pin alone, but NOEVIA_SERVICES_REF moved ($old -> $cur): drop NOEVIA_SERVICES_RS_REF/SHA256 and bump the Services Dockerfiles to NOEVIA_RS_REF"
  want_ref="$s_ref"; want_sum="$s_sum"; src=NOEVIA_SERVICES_RS
fi

for svc in model-manager ocr diary docling laya; do
  df="$tree/services/$svc/Dockerfile"
  [ -f "$df" ] || fail "services/$svc/Dockerfile missing from the assembled tree"
  [ "$(sed -n 's/^ARG NOEVIA_RS_REF=//p' "$df")" = "$want_ref" ] \
    || fail "noevia-services $svc/Dockerfile NOEVIA_RS_REF != release/versions.lock ${src}_REF ($want_ref)"
  [ "$(sed -n 's/^ARG NOEVIA_RS_SHA256=//p' "$df")" = "$want_sum" ] \
    || fail "noevia-services $svc/Dockerfile NOEVIA_RS_SHA256 != release/versions.lock ${src}_SHA256"
done
echo "services Dockerfile rs pins match $src keys ($want_ref)"
