#!/usr/bin/env bash
# Release build of the web image with the version stamp guaranteed (issue #574).
# A plain `docker build` without --build-arg COWORK_VERSION stamps version.json as
# 0.2.0+...; this always passes it, turns on the Dockerfile guard, and checks the
# built image's dist/version.json before returning.
#
# Since the repo split cutover (#952) the build context is an ASSEMBLED release tree: the
# unpacked deploy/tools/assemble-release.sh tarball (noevia/, web/, core/, services/,
# release-refs), built with noevia/build/web.Dockerfile. On the server that tree is
# releases/<sha>/ itself.
#
# Usage: build-web-release.sh <sha> [tree-dir]
#   tree-dir defaults to $COWORK_SOURCE_DIR when set, else the current directory.
# Tag: cowork-web:<sha> (the tag compose.yaml expects). Run on the Docker host.
set -euo pipefail
sha="${1:-}"
if [[ ! "$sha" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "usage: build-web-release.sh <release-sha> [tree-dir]" >&2
  exit 2
fi
tree="${2:-${COWORK_SOURCE_DIR:-.}}"
dockerfile="$tree/noevia/build/web.Dockerfile"
if [[ ! -f "$dockerfile" || ! -f "$tree/release-refs" ]]; then
  echo "error: $tree is not an assembled release tree (needs noevia/build/web.Dockerfile and release-refs; see deploy/tools/assemble-release.sh)" >&2
  exit 2
fi
# The tree must be the release being tagged: release-refs names the noevia sha it was assembled at.
tree_sha="$(sed -n 's/^NOEVIA_SHA=//p' "$tree/release-refs")"
if [[ "$tree_sha" != "$sha" ]]; then
  echo "error: $tree was assembled at noevia ${tree_sha:-<none>}, not $sha" >&2
  exit 2
fi
image="cowork-web:$sha"
docker build -f "$dockerfile" --build-arg "COWORK_VERSION=$sha" --build-arg REQUIRE_RELEASE_VERSION=1 -t "$image" "$tree"
stamped="$(docker run --rm --entrypoint cat "$image" /app/dist/version.json)"
if ! grep -q "\"version\":\"$sha\"" <<<"$stamped"; then
  echo "error: $image dist/version.json is not stamped with $sha: $stamped" >&2
  exit 1
fi
echo "ok: $image stamped $sha ($stamped)"
