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
sed -n '/^auto_roles_rs_owner() {/,/^}/p' "$here/assemble-release.sh" > "$work/rs.sh"
printf '\nauto_roles_rs_owner "$1"\n' >> "$work/rs.sh"
for mode in raw nested-comment outside-string duplicate unknown; do
  case "$mode" in
    raw) printf '%s\n' 'pub const FEATURES: &[&str] = &[r#"rust-auto-roles-write"#];' ;;
    nested-comment) printf '%s\n' '/* outer /* "rust-auto-roles-write-v2" */ comment */' 'pub const FEATURES: &[&str] = &["rust-auto-roles-write"];' ;;
    outside-string) printf '%s\n' 'const S: &str = r#"pub const FEATURES: &[&str] = &["rust-auto-roles-write-v2"];"#;' 'pub const FEATURES: &[&str] = &["rust-auto-roles-write"];' ;;
    duplicate) printf '%s\n' 'pub const FEATURES: &[&str] = &["rust-auto-roles-write", "rust-auto-roles-write"];' ;;
    unknown) printf '%s\n' 'pub const FEATURES: &[&str] = &["rust-auto-roles-write-v2"];' ;;
  esac > "$work/lib.rs"
  expected=rust; [[ "$mode" =~ ^(duplicate|unknown)$ ]] && expected=invalid
  check "Rust tokenizer $mode" "$expected" bash "$work/rs.sh" "$work/lib.rs"
done
printf 'passed %s, failed %s\n' "$passed" "$failed"
[ "$failed" = 0 ]
