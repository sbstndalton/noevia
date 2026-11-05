#!/usr/bin/env bash
# Focused synthetic detector proof, no repository downloads or live services.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:?set TMPDIR to evidence directory}/manager-read-pair.XXXXXX")
trap 'rm -rf "$work"' EXIT
sed -n '/^paired_core_version() {/,/^model_load_core_owner=/p' "$here/assemble-release.sh" | sed '$d' > "$work/functions.sh"
. "$work/functions.sh"
core=$work/core.cjs; rs=$work/lib.rs
check() { actual=$(eval "$2"); [ "$actual" = "$3" ] || { echo "FAIL $1: $actual != $3"; exit 1; }; echo "ok $1"; }
core_call='paired_core_version "$core" MANAGER_READ_MARKER noevia-model-manager-read-owner'
rs_call='paired_rs_version "$rs" noevia-model-manager-read-authority'
check missing-core "$core_call" none
check missing-rust "$rs_call" none
printf '%s\n' 'module.exports = { MANAGER_READ_MARKER: "noevia-model-manager-read-owner/1" };' > "$core"
check exported-core "$core_call" v1
printf '%s\n' 'pub const FEATURES: &[&str] = &["noevia-model-manager-read-authority/1"];' > "$rs"
check plain-rust "$rs_call" v1
for prefix in '#[cfg(any())] ' '#[cfg(any())] mod disabled { ' 'mod nested { ' 'macro_rules! hidden { () => { '; do
  printf '%s\n' "${prefix}pub const FEATURES: &[&str] = &[\"noevia-model-manager-read-authority/1\"];" > "$rs"
  check hidden-rust "$rs_call" invalid
done
for element in '#[cfg(any())] "noevia-model-manager-read-authority/1"' 'b"noevia-model-manager-read-authority/1"' 'r#"noevia-model-manager-read-authority/1"#' 'concat!("noevia-", "model-manager-read-authority/1")' '"noevia-model-manager-read-authority/1", "noevia-model-manager-read-authority\x2f1"'; do
  printf '%s\n' "pub const FEATURES: &[&str] = &[${element}];" > "$rs"
  check invalid-element "$rs_call" invalid
done
printf '%s\n' '#[cfg(any())] mod disabled { pub const FEATURES: &[&str] = &["noevia-model-load-authority/1"]; }' > "$rs"
check unprovable-unrelated-scope "$rs_call" invalid
printf '%s\n' '// noevia-model-manager-read-owner/1' 'module.exports = {};' > "$core"
check comment-core "$core_call" invalid
printf '%s\n' 'module.exports = { MANAGER_READ_MARKER: "noevia-model-manager-read-owner/2" };' > "$core"
check unknown-core "$core_call" invalid
