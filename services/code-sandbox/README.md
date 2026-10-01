# code-sandbox

The container a coding harness runs in, and the ~100-line supervisor that starts it.

Code mode's rules live in noevia (`apps/web/server/code-*.cjs`): what a task may do, what needs
a human's answer, which paths it may write. **This container is what makes those rules hold when
the harness ignores them** — and the ACP spike showed one that did: with default settings
OpenCode wrote a file without asking, and every approved command ran in its own process rather
than through the client's terminal API. ACP events are evidence of intent; the container is the
boundary.

## What it is

`supervisor.cjs` accepts one connection, reads one line from noevia naming the worktree, spawns
the harness, and pipes. Everything after that first line is the ACP stream, byte for byte. It
decides nothing about permissions, paths or tools.

It does constrain what it is told:

- **`cwd` must resolve inside `WORKSPACE_ROOT`** after `realpath`, so a symlink cannot point out.
- **Only an allowlist of environment variables** is accepted (`HOME`, `PATH`, `LANG`, `TMPDIR`
  and the proxy variables). Nothing of the supervisor's own environment is passed on.
- **The connection is the lifetime.** Hanging up — a cancelled task, a restarted web container —
  kills the agent's process group. noevia never reaches across the container boundary.

There is no authentication, on purpose. The port is on an internal network with one member; a
deployment where anything else can reach it has already lost, and a shared secret in an
environment variable would imply otherwise. `deploy/examples/code-sandbox.override.yml` is the
control: read-only root, `cap_drop: ALL`, no-new-privileges, uid 1000, tmpfs `/tmp` and `$HOME`,
bounded memory and pids, one volume, no `ports:`.

## The verifier (#703)

The pipeline's "do the tests pass?" is answered by `verifier.cjs`, not by the agent and **not in
this container**. It ships in the same image but runs as its own service, `code-verify` in
`deploy/examples/code-sandbox.override.yml`. The agent runs here as uid 1000 with a writable
`/tmp` and `HOME`, so anything it leaves behind could otherwise reach the run that judges it: a
process that outlived its turn, an `.npmrc` `script-shell`, a `.gitconfig`, a `.pth`, or a swapped
loose object in a repository it can write.

- **Its own container:** uid 1002, `network_mode: none` (web reaches it over a unix socket on a
  volume only web and the verifier mount), its own tmpfs `/tmp` and `HOME`, the workspaces volume
  mounted **read-only**, read-only root, `cap_drop: ALL`, no-new-privileges, pids/memory/CPU
  limits. The agent sandbox has no verify mode at all.
- **The command is the operator's:** `CODE_VERIFY=name|command` (one per line, names as in web's
  `CODE_REPOS`), set only on `code-verify`. noevia sends a repository name, the source path and a
  commit, never a command, and nothing in the repository decides what runs. Unset means
  verification is off.
- **A verified copy:** `git clone --no-local` from the read-only source into the run's tmpfs. The
  pack protocol makes index-pack recompute every object id, and `git fsck` runs on the copy. HEAD
  and its tree must equal the requested commit. A source whose `.git/config` names anything git
  would run (hooks path, fsmonitor, filters, includes, upload-pack settings …) is refused. noevia
  itself only asks for the current tip of a **released** branch, never one an agent still holds.
- **The run:** fixed environment (`PATH`, `LANG`, `CI`, `NO_COLOR`, and a fresh `HOME`/`TMPDIR` in
  the run's own scratch directory; no proxy variables). Stdin closed, no core dumps, CPU limit per
  process, `CODE_VERIFY_WALL_MS` (default 10 min, covering the copy and the run), one run at a
  time, and the process group is killed at the end or when noevia hangs up.
- **Output is data:** a rolling tail of `CODE_VERIFY_TAIL_BYTES` (default 16 KiB) inside one JSON
  result line. Run directories are removed after each run and leftovers are swept at start;
  removal failures are logged.

Tests that write must use `$TMPDIR` (the copy is read-only), and with no network the repository
must run without installing dependencies.

**Shipping it** needs a code-sandbox image release (new `verifier.cjs`, socket directory) **and**
the new `code-verify` container. See `docs/deployment.md` under Code mode.

## Why not the Docker socket

Running `docker run` per task from the web container would mean giving that container the Docker
socket. `docs/research-master-container.md` recorded a socket holder reachable without
authentication as the highest-severity finding open on this deployment. A sidecar on an internal
network gives the same isolation and adds no such power.

## Two things staging this proved

Both were found by building the image on DaServer and running the escape probes against it,
before any harness run:

- **The worktrees must be on the shared volume**, not in the tenant's state directory. noevia
  sends an absolute path and the supervisor resolves that same path, so they have to be the same
  path: one volume, one mount point, both containers. `CODE_WORKSPACE_ROOT` does this.
- **A fresh workspace is root-owned and the sandbox is not root**, so the harness could not write
  the tree it was given (`write /workspaces: Permission denied` in the probes).
  `CODE_HARNESS_USER=1000:1000` hands each one over as it is created, and a handover that fails
  refuses the task rather than starting a harness that cannot work.
- **A handed-over git *worktree* cannot commit.** A worktree keeps its objects and refs in the
  source repository's `.git`, which the harness cannot write — proven here: read, edit and `git
  status` all worked, `git commit` failed. So with a separate harness user noevia gives the task a
  `git clone --shared` instead: a repository it fully owns, with the source read-only to it and no
  objects copied (120 KB for the scratch fixture). On release noevia fetches the branch back into
  the source, never forced — a branch that would not fast-forward is a conflict for a human. A
  fetch that fails keeps the clone and marks the claim stuck, because a task's work is not ours to
  discard quietly.
- **The `$HOME` tmpfs needs `uid=1000,gid=1000`** or the harness cannot write its own
  `.gitconfig`; a bare `mode=0700` tmpfs belongs to root.

## Running it

Built and started only with the `code` profile; see the override file's header for the
environment the web container needs. `CODE_HARNESS_ENDPOINT` takes precedence over
`CODE_HARNESS_COMMAND`, so a deployment that has a sandbox cannot silently fall back to running
the agent beside noevia's own state.

The harness version is pinned as a build argument. An agent that updates itself is a
supply-chain change nobody reviewed, in the one container allowed to run arbitrary commands.

## pi (not installed by default)

pi has no permission prompts of its own and speaks JSONL RPC rather than ACP. noevia pins it with
a gate extension written into the task's `~/.pi/agent/` (`server/code-harness-config.cjs`) and
bridges it with `pi-acp-bridge.cjs`, which turns the gate's confirm into an ACP
`session/request_permission`, so pi's commands reach the same approval card as any harness. The
bridge can only turn a question into "no" by itself. Installing pi in this image is the user's
decision (a supply-chain change); see docs/spec-agent-execution.md.
