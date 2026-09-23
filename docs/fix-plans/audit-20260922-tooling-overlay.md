# Repo-index and overlay deployment implementation plan

Issues: [#12](https://github.com/sbstndalton/noevia/issues/12), [#13](https://github.com/sbstndalton/noevia/issues/13)

## Scope

Repair repo-index regressions after the server split and make overlay releases remove OLD-only nested application code while retaining inherited dependencies and runtime state.

## Implementation

1. Decide and document whether search reports only enclosing top-level declarations or also nested functions. Update the `toolTokenBudgetFor` regression to target `server/toolboxes.cjs` and make tests assert that documented contract rather than the obsolete `index.cjs` layout.
2. Change the overlay Dockerfile sequence so application-owned `/app/server` content is replaced. Preserve `/app/server/node_modules` explicitly, since dependency reuse is the purpose of the overlay, and leave runtime-mounted state outside the image replacement.
3. Add a synthetic release fixture with OLD-only files under `server/routes` and another nested directory. Verify they disappear while NEW files and inherited dependencies remain.
4. Keep flattening, config equivalence checks, health waits, rollback, sidecar handling, and the native-engine identity check unchanged.

## Verification

- `node --test tools/repo-index/*.test.cjs` passes and returned ranges contain the intended declaration/enclosing scope.
- A no-Docker filesystem test covers replacement semantics; if feasible, an image test also checks `/app/server/node_modules` and the final manifest.
- Run deployment preflight/unit tests and shell syntax checking for the release script.

## Risks

Blindly removing `/app/server` would discard inherited dependencies and break the release. Moving dependencies aside must occur within the image build and restore permissions/ownership. Never operate on host appdata or mounted runtime paths during the image cleanup.
