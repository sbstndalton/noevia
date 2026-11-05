#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# Exercise the exact detector shipped by the assembler.
source <(sed -n '/^machines_core_version() {/,/^}/p; /^machines_rs_version() {/,/^}/p; /^check_machines_pair() {/,/^}/p' "$here/assemble-release.sh")
printf '%s\n' "module.exports = {};" > "$work/core"
printf '%s\n' 'pub const FEATURES: &[&str] = &[];' > "$work/rs"
check_machines_pair "$work/core" "$work/rs"
printf '%s\n' "module.exports.MACHINES_CLIENT_MARKER = 'noevia-inference-machines-client/1';" > "$work/core"
if check_machines_pair "$work/core" "$work/rs"; then exit 1; fi
printf '%s\n' 'pub const FEATURES: &[&str] = &["rust-inference-machines"];' > "$work/rs"
check_machines_pair "$work/core" "$work/rs"
printf '%s\n' 'module.exports = {};' > "$work/legacy"
if check_machines_pair "$work/legacy" "$work/rs"; then exit 1; fi
for element in '"rust-inference-machines", "rust-inference-machines"' '"rust-inference-machines", "rust-inference-\x6dachines"' 'r"rust-inference-machines"' 'b"rust-inference-machines"' 'concat!("rust-inference-machines")' '#[cfg(any())] "rust-inference-machines"' 'OTHER'; do
  printf 'pub const FEATURES: &[&str] = &[%s];\n' "$element" > "$work/rs"
  if check_machines_pair "$work/core" "$work/rs"; then echo "accepted invalid element: $element"; exit 1; fi
done
for wrap in '#[cfg(any())] pub const FEATURES: &[&str] = &["rust-inference-machines"];' '#[cfg(any())] mod inner { pub const FEATURES: &[&str] = &["rust-inference-machines"]; }'; do
  printf '%s\n' "$wrap" > "$work/rs"
  if check_machines_pair "$work/core" "$work/rs"; then echo 'accepted gated declaration'; exit 1; fi
done
printf '%s\n' "Object.defineProperty(module.exports,'MACHINES_CLIENT_MARKER',{get(){while(true){}}});" > "$work/core"
[ "$(machines_core_version "$work/core")" = invalid ]
echo 'machines pairing: 14 cases passed'
