#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/model-writes-pairing.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/model-writes-pair.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/core/server" "$work/rs/bins/noevia-server/src"
c="$work/core/server/rust-model-write-effects.cjs"
r="$work/rs/bins/noevia-server/src/lib.rs"
legacy() { echo 'module.exports = {};' > "$c"; echo 'pub const FEATURES: &[&str] = &[];' > "$r"; }
new_core() { echo 'module.exports = { MODEL_WRITES_OWNER: "rust-model-writes-d-v1" };' > "$c"; }
new_rs() { echo 'pub const FEATURES: &[&str] = &["rust-model-writes-d-v1"];' > "$r"; }
legacy; model_writes_pair "$work/core" "$work/rs"
new_core; if model_writes_pair "$work/core" "$work/rs"; then exit 1; fi
legacy; new_rs; if model_writes_pair "$work/core" "$work/rs"; then exit 1; fi
new_core; new_rs; model_writes_pair "$work/core" "$work/rs"
count=4
while IFS= read -r src; do
  printf '%s\n' "$src" > "$r"
  if model_writes_pair "$work/core" "$work/rs"; then echo "accepted invalid FEATURES: $src" >&2; exit 1; fi
  count=$((count+1))
done <<'CASES'
pub const FEATURES: &[&str] = &["rust-model-writes-d-v1", "rust-model-writes-d-v1"];
pub const FEATURES: &[&str] = &["rust-model-writes-d-v1", "rust-model-writes-d-\u{76}1"];
pub const FEATURES: &[&str] = &[#[cfg(any())] "rust-model-writes-d-v1"];
#[cfg(any())] pub const FEATURES: &[&str] = &["rust-model-writes-d-v1"];
#[cfg(any())] mod absent {pub const FEATURES: &[&str] = &["rust-model-writes-d-v1"];}
mod nested {pub const FEATURES: &[&str] = &["rust-model-writes-d-v1"];}
pub const FEATURES: &[&str] = &[b"rust-model-writes-d-v1"];
pub const FEATURES: &[&str] = &[r#"rust-model-writes-d-v1"#];
pub const FEATURES: &[&str] = &[concat!("rust-model-writes-d-", "v1")];
pub const FEATURES: &[&str] = &["rust-model-writes-d-v2"];
pub const FEATURES: &[&str] = &[other!(), "rust-model-writes-d-v1"];
pub const FEATURES: &[&str] = &[NAMED_CAPABILITY, "rust-model-writes-d-v1"];
#![cfg(any())] use std::fmt; pub const FEATURES: &[&str] = &["rust-model-writes-d-v1"];
CASES
mkdir -p "$work/rs/crates/server-projects/src"
module="$work/rs/crates/server-projects/src/research_jobs.rs"
lib="$work/rs/crates/server-projects/src/lib.rs"
echo 'pub mod research_jobs;' > "$lib"
echo 'pub const RESEARCH_JOBS_STORE_MARKER: &str = "noevia-research-jobs-store/1";' > "$module"
echo 'pub const FEATURES: &[&str] = &[server_projects::research_jobs::RESEARCH_JOBS_STORE_MARKER, "rust-model-writes-d-v1"];' > "$r"
model_writes_pair "$work/core" "$work/rs"; count=$((count+1))
for definition in 'pub const RESEARCH_JOBS_STORE_MARKER: &str = "rust-model-writes-d-v1";' '#[cfg(any())] pub const RESEARCH_JOBS_STORE_MARKER: &str = "noevia-research-jobs-store/1";' '/* pub const RESEARCH_JOBS_STORE_MARKER: &str = "noevia-research-jobs-store/1"; */'; do
  printf '%s\n' "$definition" > "$module"
  if model_writes_pair "$work/core" "$work/rs"; then exit 1; fi
  count=$((count+1))
done
new_rs
printf '%s\n' 'const MODEL_WRITES_OWNER = "rust-model-writes-d-v1"; module.exports = {};' > "$c"
if model_writes_pair "$work/core" "$work/rs"; then exit 1; fi
printf '%s\n' 'module.exports = {get MODEL_WRITES_OWNER() { while(true){} }};' > "$c"
if model_writes_pair "$work/core" "$work/rs"; then exit 1; fi
printf 'pairing fixtures: %s passed\n' "$((count+2))"
