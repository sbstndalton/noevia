#!/usr/bin/env bash
# Release build of the web image with the version stamp guaranteed (issue #574).
# A plain `docker build` without --build-arg COWORK_VERSION stamps version.json as
# 0.2.0+...; this always passes it, turns on the Dockerfile guard, and checks the
# built image's dist/version.json before returning.
#
# Usage: build-web-release.sh <sha> [context-dir]
#   context-dir defaults to $COWORK_SOURCE_DIR/apps/web when set, else ./apps/web.
# Tag: cowork-web:<sha> (the tag compose.yaml expects). Run on the Docker host.
set -euo pipefail
sha="${1:-}"
if [[ ! "$sha" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "usage: build-web-release.sh <release-sha> [context-dir]" >&2
  exit 2
fi
context="${2:-${COWORK_SOURCE_DIR:+$COWORK_SOURCE_DIR/apps/web}}"
context="${context:-apps/web}"
if [[ ! -f "$context/Dockerfile" ]]; then
  echo "error: no Dockerfile in web build context: $context" >&2
  exit 2
fi
image="cowork-web:$sha"
docker build --build-arg "COWORK_VERSION=$sha" --build-arg REQUIRE_RELEASE_VERSION=1 -t "$image" "$context"
stamped="$(docker run --rm --entrypoint cat "$image" /app/dist/version.json)"
if ! grep -q "\"version\":\"$sha\"" <<<"$stamped"; then
  echo "error: $image dist/version.json is not stamped with $sha: $stamped" >&2
  exit 1
fi
echo "ok: $image stamped $sha"
