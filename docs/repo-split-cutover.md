# Repo split cutover runbook (#952)

Completes [ADR 0001](adr-0001-rust-and-repo-split.md): `apps/web/` and `services/` move out of
noevia into three repos, the way `clients/macos/` moved to noevia-macos in #900.

| Repo | Gets (noevia path -> repo path) |
| --- | --- |
| [noevia-web](https://github.com/sbstndalton/noevia-web) | `apps/web/{src,public,scripts,contracts,qa,tests/client,tests/hermetic-network.cjs,index.html,vite.config.ts,tsconfig.json,package.json,package-lock.json,.gitignore,.dockerignore}` -> same name at the root |
| [noevia-core](https://github.com/sbstndalton/noevia-core) | `apps/web/{server,contracts,tests/server,tests/fixtures,tests/hermetic-network.cjs}` -> same name; `services/code-sandbox` -> `code-sandbox` |
| [noevia-services](https://github.com/sbstndalton/noevia-services) | `services/{diary,docling,laya,model-manager,ocr}` -> `diary`, `docling`, ... |

`apps/web/Dockerfile` stays in noevia (the monorepo image build is retired at cutover; releases
build `build/web.Dockerfile` from the assembled tree). `repo-split map` prints the exact table.

## What exists before the cutover

- **`tools/repo-split`** (Rust, no dependencies): `extract` clones noevia at a commit
  (`git clone --no-local`), keeps one ref, and runs `git filter-repo` with the path filters and
  renames above, so each repo keeps the history of its paths (including the pre-2026-09-03 `ui/`
  location of the client and server). It then adds one scaffold commit from
  `tools/repo-split/scaffold/<repo>/` (CI workflow, README) with a fixed identity, the cut
  commit's date and a `Split-Source: <cut sha>` trailer, so a re-run at the same sha produces the
  same commit SHAs. It refuses a cut commit that has an `apps/web/` or `services/` entry no repo
  maps, so a new service cannot be dropped silently. `verify` is the byte-identity check (same git
  mode and object id for every mapped path, nothing else in the repo but the scaffold).
  - Wrapping `git filter-repo` instead of rewriting history in Rust is deliberate: filter-repo is
    the tool git's own documentation recommends for this, and re-implementing a fast-export /
    fast-import rewriter would be far more code to get wrong. The Rust side owns everything noevia
    decides: the map, the coverage check, reproducibility and verification.
- **The three repos**, public like noevia-rs and noevia-macos, holding an extraction of noevia
  `677ddfaa` (origin/main on 2026-10-06), each with its own CI. Their CI builds a noevia-shaped
  workspace (noevia `main` + the sibling repos' `main` + the repo itself, each at its old path),
  because several tests cross repo lines (server tests read `src/`, the OCR test reads
  `server/pdf-reduce.cjs`, model-manager tests read `docs/spec-model-loader-api-v1.md`).
- **`release/split-candidate.lock`**: the cut sha and the three repos' pinned SHAs (+ tarball
  SHA256). CI only; nothing releases from it.
- **`release/versions.lock`** has `NOEVIA_SERVICES_REF=self` next to the web/core keys; all three
  stay `self`, so releases are unchanged.
- **CI in noevia**:
  - "Repo split tool and byte identity": the tool's tests, then `repo-split verify` of each
    pinned repo against the cut sha.
  - "Assembled release dry run (split)": `assemble-release.sh --lock release/split-candidate.lock`
    at the cut sha must give web/, core/ (including code-sandbox/) and services/ trees identical to
    a `self` assembly of the same sha (every sidecar's build context), and a web image whose files,
    packages, config and hashes match `apps/web/Dockerfile` built from the cut sha.

Until the cutover, **noevia is the source of truth**. Do not commit to the split repos: the cutover
force-replaces their history with a fresh extraction.

## Cutover steps

Do these in one sitting, after the in-flight UI work (#951) has merged, on a quiet main. Nothing
here touches DaServer; the next release after the cutover is a normal release.

1. **Freeze and pick the cut sha.** Make sure no open PR still edits `apps/web/` or `services/`
   (merge or rebase them first; anything merged after the cut is lost from the split repos).
   ```sh
   git fetch origin && CUT=$(git rev-parse origin/main)
   ```
2. **Re-run the extraction at the cut sha** (from a noevia checkout that has this tool; needs
   `git filter-repo` and the Rust toolchain):
   ```sh
   cargo build --release --manifest-path tools/repo-split/Cargo.toml
   tools/repo-split/target/release/repo-split extract --source . --sha "$CUT" --force
   ```
   It writes `tools/repo-split/out/noevia-{web,core,services}`, verifies byte identity, and prints
   each head. Inspect them (`git -C tools/repo-split/out/noevia-web log --stat -3`). Then publish,
   which **replaces** the repos' history:
   ```sh
   tools/repo-split/target/release/repo-split extract --source . --sha "$CUT" --force --push
   ```
   (or the `git -C ... push --force` line it printed). The extraction is reproducible, so the
   second run yields the same SHAs.
3. **Pin the SHAs.** Compute each tarball checksum:
   ```sh
   curl -fsSL https://codeload.github.com/sbstndalton/noevia-web/tar.gz/<sha> | shasum -a 256
   ```
   On a noevia branch, first update `release/split-candidate.lock` (cut sha, refs, SHA256s) and
   let CI prove byte identity at the new cut (both split jobs green). Then copy the three
   `_REF`/`_SHA256` pairs into `release/versions.lock`, replacing `self`.
4. **Delete the extracted paths from noevia** in the same PR:
   `git rm -r apps/web services/diary services/docling services/laya services/model-manager services/ocr services/code-sandbox`.
   Then fix what pointed at them:
   - `compose*.yaml` build contexts (`./apps/web`, `./services/*`): releases build from the
     assembled tree (`web/`, `core/code-sandbox`, `services/<name>`); update the live release flow
     in `docs/deployment.md` and `deploy/tools/build-web-release.sh` / `overlay-release.sh` to
     assemble first. The overlay-per-sidecar flow keeps its per-service tags.
   - `.github/workflows/ci.yml`: drop the jobs that now run in the split repos (node-tests,
     python-tests, docling/model-manager/ocr/laya/code-sandbox tests, the `apps/web` image build)
     and their path filters; keep deploy-tests, the assembled-release dry run (switch the `self`
     mode to the pinned lock) and repo-split. `self` is no longer valid once the paths are gone.
   - `tools/repo-index` imports `apps/web/server/tool-result-reduce.cjs`: point it at a noevia-core
     checkout or move it to noevia-core.
   - `apps/web/server` tests that read `deploy/examples/code-sandbox.override.yml` or
     `tools/embed-parity-check.cjs` keep working through the split repos' noevia-shaped CI
     workspace; nothing to do unless those files move.
   - Docs that link `apps/web/...` or `services/...` (AGENTS.md, agent-brief, roadmap,
     deployment.md, DEPLOY.md): point at the new repos.
5. **Add CI guards** in the `changes` job of `.github/workflows/ci.yml`, next to the macOS one:
   ```yaml
   - name: Guard against re-added split paths
     run: |
       for p in apps/web services/diary services/docling services/laya services/model-manager services/ocr services/code-sandbox; do
         if [ -e "$p" ]; then
           echo "::error::$p/ must not exist in this repo. It lives in noevia-web, noevia-core or noevia-services (#952); make the change there."
           exit 1
         fi
       done
   ```
6. **Open the split repos for work.** Remove the "do not commit here yet" paragraph from each
   README (a normal commit in each repo), and from then on bump the pinned SHAs in
   `release/versions.lock` like `NOEVIA_RS_REF`. Each repo's CI keeps using noevia `main` for
   the integration files.
7. **First release after the cutover**: assemble (`deploy/tools/assemble-release.sh <noevia sha>`)
   and build from the tree; `COWORK_VERSION` stays the noevia sha and `version.json` records the
   web/core SHAs. Live-test as usual.

## Re-running before the cutover

To refresh the candidate (for example to re-prove identity after the UI work lands), repeat steps
1-3 but stop after updating `release/split-candidate.lock`; leave `release/versions.lock` at `self`
and do not delete anything.
