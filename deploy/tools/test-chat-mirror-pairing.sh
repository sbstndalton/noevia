#!/usr/bin/env bash
# Synthetic direct fixtures for the reviewed release detectors; no network.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
work=$(mktemp -d "${TMPDIR:-/tmp}/chat-mirror-pairing.XXXXXX")
trap 'rm -rf "$work"' EXIT
sed -n '/^chat_mirror_core_version()/,/^chat_mirror_core_owner=/{ /^chat_mirror_core_owner=/d; p; }' "$here/assemble-release.sh" > "$work/functions.sh"
. "$work/functions.sh"
n=0
check() { local got; got=$("$@"); [ "$got" = "$expected" ] || { echo "FAIL: $* expected $expected got $got"; exit 1; }; n=$((n+1)); }
rs() { printf 'pub const FEATURES: &[&str] = &[%s];\n' "$1" > "$work/lib.rs"; }
expected=v1
printf '%s\n' "const RUST_CHAT_MIRROR_OWNED = 'rust-chat-mirror-v1';" 'module.exports = { RUST_CHAT_MIRROR_OWNED };' > "$work/core.cjs"
check chat_mirror_core_version "$work/core.cjs"
rs '"rust-chat-mirror-v1"'; check chat_mirror_rs_version "$work/lib.rs"
printf '%s\n' "const RUST_CHAT_MIRROR_OWNED = ['rust-chat-', 'mirror-v1'].join('');" "const { x } = require('./missing.cjs');" 'module.exports = { RUST_CHAT_MIRROR_OWNED, x };' > "$work/core.cjs"
check chat_mirror_core_version "$work/core.cjs"
rs '"rust-chat-mirror-v\u{31}"'; check chat_mirror_rs_version "$work/lib.rs"
for inner in '#![allow(dead_code)]' '#![allow(dead_code)] #![warn(missing_docs)]'; do
  printf '%s\npub const FEATURES: &[&str] = &["rust-chat-mirror-v1"];\n' "$inner" > "$work/lib.rs"
  check chat_mirror_rs_version "$work/lib.rs"
done
expected=none
rs '"legacy"'; check chat_mirror_rs_version "$work/lib.rs"
expected=invalid
for entry in '#[cfg(any())] "rust-chat-mirror-v1"' '"rust-chat-mirror-v1", "rust-chat-mirror-v1"' '"rust-chat-mirror-v1", "rust-chat-mirror-v\x31"' 'b"rust-chat-mirror-v1"' 'r#"rust-chat-mirror-v1"#' 'concat!("rust-chat-mirror-v", "1")' '"rust-chat-mirror-v2"'; do
  rs "$entry"; check chat_mirror_rs_version "$work/lib.rs"
done
for prefix in '#[cfg(any())]' '#[cfg(feature = "disabled")]' '#![cfg(any())]' '#![cfg_attr(any(), allow(dead_code))]' '#![allow(dead_code)] #[cfg(any())]'; do
  printf '%s\npub const FEATURES: &[&str] = &["rust-chat-mirror-v1"];\n' "$prefix" > "$work/lib.rs"
  check chat_mirror_rs_version "$work/lib.rs"
done
for scope in '#[cfg(any())] mod disabled' 'mod inner' 'macro_rules! hidden'; do
  printf '%s { pub const FEATURES: &[&str] = &["rust-chat-mirror-v1"]; }\n' "$scope" > "$work/lib.rs"
  check chat_mirror_rs_version "$work/lib.rs"
done
printf '%s\n' "const RUST_CHAT_MIRROR_OWNED = 'rust-chat-mirror-v1';" 'module.exports = {};' > "$work/core.cjs"
check chat_mirror_core_version "$work/core.cjs"
printf '%s\n' "module.exports = { RUST_CHAT_MIRROR_OWNED: 'wrong' };" > "$work/core.cjs"
check chat_mirror_core_version "$work/core.cjs"
printf '%s\n' "const RUST_CHAT_MIRROR_OWNED = 'rust-chat-mirror-v1';" 'for (;;) {}' 'module.exports = { RUST_CHAT_MIRROR_OWNED };' > "$work/core.cjs"
check chat_mirror_core_version "$work/core.cjs"
printf '%s\n' "module.exports = { RUST_CHAT_MIRROR_OWNED: { toString: () => 'rust-chat-mirror-v1' } };" > "$work/core.cjs"
check chat_mirror_core_version "$work/core.cjs"
rs '"rust-chat-mirror-v1"'; echo 'pub const FEATURES: &[&str] = &["rust-chat-mirror-v1"];' >> "$work/lib.rs"
check chat_mirror_rs_version "$work/lib.rs"
for src in '#[cfg(any())] fn main() { ChatMirror::start(); }' 'fn main() { #[cfg(any())] { ChatMirror::start(); } }' '#[cfg(any())] mod hidden { fn main() { ChatMirror::start(); } }'; do
  printf '%s\n' "$src" > "$work/main.rs"; check chat_mirror_start_enabled "$work/main.rs" 'ChatMirror\s*::\s*start\s*\('
done
expected=v1
printf '%s\n' '#[tokio::main] async fn main() { ChatMirror::start(); }' > "$work/main.rs"
check chat_mirror_start_enabled "$work/main.rs" 'ChatMirror\s*::\s*start\s*\('
printf 'passed %s\n' "$n"
