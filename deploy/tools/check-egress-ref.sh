#!/usr/bin/env bash
# check-egress-ref.sh <egress-built-at> <candidate> : does this release have to rebuild the egress image? (#2597)
# deploy/egress-proxy/Dockerfile follows release/versions.lock's NOEVIA_RS_REF (CI's egress job), so its ref moves with
# every Rust pin, while the running egress image is only rebuilt by a release that builds it. Run this in the release's
# GATE with <egress-built-at> = the noevia commit the running egress image was built from (EGRESS_RS_VERSION in the
# server's .env names it; a short SHA is fine) and <candidate> = the release's noevia commit. Both must be commits of
# this repository (git only; no network, no image is read).
#   exit 0  same NOEVIA_RS_REF/NOEVIA_RS_SHA256 in both Dockerfiles: the running egress image matches the candidate's
#   exit 3  they differ: build deploy/egress-proxy (target native-control) from the candidate tree and move
#           EGRESS_RS_VERSION in this release (release the whole stack), or say in the GATE why it stays (the recorded
#           version and the running code then drift apart)
#   exit 1  a commit or the Dockerfile's ARG lines could not be read
set -euo pipefail
built=${1:?egress-built-at commit}; cand=${2:?candidate commit}
here="$(cd -- "$(dirname -- "$0")" && pwd)"; repo=${CHECK_EGRESS_REPO:-$(git -C "$here" rev-parse --show-toplevel)}
args() {  # args <commit>: "<ref> <sha256>" of the egress Dockerfile at that commit
  local df ref sum
  df=$(git -C "$repo" show "$1:deploy/egress-proxy/Dockerfile" 2>/dev/null) || { echo "check-egress-ref: no deploy/egress-proxy/Dockerfile at $1" >&2; return 1; }
  ref=$(sed -n 's/^ARG NOEVIA_RS_REF=\([0-9a-f]\{40\}\)$/\1/p' <<<"$df"); sum=$(sed -n 's/^ARG NOEVIA_RS_SHA256=\([0-9a-f]\{64\}\)$/\1/p' <<<"$df")
  [ "$(wc -l <<<"$ref")" = 1 ] && [ -n "$ref" ] && [ -n "$sum" ] || { echo "check-egress-ref: the Dockerfile at $1 has no single NOEVIA_RS_REF/NOEVIA_RS_SHA256 ARG line" >&2; return 1; }
  echo "$ref $sum"
}
a=$(args "$built") || exit 1; b=$(args "$cand") || exit 1
if [ "$a" = "$b" ]; then echo "egress_ref=unchanged rs=${a:0:12} (built at ${built:0:12}, candidate ${cand:0:12}): no egress rebuild needed"; exit 0; fi
echo "egress_ref=moved rs ${a:0:12} -> ${b:0:12} (built at ${built:0:12}, candidate ${cand:0:12}): rebuild deploy/egress-proxy (native-control) and move EGRESS_RS_VERSION in this release, or record the drift in the GATE"
exit 3
