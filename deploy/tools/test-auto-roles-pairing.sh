#!/usr/bin/env bash
set -euo pipefail
here="$(cd -- "$(dirname -- "$0")" && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
passed=0; failed=0
check() { local name=$1 expected=$2; shift 2; local got rc=0
  got="$(timeout -k 2 5 "$@" 2>/dev/null)" || rc=$?
  if [ "$rc" = 0 ] && [ "$got" = "$expected" ]; then echo "ok - $name"; passed=$((passed+1))
  else echo "FAIL - $name: rc=$rc got=$got expected=$expected"; failed=$((failed+1)); fi
}
for script in "$here/assemble-release.sh" "$here/../../build/web-supervisor.sh"; do
  sed -n '/^auto_roles_core_owner() {/,/^}/p' "$script" > "$work/core.sh"
  printf '\nauto_roles_core_owner "$1"\n' >> "$work/core.sh"
  for mode in no-export evaluation getter proxy; do
    case "$mode" in
      no-export) printf '%s\n' 'module.exports = {};' ;;
      evaluation) printf '%s\n' 'while (true) {}' ;;
      getter) printf '%s\n' 'module.exports = {get RUST_AUTO_ROLES_WRITE_OWNED() {while (true) {}}};' ;;
      proxy) printf '%s\n' 'module.exports = new Proxy({}, {get() {while (true) {}}});' ;;
    esac > "$work/module.cjs"
    check "$(basename "$script") $mode is bounded and refused" invalid bash "$work/core.sh" "$work/module.cjs"
  done
done
# The reviewed pre-tokenizer guard needs its awk prelude too, for valid before evidence.
sed -n "/^auto_roles_awk_strip='/,/^'/p" "$here/assemble-release.sh" > "$work/rs.sh"
sed -n '/^auto_roles_rs_owner() {/,/^}/p' "$here/assemble-release.sh" >> "$work/rs.sh"
printf '\nauto_roles_rs_owner "$1"\n' >> "$work/rs.sh"
for mode in raw bytes raw-bytes nested-comment outside-string duplicate unknown concat attribute gated escaped-duplicate escaped-alone unicode continuation byte-constant; do
  case "$mode" in
    raw) printf '%s\n' 'pub const FEATURES: &[&str] = &[r#"rust-auto-roles-write"#];' ;;
    bytes) printf '%s\n' 'pub const FEATURES: &[&str] = &[b"rust-auto-roles-write"];' ;;
    raw-bytes) printf '%s\n' 'pub const FEATURES: &[&str] = &[br#"rust-auto-roles-write"#];' ;;
    concat) printf '%s\n' 'pub const FEATURES: &[&str] = &[concat!("rust-auto-roles-write", "-v2")];' ;;
    attribute) printf '%s\n' 'pub const FEATURES: &[&str] = &[#[cfg(feature = "rust-auto-roles-write")] "unrelated"];' ;;
    gated) printf '%s\n' 'pub const FEATURES: &[&str] = &[#[cfg(feature = "enabled")] "rust-auto-roles-write"];' ;;
    escaped-duplicate) printf '%s\n' 'pub const FEATURES: &[&str] = &["rust-auto-roles-write", "\x72ust-auto-roles-write"];' ;;
    escaped-alone) printf '%s\n' 'pub const FEATURES: &[&str] = &["\x72ust-auto-roles-write"];' ;;
    unicode) printf '%s\n' 'pub const FEATURES: &[&str] = &["\u{72}ust-auto-roles-write"];' ;;
    continuation) printf '%s\n' 'pub const FEATURES: &[&str] = &["rust-auto-roles-\' ' write"];' ;;
    byte-constant) printf '%s\n' 'const UNUSED: &[u8] = b"\xFF";' 'pub const FEATURES: &[&str] = &["rust-auto-roles-write"];' ;;
    nested-comment) printf '%s\n' '/* outer /* "rust-auto-roles-write-v2" */ comment */' 'pub const FEATURES: &[&str] = &["rust-auto-roles-write"];' ;;
    outside-string) printf '%s\n' 'const S: &str = r#"pub const FEATURES: &[&str] = &["rust-auto-roles-write-v2"];"#;' 'pub const FEATURES: &[&str] = &["rust-auto-roles-write"];' ;;
    duplicate) printf '%s\n' 'pub const FEATURES: &[&str] = &["rust-auto-roles-write", "rust-auto-roles-write"];' ;;
    unknown) printf '%s\n' 'pub const FEATURES: &[&str] = &["rust-auto-roles-write-v2"];' ;;
  esac > "$work/lib.rs"
  expected=rust; [[ "$mode" =~ ^(raw|bytes|raw-bytes|duplicate|unknown|concat|attribute|gated|escaped-duplicate)$ ]] && expected=invalid
  check "Rust tokenizer $mode" "$expected" bash "$work/rs.sh" "$work/lib.rs"
done
# Exercise the production pairing condition with a decoded capability and no Core bridge.
mkdir -p "$work/pair/core/server" "$work/pair/rs/bins/noevia-server/src"
printf '%s\n' 'pub const FEATURES: &[&str] = &["\x72ust-auto-roles-write"];' > "$work/pair/rs/bins/noevia-server/src/lib.rs"
{
  printf '%s\n' 'die() { printf refused; exit 0; }' 'tree=$1'
  sed -n '/^auto_roles_core_owner() {/,/^}/p' "$here/assemble-release.sh"
  sed -n '/^auto_roles_rs_owner() {/,/^}/p' "$here/assemble-release.sh"
  sed -n '/^auto_roles_write_owner=.*auto_roles_core_owner/,/Core and Rust must move together/p' "$here/assemble-release.sh"
  printf '%s\n' 'printf accepted'
} > "$work/pair.sh"
check "escaped capability refuses a Core lacking the bridge" refused bash "$work/pair.sh" "$work/pair"
# Pass the actual Rust lib.rs when validating the paired source artifact.
if [ -n "${1:-}" ]; then check "real Rust FEATURES" rust bash "$work/rs.sh" "$1"; fi
printf 'passed %s, failed %s\n' "$passed" "$failed"
[ "$failed" = 0 ]
