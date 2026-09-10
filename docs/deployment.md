# Deploying noevia to daserver

This is the **live, personal** runbook for the Unraid box. It is not the same as
repo-root `DEPLOY.md`, which describes a generic single-host `docker compose up`
for a fresh install. That flow does not match production, and following it here
will not update anything.

Verified 2026-09-09 by deploying `f6832bf`.

**Never trust a doc for what is currently live** — including this one. Check it:

```sh
ssh root@100.70.173.74 "readlink -f /mnt/docker/appdata/cowork/current; \
  docker ps --format '{{.Names}}\t{{.Image}}' | grep cowork"
```

`changelog.md` says DaServer ran `0f8a9c1`; that was true on 2026-09-08 and was
already stale by the next day.

## Reaching the host

SSH as root. **Use Tailscale at `100.70.173.74`.** The `daserver` SSH alias points
at `10.69.0.130`, which only resolves on the home LAN — Tailscale reports "peers
are advertising routes but `--accept-routes` is false", which is why the LAN
address stays unreachable off-site.

Public URL is `https://cowork.daserver.work` via a Cloudflare tunnel (the hostname
kept its old name after the rebrand, deliberately).

## Layout on the box

Unraid Compose Manager plugin, project name **"Cowork"**. Three containers:
`cowork-web-1`, `cowork-diary-1`, `cowork-ocr-1`.

- **Releases**: `/mnt/docker/appdata/cowork/releases/<git-sha>/` holds a full
  source checkout. `/mnt/docker/appdata/cowork/current` is a symlink to the active
  one. `COWORK_SOURCE_DIR` in `.env` points the compose file's `build: context:`
  at `current`; `COWORK_VERSION` sets the image tag.
- **Env**: `/mnt/docker/appdata/cowork/config/.env`, chmod 600. Back it up before
  editing — the `.env.bak.<timestamp>` convention is already established.
- **There are no git credentials on the server.** `git fetch` in
  `/mnt/docker/appdata/cowork` (a stale, far-behind checkout) fails with "could not
  read Username". Only release `a576ecf` is a real `git worktree`; everything later
  is a plain directory. Deploy by shipping a tarball.

## Three copies of the compose config exist and do not auto-sync

A new env var must be added to **all three** by hand:

1. repo `compose.yaml`
2. `deploy/examples/unraid-compose-manager.yml`
3. **`/boot/config/plugins/compose.manager/projects/Cowork/docker-compose.yml`** —
   the live one, plus its `docker-compose.override.yml` for the `lemonade_default`
   external network. Editing only the repo file does nothing.

Back the live one up first:
`cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)`

## The deploy

```sh
SHA=$(git rev-parse --short HEAD)
git archive --format=tar.gz -o "/tmp/$SHA.tar.gz" HEAD
scp "/tmp/$SHA.tar.gz" root@100.70.173.74:/mnt/docker/appdata/cowork/releases/
ssh root@100.70.173.74 "set -e
cd /mnt/docker/appdata/cowork/releases && mkdir -p $SHA && tar -xzf $SHA.tar.gz -C $SHA && rm -f $SHA.tar.gz
cd /mnt/docker/appdata/cowork && cp config/.env config/.env.bak.\$(date +%Y%m%d%H%M%S)
cd /boot/config/plugins/compose.manager/projects/Cowork
COWORK_SOURCE_DIR=/mnt/docker/appdata/cowork/releases/$SHA COWORK_VERSION=$SHA docker compose --env-file /mnt/docker/appdata/cowork/config/.env build
# Stop here if candidate verification fails (see the image-test mounts below).
ln -sfn /mnt/docker/appdata/cowork/releases/$SHA /mnt/docker/appdata/cowork/current
sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=$SHA/' /mnt/docker/appdata/cowork/config/.env
docker compose --env-file /mnt/docker/appdata/cowork/config/.env up -d --no-build --wait --wait-timeout 120"
```

A build takes ~10 min over the Tailscale relay. Run it in the background and poll
for `docker ps | grep cowork-web`. Rolling back is repointing `current` and
`COWORK_VERSION` at the previous SHA and re-running Compose up with `--no-build --wait`.

## After deploying

`LEGACY_AUTH_COMPAT=false`, so there is no bearer-token path — verify from a real
authenticated browser session. Check the things that only break against real data:
Nextcloud uploads and deletions, MCP approval decisions, source refresh, vision.

Record the change in the canonical DaServer changelog.

## Known gaps

- **`UPGRADES.md` on the server is stale.** It describes a retired
  AnythingLLM + LiteLLM stack. Ignore it.
- **`/mnt/docker` has no redundancy and no backup** — a single-device btrfs pool on
  one NVMe, holding `secrets.key`, which decrypts stored provider API keys. The
  Unraid Appdata Backup plugin is installed but unconfigured. This is the top item
  in `backlog.md`.
- The route from a sandboxed dev environment to `10.69.0.130` has been transiently
  flaky ("No route to host" that resolved on retry). One SSH failure does not mean
  the host is down.


## PDF OCR service and image inference (2026-09-10)

`compose.yaml` and the Compose Manager example now include `cowork-ocr` and a
private internal `ocr` network. Add the same service/network to the live Manager
file, attach web to both its existing networks and `ocr`, and set web's
`OCR_BASE_URL=http://ocr:8030`. The worker has no host port or durable volume.
Build all three images; confirm `/health` from web before synthetic PDF upload.
Do not refresh existing personal sources as part of agent verification.

The LAN SSH route `root@10.69.0.130` worked while Tailscale timed out during this
change. Lemonade is version 10.8.0. Back up
`/mnt/docker/appdata/lemonade/user_models.json` before model registration edits.
The existing `Qwen3.5-9B-GGUF-UD-Q4_K_XL` entry now needs `checkpoints.main` equal
to its existing checkpoint and `checkpoints.mmproj` equal to
`unsloth/Qwen3.5-9B-GGUF:mmproj-F16.gguf`. Absolute paths in this registered
checkpoint field are rejected by this version. The matching projector was
obtained from revision `3885219b6810b007914f3a7950a8d1b469d598a5`; restart Lemonade
and verify a real synthetic image, not just its advertised vision label.


Verified rollout: release `e3b29bb`, replacing `cd717b0`. All three production
images use that tag. Config/Compose backups use `.bak.before-e3b29bb`; retain
those with the previous release for rollback. Web-to-OCR health returned 200,
diary passed its authenticated health check, and the authenticated browser passed
synthetic mixed-PDF upload/OCR and image/PDF question checks. No real corpus was
used for test prompts. The commit recording these results is documentation only;
the deployed application source remains `e3b29bb`.


Latest application rollout: `48027ef` (unified uploads), replacing `e3b29bb`.
No Compose schema or environment additions were needed for this follow-up.
All three images use the new tag. `.bak.before-48027ef` config/Compose backups
and the previous release are retained. Tailscale was stopped on the client;
reconnecting its existing configuration restored SSH access. Browser verification
used a separate synthetic project, never a real diary or financial source.
Tailscale was restored to its previous stopped state after verification. The
synthetic chat and project are archived. The rollout record is documentation only;
the deployed application source remains `48027ef`.

Latest application rollout: `3320fc3` (composer actions), replacing `48027ef`.
All three images use `3320fc3`; no environment or Compose schema changes. Retain
`.bak.before-3320fc3` backups with the previous release. Authenticated synthetic
upload and actual Lemonade-to-Nextcloud MCP listing passed. The following rollout
record commit is documentation only; deployed application source is `3320fc3`.

Latest application rollout: `12ba04f` (shared composers and opt-in Diary extras),
replacing `3320fc3`. All three images use `12ba04f`; no environment or Compose
schema additions. Retain `.bak.before-12ba04f` backups and the previous release.
Diary/OCR health and the live default-off menu check passed. The following rollout
record is documentation only; deployed application source remains `12ba04f`.

Latest application rollout: `4ec8269` (live-audit fixes), following `cfc3a05`, which
replaced `12ba04f`. All three images use `4ec8269`. Build and isolated image tests
completed before switching the live symlink/version. Retain the prior releases
and `.bak.before-cfc3a05` / `.bak.before-4ec8269` config/Compose backups. No
environment or Compose schema additions. Fixed migration/image behavior and
administrator deletion were verified against live routes. Synthetic account,
diary and Nextcloud cleanup completed; public UI and health passed. See
[the live audit report](live-audit-2026-09-10.md) for coverage and unresolved issues.

Latest application rollout: `dc325d5`, replacing `4ec8269`. The chat model picker
now sits inside the composer next to Send. All three images use this tag; retain
`.bak.before-dc325d5` backups and the previous release. 266 web tests,
typecheck/build, and 157 diary tests (3 skipped) passed. Synthetic mobile/desktop
and light/dark checks passed; the live composer picker opens correctly. Diary/OCR
health passed. Thinking-effort controls remain planned, not implemented here.

Latest application rollout: `66af1ad`, replacing `dc325d5`. Shared composer model
controls now include project landing and Diary home/day views. Diary extras stay
opt-in; its default companion is displayed without exposing a replacement picker.
All three images use the tag; `.bak.before-66af1ad` backups and the prior release
are retained. 266 web tests, typecheck/build, and 157 diary tests (3 skipped) pass.
Synthetic project/Diary picker and layout checks plus live project/default Diary
checks passed. Diary/OCR health passed; no test prompt touched the real diary.


Latest application rollout: **`baf38aa`** (onboarding correctness), replacing
`66af1ad`. All three images use this tag. Build candidates against the new release
path and version **before** switching `current` or editing the live environment.
The example above now reflects that ordering. This rollout used shell overrides
`COWORK_SOURCE_DIR=<candidate release>` and `COWORK_VERSION=<candidate tag>` for
`docker compose --env-file ... build`, followed by a disposable, network-disabled
web-image server test run. Mount repository `.env.example` at `/.env.example`,
`compose.yaml` at `/compose.yaml`, `deploy` at `/deploy`, and server fixtures at
`/app/server/fixtures`, all read-only: deployment fixtures are absent from the
runtime image by design. The initial missing-fixture check was corrected before
cutover; all **234 server tests** passed on the final candidate.

Only then back up `.env`, `docker-compose.yml` and `docker-compose.override.yml`
with `.bak.before-baf38aa`, switch `current`/version and run Compose `up -d
--no-build --wait --wait-timeout 120`. Preserve `66af1ad` and those backups. This
batch adds no environment/Compose/schema fields. Rollback restores the backed-up
environment and points `current` at `66af1ad`, then runs the same no-build up/wait.

278 web tests, typecheck/build and 157 diary tests (3 skipped, two existing
warnings) passed. Synthetic local browser regression plus manual UI review passed;
42 scoped live assertions verified existing completion preservation, new invite
roles/Diary yes/no, login/resume, updates/completion, role/tenant isolation,
application/OCR health and cleanup. Diary health passes; zero restarts/OOM on all
services. The public browser loaded `index-DE1yxV8o.js` and the existing account
remained in Projects. All five synthetic accounts/sessions/workspaces and the
exact bootstrap invite were removed; no diary test prompts/corpus writes. Tabs
and the temporary local server were closed; viewport and stopped Tailscale state
restored. The following record commit is documentation only; application source
remains `baf38aa`. Diary 4c is next; known live-audit model limits remain unresolved.


Latest application rollout: **`5b1ef12`**, replacing `baf38aa`, implements Diary
landing-to-day navigation. All three candidate images built before cutover;
234 isolated Linux server tests passed. Retain `baf38aa` and configuration backups
`.bak.before-5b1ef12`. All services have zero restarts/OOM; Diary and internal OCR
health pass. Public authenticated Projects loads `index-BZjK7Bdp.js`. UI behavior
was verified with synthetic local/browser-folder fixtures, without live capture.


Latest application rollout: **`23ba691`**, replacing `5b1ef12`, adds bounded
older-entry context fallback. All three candidates built and 234 isolated Linux
server tests passed before cutover. Retain prior release and `.bak.before-23ba691`
configuration backups. Diary/internal OCR health pass; zero restarts/OOM. No live
diary test prompt or corpus access. Frontend bundle is unchanged from `5b1ef12`.


Latest application rollout: **`b34c33f`**, replacing `23ba691`, adds durable
first-entry scaffolding. All three candidates built; 234 isolated Linux server
tests passed before cutover. Prior release and `.bak.before-b34c33f` configuration
backups retained. Diary/internal OCR health pass, zero restarts/OOM. No production
corpus touched; frontend bundle remains unchanged.


Latest application rollout: **`8edacf7`**, replacing `b34c33f`, adds empty/populated
Diary landing views. All three candidate images built and 234 isolated Linux
server tests passed before cutover. Retained prior release and configuration
backups `.bak.before-8edacf7`. Diary/internal OCR health pass, zero restarts/OOM.
Synthetic browser checks cover the UI; no production diary access used.


Latest application rollout: **`7a34a0a`**, replacing `8edacf7`, completes the Diary
component split. Candidate images built first. The initial parallel test run hit
a disposable secrets.key creation race; all 234 server tests then passed with
`--test-concurrency=1` before cutover. Use that flag for subsequent isolated image
runs. Retain prior release and `.bak.before-7a34a0a` configuration backups. Diary
and internal OCR health pass; zero restarts/OOM. No production diary access.


Latest application rollout: **`6570c51`**, replacing `7a34a0a`, adds thinking effort
v1. All three candidates built and 245 serial isolated Linux server tests passed
before cutover. Prior release and `.bak.before-6570c51` backups retained. Diary and
internal OCR health pass; zero restarts/OOM. No live settings/corpus mutation.
Absent global default leaves existing chat requests unchanged.


Latest application rollout: **`34df7c2`**, replacing `6570c51`, stops promoting
reasoning-only narration into final answers. Candidates and 248 serial isolated
Linux server tests passed before cutover. Retain prior release and
`.bak.before-34df7c2` configuration backups. Compose reports services healthy.
No production diary access; web bundle remains unchanged.


Latest application rollout: **`3b1e256`**, replacing `34df7c2`, guards unstable
reported engine-rate samples. Candidates and 250 serial isolated Linux server
tests passed before cutover. Prior release and `.bak.before-3b1e256` backups
retained. Diary/internal OCR health pass; zero restarts/OOM. No corpus access.
