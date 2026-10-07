#!/usr/bin/env bash
# Assemble one release tarball from pinned sources (#922, docs/adr-0001-rust-and-repo-split.md).
# Runs on the Mac (or CI). Since the repo split cutover (#952) this is THE release source: the
# tarball it writes is what docs/deployment.md ships to releases/<sha>/ on the server, and
# build-web-release.sh / overlay-release.sh consume it.
#
# Usage: assemble-release.sh [--lock <file>] <noevia-sha> [out-dir]
#   <noevia-sha>  7-40 lowercase hex commit in this repo. It becomes COWORK_VERSION / the version.json
#                 `version`, exactly as in today's releases.
#   out-dir       where noevia-release-<sha>.tar.gz is written (default: current directory).
#   --lock <file> CI ONLY (#952): read the component refs from <file> instead of
#                 release/versions.lock at <noevia-sha> (used before the cutover to prove the
#                 split candidate; kept for re-proving a candidate lock).
#
# The tarball holds, at its top level:
#   noevia/        git archive of this repo at <noevia-sha>
#   web/           client tree (noevia-web layout): src, public, index.html, vite.config.ts,
#                  tsconfig.json, package*.json, scripts, contracts, plus tests/client and qa
#                  (the client tests the image build runs)
#   core/          server tree (noevia-core layout): server, contracts, plus tests/server,
#                  tests/fixtures and code-sandbox/ (services/code-sandbox's build context)
#   services/      Python sidecars (noevia-services layout): diary, docling, laya, model-manager,
#                  ocr, one image build context each
#   release-refs   NOEVIA_SHA / NOEVIA_WEB_SHA / NOEVIA_CORE_SHA / NOEVIA_SERVICES_SHA
#                  (build/web.Dockerfile reads the first three)
#   .dockerignore  keeps noevia/ and services/ out of the web image build context
#
# The self-mode path lists match tools/repo-split's map exactly, so a self assembly and one from
# the extracted repos differ only by those repos' README.md and .github/ (CI checks this).
#
# web/, core/ and services/ come from release/versions.lock AS COMMITTED AT <noevia-sha>:
#   NOEVIA_{WEB,CORE,SERVICES}_REF = self      -> exported from apps/web and services/ at <noevia-sha>
#     (only commits from before the cutover have those paths; a lock without NOEVIA_SERVICES_REF,
#     i.e. any commit before #952, means self). This keeps old SHAs assemblable for rollback.
#   NOEVIA_{WEB,CORE,SERVICES}_REF = <40 hex>  -> anonymous https tarball from
#     codeload.github.com/sbstndalton/noevia-web|noevia-core|noevia-services, verified against
#     NOEVIA_{WEB,CORE,SERVICES}_SHA256, which a pinned ref requires (checked before download). The repo root becomes web/, core/
#     or services/. The path map is the one tools/repo-split extracts with.
#
# Build (no push): docker build -f noevia/build/web.Dockerfile --build-arg COWORK_VERSION=<sha> <tree>
set -euo pipefail

die() { echo "assemble-release: $*" >&2; exit 1; }

lock_file=""
if [ "${1:-}" = --lock ]; then
  lock_file="${2:-}"; shift 2 || true
  # A release must come from the lock committed at the released sha; an override is CI-only.
  [ "${CI:-}" = true ] || { echo "assemble-release: --lock is for CI dry runs only (CI=true); releases read release/versions.lock" >&2; exit 2; }
  [ -f "$lock_file" ] || { echo "assemble-release: --lock file not found: $lock_file" >&2; exit 2; }
fi
sha="${1:-}"
out_dir="${2:-.}"
[[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "usage: assemble-release.sh [--lock <file>] <noevia-sha (7-40 lowercase hex)> [out-dir]" >&2; exit 2; }
[ -d "$out_dir" ] || die "out-dir does not exist: $out_dir"
out_dir="$(cd -- "$out_dir" && pwd)"

repo="$(cd -- "$(dirname -- "$0")" && git rev-parse --show-toplevel)" || die "not inside a git checkout"
git -C "$repo" cat-file -e "$sha^{commit}" 2>/dev/null || die "unknown commit: $sha (fetch it first)"
full_sha="$(git -C "$repo" rev-parse --verify "$sha^{commit}")"
# A short sha must not be ambiguous and must be a prefix of what it resolved to.
[[ "$full_sha" == "$sha"* ]] || die "$sha resolved to $full_sha; pass a commit sha, not a ref"
# The archive is taken from the commit, but a dirty checkout usually means the operator meant to
# release something that is not committed yet. Refuse rather than ship the wrong thing.
if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ]; then
  die "checkout $repo has uncommitted changes; commit them or assemble from a clean worktree"
fi

if [ -n "$lock_file" ]; then
  lock="$(cat -- "$lock_file")"
  echo "assemble-release: dry run with component refs from $lock_file, not the committed lock" >&2
else
  lock="$(git -C "$repo" show "$full_sha:release/versions.lock" 2>/dev/null)" \
    || die "release/versions.lock does not exist at $sha"
fi
lock_value() { printf '%s\n' "$lock" | sed -n "s/^$1=//p" | tail -n 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/assemble-release.XXXXXX")"
out_partial=""
# Never leave <out>.partial behind when the final tar (or anything after it) fails.
trap 'rm -rf "$work"; if [ -n "$out_partial" ]; then rm -f "$out_partial"; fi' EXIT
tree="$work/tree"
mkdir -p "$tree/noevia" "$tree/web" "$tree/core" "$tree/services"

git -C "$repo" archive --format=tar "$full_sha" | tar -x -C "$tree/noevia"

# Export <prefix>/<paths> at the noevia commit into <dest>, <prefix> stripped.
export_self() {
  local dest="$1" prefix="$2"; shift 2
  local specs=() p strip
  for p in "$@"; do
    git -C "$repo" cat-file -e "$full_sha:$prefix/$p" 2>/dev/null || die "$prefix/$p is missing at $sha"
    specs+=("$prefix/$p")
  done
  strip="$(printf '%s' "$prefix" | tr -cd / | wc -c)"
  git -C "$repo" archive --format=tar "$full_sha" -- "${specs[@]}" | tar -x --strip-components="$((strip + 1))" -C "$dest"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# Fetch sbstndalton/<repo_name> at a pinned 40-hex ref into <dest> (repo root -> dest).
fetch_remote() {
  local repo_name="$1" ref="$2" want_sum="$3" dest="$4" tgz
  tgz="$work/$repo_name.tar.gz"
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$tgz" \
    "https://codeload.github.com/sbstndalton/$repo_name/tar.gz/$ref" \
    || die "could not download $repo_name at $ref"
  [ "$(sha256_of "$tgz")" = "$want_sum" ] || die "$repo_name tarball checksum mismatch at $ref"
  tar -xzf "$tgz" --strip-components=1 -C "$dest"
}

# Resolve one component; prints the resolved 40-hex sha.
resolve_component() {
  local key="$1" repo_name="$2" dest="$3"; shift 3
  local ref sum
  ref="$(lock_value "${key}_REF")"
  sum="$(lock_value "${key}_SHA256")"
  # Locks from before #952 have no NOEVIA_SERVICES_REF: services were always exported from here.
  if [ -z "$ref" ] && [ "$key" = NOEVIA_SERVICES ] && ! printf '%s\n' "$lock" | grep -q '^NOEVIA_SERVICES_REF='; then
    ref=self
  fi
  if [ "$ref" = self ]; then
    export_self "$dest" "$@"
    printf '%s' "$full_sha"
  elif [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
    [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || die "${key}_REF is pinned but ${key}_SHA256 is missing or not 64 lowercase hex"
    fetch_remote "$repo_name" "$ref" "$sum" "$dest"
    printf '%s' "$ref"
  else
    die "${key}_REF in versions.lock at $sha must be 'self' or a 40-char lowercase sha, got: '${ref}'"
  fi
}

web_sha="$(resolve_component NOEVIA_WEB noevia-web "$tree/web" apps/web \
  src public index.html vite.config.ts tsconfig.json package.json package-lock.json scripts contracts tests/client qa \
  tests/hermetic-network.cjs .gitignore .dockerignore)"
core_sha="$(resolve_component NOEVIA_CORE noevia-core "$tree/core" apps/web \
  server contracts tests/server tests/fixtures tests/hermetic-network.cjs)"
if [ "$(lock_value NOEVIA_CORE_REF)" = self ]; then
  # noevia-core also owns services/code-sandbox, at code-sandbox/ (tools/repo-split's map).
  export_self "$tree/core" services code-sandbox
fi
services_sha="$(resolve_component NOEVIA_SERVICES noevia-services "$tree/services" services \
  diary docling laya model-manager ocr)"

for need in web/package.json web/package-lock.json web/src web/index.html core/server/package.json core/server/index.cjs core/contracts \
            core/code-sandbox/Dockerfile services/diary/Dockerfile services/docling/Dockerfile services/laya/Dockerfile \
            services/model-manager/Dockerfile services/ocr/Dockerfile; do
  [ -e "$tree/$need" ] || die "assembled tree lacks $need"
done

printf 'NOEVIA_SHA=%s\nNOEVIA_WEB_SHA=%s\nNOEVIA_CORE_SHA=%s\nNOEVIA_SERVICES_SHA=%s\n' \
  "$sha" "$web_sha" "$core_sha" "$services_sha" > "$tree/release-refs"
printf 'noevia\nservices\n' > "$tree/.dockerignore"

out="$out_dir/noevia-release-$sha.tar.gz"
out_partial="$out.partial"
COPYFILE_DISABLE=1 tar -czf "$out_partial" -C "$tree" .dockerignore release-refs noevia web core services
mv -f "$out_partial" "$out"
echo "ok: $out (noevia $full_sha, web $web_sha, core $core_sha, services $services_sha)"
