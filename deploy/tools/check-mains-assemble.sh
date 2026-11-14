#!/usr/bin/env bash
# Assemble the CURRENT mains of noevia-rs, noevia-core, noevia-web and noevia-services with this checkout's
# assemble-release.sh, so a pairing guard that a merge in one repo has made stale fails here (sbstndalton/noevia#2596)
# instead of at the next release. Scheduled by .github/workflows/assemble-mains.yml; it can be run by hand.
#
#   check-mains-assemble.sh [--rs <sha>] [--core <sha>] [--web <sha>] [--services <sha>] [out-dir]
#
# A component not named is that repo's main, read with `git ls-remote` over anonymous https. Nothing is published,
# written to a cache or pushed; the assembled tarball goes to out-dir (default: a temporary directory that is removed).
#
# The lock it assembles from is built here (the four refs and the tarball checksums it computes itself), and
# assemble-release.sh runs on it with --lock exactly as a release runs, every guard on. One thing differs from a
# release: the Services pin lags rs main between batches (a pin-only Services pull request follows each rs batch), and
# the Diary packaging check (the Diary Dockerfile carries the lock's rs pin) would then refuse every run before the
# pairing guards are reached. So when a Services Dockerfile's NOEVIA_RS_REF / NOEVIA_RS_SHA256 differ from the rs ref
# being assembled, those two ARG lines (and only those) are rewritten in the Services tarball that is fetched, the way
# the pin-only Services pull request does, and a notice names the lag. Nothing else is changed.
#
# Reading a red run: the last lines are assemble-release.sh's own refusal, naming both sides ("... pairing: the Rust
# front ... but Core ..."). It means that pair of main commits cannot ship together as they stand: the front or Core
# side that moved last needs its counterpart (or the guard needs the new marker) before the next pin pull request.
# A run that cannot reach github.com is a failure of the run, not of a pair: its message is a download error.
set -euo pipefail

here="$(cd -- "$(dirname -- "$0")" && pwd)"
repo="$(cd -- "$here" && git rev-parse --show-toplevel)"
assemble="${ASSEMBLE_RELEASE:-$here/assemble-release.sh}"
remote_base="${MAINS_REMOTE_BASE:-https://github.com/sbstndalton}"
die() { echo "check-mains-assemble: $*" >&2; exit 1; }

refs_rs=""; refs_core=""; refs_web=""; refs_services=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rs) refs_rs="${2:-}"; shift 2 ;;
    --core) refs_core="${2:-}"; shift 2 ;;
    --web) refs_web="${2:-}"; shift 2 ;;
    --services) refs_services="${2:-}"; shift 2 ;;
    -*) die "unknown option $1" ;;
    *) out="$1"; shift ;;
  esac
done

work="$(mktemp -d "${TMPDIR:-/tmp}/check-mains.XXXXXX")"
trap 'rm -rf "$work"' EXIT
[ -n "$out" ] || { out="$work/out"; mkdir -p "$out"; }
[ -d "$out" ] || die "out-dir does not exist: $out"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
main_of() {
  local sha
  sha="$(git ls-remote "$remote_base/$1" refs/heads/main | cut -f1)"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "could not read $1's main"
  printf '%s' "$sha"
}
pick() { if [ -n "$1" ]; then printf '%s' "$1"; else main_of "$2"; fi; }
rs="$(pick "$refs_rs" noevia-rs)"; core="$(pick "$refs_core" noevia-core)"
web="$(pick "$refs_web" noevia-web)"; services="$(pick "$refs_services" noevia-services)"
for r in "$rs" "$core" "$web" "$services"; do [[ "$r" =~ ^[0-9a-f]{40}$ ]] || die "a ref is not a 40-hex sha: $r"; done

fetch() { # <repo> <ref> <file>
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$3" "https://codeload.github.com/sbstndalton/$1/tar.gz/$2" \
    || die "could not download $1 at $2"
}
mkdir -p "$work/tgz"
fetch noevia-rs "$rs" "$work/tgz/rs"; fetch noevia-core "$core" "$work/tgz/core"
fetch noevia-web "$web" "$work/tgz/web"; fetch noevia-services "$services" "$work/tgz/services"
rs_sum="$(sha256_of "$work/tgz/rs")"

# The Services tree's Rust pins follow the rs ref being assembled (see the header).
services_file="$work/tgz/services"; patched=no
mkdir -p "$work/sx"
tar -xzf "$services_file" -C "$work/sx"
sdir="$(find "$work/sx" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "$sdir" ] || die "the Services tarball has no top directory"
lagging=""
for svc in model-manager ocr diary docling laya; do
  df="$sdir/$svc/Dockerfile"
  [ -f "$df" ] || continue
  cur_ref="$(sed -n 's/^ARG NOEVIA_RS_REF=//p' "$df" | head -n 1)"
  if [ -n "$cur_ref" ] && [ "$cur_ref" != "$rs" ]; then
    lagging="$lagging $svc"
    sed -i.bak -e "s/^ARG NOEVIA_RS_REF=.*/ARG NOEVIA_RS_REF=$rs/" -e "s/^ARG NOEVIA_RS_SHA256=.*/ARG NOEVIA_RS_SHA256=$rs_sum/" "$df"
    rm -f "$df.bak"; patched=yes
  fi
done
if [ "$patched" = yes ]; then
  echo "::notice::the Services pin lags noevia-rs main (Dockerfiles of${lagging} pin another rs ref than $rs): assembled as if a pin-only Services pull request had landed"
  tar -czf "$work/tgz/services-patched" -C "$work/sx" "$(basename "$sdir")"
  services_file="$work/tgz/services-patched"
fi
services_sum="$(sha256_of "$services_file")"

lock="$work/versions.lock"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=%s\nNOEVIA_WEB_SHA256=%s\nNOEVIA_CORE_REF=%s\nNOEVIA_CORE_SHA256=%s\nNOEVIA_SERVICES_REF=%s\nNOEVIA_SERVICES_SHA256=%s\n' \
  "$rs" "$rs_sum" "$web" "$(sha256_of "$work/tgz/web")" "$core" "$(sha256_of "$work/tgz/core")" "$services" "$services_sum" > "$lock"
printf 'check-mains-assemble: rs %s core %s web %s services %s\n' "$rs" "$core" "$web" "$services"

# The assembler downloads again; serve it the files already fetched (and the patched Services tarball), so the
# checksums it verifies are the ones computed above and no ref moves between the two reads.
mkdir -p "$work/bin"
cat > "$work/bin/curl" <<SHIM
#!/usr/bin/env bash
dest=""; url=""
while [ \$# -gt 0 ]; do case "\$1" in -o) dest="\$2"; shift 2 ;; http*) url="\$1"; shift ;; *) shift ;; esac; done
case "\$url" in
  */noevia-rs/tar.gz/$rs) cp "$work/tgz/rs" "\$dest" ;;
  */noevia-core/tar.gz/$core) cp "$work/tgz/core" "\$dest" ;;
  */noevia-web/tar.gz/$web) cp "$work/tgz/web" "\$dest" ;;
  */noevia-services/tar.gz/$services) cp "$services_file" "\$dest" ;;
  *) echo "check-mains-assemble: unexpected download \$url" >&2; exit 1 ;;
esac
SHIM
chmod +x "$work/bin/curl"

sha="$(git -C "$repo" rev-parse HEAD)"
CI=true PATH="$work/bin:$PATH" bash "$assemble" --lock "$lock" "$sha" "$out"
echo "check-mains-assemble: assembled (every pairing guard passed)"
