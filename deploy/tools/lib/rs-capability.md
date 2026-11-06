# Shared Rust capability detector

`detect(sourceText, declarationName, capabilityLiteral, enabledFeatures = null)`
returns `v1`, `legacy`, or `invalid(reason)`. Only a direct ordinary string-literal
element can satisfy a query. Rust escapes decode before comparison. Paths are
ignored, including unresolved aliases to the queried literal. This is intentional:
this API proves literal declarations, not the evaluated contents of FEATURES.

The target must be exactly one crate-root `pub const` or immutable `pub static`
`&[&str]` initialized by `&[...]`; explicit `'static` lifetimes are supported.
Crate/declaration cfg and unknown attributes refuse. Nested target declarations
refuse; this helper does not infer re-exports. Inner attributes in closed unrelated
scopes do not affect the target. Unknown target shapes, raw/byte/C literals,
macros and non-path expressions refuse. Rust compilation remains required; this
is a bounded token-tree proof, not a full Rust parser.

Only duplicates of the queried literal refuse. Attributes/cfg and duplicate
literals on other elements are ignored. Harmless attributes on the queried
literal are allowed. One exact `#[cfg(feature = "F")]` is allowed alongside
harmless attributes, and succeeds only if F is enabled. A disabled feature is
`legacy`. Multiple cfg attributes, cfg_attr, not/any/all/target forms, and unknown
queried attributes refuse. A queried cfg with no derivable feature set refuses.
Unconditional literals do not require feature evidence.

`deriveFeatures(dockerfileText, cargoTomlText)` returns a Set or null. It recognizes
the production front-stage build's explicit feature seed and conditional grep
selectors, then expands default and transitive local features from that exact
source snapshot's manifest. It never executes shell code. Unsupported build
syntax/flags or feature-table syntax return null. Dependency-qualified features
are not local cfg features. Changes to the production build require updating this
bounded reader and its fixtures; no arbitrary environment supplies enabled flags.

The POSIX adapter defines `rs_capability_version FILE NAME LITERAL`. Set
`rs_capability_lib` to the absolute JS path before sourcing `rs-capability.sh`.
It runs `timeout -k 2 10 node`. The CLI derives features from the source's sibling
`../Cargo.toml` and this Top checkout's `build/web.Dockerfile` by default.
Set `rs_capability_build` to the Dockerfile actually compiling the release source;
the assembler uses `$tree/noevia/build/web.Dockerfile`. An optional
`rs_capability_cargo` explicitly selects the same-snapshot manifest. Missing build
or manifest evidence produces null, never an invented feature set.

Missing source files are `legacy`; read/runtime/helper failures are invalid.
Always reject `invalid(*)` before mapping `legacy` to older absence labels.
An exact `/1` query does not validate a protocol family; retain caller validation
for unknown/mixed versions. Scalar constants, startup calls and route registration
still require separate proofs.

Path-declared markers must migrate to a direct literal plus a compile-time const
string equality assertion against the referenced constant. This ties the literal
to Rust's actual marker without asking the release detector to resolve aliases.
See the private integration handoff for branch-specific recipes.

Run `TMPDIR=<evidence-dir> sh deploy/tools/test-rs-capability.sh`; the same fixture
suite runs under bash and dash, including enabled/disabled/underivable cfg cases,
production build/default-feature derivation, scope and tokenizer regressions.
