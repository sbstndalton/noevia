#!/usr/bin/env bash
set -eu
source "$(dirname "$0")/model-load-gate-pairing.sh"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/services/model-manager" "$work/rs/bins/noevia-inference-gate/src"
ref=1111111111111111111111111111111111111111
file="$work/rs/bins/noevia-inference-gate/src/lib.rs"
docker="$work/services/model-manager/Dockerfile"
ok() { model_load_gate_pairing "$work" "$ref"; }
no() { if ok 2>/dev/null; then echo "unexpected acceptance: $1"; exit 1; fi; }
printf 'ARG NOEVIA_RS_REF=%s\n' "$ref" > "$docker"
printf '%s\n' 'pub const FEATURES: &[&str] = &["noevia-model-load-settlement/1"];' > "$file"
ok
for text in  'pub const FEATURES: &[&str] = &[];'  '#[cfg(any())] pub const FEATURES: &[&str] = &["noevia-model-load-settlement/1"];'  'mod hidden { pub const FEATURES: &[&str] = &["noevia-model-load-settlement/1"]; }'  '#![cfg(any())]
 pub const FEATURES: &[&str] = &["noevia-model-load-settlement/1"];'  'pub const FEATURES: &[&str] = &["noevia-model-load-settlement/1", "noevia-model-load-settlement\x2f1"];'  'pub const FEATURES: &[&str] = &[r#"noevia-model-load-settlement/1"#];'  'pub const FEATURES: &[&str] = &[concat!("noevia-model-load-", "settlement/1")];'  'pub const FEATURES: &[&str] = &["noevia-model-load-settlement/2"];'; do
  printf '%s\n' "$text" > "$file"; no "$text"
done
printf '%s\n' 'pub const FEATURES: &[&str] = &["noevia-model-load-settlement/1"];' > "$file"
printf 'ARG NOEVIA_RS_REF=%040d\n' 2 > "$docker"; no stale-pin
printf 'ARG NOEVIA_RS_REF=%s\nARG NOEVIA_RS_REF=%s\n' "$ref" "$ref" > "$docker"; no duplicate-pin
printf ' ARG NOEVIA_RS_REF=%s\n' "$ref" > "$docker"; no ambiguous-pin
printf 'ARG NOEVIA_RS_REF=%s\n' "$ref" > "$docker"; ok
echo 'gate pairing: 13 checks passed'
