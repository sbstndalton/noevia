#!/usr/bin/env bash
# Image-level provenance of the native Diary binaries (noevia#2391). Run against a BUILT candidate Diary image during
# release qualification (diary-overlay.sh runs it on cowork-diary:<sha>-candidate before anything is stopped; run it by
# hand on an image built from services/diary/Dockerfile). The static Dockerfile guard (assemble-release.sh) proves what
# the Dockerfile says; this proves what the image holds:
#   1. every native binary is present and executable at /usr/local/bin;
#   2. `noevia-diary --version` carries exactly the pinned noevia-rs ref (the binary embeds the ref it was built
#      from: its crate reads NOEVIA_RS_REF at build time, which the Dockerfile passes as an ARG);
#   3. the binaries with a self-test answer it (tenant-assertion, workspace-restore-verify).
# Every container runs with --network none and no volumes, env files or data: nothing is read from or written to a
# real tenant, and no model is touched.
#
# Usage: check-diary-image-native.sh <image> <noevia-rs-ref>      (ref: the 40-hex NOEVIA_RS_REF of the release pin)
# Exit 0 only when all checks pass; any docker failure, missing binary or ref mismatch exits non-zero.
set -euo pipefail
image=${1:-}; ref=${2:-}
[[ $image =~ ^[A-Za-z0-9][A-Za-z0-9._:/@-]*$ ]] || { echo "check-diary-image-native: invalid image name" >&2; exit 2; }
[[ $ref =~ ^[0-9a-f]{40}$ ]] || { echo "check-diary-image-native: the noevia-rs ref must be 40 lowercase hex" >&2; exit 2; }
# The same list diary-overlay.sh removes and rebuilds (native_bin_names); deploy/tests/test_overlay_scripts.py keeps them equal.
native_bins="tenant-assertion workspace-restore-verify diary-corpus-write-cli diary-corpus-parse diary-score-gap diary-temporal-cli diary-workspace-export diary-workspace-import-apply diary-entity-focus diary-index-transform diary-storage-backoff diary-workspace-rules diary-backup-format diary-backup-run noevia-diary"
run() { docker run --rm --network none "$@"; }

missing=$(run --entrypoint sh "$image" -c \
  "for b in $native_bins; do if [ ! -f \"/usr/local/bin/\$b\" ] || [ ! -x \"/usr/local/bin/\$b\" ]; then echo \"\$b\"; fi; done") \
  || { echo "check-diary-image-native: could not list the native binaries in $image" >&2; exit 1; }
if [ -n "$missing" ]; then
  echo "check-diary-image-native: $image lacks (or cannot execute): $(printf '%s ' $missing)" >&2
  exit 1
fi

version=$(run --entrypoint /usr/local/bin/noevia-diary "$image" --version) \
  || { echo "check-diary-image-native: noevia-diary --version failed in $image (a binary built before it embeds its noevia-rs ref cannot be qualified)" >&2; exit 1; }
refs=$(printf '%s\n' "$version" | grep -oE '(^|[^0-9a-f])[0-9a-f]{40}([^0-9a-f]|$)' | grep -oE '[0-9a-f]{40}' | sort -u || true)
if [ "$refs" != "$ref" ]; then
  echo "check-diary-image-native: noevia-diary --version in $image reports noevia-rs '${refs:-none}', not the pinned $ref" >&2
  exit 1
fi

for b in tenant-assertion workspace-restore-verify; do
  answer=$(run --entrypoint "/usr/local/bin/$b" "$image" self-test) \
    || { echo "check-diary-image-native: $b self-test failed in $image" >&2; exit 1; }
  [ "$answer" = ok ] || { echo "check-diary-image-native: $b self-test did not answer ok in $image" >&2; exit 1; }
done
echo "diary image native provenance ok: $image noevia-rs $ref"
