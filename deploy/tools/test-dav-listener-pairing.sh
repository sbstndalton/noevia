#!/usr/bin/env bash
set -euo pipefail
# Isolated fixtures, no fetches. Every detector process has its own 10-second deadline.
base=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/dav-listener-pairing.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
sed -n '/^dav_listener_core_version() {/,/^dav_listener_core_owner=/p' "$base/assemble-release.sh" | sed '$d' > "$work/functions.sh"
. "$work/functions.sh"
count=0
check() {
  local expected=$1 js=$2 rs=$3
  printf '%s\n' "$js" > "$work/core.cjs"
  printf '%s\n' "$rs" > "$work/lib.rs"
  local c r result=refused
  c=$(dav_listener_core_version "$work/core.cjs")
  r=$(dav_listener_rs_version "$work/lib.rs")
  if [ "$c" != invalid ] && [ "$r" != invalid ] && [ "$c" = "$r" ]; then result=accepted; fi
  [ "$result" = "$expected" ] || { echo "fixture $count failed: $c/$r ($result != $expected)" >&2; exit 1; }
  count=$((count+1))
}
js="const RUST_DAV_LISTENER_OWNED = 'rust-dav-listener-v1'; module.exports = { RUST_DAV_LISTENER_OWNED };"
rs='pub const FEATURES: &[&str] = &["rust-dav-listener-v1"];'
check accepted "$js" "$rs"
check accepted 'module.exports = {};' 'pub const FEATURES: &[&str] = &[];'
check refused "$js" 'pub const FEATURES: &[&str] = &[];'
check refused 'module.exports = {};' "$rs"
check refused "$js" 'pub const FEATURES: &[&str] = &["rust-dav-listener-v1", "rust-dav-listener-v1"];'
check refused "$js" 'pub const FEATURES: &[&str] = &["rust-dav-listener-v1", "rust-dav-listener-\x761"];'
check refused "$js" '#[cfg(any())] pub const FEATURES: &[&str] = &["rust-dav-listener-v1"];'
check refused "$js" '#[cfg(any())] mod hidden { pub const FEATURES: &[&str] = &["rust-dav-listener-v1"]; }'
check refused "$js" '#![cfg(any())] pub const FEATURES: &[&str] = &["rust-dav-listener-v1"];'
check refused "$js" 'pub const FEATURES: &[&str] = &[#[cfg(any())] "rust-dav-listener-v1"];'
check refused "$js" 'pub const FEATURES: &[&str] = &[r"rust-dav-listener-v1"];'
check refused "$js" 'pub const FEATURES: &[&str] = &[b"rust-dav-listener-v1"];'
check refused "$js" 'pub const FEATURES: &[&str] = &[concat!("rust-dav-listener-v1")];'
check refused "// rust-dav-listener-v1
module.exports={};" "$rs"
check refused 'Object.defineProperty(module.exports,"RUST_DAV_LISTENER_OWNED",{get(){while(true){}}});' "$rs"
echo "DAV listener pairing: $count fixtures passed"
