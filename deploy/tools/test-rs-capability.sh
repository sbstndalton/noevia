#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
rs_capability_lib="$here/lib/rs-capability.cjs"
. "$here/lib/rs-capability.sh"
# Every shell uses the production timeout and CLI, as well as the source-text API.
timeout -k 2 10 node "$here/test-rs-capability.cjs"
timeout -k 2 10 node "$here/test-rs-feature-proof.cjs"
: "${TMPDIR:?set TMPDIR to an evidence directory}"
work=$(mktemp -d "$TMPDIR/rs-capability.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
printf '%s\n' 'mod unrelated { #![cfg(test)] fn helper() {} }' 'pub const FEATURES: &[&str] = &["cap"];' > "$work/source.rs"
[ "$(rs_capability_version "$work/source.rs" FEATURES cap)" = v1 ]
[ "$(rs_capability_version "$work/source.rs" FEATURES absent)" = legacy ]
printf '%s\n' 'const ALIAS: &str = "cap"; pub const FEATURES: &[&str] = &[ALIAS];' > "$work/source.rs"
[ "$(rs_capability_version "$work/source.rs" FEATURES cap)" = legacy ]
[ "$(rs_capability_version "$work/absent" FEATURES cap)" = legacy ]
# Runtime failures and invalid output must never become absence.
rs_capability_lib="$work/missing.cjs"
case "$(rs_capability_version "$work/source.rs" FEATURES cap)" in invalid\(*\)) ;; *) exit 1;; esac
rs_capability_lib="$here/lib/rs-capability.cjs"
rs_capability_build="$here/fixtures/rs-capability/production.Dockerfile"
rs_capability_cargo="$here/fixtures/rs-capability/production-Cargo.toml"
printf '%s\n' 'pub const FEATURES: &[&str] = &[#[cfg(feature = "rust-storage-reads")] "cap"];' > "$work/source.rs"
[ "$(rs_capability_version "$work/source.rs" FEATURES cap)" = v1 ]
printf '%s\n' 'pub const FEATURES: &[&str] = &[#[cfg(feature = "disabled-feature")] "cap"];' > "$work/source.rs"
[ "$(rs_capability_version "$work/source.rs" FEATURES cap)" = legacy ]
rs_capability_build="$work/missing.Dockerfile"
case "$(rs_capability_version "$work/source.rs" FEATURES cap)" in invalid\(*\)) ;; *) exit 1;; esac
printf '%s\n' 'shell adapter: 8 passed'
