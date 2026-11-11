#!/usr/bin/env bash
# Synthetic pairing detectors: no archives, services, models or network.
set -eu
here="$(cd -- "$(dirname -- "$0")" && pwd)"
source_file=${1:-$here/assemble-release.sh}
work=$(mktemp -d "${TMPDIR:-/tmp}/residual-pairing.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/core/server" "$work/rs/bins/noevia-server/src"
core="$work/core/server/rust-residual-fallbacks.cjs"
rs="$work/rs/bins/noevia-server/src/lib.rs"
guard=$(sed -n '/^# BEGIN residual fallback pairing$/,/^# END residual fallback pairing$/p' "$source_file")
[ -n "$guard" ] || { echo 'missing residual pairing guard'; exit 1; }
passes=0
pair() ( tree=$work; die() { exit 1; }; eval "$guard"; )
check() {
  actual=0; pair || actual=$?
  if [ "$1" = pass ]; then [ "$actual" = 0 ]; else [ "$actual" != 0 ]; fi
  passes=$((passes+1)); echo "ok $passes - $2"
}
c() { printf '%s\n' 'module.exports.RUST_RESIDUAL_FALLBACKS_OWNED = "rust-residual-fallbacks-v1";' > "$core"; }
r() { printf '%s\n' 'pub const FEATURES: &[&str] = &["rust-residual-fallbacks-v1"];' > "$rs"; }
check pass legacy-legacy
c; check fail core-only
rm "$core"; r; check fail rust-only
c; check pass paired
for expression in '0' 'null' '"rust-residual-fallbacks-v2"' '(() => { throw Error(); })()'; do
  printf 'module.exports.RUST_RESIDUAL_FALLBACKS_OWNED = %s;\n' "$expression" > "$core"
  check fail "invalid Core export $expression"
done
printf '%s\n' 'Object.defineProperty(module.exports, "RUST_RESIDUAL_FALLBACKS_OWNED", { get() { while(true) {} } });' > "$core"
check fail bounded-export-getter
c
for entries in \
  '"rust-residual-fallbacks-v1", "rust-residual-fallbacks-v1"' \
  '"rust-residual-fallbacks-v1", "rust-residual-fallbacks-\x76\x31"' \
  '#[cfg(any())] "rust-residual-fallbacks-v1"' \
  'b"rust-residual-fallbacks-v1"' \
  'r#"rust-residual-fallbacks-v1"#' \
  'concat!("rust-residual-fallbacks-", "v1")' \
  'capability!("rust-residual-fallbacks-v1")' \
  '"rust-residual-fallbacks-v2"'; do
  printf 'pub const FEATURES: &[&str] = &[%s];\n' "$entries" > "$rs"
  check fail "invalid Rust entry $entries"
done
for prefix in '#[cfg(any())]' '#[cfg_attr(all(), cfg(any()))]' '#![cfg(any())]'; do
  printf '%s\npub const FEATURES: &[&str] = &["rust-residual-fallbacks-v1"];\n' "$prefix" > "$rs"
  check fail "gated declaration $prefix"
done
printf '%s\n' '#[cfg(any())] mod hidden { pub const FEATURES: &[&str] = &["rust-residual-fallbacks-v1"]; }' > "$rs"
check fail enclosing-module
printf '%s\n' 'pub const FEATURES: &[&str] = &[#[cfg(any())] "other", "rust-residual-fallbacks-v1"];' > "$rs"
check pass unrelated-gated-entry
printf '%s\n' '// rust-residual-fallbacks-v1' 'pub const FEATURES: &[&str] = &["other"];' > "$rs"
check fail comment-only-half-pair
rm "$core"
printf '%s\n' 'const CAP: &str = "rust-residual-fallbacks-v1"; pub const FEATURES: &[&str] = &[CAP];' > "$rs"
check fail named-alias-half-pair
printf '%s\n' 'const CAP: &str = concat!("rust-", "residual-fallbacks-v1"); pub const FEATURES: &[&str] = &[CAP];' > "$rs"
check fail concatenated-alias-half-pair
printf '%s\n' 'pub const FEATURES: &[&str] = concat!("rust-", "residual-fallbacks-v1");' > "$rs"
check fail opaque-declaration-half-pair
c; r; check pass restored-pair
printf 'pairing tests: %s passed\n' "$passes"
