#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${TMPDIR:?set TMPDIR to the private evidence folder}"
work=$(mktemp -d "$TMPDIR/reranker-pairing.XXXXXX")
trap 'rm -rf "$work"' EXIT
sed -n '/^reranker_core_version() {/,/^reranker_core_owner=/p' "$here/assemble-release.sh" | sed '$d' > "$work/detectors.sh"
source "$work/detectors.sh"
check() { local got; got=$($1 "$2"); test "$got" = "$3" || { echo "$1 expected $3 got $got"; exit 1; }; }
printf "module.exports.RERANKER_SETTINGS_OWNER='reranker-settings-v1';\n" > "$work/core"
printf 'pub const FEATURES: &[&str] = &["reranker-settings-v1"];\n' > "$work/rs"
check reranker_core_version "$work/core" v1
check reranker_rs_version "$work/rs" v1
check reranker_core_version "$work/absent" none
check reranker_rs_version "$work/absent" none
# Paired, two half-pairs and legacy/legacy.
test "$(reranker_core_version "$work/core")" = "$(reranker_rs_version "$work/rs")"
test "$(reranker_core_version "$work/core")" != "$(reranker_rs_version "$work/absent")"
test "$(reranker_core_version "$work/absent")" != "$(reranker_rs_version "$work/rs")"
test "$(reranker_core_version "$work/absent")" = "$(reranker_rs_version "$work/absent")"
for src in \
 'pub const FEATURES: &[&str] = &["reranker-settings-v1","reranker-settings-v1"];' \
 'pub const FEATURES: &[&str] = &["reranker-settings-v1","reranker-settings-\x76\x31"];' \
 'pub const FEATURES: &[&str] = &[#[cfg(any())] "reranker-settings-v1"];' \
 '#[cfg(any())] pub const FEATURES: &[&str] = &["reranker-settings-v1"];' \
 '#[cfg(any())] mod hidden { pub const FEATURES: &[&str] = &["reranker-settings-v1"]; }' \
 'pub const FEATURES: &[&str] = &[r"reranker-settings-v1"];' \
 'pub const FEATURES: &[&str] = &[b"reranker-settings-v1"];' \
 'pub const FEATURES: &[&str] = &[concat!("reranker-settings-","v1")];' \
 'pub const FEATURES: &[&str] = &[concat!("reranker","-settings-v1")];'; do
 printf '%s\n' "$src" > "$work/bad"; check reranker_rs_version "$work/bad" invalid
done
printf '%s\n' "pub const FEATURES: &'static [&str] = &[\"reranker-settings-v1\"];" > "$work/bad"
check reranker_rs_version "$work/bad" invalid
# A legacy unrelated reference is accepted only after proving its module and literal value.
base="$work/legacy"
mkdir -p "$base/bins/noevia-server/src" "$base/crates/server-projects/src"
printf 'pub mod source_jobs;\n' > "$base/crates/server-projects/src/lib.rs"
printf 'pub const SOURCE_JOBS_STORE_MARKER: &str = "noevia-source-jobs-store/1";\n' > "$base/crates/server-projects/src/source_jobs.rs"
printf 'pub const FEATURES: &[&str] = &[server_projects::source_jobs::SOURCE_JOBS_STORE_MARKER];\n' > "$base/bins/noevia-server/src/lib.rs"
check reranker_rs_version "$base/bins/noevia-server/src/lib.rs" none
printf 'pub const FEATURES: &[&str] = &[UNKNOWN_ALIAS];\n' > "$work/bad"
check reranker_rs_version "$work/bad" invalid
printf '#[cfg(any())] pub mod source_jobs;\n' > "$base/crates/server-projects/src/lib.rs"
check reranker_rs_version "$base/bins/noevia-server/src/lib.rs" invalid-source
printf 'pub mod source_jobs;\n' > "$base/crates/server-projects/src/lib.rs"
printf 'pub const SOURCE_JOBS_STORE_MARKER: &str = "reranker-settings-v1";\n' > "$base/crates/server-projects/src/source_jobs.rs"
check reranker_rs_version "$base/bins/noevia-server/src/lib.rs" invalid-source
printf "Object.defineProperty(module.exports,'RERANKER_SETTINGS_OWNER',{get(){while(true){}}});\n" > "$work/bad"
check reranker_core_version "$work/bad" invalid
# Exercise the production refusal block as well as the detectors.
sed -n '/^reranker_core_owner=/,/^$/p' "$here/assemble-release.sh" > "$work/guard.sh"
assert_pair() {
  local expected=$1 core_file=$2 rs_file=$3 tree="$work/pair"
  rm -rf "$tree"
  mkdir -p "$tree/core/server" "$tree/rs/bins/noevia-server/src"
  [ "$core_file" = none ] || cp "$core_file" "$tree/core/server/rerank-settings.cjs"
  [ "$rs_file" = none ] || cp "$rs_file" "$tree/rs/bins/noevia-server/src/lib.rs"
  if (die() { echo "$*" >&2; exit 1; }; source "$work/guard.sh") >"$work/guard.log" 2>&1; then
    [ "$expected" = pass ] || { echo 'half-pair unexpectedly accepted'; exit 1; }
  else
    [ "$expected" = fail ] || { cat "$work/guard.log"; exit 1; }
    grep -q 'reranker settings ownership pairing' "$work/guard.log"
  fi
}
assert_pair pass "$work/core" "$work/rs"
assert_pair fail "$work/core" none
assert_pair fail none "$work/rs"
assert_pair pass none none
assert_pair fail "$work/bad" "$work/rs"
echo 'reranker pairing fixtures passed'
