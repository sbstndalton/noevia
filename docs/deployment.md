# Deployment and release operations

This public guide describes the release process. It is not an inventory of any running
installation. Keep host addresses, accounts, filesystem layouts, Compose Manager copies,
backup locations, credentials, and deployment receipts in an operator-owned local runbook.
`deploy/private/` is ignored by this repository; verify that local records remain untracked
before committing. Do not place them in a cloud-synced folder or attach them to an issue.

## Releasing after the repo split (#952)

The integration repository contains Compose definitions, deployment helpers, documentation,
and `release/versions.lock`. The client, core, services, and Rust workspace live in separate
repositories. An archive of this repository alone is not a complete application release.

1. Select reviewed commits with green CI. Record the exact integration commit and component
   refs. Preserve the current release and rollback configuration locally.
2. Assemble the pinned source with `deploy/tools/assemble-release.sh <commit> <output-dir>`.
   Verify the archive and recorded checksums. Use the supported build flow described by
   [DEPLOY.md](../DEPLOY.md), the helper usage, and the selected release's contracts.
3. Build and qualify the candidate before changing the active release. Keep disposable test
   state separate from production mounts. No test may read or modify a real Diary corpus.
4. Validate the installation's effective Compose configuration and writable mounts. Generic
   repository Compose files do not automatically synchronize with an operator's saved copies.
5. Back up configuration and application state with the installation's approved procedure;
   verify the backup and recovery inputs before cutover.
6. Check idle jobs, model activity, and the installation's backup/maintenance windows. Recreate
   only the services covered by the approved release, through the required preflight wrapper.
7. Verify readiness, selected image identities, native capabilities, scoped state integrity,
   and logs. Record what passed, what was skipped, and the rollback decision locally.

Keep `cowork`-prefixed environment variables, image names, container identities, cookies,
state paths, and storage keys compatible. Documentation cleanup does not migrate them.
Preserve configured remote inference endpoints and intentionally stopped model containers.
Do not start a model, benchmark, or deployment simply to check this guide.

## Settings and native-service compatibility

Model execution may use a self-hosted inference service, external providers, or an optional
local runtime. Retain the service-role boundaries, authentication, tenant isolation, write
approvals, and endpoint validation whichever execution path is configured.

At a native-image boundary, review the exact release contract before removing retired selector
keys. Keep the old image, its configuration, and its selector values together for rollback.
Do not copy historical selector lists into a newer release without checking current support.
`NOEVIA_RUST_PROJECT_WRITES` is retired: chat-context routes are always native, so do not set it for
a current image; the supervisor warns and ignores it. Set it only to roll back to an older image that
still reads it.

Native model-manager startup requires its configured roots and publisher lists to validate.
For an image transition requiring a publisher-data seed, use
`deploy/tools/seed-search-trusted.sh` against a verified compatible predecessor image. Preserve
an existing administrator-owned file and validate it; a missing or malformed publisher set
must refuse startup. The source image, output path, and release boundary are local runbook
inputs. The production image is not a source for data it no longer ships.

Filesystem ownership guards remain enforced. Inspect the actual candidate mounts rather
than recursively changing permissions or weakening validation. Retain the exact timezone,
trusted-set, startup, writer-lease, shutdown, and process-ownership requirements of the release.

## Native egress is a release prerequisite (#2226)

A current Core has no in-process egress proxy. With `CODE_EGRESS_PORT` set, web stops at startup unless the native
egress profile is deployed beside it, so a release from an older image must add it in the same cutover:

- Build `deploy/egress-proxy`, target `native-control`, from the release tree and tag it through `EGRESS_RS_VERSION`.
- Prepare a new control key directory as `deploy/examples/code-egress-rust.override.yml` describes.
- Add the `egress-rs` service and the web settings to the operator's Compose files. Publish no ports. Keep web's
  `egress` alias on the code network: the model relay and the code-network refusal still use it.
- Qualify with `CANDIDATE_EGRESS_IMAGE=<image> deploy/tools/candidate-boot.sh <sha>`. Also boot with the installation's
  effective configuration, using synthetic state and secrets.

The installed preflight refuses `CODE_EGRESS_PORT` without this profile. `CODE_EGRESS_PORT` unset or `0` boots but
removes network access for Code and Browser tasks, so it is a decision, not a fix.

Behaviour to plan for. Web and `egress-rs` can start in either order and either can restart. While `egress-rs` is away,
new Code and Browser network grants are refused, the Code and Browser panels report no network and web logs
`egress.control_unavailable`. Web retries with a backoff of at most 15 s, then logs `egress.control_ready` with
`recovered: true`. A task that was running keeps its old token, which no new session accepts: it stays without network
until it ends. A wrong egress profile (key directory, ids, port) is a configuration error and still stops web at
startup. Rolling back to an image older than this requirement
must restore that image's Compose files, environment file and preflight `check.php`, and remove `egress-rs`.

## Diary model settings gate (#2105)

A Diary that runs the strict model selection refuses every answer when its configured chat or aux id is not
served by the chat router and no explicit fallback is set. Set the Diary's model settings (or
`LLM_CHAT_FALLBACK_MODEL` / `LLM_AUX_FALLBACK_MODEL`, which the deployed Compose files must map into the
Diary service) to served ids in the operator-owned environment file before the cutover. Both overlay scripts
run `diary-models-check.sh` from the installed preflight directory before anything changes. It resolves the
deployed Compose project with that environment file, reads the Diary service's effective environment, and
compares it with the router's model list using one read-only request. It never wakes a model, and it refuses
on an unserved id, a fallback that the Diary service does not receive, a missing key, an unreachable router or
a Compose configuration that does not resolve. It is stricter than the Diary itself. See
[deploy/preflight/README.md](../deploy/preflight/README.md).

## Release idle gate: Coding jobs (#1391)

Use `deploy/tools/release-idle-jobs.sh` and its companion against the selected application
image. A malformed, unreadable, or symlinked job store, a missing strict-mode implementation,
a timeout, or a failed container command refuses cutover. An absent job directory alone may
count as no jobs. The gate must not mutate job state or print account identifiers.

## Overlay releases

An overlay is appropriate only when the existing image and the candidate's dependency and
runtime contracts permit it. Read `deploy/examples/overlay-release.sh` and
`deploy/examples/diary-overlay.sh` before selecting this flow; inspect their actual service
scope. An overlay is not automatically web-only. Qualify the resulting image before activating
it, and do not use an overlay to bypass required native binaries or changed dependencies.

### Diary overlay

`deploy/examples/diary-overlay.sh` starts from the Diary image that is currently running and replaces
whole the directories that the Diary image's `Dockerfile` copies into `/app`, so a change to the system
prompt, `config.yaml` or a helper script ships together with the agent code (#2112):

Diary overlay directories: `agent/`, `config/`, `scripts/`

Before anything is built, stopped or changed the script reads the release's own Diary `Dockerfile` and
refuses when its `COPY <dir>/ ./<dir>/` lines name a different set of directories (it names the one it
would leave out). Every `COPY` and `ADD` of the final stage counts: besides `COPY requirements.txt .` and the
binaries taken from the Rust stage, any other copying line (a file, `--chown`, a hyphenated directory, `ADD`,
JSON form) stops the overlay, because it would put content in the image that the overlay does not ship. It also
refuses when the release's `requirements.txt` differs from the one in the running image. After the build it compares each directory in the candidate with the release tree (file
names and sha256) and refuses on any difference, so a file the release dropped does not survive. A change to
`requirements.txt` or to any other part of the `Dockerfile` (apart from the noevia-rs pin, whose binaries the
script builds) needs a rebuild, not this overlay. A test
(`OverlayDirsInSync` in `deploy/tests/test_overlay_scripts.py`) keeps this line, the script's list and the
fixture `Dockerfile` the same; with `NOEVIA_SERVICES_DIR` set to a noevia-services checkout it compares the
real `diary/Dockerfile` too.

### Document extraction app-only overlay

Use this flow only when the document extraction service's Python app files changed and its native binary, dependency locks and downloaded models did not. The overlay starts from the document extraction image that is currently running and replaces exactly the app files that the production image copies into `/app/`. The whole overlay is these two lines:

```Dockerfile
FROM <running-document-extraction-image>
COPY extract.py isolated_worker.py selftest.py synthetic_pdfs.py /app/
```

The file list must match the final `COPY <files> ./` in the production stage of the document extraction service's `Dockerfile` in the noevia-services repository. Since #1071 the Python HTTP server (`server.py`) and its supervisor (`isolation.py`) are no longer in that list: the native server in the image is the only owner. An overlay does not delete files, so an image overlaid from one that still carries them keeps two unused files; nothing starts them. The native binary itself changes only with a rebuild, not with this overlay. A services test, `test_overlay_docs_list_exactly_the_files_the_dockerfile_copies_to_app` in `docling/test_requirements_pinned.py`, enforces that this line lists the same files, so a change to that Dockerfile line must update this one in the same change. Qualify the resulting image before activating it, as for any overlay.

## The deploy

The operator's local runbook supplies the SSH target, application origin, release root,
environment file, saved Compose project, preflight installation path, and previous release.
Use explicitly configured values, not addresses copied from historical public notes. Keep
secrets out of URLs, command output, issue bodies, commit messages, and screenshots.

When Compose Manager is used, confirm the files the manager actually reads. Back up each
operator-owned copy before a scoped change. Always use the installed preflight entry point;
launching directly from a GUI may bypass mount and idle checks.

## Verification and rollback

Passing unit tests is not proof of a live user workflow. Distinguish local tests, CI, packaged
candidate checks, deployment readiness, authenticated UI verification, and model inference.
Use synthetic accounts and data for functional checks. Live tests need their own authorization.

Retain the previous assembled release, image identities, environment, and Compose files.
Rollback must restore the matching configuration and scoped services. Do not overwrite live
SQLite files or restore application data merely to revert an image. Recovery involving data
requires its own verified backup and migration plan. Preserve old releases until the operator's
retention policy permits removal.

Keep exact backup paths, host/service inventories, recovery manifests, and deployment evidence
outside version control. Public release notes should describe software behavior and validation
limits rather than the private state of an installation.

## Inference gate (#2115)

The chat router holds one model at a time. Before this gate, a request for another model unloaded
the one in use, even while it was answering another chat. The gate sits in front of the router and
admits one chat model at a time:

- A turn for another model waits in the gate's queue, and web shows that it is waiting.
- The gate unloads the previous model only once nothing is using it.
- An unload of a model that is answering a request is refused. An administrator can force it with
  the gate's admin token.

It ships in the model manager image (`noevia-inference-gate`) and runs as its own service, so a
model-manager restart never touches it. Its contract is in the pinned Rust
`bins/noevia-inference-gate` crate.

**Layout.**

- *One host.* `compose.llamacpp.yaml` (and `deploy/examples/unraid-llamacpp.override.yml`)
  run `inference-gate` beside `llama`.
  - Web and Diary use `http://inference-gate:8080`.
  - The router is on the `models` network only. The gate reaches it there, and so does the model
    manager (see "Known limitations" below for what the model manager sends it).
  - Install: recreate `llama` by name (`up -d --no-deps llama`) while chat is idle, so it drops its
    host port, then start `inference-gate` by name. Recreating `llama` cuts every stream.
  - In the Unraid one-host layout, set `INFERENCE_BASE_URL` and `MODEL_MANAGER_BASE_URL` to the gate
    (`.env.example`). If `AUX_INFERENCE_BASE_URL` names the router directly, point it at the gate
    too: the router is no longer on Diary's network.
  - Both web inference addresses, `INFERENCE_BASE_URL` and `MODEL_MANAGER_BASE_URL`, must name the
    same gate. Web sends the lease header only to the origin of `MODEL_MANAGER_BASE_URL`.
- *Separate inference machine.* Add `deploy/examples/inference-gate.override.yml` to that
  machine's Compose files.
  - The gate takes over the address and port that web and Diary already use for the router
    (`INFERENCE_GATE_PUBLISH`, required), so nothing changes on the web host.
  - The router's host port is removed (`ports: !reset []`, Compose 2.24 or later).
  - The web host's addresses stay unchanged: `INFERENCE_BASE_URL`, `MODEL_MANAGER_BASE_URL` and,
    when it is set, `AUX_INFERENCE_BASE_URL`. Do not add the one-host gate service on the web host.
  - The inference machine's environment file needs `MODEL_MANAGER_VERSION`,
    `INFERENCE_GATE_PUBLISH` and `INFERENCE_GATE_ADMIN_TOKEN` (names only here), plus any `GATE_*`
    limits.
  - The gate uses `pull_policy: never`: load the release-built model manager image onto the
    inference machine before applying.
  - Apply order on the inference machine: recreate `llama` first, then `inference-gate`, each by
    name with `--no-deps`. This frees the shared address before the gate binds it and leaves
    intentionally stopped services alone.

**Configuration.** Use key names only; the values belong in the operator's environment file.

- `INFERENCE_GATE_ADMIN_TOKEN` is one secret, read by the gate (as `GATE_ADMIN_TOKEN`) and by
  web. Give the same value on both hosts. Blank means nobody can unload a model that is answering.
  That includes the memory watchdog (#697): without the token it falls back to a plain unload,
  which the gate refuses for a busy model. Set `INFERENCE_GATE_ADMIN_TOKEN` on both hosts.
- Every `GATE_*` limit is optional (`.env.example` lists them with their defaults). An invalid
  value stops the gate before it listens, and the error names the variable, never its value.

**Release.**

- Release the core gate client (noevia-core), the model manager image that ships the gate
  (noevia-services) and this Compose change together. The core release deletes the old eviction
  code, so there is no shadow mode.
- The web interface change can ship with them or before them.
- Check model activity first, as for any release.
- On one host, `deploy/examples/overlay-release.sh` starts `inference-gate` by name, with
  `--no-deps`, before the Diary model check and the web cutover. The split layout's release is
  unchanged: the gate runs on the inference machine.
- A project-wide `up -d` after a `MODEL_MANAGER_VERSION` bump also recreates the gate, which cuts
  open streams. Recreate services by name instead.
- Add the gate's port to the host's model-port firewall script as part of the release (see "Host
  firewall" below).

**Read-only verification.**

- `GET /gate/v1/health` answers 200 from the gate's address.
- `GET /gate/v1/status` lists the resident model and any leases.
- The router answers only on the Compose network.
- A chat turn shows the waiting line while another chat's model answers, then answers.
- Do not send loads, unloads or generations to a live router to check this.

**Rollback.** Restore the previous Compose files and the previous web image (core pin) together:

- the router publishes its port again;
- `inference-gate` is stopped and removed;
- web goes back to the release that still has its own eviction.

Two half-states lose protection, so avoid both:

- New web without the gate keeps working, but nothing stops one chat unloading another's model.
  Its client treats a missing gate as no gate and logs it once.
- Old web behind the gate gets refusals instead of eviction for a model in use.

The model manager image can stay, since its default command is unchanged.

**Known limitations.**

- After a model download finishes, the router can reload its presets on its own at the next
  request. The gate does not see this reload, so it cannot protect a model in use from it. Expect
  that request to wait on the reload, and the resident model may be unloaded. Run downloads while
  chat is idle.
- The model manager still reaches the router directly, outside the gate, for more than presets:
  its backend restart (which restarts the router and cuts every stream), its backend test (a chat
  completion) and its benchmark runner (loads and completions). These are admin-only paths. Use
  them only while the engine is idle. Routing them through the gate is tracked in
  sbstndalton/noevia#2138.

**Host firewall (#2122). Release step: add the gate's port to the host's model-port firewall script.**

- The gate's published port is the router's old one: 18000 by default on the inference host, and
  configurable through `INFERENCE_GATE_PUBLISH`. Use the port you set wherever 18000 appears below.
  Without a rule it is reachable from every host that could reach the router before.
- Unpublishing the router closes the router's direct port. It does not restrict the gate's port.
- As part of this release, add port 18000 to the host's model-port firewall script, beside the
  other model ports it already restricts. The rule is a `DOCKER-USER` rule that rejects new
  connections to that published address and port from any source but the web host. For example,
  with operator-local values:

  ```sh
  rule=(-p tcp -m conntrack --ctstate NEW --ctorigdst "$INFERENCE_ADDRESS" --ctorigdstport 18000 \
        ! -s "$WEB_HOST_ADDRESS" -j REJECT --reject-with tcp-reset)
  iptables -C DOCKER-USER "${rule[@]}" 2>/dev/null || iptables -I DOCKER-USER 1 "${rule[@]}"
  ```

- Keep the rule in that script, so it survives restarts, not in a one-off shell.
- Verify after applying:
  - from a LAN host that should be refused, `curl -sS -m 5 http://$INFERENCE_ADDRESS:18000/gate/v1/health`
    fails with a refused or reset connection;
  - from the allowed peer (the web host), the same request answers 200.

## Services on other Inference machines (#1843)

Services assigned to another inference machine are not counted against this host's budget.
The remote inference model is outside this budget too. Account for each role's residency on
its own machine; do not restart retained local sidecars merely because the selected role runs
elsewhere. This describes resource accounting, not any installation's current assignments.

Host preflight and restart-notification tooling reads an explicit `NOEVIA_REMOTE_SERVICES`
list because it cannot depend on web administrator credentials or settings while web is stopped.
The accepted role names and compatibility aliases are:

| Role | Earlier service name |
| --- | --- |
| `decision` | `kev` |
| `sensitivity` | `laya` |
| `embedding` | `embed` |
| `reranker` | `rerank` |

For each selected role, configure `NOEVIA_REMOTE_<ROLE>_HEALTH_URL` and an optional
`NOEVIA_REMOTE_<ROLE>_MACHINE` label using operator-local values. Role-named variables take
precedence over their earlier service-name aliases. An unset or empty role list leaves the
host helper inert. `NOEVIA_REMOTE_ENV_FILE` may name an operator-owned configuration file;
the helper reads only `NOEVIA_REMOTE_*` assignments as data, never executes the file, and
preserves values already present in the environment.

Health probes are bounded, advisory, restricted to accepted private/overlay destinations,
and do not follow redirects. URLs must contain no credentials. A 2xx response is healthy.
Without an authentication file, HTTP 401 (needs auth) or 403 means the endpoint is reachable
and requests authentication; a rejection after configured authentication is unhealthy.

`NOEVIA_REMOTE_<ROLE>_AUTH_FILE` optionally supplies complete header lines. The helper checks
the opened file's ownership, regular-file type, mode 0600 or stricter, bounded size, and safe
header syntax. Symlinks are refused; ancestors must not be writable by another user unless
protected by the sticky bit. A configured but unusable file reports
`NOEVIA_REMOTE_<ROLE>_AUTH_FILE unusable` and sends no request. It must not be interpreted as
healthy, unauthenticated, or recovered. Credential contents and paths are never logged.

Keep actual assignments, hosts, endpoints, labels, and authentication-file locations in the
local operator runbook or ignored configuration. These generic interfaces do not authorize
probing a machine, changing its assignments, or starting model inference.
