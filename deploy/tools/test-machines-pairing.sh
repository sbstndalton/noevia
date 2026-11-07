#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# Exercise the assembler's adapter and maintained source-literal proof, not a copied parser.
rs_capability_lib="$here/lib/rs-capability.cjs"
source "$here/lib/rs-capability.sh"
source <(sed -n '/^machines_core_version() {/,/^}/p; /^machines_rs_version() {/,/^}/p; /^check_machines_pair() {/,/^}/p' "$here/assemble-release.sh")
cases=0
expect_version() {
  local expected="$1" source="$2" observed
  printf '%s\n' "$source" > "$work/rs"
  observed=$(machines_rs_version "$work/rs")
  [ "$observed" = "$expected" ] || { echo "expected $expected, got $observed: $source"; exit 1; }
  cases=$((cases+1))
}
expect_pair() {
  local expected="$1" core="$2" observed=no
  if check_machines_pair "$core" "$work/rs"; then observed=yes; fi
  [ "$observed" = "$expected" ] || { echo "expected pairing $expected, got $observed"; exit 1; }
  cases=$((cases+1))
}
printf '%s\n' 'module.exports = {};' > "$work/legacy"
printf '%s\n' "module.exports.MACHINES_CLIENT_MARKER = 'noevia-inference-machines-client/1';" > "$work/core"
expect_version none 'pub const FEATURES: &[&str] = &[];'
expect_pair yes "$work/legacy"
expect_pair no "$work/core"
# Actual current-main research path is unrelated; B is still a direct literal.
expect_version v1 'pub const FEATURES: &[&str] = &[server_projects::research_jobs::RESEARCH_JOBS_STORE_MARKER, "rust-inference-machines"];'
expect_pair yes "$work/core"
expect_pair no "$work/legacy"
# Explicit Root adjudication: aliases do not prove declared literals, even when their
# text names the capability. This is no claim about evaluated Rust runtime features.
expect_version none 'const CAP: &str = "rust-inference-machines"; pub const FEATURES: &[&str] = &[CAP];'
expect_pair yes "$work/legacy"
expect_pair no "$work/core"
expect_version none 'const CAP: &str = concat!("rust-inference-", "machines"); pub const FEATURES: &[&str] = &[CAP];'
expect_pair yes "$work/legacy"
expect_pair no "$work/core"
expect_version v1 'pub static FEATURES: &[&str] = &["rust-inference-machines"];'
expect_pair yes "$work/core"
expect_pair no "$work/legacy"
# Unrelated paths also coexist with a decoded literal; actual duplicate queries refuse.
expect_version v1 'pub const FEATURES: &[&str] = &[OTHER, "rust-inference-\x6dachines"];'
for element in '"rust-inference-machines", "rust-inference-machines"' '"rust-inference-machines", "rust-inference-\x6dachines"' 'r"rust-inference-machines"' 'b"rust-inference-machines"' 'concat!("rust-inference-machines")' 'concat!("rust-inference-", "machines")' '#[cfg(any())] "rust-inference-machines"' '#[unknown] "rust-inference-machines"'; do
  expect_version invalid "pub const FEATURES: &[&str] = &[$element];"
  expect_pair no "$work/core"
  expect_pair no "$work/legacy"
done
for decl in '#[cfg(any())] pub const FEATURES: &[&str] = &["rust-inference-machines"];' '#[cfg(any())] mod inner { pub const FEATURES: &[&str] = &["rust-inference-machines"]; }' 'pub(crate) const FEATURES: &[&str] = &["rust-inference-machines"];' 'pub const FEATURES: &[&str] = make_features();'; do
  expect_version invalid "$decl"
done
# One supported feature cfg follows the same-snapshot build proof; it is not a
# blanket rejection of cfg. Missing build evidence remains invalid.
rs_capability_build="$here/fixtures/rs-capability/production.Dockerfile"
rs_capability_cargo="$here/fixtures/rs-capability/production-Cargo.toml"
expect_version v1 'pub const FEATURES: &[&str] = &[#[cfg(feature = "rust-storage-reads")] "rust-inference-machines"];'
expect_version none 'pub const FEATURES: &[&str] = &[#[cfg(feature = "disabled-feature")] "rust-inference-machines"];'
rs_capability_build="$work/missing.Dockerfile"
expect_version invalid 'pub const FEATURES: &[&str] = &[#[cfg(feature = "rust-storage-reads")] "rust-inference-machines"];'
printf '%s\n' "Object.defineProperty(module.exports,'MACHINES_CLIENT_MARKER',{get(){while(true){}}});" > "$work/core"
[ "$(machines_core_version "$work/core")" = invalid ]
cases=$((cases+1))
echo "machines pairing: $cases cases passed"
