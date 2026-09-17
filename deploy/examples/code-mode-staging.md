# Code mode — staged, off

Everything here is prepared on DaServer and **nothing is running**. Code mode is unreachable:
the web container has no `CODE_*` environment and `features.codeHarness` is off, so its routes
return 404. A copy of this file sits at `/mnt/docker/appdata/cowork/tools/CODE-MODE-READY.md`.

Prepared 2026-09-17, release `1fe3f1b`:

- **`cowork-code-sandbox:1fe3f1b`** — image built, OpenCode 1.18.31 pinned at build time, runs
  as uid 1000.
- **`cowork_code-workspaces` volume**:
  - `repos/scratch` — a throwaway git repository whose `median()` has two deliberate bugs
    (lexicographic in-place sort; no averaging of the middle two on an even-length list) and a
    `test.js` that must not be edited. This is what the first real run should be pointed at,
    **not** noevia's own source.
  - `trees/` — owned by `1000:1000`, where per-task clones are created.
- **`code-sandbox.override.yml`** beside this file on the server — the compose override,
  deliberately **not wired into the Compose Manager project**: bringing it up would add a
  network and a volume to the running web container for no benefit while the feature is off.

## Verified on the box, not merely intended

Escape probes against the image under the override's hardening:

| Probe | Result |
|---|---|
| write `/etc`, `/srv` | refused (read-only root) |
| write the source repo as the harness | refused |
| Docker socket present | absent |
| secrets in the environment | none |
| `su root` | authentication failure |
| harness version | 1.18.31, `uid=1000(node)` |
| task clone: edit, `git status`, `git commit` | all succeed |
| noevia fetching the task branch back | succeeds |

## What staging found, and the code now handles

1. **Worktrees must live on the shared volume**, at a path identical in both containers —
   noevia sends an absolute path and the supervisor resolves that same path
   (`CODE_WORKSPACE_ROOT`).
2. **A new workspace is root-owned and the harness is not root**, so it must be handed over
   (`CODE_HARNESS_USER`). A handover that fails refuses the task.
3. **A handed-over git *worktree* cannot commit** — its objects and refs live in the source
   repository's `.git`, which the harness cannot write. With a separate harness user a task
   therefore gets `git clone --shared`: a repository it owns, the source read-only to it, no
   objects copied, and the branch fetched back on release.
4. **The tmpfs mounts need `uid=1000,gid=1000`**, not just a mode, or the harness cannot write
   its own `.gitconfig`.

## To actually turn it on

1. Add to the live Compose override, on `web` (keeping a `.bak.before-code-mode` copy as always):

   ```
   NOEVIA_FEATURE_CODE_HARNESS=true
   CODE_HARNESS_ENDPOINT=code-sandbox:8030
   CODE_REPOS=scratch|/workspaces/repos/scratch
   CODE_WORKSPACE_ROOT=/workspaces/trees
   CODE_HARNESS_USER=1000:1000
   ```

   plus `code-workspaces:/workspaces` mounted on web, and web and the sandbox both on the
   internal `code` network.
2. Bring it up with the `code` profile.
3. Run one task against `scratch` and read every approval before answering it.

Do not point it at a repository that matters until that has been done once. The whole contract
is still tested only against a scripted fake agent.
