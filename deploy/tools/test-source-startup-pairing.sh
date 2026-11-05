#!/usr/bin/env bash
set -euo pipefail
# Isolated fixtures, no fetches. Every detector process has its own 10-second deadline.
base=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/source-startup-pairing.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
sed -n '/^source_startup_core_version() {/,/^source_startup_core_owner=/p' "$base/assemble-release.sh" | sed '$d' > "$work/functions.sh"
. "$work/functions.sh"
count=0
check() {
  local expected=$1 js=$2 rs=$3
  printf '%s\n' "$js" > "$work/core.cjs"
  printf '%s\n' "$rs" > "$work/lib.rs"
  local c r result=refused
  c=$(source_startup_core_version "$work/core.cjs")
  r=$(source_startup_rs_version "$work/lib.rs")
  if [ "$c" != invalid ] && [ "$r" != invalid ] && [ "$c" = "$r" ]; then result=accepted; fi
  [ "$result" = "$expected" ] || { echo "fixture $count failed: $c/$r ($result != $expected)" >&2; exit 1; }
  count=$((count+1))
}
js="const RUST_SOURCE_STARTUP_OWNED = 'rust-source-startup-v1'; module.exports = { RUST_SOURCE_STARTUP_OWNED };"
rs='pub const FEATURES: &[&str] = &["rust-source-startup-v1"];'
check accepted "$js" "$rs"
check accepted 'module.exports = {};' 'pub const FEATURES: &[&str] = &[];'
check refused "$js" 'pub const FEATURES: &[&str] = &[];'
check refused 'module.exports = {};' "$rs"
check refused "$js" 'pub const FEATURES: &[&str] = &["rust-source-startup-v1", "rust-source-startup-v1"];'
check refused "$js" 'pub const FEATURES: &[&str] = &["rust-source-startup-v1", "rust-source-startup-\x761"];'
check refused "$js" '#[cfg(any())] pub const FEATURES: &[&str] = &["rust-source-startup-v1"];'
check refused "$js" '#[cfg(any())] mod hidden { pub const FEATURES: &[&str] = &["rust-source-startup-v1"]; }'
check refused "$js" '#![cfg(any())] pub const FEATURES: &[&str] = &["rust-source-startup-v1"];'
check refused "$js" 'pub const FEATURES: &[&str] = &[#[cfg(any())] "rust-source-startup-v1"];'
check refused "$js" 'pub const FEATURES: &[&str] = &[r"rust-source-startup-v1"];'
check refused "$js" 'pub const FEATURES: &[&str] = &[b"rust-source-startup-v1"];'
check refused "$js" 'pub const FEATURES: &[&str] = &[concat!("rust-source-startup-v1")];'
check refused "// rust-source-startup-v1
module.exports={};" "$rs"
check refused 'Object.defineProperty(module.exports,"RUST_SOURCE_STARTUP_OWNED",{get(){while(true){}}});' "$rs"
echo "source startup pairing: $count fixtures passed"
