# Shared Rust capability detector

`detect(sourceText, declarationName, capabilityLiteral)` from `rs-capability.cjs`
returns `v1`, `legacy`, or `invalid(reason)`. This API does not execute Rust or
resolve constants. It reads balanced Rust token trees; release sources must also
pass their normal Rust compilation checks. It is deliberately not a general Rust
parser or evaluator. Unknown syntax in the target declaration fails closed.

The supported target is exactly one crate-root `pub const` or immutable `pub static`
`&[&str]` initialized by `&[ordinary string literals]`. Explicit `'static` lifetimes
are supported. Rust escapes are decoded before checking duplicates. Raw/byte/C
strings, characters, macros, identifiers/paths and conditional elements refuse.
All duplicates refuse, including unrelated capabilities and escaped duplicates.
Harmless allow/warn/deny/forbid/doc/deprecated/must_use attributes are accepted;
other target/crate attributes refuse. Nested target declarations refuse because
this helper does not infer public re-exports or module reachability. Inner
attributes in closed unrelated scopes do not affect the crate-root target.

The POSIX adapter in `rs-capability.sh` defines `rs_capability_version FILE NAME
LITERAL`; set `rs_capability_lib` to the absolute JS path before sourcing it.
It runs `timeout -k 2 10 node`, converts runtime failures to `invalid(runtime)`,
and treats a missing source file as `legacy`. Check invalid first:

```sh
version=$(rs_capability_version "$source" FEATURES "$marker")
case "$version" in
  invalid\(*\)) die "cannot prove Rust capability: $version" ;;
esac
```

Callers using `none` for absence must explicitly map `legacy` to `none` after
checking invalid. A literal `/2` queried as `/1` is absent for that query: guards
that support multiple protocol versions must check each known literal and retain
their existing unknown-version/family validation. The detector does not infer
protocol versions from strings. Scalar markers, module declarations, route wiring
and startup calls require separate proofs; never replace those proofs with a
FEATURES presence check.

The assembler sources this helper for migration of pairing guards. Existing
legacy `move_capability` checks remain unchanged: current Rust FEATURES arrays
contain paths and cfg elements outside this stricter contract. Normalize those
sources before adopting strict guards, rather than silently accepting identifiers
or ignoring conditional elements.

Run `TMPDIR=<evidence-dir> sh deploy/tools/test-rs-capability.sh`. The same suite
runs under bash and dash. Fixtures preserve review inputs and branch provenance;
branch mutation cases are additionally normalized across the collected markers.
