#!/usr/bin/env bash
# Focused release capability proof, including disabled declarations and imports.
set -eu
here=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/autotune-pairing.XXXXXX")
trap 'rm -rf "$work"' EXIT
sed -n '/^at_core_version()/,/^autotune_state_pairing()/p' "$here/assemble-release.sh" | sed '$d' > "$work/detectors.sh"
. "$work/detectors.sh"
tree=$work/tree
mkdir -p "$tree/core/server" "$tree/rs/crates/server-projects/src" "$tree/rs/bins/noevia-server/src"
marker=$tree/rs/crates/server-projects/src/autotune_state.rs
project=$tree/rs/crates/server-projects/src/lib.rs
server=$tree/rs/bins/noevia-server/src/lib.rs
core=$tree/core/server/autotune-state-client.cjs
valid() {
  echo 'module.exports.AUTOTUNE_STATE_CLIENT_MARKER = "noevia-autotune-state-client/1";' > "$core"
  echo 'pub const AUTOTUNE_STATE_STORE_MARKER: &str = "noevia-autotune-state-store/1";' > "$marker"
  echo 'pub mod autotune_state;' > "$project"
  echo 'pub mod autotune_state;' > "$server"
}
check() { [ "$2" = "$3" ] || { echo "FAIL $1: expected $3 got $2"; exit 1; }; echo "ok $1"; }
valid
check paired-core "$(at_core_version "$core")" v1
check paired-store "$(at_store_version)" v1
for file in "$marker" "$project" "$server"; do
  for attr in '#[cfg(any())]' '#[cfg_attr(all(), cfg(any()))]' '#![cfg(any())]'; do
    valid
    { echo "$attr"; cat "$file"; } > "$work/disabled"
    cp "$work/disabled" "$file"
    check "disabled $file $attr" "$(at_store_version)" invalid
  done
done
for expr in 'r"noevia-autotune-state-store/1"' 'b"noevia-autotune-state-store/1"' 'concat!("noevia-autotune-state-store/1")'; do
  valid
  echo "pub const AUTOTUNE_STATE_STORE_MARKER: &str = $expr;" > "$marker"
  check "ambiguous $expr" "$(at_store_version)" invalid
done
valid
{ echo 'mod hidden {'; cat "$marker"; echo '}'; } > "$work/nested"
cp "$work/nested" "$marker"
check nested-marker "$(at_store_version)" invalid
valid
cat "$marker" >> "$work/duplicate"
cat "$work/duplicate" >> "$marker"
check duplicate-marker "$(at_store_version)" invalid
valid
rm "$project"
check unreachable-module "$(at_store_version)" invalid
valid
rm "$core" "$marker"
check legacy-core "$(at_core_version "$core")" none
check legacy-store "$(at_store_version)" none
