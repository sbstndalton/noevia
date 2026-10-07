# Repo split cutover runbook (#952)

> **Done 2026-10-07.** Cut at noevia `f42f65f1271ef27bf697bf7e069c232468479791`: noevia-web
> `9ca6a48375624df2751bfdee1a3657aae8f25bd1`, noevia-core `93d180a199f06769be2c12f47277637f06c354c7`,
> noevia-services `54449fce271398da58117d280ca8089058fff0cc` (pinned in `release/versions.lock`).
> Identity at the cut (git level, release trees and web image) was proven by
> [CI run 37559918085](https://github.com/sbstndalton/noevia/actions/runs/37559918085). The
> cutover landed as one squash commit (PR #958); rollback is `git revert` of that commit (see
> Rollback). Choices made at the cutover: `tools/repo-index` moved to noevia-core (it indexes the
> server code); the `experiments/` harness workflows lay the pinned noevia-core out at `apps/web`
> in CI (never committed; the CI guard refuses it); release folders on the box are the unpacked assembled
> tree, which keeps every sidecar's `services/<name>` path. The steps below are the record.

Completes [ADR 0001](adr-0001-rust-and-repo-split.md): `apps/web/` and `services/` move out of
noevia into three repos, the way `clients/macos/` moved to noevia-macos in #900.

| Repo | Gets (noevia path -> repo path) |
| --- | --- |
| [noevia-web](https://github.com/sbstndalton/noevia-web) | `apps/web/{src,public,scripts,contracts,qa,tests/client,tests/hermetic-network.cjs,index.html,vite.config.ts,tsconfig.json,package.json,package-lock.json,.gitignore,.dockerignore}` -> same name at the root |
| [noevia-core](https://github.com/sbstndalton/noevia-core) | `apps/web/{server,contracts,tests/server,tests/fixtures,tests/hermetic-network.cjs}` -> same name; `services/code-sandbox` -> `code-sandbox` |
| [noevia-services](https://github.com/sbstndalton/noevia-services) | `services/{diary,docling,laya,model-manager,ocr}` -> `diary`, `docling`, ... |

`apps/web/Dockerfile` (the monorepo image build) is not extracted. Until the cutover it stays as
the reference the assembled image is compared with; **the cutover deletes it** together with the
rest of `apps/web/`, and `build/web.Dockerfile` (already in noevia) becomes the only web image
recipe. `repo-split map` prints the exact table.

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

Do these in one sitting, on a quiet main. Nothing here touches DaServer; the next release after the
cutover is a normal release.

1. **Freeze and pick the cut sha.** The UI redo, **PR #953 (issue #951), must be merged first**.
   Make sure no other open PR still edits `apps/web/` or `services/` (merge or rebase them first;
   anything merged after the cut is lost from the split repos).
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
   each head. Inspect them (`git -C tools/repo-split/out/noevia-web log --stat -3`). Then publish:
   ```sh
   tools/repo-split/target/release/repo-split extract --source . --sha "$CUT" --force --push
   ```
   The push is guarded: it replaces a repo's `main` only if that is missing, already the new head,
   or itself an extraction (its commit has a `Split-Source:` trailer), and it pushes with
   `--force-with-lease`. If someone committed to a split repo, the push stops; find out why, then
   either fold the change into noevia first or replace it deliberately with
   `--target <repo> --push --replace-remote <its current main sha>`. The extraction is
   reproducible, so the second run yields the same SHAs.
3. **Pin the SHAs.** Compute each tarball checksum (a pinned ref without one is refused):
   ```sh
   curl -fsSL https://codeload.github.com/sbstndalton/noevia-web/tar.gz/<sha> | shasum -a 256
   ```
   On the cutover branch, first update `release/split-candidate.lock` (cut sha, refs, SHA256s),
   push, and let CI prove byte identity at the new cut (both split jobs green). This run is the
   last image comparison against `apps/web/Dockerfile`; keep its URL in the PR body.
4. **Make the cutover commit.** One commit on the same branch, merged as a **single squash
   commit**, so rollback is one revert (see Rollback):
   - copy the three `_REF`/`_SHA256` pairs into `release/versions.lock`, replacing `self`;
   - `git rm -r apps/web services/diary services/docling services/laya services/model-manager services/ocr services/code-sandbox`
     (this deletes `apps/web/Dockerfile` too);
   - add the CI guard (step 5);
   - fix what pointed at the deleted paths:
     - `compose*.yaml` build contexts (`./apps/web`, `./services/*`): releases build from the
       assembled tree (`web/` + `core/` with `build/web.Dockerfile`, `core/code-sandbox`,
       `services/<name>`); update the live release flow in `docs/deployment.md` and
       `deploy/tools/build-web-release.sh` / `overlay-release.sh` to assemble first. The
       overlay-per-sidecar flow keeps its per-service tags.
     - `.github/workflows/ci.yml`: drop the jobs that now run in the split repos (node-tests,
       python-tests, docling/model-manager/ocr/laya/code-sandbox tests, the `apps/web` image build)
       and their path filters. Replace the assembled-release matrix with one job that assembles
       from `release/versions.lock`, builds `build/web.Dockerfile` and boots it (`/api/ready`).
       **After the cutover there is no monorepo build left to compare with**, so the image
       byte-identity check retires: its last result is the step-3 run, which proved the pinned
       repos build the same image as `apps/web/Dockerfile` at the cut sha. From then on each
       split repo's CI owns its tests and image build. Delete `release/split-candidate.lock`.
     - `tools/repo-index` imports `apps/web/server/tool-result-reduce.cjs`: point it at a
       noevia-core checkout or move it to noevia-core.
     - Docs that link `apps/web/...` or `services/...` (AGENTS.md, agent-brief, roadmap,
       deployment.md, DEPLOY.md): point at the new repos.
   - Server tests that read `deploy/examples/code-sandbox.override.yml` or
     `tools/embed-parity-check.cjs` keep working through the split repos' noevia-shaped CI
     workspace; nothing to do unless those files move.
5. **CI guard** (part of the step-4 commit), in the `changes` job of `.github/workflows/ci.yml`
   next to the macOS one. It covers all of `apps/web`, so the deleted `apps/web/Dockerfile` cannot
   return either:
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

## Rollback

Because step 4 lands as one squash commit, rollback is `git revert <that commit>` on a branch,
merged like any PR. The revert restores `apps/web/` (including `apps/web/Dockerfile`), the six
service folders, `self` for all three refs in `release/versions.lock`, the old CI jobs and
`release/split-candidate.lock`, and removes the guard. Releases go back to the monorepo flow
unchanged.

The split repos are **left alone**: no deletion, no force-push. Anything committed there after
the cutover (step 6) has to be brought back into noevia by hand (a patch per commit) before the
next release, because the reverted noevia no longer reads those repos. To retry the cutover
later, start again at step 1; the guarded push will refuse to overwrite such commits until they
are handled.

## If GitHub changes its archive format

The `_SHA256` values pin codeload tarball bytes, not git content. If GitHub changes how it
compresses or orders those archives (it did briefly in 2023), every pinned checksum stops matching
and assembly fails with "tarball checksum mismatch" even though nothing changed. To re-pin:

1. Confirm the content is unchanged: `repo-split verify --source . --sha <cut or release sha>
   --target <web|core|services> --split <fresh clone> --rev <pinned ref>` (the git-level check
   does not depend on archive bytes), or compare `tar -tzvf` listings of the old and new archive.
2. Recompute each checksum with the `curl ... | shasum -a 256` line from step 3 and update the
   `_SHA256` values in `release/versions.lock` (and `release/split-candidate.lock` before the
   cutover) in one PR whose body says why. The refs do not change.
3. The same applies to `NOEVIA_RS_SHA256` in the model-manager Dockerfile (`services/model-manager/` here, `model-manager/` in noevia-services after the cutover).

## Re-running before the cutover

To refresh the candidate (for example to re-prove identity after PR #953 lands), repeat steps
1-3 but stop after updating `release/split-candidate.lock`; leave `release/versions.lock` at `self`
and do not delete anything.
