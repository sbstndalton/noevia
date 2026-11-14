#!/usr/bin/env bash
# check-egress-ref.sh <EGRESS_RS_VERSION> <candidate> : does this release have to rebuild the egress image? (#2597)
# deploy/egress-proxy/Dockerfile follows release/versions.lock's NOEVIA_RS_REF (CI's egress job), so its ref moves with
# every Rust pin, while the running egress image is only rebuilt by a release that builds it. Run this in the release's
# GATE with the server's EGRESS_RS_VERSION (the running egress image's tag) and the release's noevia commit. The tag is
# read in one of two forms (the mode is printed; --rs-ref or --noevia forces one):
#   noevia  the tag is a commit of this repository (the tree the image was built from): the whole deploy/egress-proxy
#           directory is compared with the candidate's (the Rust ref, the base image digests, the stages)
#   rs-ref  otherwise a 7-40 hex Rust commit (as production's tag today): it must be a prefix of the candidate
#           Dockerfile's NOEVIA_RS_REF
# Git only: no network, no image is read.
#   exit 0  the running egress image matches the candidate
#   exit 3  it does not: build deploy/egress-proxy (target native-control) from the candidate tree and move
#           EGRESS_RS_VERSION in this release (release the whole stack), or say in the GATE why it stays
#   exit 1  the tag, a commit or the Dockerfile's ARG lines could not be read
set -euo pipefail
mode=auto; case "${1:-}" in --rs-ref) mode=rs-ref; shift ;; --noevia) mode=noevia; shift ;; esac
built=${1:?EGRESS_RS_VERSION}; cand=${2:?candidate commit}
here="$(cd -- "$(dirname -- "$0")" && pwd)"; repo=${CHECK_EGRESS_REPO:-$(git -C "$here" rev-parse --show-toplevel)}
[[ "$built" =~ ^[0-9a-f]{7,40}$ ]] || { echo "check-egress-ref: EGRESS_RS_VERSION must be 7-40 lowercase hex (got a tag of another form)" >&2; exit 1; }
cand_ref() {
  local df ref
  df=$(git -C "$repo" show "$1:deploy/egress-proxy/Dockerfile" 2>/dev/null) || { echo "check-egress-ref: no deploy/egress-proxy/Dockerfile at $1" >&2; return 1; }
  ref=$(sed -n 's/^ARG NOEVIA_RS_REF=\([0-9a-f]\{40\}\)$/\1/p' <<<"$df")
  [ -n "$ref" ] && [ "$(wc -l <<<"$ref")" = 1 ] && grep -qE '^ARG NOEVIA_RS_SHA256=[0-9a-f]{64}$' <<<"$df" \
    || { echo "check-egress-ref: the Dockerfile at $1 has no single NOEVIA_RS_REF/NOEVIA_RS_SHA256 ARG line" >&2; return 1; }
  echo "$ref"
}
cr=$(cand_ref "$cand") || exit 1
if [ "$mode" = auto ]; then
  if git -C "$repo" cat-file -e "$built^{commit}" 2>/dev/null && git -C "$repo" cat-file -e "$built:deploy/egress-proxy/Dockerfile" 2>/dev/null; then mode=noevia; else mode=rs-ref; fi
fi
if [ "$mode" = noevia ]; then
  br=$(cand_ref "$built") || exit 1
  ta=$(git -C "$repo" rev-parse "$built:deploy/egress-proxy"); tb=$(git -C "$repo" rev-parse "$cand:deploy/egress-proxy")
  if [ "$ta" = "$tb" ]; then echo "egress=current mode=noevia built_at=${built:0:12} candidate=${cand:0:12} rs=${cr:0:12}: no egress rebuild needed"; exit 0; fi
  echo "egress=stale mode=noevia built_at=${built:0:12} candidate=${cand:0:12} rs ${br:0:12} -> ${cr:0:12} (deploy/egress-proxy differs): rebuild deploy/egress-proxy (native-control) and move EGRESS_RS_VERSION in this release, or record why not in the GATE"
  exit 3
fi
if [ "${cr#"$built"}" != "$cr" ]; then echo "egress=current mode=rs-ref tag=$built candidate=${cand:0:12} rs=${cr:0:12}: no egress rebuild needed"; exit 0; fi
echo "egress=stale mode=rs-ref tag=$built candidate=${cand:0:12} rs=${cr:0:12}: the running egress image was built from another Rust commit: rebuild deploy/egress-proxy (native-control) and move EGRESS_RS_VERSION in this release, or record why not in the GATE"
exit 3
