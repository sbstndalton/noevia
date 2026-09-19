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

SSH as root. Off-site use Tailscale at `100.70.173.74`; on the home LAN use
`10.69.0.130` (verified again 2026-09-10). The `daserver` SSH alias points
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

Before any Compose `up` on Unraid, validate resolved writable mounts with the
[host-side preflight](../deploy/preflight/README.md). The installed wrapper is
`/mnt/docker/appdata/cowork/tools/preflight/up.sh`; call it from the existing
Compose Manager project directory with `--env-file ... --` followed by the usual
`up` options. It rejects writable `/boot` paths/device aliases without changing
state bindings. Direct Compose Manager GUI startup bypasses this helper.

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
bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --wait --wait-timeout 120"
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
- **`/mnt/docker` has no redundancy** — the single-device pool now has daily
  noevia state/configuration backups on a separate array disk. See
  [backup scope and restore evidence](../deploy/backups/README.md). This does not
  cover unrelated appdata or the remote Nextcloud corpus; off-site is undecided.
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
[the live audit report](roadmap.md) for coverage and unresolved issues.

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


Latest rollout: **`e18f1de`**, replacing `3b1e256`, adds DOCX body/table extraction.
254 serial isolated Linux server tests and all eight worker tests (including PDF
OCR) passed before cutover. Retain previous release and `.bak.before-e18f1de`
backups. Diary/internal OCR health pass; zero restarts/OOM. Synthetic fixtures only.


Latest rollout: **`2525de5`**, replacing `e18f1de`, adds app-password lifecycle.
257 serial isolated Linux server and eight worker tests passed before cutover.
Retain prior release and `.bak.before-2525de5` backups. Compose health passes;
no production device credentials created and no sharing port exposed.


Latest rollout: **`9e2bfbb`**, replacing `2525de5`, includes the limited DAV endpoint
and verified wizard/storage choices. 263 serial isolated Linux server and eight
worker tests passed. LAN SSH 10.69.0.130 verified web/OCR 200, healthy Diary,
zero restarts/OOM, and DAV port 0. Prior release/config backups retained. The live
Compose file has no new DAV publication. No real diary testing used.


Latest rollout: **`79cd24f`**, replacing `9e2bfbb`, fixes bounded skill metadata
filenames. 267 serial isolated Linux server and eight worker tests passed before
cutover. All three services healthy; prior release and `.bak.before-79cd24f`
backups retained. Frontend unchanged, no production corpus tests, DAV remains off.


Latest rollout: **`ecaaa73`**, replacing `79cd24f`, fixes Diary saved-record
presentation, provider reasoning transport/display, stationary day composer and
Diary/ordinary-chat scroll following. All three images use `ecaaa73`; 267 Linux
server and eight worker tests passed before cutover. Compose health passed,
web/OCR returned 200, and all services have zero restarts/OOM. Public HTML and
its JS/CSS return 200 and match the candidate build assets (`index-Dew5_5_t.js`,
`index-Clk49Sb3.css`). Retain `79cd24f` and `.bak.before-ecaaa73` backups. No real
Diary prompts or corpus changes. This rollout record is documentation only;
application source remains `ecaaa73`. Broader roadmap testing pause continues.


Latest rollout: **`3ef0501`**, replacing `ecaaa73`, streams live Diary provider
output and actual capture phases with immediate headers/5-second keep-alives.
271 isolated Linux server and eight worker tests passed before cutover. All three
images run the release, Compose health passes, web/OCR return 200, zero restarts
or OOM. Public HTML/JS/CSS match `index-DjreUSVc.js` / `index-CeqiWBYp.css` and
include the live Diary activity/error UI. Prior release and `.bak.before-3ef0501`
backups retained; no environment or Compose changes. No real Diary prompts or
corpus edits. This rollout record changes documentation only; application source
remains `3ef0501`. Full browser reload/job recovery remains future work.


Latest rollout: **`cac1778`**, replacing `3ef0501`, includes native MTP load
controls, actual acceptance telemetry in Chat/Diary, permanent inference details
and New chat launch. `8eb7b99` was built but not cut over; the installed backend
needed the per-response timing fallback added in `cac1778`. All three images
run `cac1778`; 277 isolated Linux server and eight worker tests passed before
cutover. Diary health, web HTTP 200 and internal OCR health 200 pass; no restarts
or OOM. Public HTML/assets return 200 and match `index-D3bApFIM.js` and
`index-DObGn_iJ.css`. Prior `3ef0501` release and `.bak.before-cac1778` backups
retained; no environment schema/Compose changes, inference model loads or corpus
tests. This rollout record changes documentation only; runtime remains `cac1778`.


Latest rollout: **`ddbe852`**, replacing `cac1778`, includes `2408c32` local-Qwen
thinking switches and PDF reduction in the isolated document worker. All three
images run this release. 281 isolated Linux server and 13 worker tests passed
before cutover. Diary healthy, web/internal OCR health 200, zero restarts/OOM;
public assets match `index-CVEhmnpx.js` and `index-DObGn_iJ.css`. Prior release
and `.bak.before-ddbe852` backups retained. No environment schema/Compose changes;
Ghostscript is added inside the existing restricted OCR image. No real Diary tests,
model loads, proxy trust changes or Claude migration. Subsequent documentation
commit records this rollout; application runtime stays `ddbe852`.


Latest application rollout: **`12a1646`**, replacing `ddbe852`, adds the scoped
Diary connector. All three production containers run this release with zero
restarts/OOM; public HTML and unchanged JS/CSS return 200. 332 web tests,
typecheck/build, three bridge tests, synthetic HTTP checks, 284 Linux server and
13 worker tests pass. Invalid credentials return 401; traversal returns 400 in
production without corpus access. Prior release and `.bak.before-12a1646` retained.
The subsequent bridge-only change adds its explicit HTTP client identifier; it
runs on the Mac, not in the production containers. Claude import remains pending.
See `../deploy/nextcloud/README.md` for the separately applied push repair and AIO
update caveat. No production Diary prompts or file modifications were used in QA.


Latest application rollout: **`ae39000`**, replacing `12a1646`. Adds per-chat
context estimates, manual/automatic history summaries, bounded output and streamed
context errors. All three images run this release, zero restarts/OOM; public
HTML and assets `index-DjDPTIbR.js` / `index-Cf9BFFht.css` return 200. Unauthenticated
context-window access returns 401. 338 web tests, typecheck/build, synthetic
responsive UI/HTTP QA, 290 Linux server and 13 worker tests pass. Previous release
and `.bak.before-ae39000` retained. No model reload, real chat retry, or Diary
corpus changes. Refresh the browser to load the new controls. The first prepared
request establishes its estimated context snapshot; existing chats can compact
manually. Documentation-only follow-up does not change the runtime version.


### Dedicated Diary support — 2026-09-12

Diary alone runs `cowork-diary:ae39000-diary-smb-20260912`, image digest
`sha256:4d3ead98e83c7192e4e77fc4e4b9d7ba52dca30b753a5e5bb0f758c4448c348d`.
Its source is `/mnt/docker/appdata/cowork/releases/ae39000-diary-smb-20260912/services/diary`.
The live `docker-compose.override.yml` pins this Diary image and build context
while preserving the inference network. Web/OCR and `current` remain `ae39000`.
Future full releases must deliberately remove/update this pin after incorporating
the dedicated-volume code; do not silently revert it or discard future mounts.
Main Compose now forwards `DIARY_LOCAL_VOLUMES`; currently empty, so real storage
is unchanged. Config and both Compose files are backed up with
`.bak.before-diary-smb-20260912`.

195 isolated Linux Diary tests and synthetic real-image/bind HTTP checks passed.
Diary health and zero restarts verified. Before enabling the selected tenant
mapping, finish the Mac SMB pilot and the cutover steps in
[spec-diary-smb.md](spec-diary-smb.md). The new `/boot/config/smb-extra.conf`
currently defines only restricted synthetic `Diary-Pilot`. No real corpus export
or new public port was introduced. Read-only pilot rollback is removing just its
section and reloading Samba; no original Diary data needs deleting.


### Unified context/storage release — 2026-09-12

All three services now run `cc59e8f`. The cold-model context fix is deployed along
with the existing dedicated-volume support. `current` points to this release;
the temporary Diary-only image/build pin was removed because the unified source
contains it. Inference networks and the unset DIARY_LOCAL_VOLUMES setting remain.
Rollback env/Compose backups use `.bak.before-cc59e8f` and retain the old Diary
pin. 342 local web tests, typecheck/build, real HTTP cold/auto-model regression,
and 294 isolated Linux server tests passed. All 13 OCR worker checks passed
after mounting their document fixtures. All services restarted,
zero restarts/OOM; public web returned 200. No live inference/Diary prompt used.

### Instruction skills — 2026-09-12

All three services run `095d308`, replacing `cc59e8f`. 349 local web tests,
typecheck/build, synthetic HTTP and responsive browser checks, and 301 Linux
server tests pass. Zero restarts/OOM; public assets match index-Jg7lAr4m.js and
index-DtPQRNYF.css. Rollback backups use .bak.before-095d308. Storage mapping
remains unset. No inference model loads or real Diary prompts used.

### Hugging Face MTP evidence — 2026-09-12

All three services run `f6688f3`, replacing `095d308`; 353 local web tests,
typecheck/build, public-GGUF synthetic HTTP checks, responsive browser QA and
305 Linux server tests pass. Zero restarts/OOM. Public assets match
index-CEkb-ul1.js and index-CJPL3E7N.css. Rollback backups use
.bak.before-f6688f3. No inference loads/settings or Diary storage changes.

### Saved-storage Diary recovery — 2026-09-12

All three services run `f7b9d95`, replacing `f6688f3`. 356 local web tests,
typecheck/build, mock-companion HTTP and browser reload checks, and 308 Linux
server tests pass. Services healthy with zero restarts/OOM; public assets match
index-BnGKPbgk.js and index-CJPL3E7N.css. Rollback configs use
.bak.before-f7b9d95. New per-user web-state records are included in existing
backups. Dedicated real Diary mapping remains unset; no real corpus prompts used.

## Source refresh rollout — 2026-09-13

All three services now run `8fa1112`, replacing `f7b9d95`. Candidate validation:
358 local web tests, typecheck/build and 308 isolated Linux server tests pass.
The installed boot-storage preflight wrapper passed and performed the rollout.
Diary reports Docker healthy; web setup-status and OCR health return HTTP 200.
Web/OCR have no Docker healthcheck configured, so Compose's Healthy output alone
is not application-health evidence. All three show zero restarts and no OOM.
Public assets match `index-DJTWu6Rf.js` and `index-CJPL3E7N.css`.

Rollback release `f7b9d95` and configuration backups `.bak.before-8fa1112` remain.
No storage mapping, production model setting or real Diary corpus was changed.
The earlier managed-volume installer/preflight commits are included; live host
bindings remain intact. This is a verified increment, not completion of the
remaining SMB authentication/cutover, context qualification or tool experiments.

## Unified glass and Settings release — 2026-09-14

All three services run **fca1f19**, replacing 8fa1112. Twelve unpublished UI/theme
increments were consolidated into this release commit; existing published backend
candidates are included. GitHub release tag: release-2026.09.14.

390 local web tests, typecheck/build, synthetic HTTP usage and full backup/restore
checks pass. Exact candidate images pass 321 serial Linux server tests, 199 Diary
tests (two existing dependency warnings), and 13 OCR tests with document fixtures.
Populated synthetic browser QA verified account/aggregate costs and pricing save.

Pre-release backup ab_20260914_001944 verified successfully. Retain 8fa1112 and
config/Compose backups .bak.before-fca1f19. Installed mount preflight passed before
cutover. All containers healthy, zero restarts/OOM; web and internal OCR health 200.
Public assets match index-DwIft049.js / index-CG4nO7GL.css. Authenticated Settings
shows profile-saved appearance, one scene and no legacy inspector toggle. No real
Diary prompts/corpus edits or storage mapping/model configuration changes.

## Diary workspace, model guidance and context rails — 2026-09-14

Production now runs **a6d15c3** on web, Diary and OCR, replacing fca1f19.
Includes guarded Markdown editing/recovery/navigation, explicit hardware and
memory guidance, and continuous context rails that move below narrow content.
GitHub main includes all five application commits.

Validation: 404 local web tests, typecheck/build and synthetic responsive editor
checks pass. Exact candidate images pass 324 serial Linux server tests, 199 Diary
tests (two existing dependency warnings), and all 13 OCR tests with fixtures.
The installed writable-mount preflight passed. All three services are healthy
with zero restarts/OOM; web setup-status and internal OCR return HTTP 200.
Public JS/CSS hashes match the tested build (index-CXIpF5Wf.js and
index-DGAF1v_V.css). Authenticated production reload succeeds, and the project
view has one transparent context rail. No real Diary prompts or corpus edits.

Retain fca1f19 and config/Compose backups .bak.before-a6d15c3 for rollback.
No environment schema, mounts or model configuration changes. This documentation
commit records the rollout; deployed application source remains a6d15c3.

## Calendar landing rollout — 2026-09-14

All three services run **5894266**, replacing a6d15c3. Diary opens on the current
month with Calendar selected, a List toggle above, and the composer below.
404 local web tests, typecheck/build and synthetic responsive/draft recovery
checks pass; the candidate passes 324 serial Linux server tests. Diary/OCR image
IDs are identical to the prior release's verified images (199/13 tests).
Mount preflight passed; all services healthy, zero restarts/OOM; web and OCR
health return 200. Public JS/CSS hashes match index-CdTrv7d0.js and
index-Bm_DWXB9.css. Authenticated production Diary opens with Calendar selected
and date markers loaded. No prompts sent or corpus edits. Retain a6d15c3 and
.bak.before-5894266 configuration backups for rollback. This record is
documentation only; deployed application source remains 5894266.


## App-owned Diary candidate — not deployed (2026-09-14)

The managed Diary implementation is prepared locally; production remains
`5894266`. No new storage mapping, real import or architecture rollout is authorized
by this implementation task. See [the managed Diary runbook](spec-managed-diary.md)
for persistent state, backup/restore and staged rollout requirements. Existing
legacy corpora remain active until explicit verified import. Preserve the full
Diary DB-parent directory in disaster-recovery archives: `managed-diary.db` is
primary data, not a rebuildable retrieval cache.


## Managed Diary release — 2026-09-14

User authorized the current changes for GitHub and production. All three services
now run **55b2767**, replacing 5894266. Exact candidate images passed 324 serial
Linux server tests and 220 Diary tests (two existing dependency warnings). OCR's
image ID is identical to the previous verified release. Local web tests,
typecheck/build, synthetic WebDAV/restore and responsive editor checks passed.

Pre-release backup `ab_20260914_022413` verified web and Diary state and restarted
both services. Retain 5894266 and `.bak.before-55b2767` env/Compose backups. The
installed writable-mount preflight passed; the full Diary state remains on
`/mnt/docker/appdata/cowork/state/diary` at `/app/data`. All services report healthy;
web setup-status and internal OCR health return 200. Public JS/CSS hashes match
`index-C03IOv_X.js` / `index-0b_5wm7O.css`. Authenticated browser reload and Diary
calendar/storage controls passed. The existing Diary visibly remains on WebDAV
with the explicit import preview available. No real import or test prompt was sent.

The direct llama.cpp rewrite starts after this release; no production inference
backend switch is included in 55b2767.

## Mobile viewport and native adapter release — 2026-09-14

Production web, Diary and OCR run **2570a02**, replacing 55b2767. Mobile composers
remain reachable at keyboard height; model/settings dialogs follow the visible
viewport and phone telemetry uses one scrollable row. Direct llama.cpp support
is included, while the active production inference backend remains Lemonade.
Native GPU workload qualification and cutover are still outstanding.

Verification: 423 local web tests, typecheck/build, seven viewport sizes in both
themes, keyboard/draft/zoom regressions, all personal settings categories, Diary
calendar/list and Markdown conflict/save checks, native profiles and model guidance.
The exact Linux candidate passed 342 server tests and 221 Diary tests (two existing
dependency warnings). OCR image matches the previously verified image. GitHub CI
passed. Backup `ab_20260914_031839` verified web/Diary state before the installed
mount preflight performed rollout. All three services are healthy with zero
restarts/OOM; web and internal OCR probes return 200. Public assets match
`index-DZyp8_tE.js` and `index-D7vxMZ0U.css`, with `/viewport.js` present.

Authenticated production checks reproduced and resolved the short-height composer
bug, verified populated model selection and administrator settings, and completed
a synthetic ordinary-chat inference returning `MOBILE_OK`. That test chat was
archived. No real Diary prompts, corpus edits/import or model configuration changes.
Retain 55b2767 and `.bak.before-2570a02` env/Compose backups for rollback.

## Direct native backend cutover — 2026-09-14

**Current:** application web/Diary/OCR images remain `2570a02`; inference is now
`cowork-llama-1`, immutable image
`sha256:9f88885b46c8af0696d02b6d0d93f39cc0d81f29b99fb45030dcaf3a0193e282`
(pinned server-vulkan digest in `deploy/examples/unraid-llamacpp.override.yml`).
The live Compose Manager override now adds native inference on the internal
Compose network, without host ports. Its web mount shares the **directory**
`/mnt/docker/appdata/cowork/config/llamacpp` at `/llamacpp-config`; the router sees
it read-only at `/config`. Public models remain `/mnt/user/ai-models:ro`.
Writable native downloads use `/mnt/docker/appdata/cowork/state/llamacpp-cache`.

`INFERENCE_BASE_URL` and `AUX_INFERENCE_BASE_URL` are `http://llama:8080/v1`;
`MODEL_MANAGER_KIND=llamacpp`, manager base `http://llama:8080`. The saved `default`
row in `state/web/shared-providers.json` also has the native URL: **this saved row
can override the environment**, so changing environment alone is insufficient.
Only that endpoint changed; no private providers, tenant model selections or
Diary storage settings changed. Real Diary stays legacy WebDAV until its explicit
verified import. All eleven installed Lemonade names, including historical hash
IDs, remain available as native preset sections pointing at the same public files.

Qualified presets: Qwen 4B Q8 MTP, Gemma E4B and E2B have 32,768 context/one slot;
Qwen 9B retains the previously qualified 262,144 context/one slot profile. Chat
models use q8 KV, flash attention, GPU layers 999, 1 GiB prompt cache and microbatch
1024. Vision projectors retain 1024 image-token caps. Nomic uses 2048 context,
mean pooling and original q5_0/q4_0 cache flags. Router `models-max=1`, memory cap
14 GiB. Host swap enforcement remains unavailable; the rollout watchdog observed
available memory and failed closed below 4 GiB. This watchdog was disarmed after
acceptance; it is not a newly installed background scheduler.

Lemonade, Model Loader UI, and `llama-vulkan-test` are **stopped**, restart `no`.
Lemonade's saved Compose restart policy is also `no`. Do not start those containers
while native is running. Their caches/configuration are retained for rollback.
No inference services were run concurrently during qualification or rollout.

The fresh pre-cutover backup `ab_20260914_034204` contains verified web and Diary
archives. All operations and confidential config backups are in
`/mnt/docker/appdata/cowork/operations/native-20260914b` (directory mode 0700).
This successful run has `complete`, no guard event, and immutable-in-practice
original config copies. The earlier `native-20260914` attempt is retained as failure
evidence: a compound SSH launch blocked heartbeat delivery, causing rollback;
concurrent repair of the rollback script was corrected and the original state
independently restored before retry. **Never edit an executing shell script.**
The successor launch used an independent heartbeat thread and the saved-provider
change was integrated before app startup.

Rollback, if required, is the reviewed host script:

```sh
bash /mnt/docker/appdata/cowork/operations/native-20260914b/rollback.sh
```

It stops app clients and native, verifies native stopped, restores the environment,
both Compose files, saved shared-provider endpoint and Lemonade Compose file,
restores Lemonade's original loaded models/options, and runs the installed mount
preflight before bringing the app back. It retains the stopped native container.
After rollback, verify all app services and Lemonade health; never run both GPU
providers. Do not replace production state with an old appdata archive merely to
switch inference backends.

Evidence: real GPU chat/tools/cancellation, 28,671 measured input tokens with
2048 output reserve, embedding/aux/chat reloads, Gemma/Qwen vision; minimum free
host memory 8.67 GiB. Isolated real noevia HTTP verified all three write approvals
and grant scope; actual Diary LLMClient tested synthetic chat/aux/embedding without
opening a corpus. Numerical embedding differences remain: 18-vector cosine minimum
0.99884; all eight intended retrievals agree, including native queries against old
vectors. This is scoped compatibility evidence, not proof for every retrieval.

Authenticated production returned `NATIVE_PROD_OK` (519 input/89 output tokens,
8.6 s, 23 tok/s), reported 32768 context/one slot and 58.6% MTP acceptance. The exact
synthetic chat was archived. Phone 390×844 and keyboard-height 375×360 composer,
model dialog and profile-read checks passed; viewport reset. All four containers
are healthy with zero restart/OOM. Native profile editing was not applied in the
production UI. No real Diary prompts, corpus changes or reindex.

The app bundle is unchanged; no new image rebuild was needed for this backend
cutover. New configuration examples, reproducible qualification scripts and
populated mobile tests are committed separately. Pending UI polish: exclude native
embedding presets from chat selection and replace the legacy “Enable MTP? No”
control with accurate native-profile guidance/status.

Post-cutover config/rollback archive:
`/mnt/disk3/noevia-backups/native-config-20260914.tar.gz`, mode 0600,
9,454 bytes, gzip verification passed. It includes the current env, native presets,
saved shared-provider registry, live Compose files, and the successful operation's
before/after configuration material. This archive contains credentials/configuration;
keep it private. It supplements the verified appdata backup, not a state reset.

## Native model UI release — 2026-09-14

Production application **02495a7** replaces 2570a02. The pinned native router
container is unchanged. Chat choices and auto roles exclude embedding/reranking
models; Manage retains them. Legacy MTP controls are capability-gated, with native
profile guidance. All approval actions have 44-pixel minimum height and retain
full argument disclosure.

424 local web tests, typecheck/build and synthetic model/approval browser checks
passed. The exact Linux web image passed 343 server tests; Diary/OCR image IDs
match the previously verified release. GitHub CI 34821414694 passed all three
jobs. Scheduled backup ab_20260914_041001 verified web/Diary archives immediately
before release. Env and both Compose backups use .bak.before-02495a7.

Installed mount preflight passed; all four services healthy, zero restarts/OOM.
Public assets match index-DPDvw100.js and index-BdQJWaar.css; OCR health returns
200. Authenticated 390×844/375×360 production checks confirmed the corrected chat
picker, preserved embedding in Manage and fitting dialog. A synthetic ordinary
chat returned UI_RELEASE_OK in 5.0 s (524 input / 95 output, 24.3 tok/s), with
32,768 context and native MTP acceptance 56.5%. The exact test chat was archived;
viewport reset and browser left on New chat. No real Diary prompt/corpus access.

App-only rollback: set current and COWORK_VERSION to 2570a02, then invoke the
preflight wrapper from the live Compose folder with --no-build --no-deps --wait
for web diary ocr. Preserve the current native override/provider configuration;
do not use the separate backend rollback merely to revert this application.

## Markdown filters release — 2026-09-14

Production application **48432fe** replaces 02495a7, adding bounded dated-filename
and hashtag filters to stored Markdown search. The UI explains the supported
syntax; no corpus migration, model call or persistent search index was introduced.
426 web tests, typecheck/build, six-size/two-theme filter QA and the existing
server/local editor save/conflict/reconciliation checks passed. The exact Linux
web image passed 343 server tests. Diary/OCR image IDs remain identical to the
previous qualified release. GitHub CI 34822124225 passed all three jobs.

Fresh backup ab_20260914_042006 verified both state archives. Installed mount
preflight passed; native router container unchanged. All four services healthy,
zero restarts/OOM, internal OCR HTTP 200. Public assets match index-DiUxf1Ea.js
and index-CyMgPvGj.css. Production keyboard-height UI reviewed at 375×360. Final
synthetic ordinary chat returned FILTER_RELEASE_OK in 7.7 s (622 input/44 output
on final call, 30.4 tok/s), with 32,768 context and live MTP58.7%. It made one
safe built-in get_current_time call despite the prompt requesting no tools; no
external write or Diary access occurred. Both synthetic release chats archived;
viewport reset and New chat restored. Filter functionality itself was tested
against synthetic stored files, not the real production Diary corpus.

Retain 02495a7 and .bak.before-48432fe env/Compose backups for app-only rollback
using the preflight wrapper with --no-build --no-deps --wait web diary ocr.
The pinned native backend/provider configuration remains in place.


## Portable workspace export release — 2026-09-14

Application 11155df replaces 48432fe; native router container unchanged.
427 local web tests, typecheck/build, 344 exact Linux web/proxy tests and 236
exact Linux Diary tests passed. GitHub CI 34823510937 passed all three jobs.
OCR image identity matches 48432fe. Synthetic browser checks cover six viewport
sizes and both themes; broader viewport/editor regressions passed. The synthetic
real-HTTP restore workflow verifies the new ZIP export and isolated restore.

Backup ab_20260914_043757 verified both state archives; completion 04:38:12.
The installed mount preflight and --no-deps web diary ocr rollout passed. All four
services healthy, zero restarts/OOM; OCR HTTP 200. Public assets are
index-m33txJ5p.js / index-KAGKyq4l.css. Production 375×360 ordinary synthetic chat
returned EXPORT_RELEASE_OK in3.0s,514in49out,26.2tok/s,32768context,MTP59.2%, no
tool calls. Chat archived,viewportreset,Newchat. No real Diary corpus access.

App-only rollback: current symlink and COWORK_VERSION back to48432fe, then
installed preflight/up.sh with --no-build --no-deps --wait web diary ocr. Keep
current native override and provider configuration. Config/Compose backups are
.bak.before-11155df; no schema, credentials or backend changes were made.

## Previewed managed workspace import release — 2026-09-14

Production application **e9358ab** replaces 11155df. ZIP preview and explicit Apply
into a new managed Imports folder are deployed, including transactional source /
empty-folder / backup / retry-receipt / index-outbox handling. Preview recognizes
a completed import after reload. Existing data/settings are preserved; legacy
storage is not migrated. Browser upload cap is 32 MiB. No retention policy added.

429 local web tests, typecheck/build; 258 local Diary tests (three skipped, two
existing warnings). Exact Linux images passed 346 web/proxy and 261 Diary tests.
CI 34825276184 passed all three jobs. Synthetic six-size/two-theme import UI,
editor save/conflict regressions and seven-size/two-theme mobile suite passed.
The real synthetic HTTP recovery workflow verifies ZIP export/import/retry/readback.

Backup ab_20260914_045459 verified both archives and completed at 04:55:15.
Installed preflight and app-only deployment passed; native container unchanged.
All four services healthy, zero restarts/OOM; OCR HTTP 200 at its configured 8030
port. An initial manual probe used the wrong 8090 port; corrected probe succeeded.
Public assets match index-CrOIZ7n1.js / index-D-NOzdGs.css. Production 375×360
ordinary-chat smoke returned IMPORT_RELEASE_OK in 3.7 s, 516 input/68 output tokens, 26.9 tok/s,
32,768 context, MTP 60.0%, no tool calls. Synthetic chat archived; normal viewport
and New chat restored. Real Diary was never opened/read/imported/reindexed.

Production mobile follow-up discovered: expanded sidebar at 375×360 leaves no
visible recent-chat list (header/footer consume available height). AX/locator
menu clicks had no effect until normal viewport was restored, where menu/archive
worked. This is a pending populated-sidebar reachability regression to fix next;
existing mobile suite did not catch it. Do not call mobile QA complete.

Retain 11155df and .bak.before-e9358ab env/Compose backups for app-only rollback.
The two added managed SQLite tables are additive; no live data was imported.
Next: short-height populated sidebar fix, then reversible managed trash/recovery,
Markdown fidelity and scoped Claude client verification. No subagents authorized.


## Short-screen sidebar release — 2026-09-14

Production **ee86c24** replaces e9358ab. Short-height/keyboard navigation scrolls
without collapsing history; touch Options targets remain 44px, and menus fit the
visible viewport. Expanded phone rail is opaque; section overlap caps removed.

429 local web tests, typecheck/build; seven populated viewport/keyboard cases in
both themes with scroll/hit/menu Rename/Escape checks and reviewed screenshots.
Existing mobile and Diary editor suites pass. Exact Linux web image: 345 server
tests pass. Initial image run lacked repository config fixtures; mounting the
three read-only config fixtures resolved its sole ENOENT failure. Diary/OCR image
identities match the previously verified release. CI 34826626504 all jobs passed.

Backup ab_20260914_051311 verified both archives; completed 05:13:27 EDT.
Preflight and app-only rollout passed, native container unchanged. All four
services healthy, zero restarts/OOM; OCR HTTP 200. Public assets match
index-B4SS5Cq1.js / index-kRE51da1.css. Production 375×360 synthetic ordinary chat
returned SIDEBAR_RELEASE_OK (5.0 s, 516 input/103 output, 26.4 tok/s, 32768 context,
MTP61.2%, no tools). Actual sidebar scrolling exposed its recent row; coordinate
Options click opened a fully visible menu and Archive removed the synthetic row
at the same viewport. Normal viewport/New chat restored. No real Diary access.

Rollback e9358ab and .bak.before-ee86c24 configuration/Compose backups retained;
app-only preflight/up.sh with --no-build --no-deps --wait web diary ocr.
Next: reversible managed trash/recovery; no retention/purge policy enabled.

## Managed Trash release — 2026-09-14

Production **724cd34** replaces ee86c24 with reversible single-file Markdown
Trash/restore. 345 exact-image web server tests pass when run serially (the
parallel run can race on `ui-data/secrets.key`); Diary image 275 pass. Backup
ab_20260914_112117 taken first. Guarded app-only rollout passed; all four
services healthy, zero restarts/OOM, native llama container unchanged. Public
assets index-ByZk1SN-.js / index-2LTQHseZ.css. Rollback ee86c24 with
`.bak.before-724cd34` configuration/Compose backups; script
/tmp/noevia-deploy-724cd34.sh on the operator machine and server.

## Freebuff review release — 2026-09-14

Production **1d9bf6a** replaces 724cd34: GFM task-list checkboxes in Markdown
preview, 44px touch targets at tablet/phone widths, per-file test data dirs (web
server tests now pass in parallel: 345/345 in the exact image), plus new
`qa/markdown-fidelity.cjs` and `qa/mobile-audit.cjs`. Implemented by Freebuff and
reviewed by Claude, who removed an unneeded calendar height cap and Diary layout
change. Diary image 275 pass. Backup ab_20260914_162750. Guarded app-only rollout
passed; four services healthy, zero restarts/OOM, native llama unchanged. Public
assets index-DFjfsfNx.js / index-DfW-uDoU.css. Rollback 724cd34 with
`.bak.before-1d9bf6a` backups.

The same day's server cleanup had removed the stopped `lemonade`,
`model-loader-test` and `llama-vulkan-test` containers that
`operations/native-20260914b/rollback.sh` starts. They were recreated stopped
(restart `no`) from their retained Compose files: llama-vulkan-test at its pinned
digest, model-loader-test rebuilt from its pinned source. Lemonade was re-pulled as
`latest`, so a native rollback may get a newer Lemonade than the 10.8.0 it replaced.

## Native preset suggestions release — 2026-09-14

Production **be34fa5** replaces 1d9bf6a. Admins get "Suggest settings from model file"
in the native runtime profile: noevia reads GGUF headers through a new read-only
`${LLAMACPP_MODELS_DIR}:/models:ro` web mount and sizes KV cache (hybrid SSM,
sliding-window, shared-KV layers), vision projector, built-in MTP draft KV and a 1 GiB
reserve, with a 5% margin, against `LLAMACPP_MEMORY_LIMIT` (14g). The sizing is
adapted from scratchhax/model-loader e11a6ec (MIT; see THIRD_PARTY_NOTICES.md).
Suggestions only fill the editor draft; applying still uses CAS, unload-all and reload
rollback. Estimates matched the 2026-09-12/13 calibration peaks: Qwen3.5 9B at 262144
with mmproj 12.7 vs 13.2 GiB raw, Gemma 4 E4B at 131072 with mmproj 8.5 vs 8.6.
The live override gained the web mount and two environment keys
(`.bak.before-be34fa5` retained). Web image 349/349, Diary 275. Backup
ab_20260914_165258. Guarded rollout (restores the override on failure) passed; four
services healthy, zero restarts/OOM, native llama unchanged, web cannot write
`/models`. In-container production run over the live presets suggested Qwen 4B 262144
(11.3 GiB, draft-mtp), Qwen 9B 262144 (13.4), Gemma E4B 131072 (8.9), Gemma E2B 131072
(6.3), refused nomic, and left models.ini unchanged. Suggestions are unqualified until
load-tested; production presets were not changed. Assets index-l9jdb2u8.js /
index-D-dyhOXC.css. Rollback 1d9bf6a plus the override backup.

## Model Loader and calibration releases — 2026-09-14

Production **ccd313e** (after 21599e8, 2c82567, 6ea246f the same day). Measured native
context calibration: load checks bound the search, then near-full streamed prompts run
middle-out under an admin time limit with recall checks; the passing size is saved and
the model is loaded with it. Model Loader (scratchhax/model-loader e11a6ec, MIT) runs as
`cowork-model-loader-1` with the model folder, llamacpp config dir and Docker socket, no
published port; noevia serves it to admins at `/model-loader` (same-origin writes only,
no cookie forwarding, URL rewriting, bundled checksummed scripts, strict CSP). Its build
patch keeps the preset preamble (`version = 1`), which upstream configparser rejected;
the first bfbeb42 rollout failed its health check on that and rolled back automatically.
New .env keys MODEL_LOADER_DATA_DIR / _LLAMA_CONTAINERS / _GPU_VRAM (cowork-llama-1:14) /
_HOST_RAM_RESERVE_GB (8). Rollback 6ea246f with `.bak.before-ccd313e` env/Compose
backups, then `docker rm -f cowork-model-loader-1`. The old `model-loader-test`,
`llama-vulkan-test` and `lemonade` containers stay stopped for the native rollback.
Note: saving from Model Loader rewrites models.ini without comments inside sections, and
its backend restart restarts the whole llama container.

## Page-load performance release — 2026-09-14

Production **e4b2f73** replaces a8d5bd2 and also carries 155a541 (model manager sees
Hugging Face cache-layout models). Measured first: the origin serves the page in ~5 ms
and every upstream call behind the first screen takes 2–25 ms. The slowness came from
(1) **20–40% packet loss on the home internet link**, seen from both the Mac and the
server to 1.1.1.1 with 0% on the LAN. TCP SYN retransmits make connect/TLS to any
Cloudflare site take 1–9 s, and cloudflared logs QUIC timeouts and DNS i/o timeouts.
The same link explains the npm stalls and the earlier unreachable episode, and it needs
fixing at the modem/router/ISP. (2) Round trips and bytes: nothing was compressed or
cacheable at the origin, one 542 KB bundle, Google Fonts blocked render, and the auth
checks waited for the bundle.

Now `server/static-files.cjs` serves brotli/gzip with one-year `immutable` caching for
hashed `/assets/*` and `no-cache` + ETag for the rest. Settings/model management, Diary,
Projects, Coding, the wizard and WebAuthn are lazy chunks prefetched when idle. index.html
preloads `/api/setup/status` and `/api/auth/session`. Fonts load from a deferred script,
and stats/health polling pauses in hidden tabs. Cloudflare HITs the immutable assets; it
drops the ETag on index.html (HTML rewriting), which is harmless at ~0.5 KB.

Numbers (`apps/web/qa/load-perf.cjs`, time until the composer is usable, medians):
local at 150 ms RTT / 12 Mbps, 1200 → 530 ms, cold transfer 815 → 273 KB, warm reload
735 → 14 KB; at 400 ms / 3 Mbps, 3.68 → 1.32 s. The production origin over LAN at 150 ms
reaches sign-in in 526 ms. Over the real internet link, production runs vary 1.5–13.6 s
with 20–30% loss, so they measure the link, not the app. The sign-in screen's cold
transfer went 259 → 183 KB.

Images were built without npm/pip as overlays: cowork-web on a8d5bd2 with the local
e4b2f73 dist (packed with COPYFILE_DISABLE=1; an earlier pack carried macOS `._*` files)
plus `server/`, and cowork-model-loader on a8d5bd2 with `app/`. Diary/OCR were retagged,
unchanged since a8d5bd2. Exact web image: 367/367 server tests, with `.env.example`,
`compose.yaml` and `deploy/` mounted at `/` for the repo-level compose test. Model manager
11/11. Backup ab_20260914_233056 (web and Diary archives gzip-verified). The guarded
rollout passed; five services healthy, zero restarts/OOM, native llama unchanged. The
model manager lists five files, all without entries (models.ini stays empty by the
user's choice), with projectors for Qwen 9B and both Gemmas. Assets index-Ckupi_DT.js /
index-CweMon5t.css. Browser QA: 15 suites pass. diary-landing, diary-reading and
reasoning fail identically on the unchanged 155a541 build (pre-existing). Rollback
a8d5bd2 with `.bak.before-e4b2f73` env/Compose/override backups; script
`deploy/examples/overlay-release.sh`.

## Releases a48a8c4 and 503b1c5 — 2026-09-15/16

**a48a8c4** (MCP compose keys and drift check, model refresh on change, in-app MCP server
off by default, unified Models & routing, minimal chat model panel, General settings,
cost estimates removed). Overlay on `cowork-web:e4b2f73` (no dependency changes);
diary/ocr/model-loader retagged. Five services healthy, zero restarts, native llama
unchanged. **Gaps:** no appdata backup was taken first, and the shipped `dist` carried
one stale bundle (index.html references the correct one). Rollback `e4b2f73` with
`.env.bak.before-a48a8c4`.

**503b1c5** (docs only: single roadmap and master prompt, `deploy/examples/overlay-release.sh`).
Backup `ab_20260916_151428` taken first. All images retagged from `a48a8c4`, no rebuild;
release dir `releases/503b1c5`, `COWORK_VERSION=503b1c5`, web/diary/ocr recreated via
preflight `up.sh`. Five healthy, zero restarts, native llama unchanged; model-loader still
runs its `e4b2f73` tag as before. Deployed over Tailscale (`root@100.70.173.74`) because
the Mac was off the LAN. Rollback `a48a8c4` with `.env.bak.before-503b1c5`.

Open on the live host: no models served (models.ini empty, GGUFs removed); the live
Compose Manager file lacks the MCP keys (`mcp: disabled`).

## Release 657d21b — 2026-09-17 (decisions build, bug hunt, UI first pass, D1 applied)

Production **657d21b** replaces 503b1c5, deployed on the user's instruction ("you can deploy to
prod"). Contents: D5 feature registry (all new features off), D8 folder sweep, D6 DAV
DELETE/MOVE/COPY (sharing listener still unconfigured), D10 Diary append (off), D12 research (off),
D7 off-site backups (off, unconfigured), D9 Kiwix (off, not deployed), D4 design lint, the bug-hunt
fixes (transcripts no longer truncated to 40 messages, merged chat lists and revisioned transcripts,
auth races and enumeration, approval/queued-append honesty, calibration restore notice, short-phone
layout and touch targets) and UI polish (Lucide icons, System appearance, status pill).

**D1 applied as the first step:** `MODEL_LOADER_TOKEN` generated into `config/.env`; the live override
gives model-loader the token and only the new `models` network, web the token and `models`, llama
`[default, models]`. The override also gained the six MCP keys and `TRUST_PROXY` the base file lacked,
so startup now logs `mcp: nextcloud+tavily` (values were already in `.env`). Installed
`tools/preflight` refreshed from the release (D1 boundary check + env-key drift).

Flow (`/tmp/noevia-release-657d21b.sh`, kept in the operator's temp during the session): appdata
backup `ab_20260917_033…` (web/Diary archives + configs) → overlay images (web on 503b1c5 with new
`dist`+`server`; Diary on 503b1c5 with new `agent/`; model-loader on e4b2f73 with new `app/`; ocr
retagged) → in-image web server tests 509/0, Diary and model-loader import checks → `.env`, override
and preflight backups `*.bak.before-657d21b` → resolved-config preflight (mounts, D1, env keys all
PASS) → `up -d --no-build --wait` for web, diary, ocr, model-loader, llama (llama recreated to join
`models`; no model was loaded) → verification: Diary cannot resolve `model-loader`; model-loader 401
without the token, 200 with it; five services healthy, zero restarts; public index and hashed
assets 200 with the new bundle. Automatic rollback restores `.env`, override, preflight tools, the
`current` symlink and runs `up` on 503b1c5.

Rollback manually: copy the three `*.bak.before-657d21b` files back, `ln -sfn releases/503b1c5
current`, `COWORK_VERSION=503b1c5`, then preflight `up.sh … -d --no-build --wait`.

Not done by agents: no sign-in to real accounts (no credentials entered); the real Diary corpus was
not touched. Still running and not ours: `llama-vulkan-test` (documented as kept stopped for native
rollback) is up — see the session summary.

## 2026-09-17 follow-up on 657d21b — D3 applied, Kiwix live, features on (user decisions)

No image change. Each file edited was copied first (`*.bak.before-d3`, `*.bak.before-kiwix-features`,
`.env.bak.before-internal-mcp`); started with the installed preflight `up.sh`, all services healthy.

- **D3:** embedding model downloaded, `models.ini` swapped, `--models-max 2`, `EMBEDDING_MODEL`
  renamed, Auto roles fixed. Evidence in `research-known-good-settings.md` § D3 applied.
- **D9 Kiwix:** `wikipedia_en_all_nopic_2026-06.zim` (52 690 706 555 bytes, size matches the
  mirror) in `/mnt/disk3/kiwix`; `kiwix` service added to the live override on an internal
  `kiwix` network shared only with web (Diary cannot resolve it); search for "Alan Turing" returns
  results. `offline-wikipedia` added to `ENABLED_TOOLBOXES`.
- **Features on** through override env: previews, Diary append tool, deep research, Kiwix.
  Off-site backup stays off (no target — user chose to skip).
- **In-app MCP server:** `MCP_INTERNAL_PORT=8022` and `noevia|http://127.0.0.1:8022/mcp|internal`
  in `MCP_SERVERS`; `diary` and `project-docs` toolboxes enabled. Startup logs
  `mcp: nextcloud+tavily+noevia`, 10 in-app tools; port 8022 is not published.
- `llama-vulkan-test` stopped (container kept) at the user's request.

Rollback: restore the three backups named above plus `models.ini.bak-before-d3` and
`ui-data/auto-roles.json.bak.before-d3`, then run preflight `up`. The ZIM can be deleted freely.

## Release 877947c and off-site backups — 2026-09-18 (early hours)

Web-only overlay from `1fe3f1b`, appdata backup `ab_20260918_004552` first (both noevia archives
present, log ends DONE). Five services healthy, restarts 0, engine container unchanged, public
entry bundle `index-DqIOe8vm.js` byte-identical to the local build. Carries the Code mode work (still
off), the folder backup target, and D21–D23. The Auto-routing repair of the night before lives in
state, not the release, and survived it.

**Off-site backups are on** (D23), except the Google half, which needs the user's one sign-in.

| Piece | Where |
|---|---|
| Encrypted store (noevia writes it, 02:00 nightly) | host `/mnt/user/noevia-backups/offsite` → web `/offsite` |
| Key (64 hex, generated on the box, never printed) | host `/mnt/docker/appdata/cowork/config/offsite-backup.key` → web `/run/offsite/backup.key:ro` |
| Diary data, so the corpus is included | host `state/diary` → web `/backup-src/diary:ro` — web **cannot write it** (verified) |
| Mirror to Google Drive, 02:45 nightly | `/mnt/docker/appdata/cowork/tools/offsite/rclone-sync.sh`, cron in `/boot/config/plugins/dynamix/noevia-offsite.cron` (Unraid loads it into `/etc/cron.d/root`; `crontab -l` does not show it) |
| rclone config (empty until the user signs in) | `/boot/config/rclone/rclone.conf` |

Live override changes, backed up as `docker-compose.override.yml.bak.before-offsite-drive`: the six
`OFFSITE_*`/feature variables and three mounts on `web`. `docker compose config` valid and the
preflight passed (all three checks) before web was recreated through `up.sh`.

Verified: the first real snapshot (139 files, 19 MB) was sealed in a second and the restore test
passed; a full restore into a scratch directory brought back all 12 SQLite databases — `cowork.db`,
the project databases and `managed-diary.db` among them — and every one passed `integrity_check`.
**No plaintext on disk:** none of the 124 objects contains a string known to be backed up (a model
name from `auto-roles.json`), the SQLite header, or `CREATE TABLE`.

Until the user signs rclone in, the nightly mirror logs `FAIL no rclone config` and exits 2 — by
design, and harmless. Steps for the user: `deploy/offsite/README.md`.

Rollback: restore the override backup and recreate web; for the code, point `current` and
`COWORK_VERSION` back at `1fe3f1b` (`config/.env.bak.before-877947c`).

One operational lesson from this deploy: waiting for the appdata backup with
`pgrep -f "[a]ppdata.backup/scripts/backup.php"` hung for ten minutes after the backup had finished,
because the same SSH command line also contained the *unbracketed* path (inside the `setsid`
argument). The bracket trick only stops a pattern matching itself. Wait on a log marker or a PID.

## Syslog mirror enabled — 2026-09-17 night (host setting, at the user's request)

The outage of 2026-09-17 (04:15–08:24) lost its evidence because the box's own syslog is on
tmpfs. It still was: `/var/log/syslog` is a 128 MB tmpfs and began at `Sep 17 08:25:26 ... Linux
version`, i.e. the reboot that ended the outage.

**"Local syslog server: Enabled" does not fix this**, which is easy to misread. That setting
makes Unraid *receive* syslog from other devices over UDP 514 and write it to
`server_folder` (here `/mnt/user/Nextcloud-backup`); `rsyslog.conf` binds it to the `remote`
ruleset. The box's own messages go through the `local` ruleset to `/var/log/syslog` — RAM. The
share held no syslog file at all.

Changed in `/boot/config/rsyslog.cfg` and applied with the same script the GUI uses
(`/usr/local/emhttp/plugins/dynamix/scripts/rsyslog_config`):

| Setting | Was | Now |
|---|---|---|
| `syslog_flash` (Mirror syslog to boot drive) | `""` (No) | `"1"` (Yes) → `/boot/logs/syslog` |
| `log_rotation` | `""` (Disabled) | `"1"` |
| `log_size` / `log_files` | `1M` / `1` | `10M` / `4` |

`syslog_shutdown` is left alone: its values are **inverted** in the page (`""` = Yes), so it was
already on.

**Unraid never rotates the flash copy.** `rsyslog_config` writes a logrotate rule for
`$server_folder/*.log` only, so `/boot/logs/syslog` would grow for as long as the mirror is on —
worst in exactly the situation it exists for, a box logging hard while something fails. Added
`/boot/config/logrotate-syslog-flash.conf` (10 MB × 4, compressed, HUP on rotate ≈ a week at this
machine's ~6 MB/day, capped near 50 MB) and three lines in `/boot/config/go` to restore it into
`/etc/logrotate.d/` each boot, since that directory is in RAM. Flash is 29 GB with 27 GB free.

Verified: a `logger` message appears in `/boot/logs/syslog` seconds later; `logrotate -d` parses
the rule; `bash -n` accepts the modified `go`. Backups: `rsyslog.cfg.bak.before-syslog-mirror`,
`go.bak.before-syslog-mirror`.

To undo: restore both backups and re-run `rsyslog_config`.

## Release 1fe3f1b — 2026-09-17 night (CodeHarness, tool hints, two live bug fixes)

Web-only overlay from `ca5d2f6` (`deploy/examples/overlay-release.sh`), appdata backup
`ab_20260917_192134` first (both `cowork-web-1.tar.gz` and `cowork-diary-1.tar.gz` present).
All five core services healthy, restarts 0, the native engine container untouched (the script
asserts its container id is unchanged), Kiwix untouched. Startup logs `mcp:
nextcloud+tavily+noevia`, 176 tools across 3 servers, 24 curated boxes — unchanged by the
`mcp-boxes.cjs` extraction. Public bundle `index-BIcLu4wO.js`, sha256 matching the local build
byte for byte.

**D1 needed no operator steps: it was already applied.** The roadmap said the live resolved
config was blocked by the new preflight until the token and network were set up; running
`check.php` against the live `docker compose config` returned three PASSes, including
"model-loader is token-gated and unreachable from the Diary sidecar", and at runtime the Diary
container still cannot resolve `model-loader`. That was done with `657d21b`; the note was stale
and is corrected.

What this ships to production: the models-settings hit targets that were under 40px on the live
release itself, auto-tune's "resume" no longer restarting silently after its 7-day TTL, the
Tasks-box tool hints, Discover's empty state offering "Show all publishers", and the whole
CodeHarness build — **off**, with no `CODE_*` environment set, so it is unreachable.

Deployed with the engine idle (no `/v1` requests in the preceding 10 minutes) and outside the
mover (03:40) and backup (04:10) windows.

Rollback: `overlay-release.sh`'s automatic path (it rolls back on a failed health wait or if the
Diary can resolve model-loader), or manually point `current` and `COWORK_VERSION` back at
`ca5d2f6` — `config/.env.bak.before-1fe3f1b` holds the previous value and every `cowork-*:ca5d2f6`
image is still on disk — then re-run the preflight `up` for web, diary and ocr.

## Release 8e4dcd0 — 2026-09-17 (stale Auto roles)

Web-only overlay from 657d21b (`deploy/examples/overlay-release.sh`), appdata backup
`ab_20260917_040312` first. `/api/chat` answers 409 when an Auto role names a model the engine no
longer serves; Models & routing shows which. All five core services healthy, restarts 0, Kiwix
untouched, startup logs `mcp: nextcloud+tavily+noevia`, public bundle `index-C9EG4mc8.js`
matches the local build.

First attempt shipped an empty `dist/` (the local `/tmp/noevia-qa-dist` target had been deleted,
so `npm run build` failed and the chained `tail` hid the exit code); the image build stopped
before anything switched and the stray release folder was removed. The script now refuses a
tarball without `dist/index.html` and JS assets.

Rollback: `overlay-release.sh`'s automatic path, or manually point `current` at
`releases/657d21b`, restore `.env.bak.before-8e4dcd0`, run preflight `up` for web.

## 2026-09-17 outage and recovery

DaServer became unreachable around 04:15 (SSH banner timeouts, Unraid UI down, later public 530).
The user restarted it at about 08:24; all services came back healthy. Syslog lives in RAM on this host
and was lost on reboot, so the cause is unconfirmed (hypotheses in
`research-findings-2026-09-17.md` §5 and §7). Ruled out: the new Docker networks (`cowork_models`
172.26.0.0/16, `cowork_kiwix` 172.27.0.0/16) don't overlap the LAN (10.69.0.0/24).

Mitigation applied after boot: engine back to `--models-max 1` (override backup
`.bak.before-models-max-1`); llama recreated, healthy, public 200. Enable the Unraid syslog mirror
to flash or a share before trying `--models-max 2` again with a GTT cap.

## Release 127b300 — 2026-09-17 (Data, Personalization, shortcuts, HIG polish)

Web-only overlay from 8e4dcd0 (`overlay-release.sh`), appdata backup `ab_20260917_082843` first.
Contents: type scale and HIG cleanups, stale-role checks, tool router (flag off), Data (export,
import, archived chats, delete old chats), Personalization (custom instructions, response style,
background notifications), keyboard shortcuts, shared-memory warning, glass glint, undefined-token
lint. Result: all services healthy with 0 restarts, Kiwix up, `mcp: nextcloud+tavily+noevia`, new
routes 401 without a session, public bundle `index-nEvEttZ0.js` matches the build,
`glass-highlight.js` 200. Engine stays at `--models-max 1`.
Rollback: point `current` at `releases/8e4dcd0`, restore `.env.bak.before-127b300`, preflight `up` web.

## 2026-09-17 live changes on 127b300 (no release)

- **Nextcloud AIO repaired.** `nextcloud-aio-apache` and `-talk` crash-looped after the nightly AIO
  update (new mastercontainer, 4-week-old child images; supervisord pid dir missing on the tmpfs
  `/run`), so `drive.daserver.work` returned 502 and the Diary's WebDAV storage failed. Fixed by
  pulling `aio-apache`/`aio-talk` and running the mastercontainer's `Cron/StopContainers.php`, then
  `Cron/StartAndUpdateContainers.php` (as `www-data`). `daily-backup.sh` is no use in this state:
  it waits for apache forever.
- **Nextcloud Assistant uses the native engine.** Override: `llama` joins the external
  `nextcloud-aio` network with alias `noevia-llama` (not published on the host; copy
  `.bak.before-nextcloud-ai`). Also connected live with `docker network connect`, so no engine
  restart. `integration_openai`: `url=http://noevia-llama:8080/v1`, service name "noevia llama.cpp",
  default completion model `Qwen3.5-4B-Q5_K_M`, image/speech providers off. Verified with a
  `core:text2text` task (status successful). With `--models-max 1`, Assistant requests share the
  one model slot with noevia chats and can evict the loaded model; the engine has no API key, so
  anything on the `nextcloud-aio` network can use it.
- **Deep research off.** `NOEVIA_FEATURE_DEEP_RESEARCH: "false"` (copy
  `.bak.before-deep-research-off`), web recreated with `up.sh … --wait web`. Gate failed; see
  `spec-deep-research.md` §8.
- **KoboldCpp test engine: added and removed the same day.** Rejected after measurement (findings
  §12). Service, container, provider row, binary and override backup with its block are gone; the
  override differs from `.bak.before-koboldcpp` only by `CONTEXT_LOG`.
- **`CONTEXT_LOG=1`** on web (copy `.bak.before-context-log`), counts only, for step 5.
- **Model downloads (user request):** gpt-oss-20b Q4_K_M, Gemma 4 E4B and 26B-A4B QAT UD-Q4_K_XL
  (+ mmproj), Unsloth, sha256-verified, in `/mnt/user/ai-models/<name>/`, not in `models.ini`.
  Qwen3.6-35B-A3B IQ3_XXS/IQ4_XS were downloaded for the KoboldCpp test and deleted with it.

## Release ea57c83 — 2026-09-17 afternoon (model tuning, Tune button, folder sync, account memory, router)

Appdata backup `ab_20260917_130015` ("Backup created without issues") first. Web overlay from
127b300 with `overlay-release.sh` (web, diary, ocr healthy; `RELEASE_ea57c83_COMPLETE`). The model
manager changed, so `cowork-model-loader:ea57c83` was built as an overlay on `8e4dcd0` (new
`/srv/app`) and only `model-loader` was recreated; the Diary still cannot resolve it (D1). Native
engine untouched.

Live config (override copy `.bak.before-embed-router`): new `embed` service (pinned llama.cpp image,
`--device none`, nomic-embed-text-v1 Q8_0, `-c 4096 -ub 2048 --parallel 2`, 1 GiB, `default`
network only, healthcheck `/health`); web gets `EMBEDDING_BASE_URL=http://embed:8080/v1` and
`NOEVIA_FEATURE_TOOL_ROUTER=true`.

Verified: live autoconfig recommends 32K for the 4B and 12K for the 9B (capped by measured prompt
speed, memory estimate 262K), built-in MTP detected on both; web → embed 46 ms, 768 dims, with the 9B
still loaded on the engine; MCP 176 tools. Not verified here (needs the user's session): the Tune
button, Easy mode and the router in a real chat.

Rollback: `current` → `releases/127b300`, restore `config/.env.bak.before-ea57c83`, copy
`docker-compose.override.yml.bak.before-embed-router` back, preflight `up` web and model-loader with
`cowork-model-loader:8e4dcd0` (retag as `127b300` or set `COWORK_VERSION=127b300`), and remove `embed`.

## Nextcloud AIO audit — 2026-09-17 afternoon (user request: optimise)

Nextcloud 34.0.4 (AIO, PHP 8.4, Postgres, Redis, Imaginary, Elasticsearch, Collabora, Talk). Measured:
`status.php` ~10 ms on the LAN, ~100 ms through Cloudflare, login page 137 ms; Postgres cache hit
99.95 % (`shared_buffers` 256 MB for a 405 MB database, 75 k files); APCu + Redis caching and locking,
OPcache 256 MB with JIT, cron background jobs current (96 jobs, none stuck), preview queue empty,
Imaginary previews, no missing indices/columns/primary keys, all apps up to date. Idle CPU: Nextcloud
~3.5 %, Postgres ~1 %. AIO rewrites PHP-FPM, `maintenance_window_start` (from
`NEXTCLOUD_MAINTENANCE_WINDOW`, default 100 = any time) and Postgres settings on start, so hand
tuning there does not persist and is not needed at these numbers.

Changed:
- Removed a stale `daily_backup_running` marker (created 10:15 by the interrupted `daily-backup.sh`
  during the apache repair); left in place it could make AIO treat the nightly backup/update as
  already running. No backup process was running.
- (Earlier today) apache/talk repaired; `integration_openai` pointed at the native engine.

Checked and left alone: "remote address could not be determined" only appears because setup checks
run from the CLI; Caddy trusts private ranges and the host-network Cloudflare tunnel forwards the
client IP. AIO Borg backup runs 04:00 UTC (00:00 Eastern, ~2 min), clear of mover 03:40 and appdata
backup 04:10 Eastern.

Needs the user: `default_phone_region` (country code), outgoing email server, Talk high-performance
backend 2.1.1 lacks `changed-users` (upstream AIO image), and whether Nextcloud Assistant should get a
dedicated task-processing worker (AI tasks otherwise wait for the 5-minute cron); in AIO that needs
the mastercontainer environment or a community container.

## 2026-09-17 later — phone region, Assistant speed, Talk, 4B preset (user request)

- **Phone region:** `default_phone_region = US`. No outgoing email server (user has none).
- **Nextcloud Assistant speed.** AIO already runs a supervised `taskprocessing-worker` (dinit,
  300 s timeout); tasks were picked up in under a second. The delay was the model thinking: a
  one-sentence text task generated 1 010–1 859 hidden reasoning tokens (53–100 s). Set
  `integration_openai llm_extra_params = {"chat_template_kwargs":{"enable_thinking":false}}`.
  Measured end to end through Nextcloud's task queue: **2.9 s** (was 57.6 s / 100.1 s). The worker
  caches app config for up to 300 s after a change. A host cron worker added briefly was removed
  (duplicate of AIO's).
- **Talk.** `aio-talk:latest` (published 2026-09-11) is already running and the mastercontainer is on
  the newest `latest` (2026-09-16); `beta` is older. The high-performance backend 2.1.1 still lacks
  `changed-users`; waiting on an upstream AIO image. Not pinned by hand (AIO would revert it).
- **Qwen3.5-4B-Q5_K_M preset** (copy `models.ini.bak.before-4b-retune`): `ctx-size` 262144 → 32768
  (Tune's capped recommendation), `cache-ram` 19968 → 4096 (a 19.5 GiB host prompt cache on a 29 GiB
  host), `spec-type` draft-eagle3 (no draft model) → `draft-mtp` using the built-in nextn layer.
  Verified: loads with `n_ctx_slot = 32768`, "creating MTP draft context against the target model";
  generation 40.2 tok/s on a list (98 % accepted), 36.0 tok/s with thinking (83 %), 23.2 tok/s on
  prose (41 %), against ~19 tok/s before. GTT 4.0 GiB, host available 16.4 GiB.

## Releases c54b5a5 and 7132487 — 2026-09-17 late afternoon (auto-tune)

Appdata backups `ab_20260917_133936` and `ab_20260917_142705` first; both web-only overlays.
`cowork-model-loader` retagged to each release (its code is unchanged since ea57c83).

Live changes with these releases:
- **Auto-tune** (`/api/models/autotune`, admin) measured every served model; results and the new
  contexts are in `research-known-good-settings.md`. Presets now carry `spec-type = draft-mtp`
  (4B, 9B), `ubatch-size` 512/1024 and verified contexts.
- **Model folder sync** runs on the server (20 s after start, then every 15 min): a new GGUF gets
  safe defaults and the engine reloads, with no page visit. The three models registered by hand
  this morning (gpt-oss-20b, Gemma 4 E4B/26B) came from the pre-fix Easy mode and carried
  unverified 131 072 contexts and a `draft-eagle3` setting with no draft model; auto-tune and
  calibration replaced both.
- **Deleted at the user's request:** `gemma-4-26B-A4B-it-qat-UD-Q4_K_XL` (15 GiB, section and
  files) — it cannot load at a usable context on this GPU.
- **Nextcloud:** `default_phone_region = US`; Assistant thinking disabled (57–100 s → 2.9 s);
  task types `core:audio2text`, `core:text2image` and `core:text2speech` disabled, because this
  server has no provider for them and the Assistant otherwise offers buttons that fail to schedule.
  Talk stays on `aio-talk:latest` (2026-09-11); no newer image exists, so its missing
  `changed-users` feature waits for upstream.

Researched, not adopted: **Qwen3.8-Flash-Next** (Qwen4-generation architecture with an n-gram table
that can live on SSD via `--model-ngram --ngram-load-mode read`) needs ~64 GiB of RAM even with the
table off-GPU — the smallest build is ~72 GB, ~38 GB of it the table. Revisit if a smaller Flash
variant ships. Qwen3.8-27B is a fine-tune of 3.6 (dense); Granite 4.2 30B (IBM, official GGUF,
Q3_K_S 12.7 GB) is the newest first-party model that fits but is dense, so slower than gpt-oss-20b.

## Releases daea26f → faeb9d2 — 2026-09-17 evening (Discover judged for this server)

Web overlays plus a model-loader image per release (its Python changed); appdata backups taken
before each. `current` and `COWORK_VERSION` both point at `faeb9d2`.

Discover now judges every search result against this machine (`services/model-manager/app/discover.py`):
real file sizes and quantisations from the repo tree (cached an hour, shards folded together,
mmproj/MTP/EAGLE/Medusa companions excluded), parameter count and mixture-of-experts from name and
tags, publisher trust, and whether a Q4-or-better file fits the GPU budget (12.5 GB here). Ranking is
fit → trusted publisher → popularity with a 90-day half-life. Untrusted publishers and unsuitable
models are hidden by default with counts and one-click toggles; filters cover size, quantisation,
parameters, architecture, vision, licence and publisher; the panel links to the same search on
Hugging Face.

Two bugs found by running it against the live hub, both fixed the same evening: repos looked
"suitable" on the strength of a stray 10 MB GGUF with no quantisation in its name, and
`ggml-org/gpt-oss-120b-GGUF` offered a 1.59 GB "BF16" file that is an EAGLE3 draft head.

## Release ca5d2f6 — 2026-09-17 night (main after PR #1 and PR #2)

First deploy from `main` rather than a branch: `ca5d2f6` is the merge of PR #2 (measured
model tuning, server-judged Discover, tool routing, CPU embeddings, account memory) on top of
PR #1 (settings-native model manager styling, layout mode, hub search that returns results).
Everything in `faeb9d2` is included; PR #1 adds `apps/web/public/layout-mode.js`,
`LayoutMode.tsx`, CSS, and the `hf.py`/`api.py`/`main.py` search changes.

Checked before shipping: 679 web server tests, typecheck, design lint clean; the merge diff
against the branch is PR #1's files only.

Flow: appdata backup `ab_20260917_164749` (run with `setsid` — a plain `nohup … &` over SSH
does not survive the session) → `deploy/examples/overlay-release.sh faeb9d2 ca5d2f6` (web
overlay on `cowork-web:faeb9d2`, diary/ocr/model-loader retagged) → a second image for
`cowork-model-loader` (`FROM cowork-model-loader:ca5d2f6`, `COPY app /srv/app`, import check)
recreated through the preflight `up.sh`.

Verified after: all five services healthy with `restarts=0`, native engine container untouched,
`current` and `COWORK_VERSION` on `ca5d2f6`, D1 holds (the Diary cannot resolve `model-loader`),
public 200 with bundle `index-BhBOCyc5.js` matching the local build, startup logs
`mcp: nextcloud+tavily+noevia` with 176 tools across 3 servers, and Discover answering live hub
searches against this machine's 12.5 GB budget (`gpt-oss` 6 shown / 20 untrusted / 13 unsuitable;
`gemma` 7 shown). A bare `qwen3` search shows nothing under the trusted default because the hub's
top 30 for that word are community fine-tunes — the "everyone" toggle widens it, as designed.

Rollback: `overlay-release.sh`'s automatic path, or point `current` and `COWORK_VERSION` back at
`faeb9d2` (`config/.env.bak.before-ca5d2f6`) and re-run the preflight `up` for web, diary, ocr and
model-loader.

## Code mode (optional, off)

`features.codeHarness` is off by default and the routes 404 without it. Two operator settings turn
it into something that can run, and both are deliberate:

- `CODE_REPOS=name|/abs/path,other|/abs/path` — the **only** repositories a task can ever open.
  Entries that are relative, missing or not a git repository are dropped at startup. Without this,
  nothing can start; a task cannot name a host path.
- **`CODE_HARNESS_ENDPOINT=code-sandbox:8030`** — the sandbox container to run the agent in.
  This is the one to use here. `deploy/examples/code-sandbox.override.yml` + the `code` profile
  bring up `services/code-sandbox`: read-only root, `cap_drop: ALL`, no-new-privileges, uid 1000,
  tmpfs `/tmp` and `$HOME`, bounded memory and pids, one volume for the task worktrees, an
  internal network whose only other member is the egress proxy, and no published port.
- `CODE_HARNESS_COMMAND` (and optional `CODE_HARNESS_ARGS`) — the alternative: run the agent as a
  child of the web process. **Don't, on this box.** It puts a coding agent inside the container
  that holds noevia's state, sessions and credentials. It is there for a workstation.
  `CODE_HARNESS_ENDPOINT` wins when both are set, so a stale variable cannot quietly downgrade a
  deployment that has a sandbox.

With neither, a task fails with "No coding harness is configured on this server."

The worktree path noevia creates must be the same path inside the sandbox — it sends the path and
the supervisor resolves it — so the volume is mounted at the same point in both containers. Egress
for a task goes through the built-in proxy (D15) and is refused unless the task was granted the
domain. The harness version is pinned as a build argument; an agent that updates itself is an
unreviewed supply-chain change in the one container allowed to run arbitrary commands.

## Release f0ea80b — 2026-09-18 early morning (noevia.daserver.work, Google Drive in-app)

Appdata backup `ab_20260918_040536` first. Web-only overlay `27c07b9 → f0ea80b`
(`overlay-release.sh`, `RELEASE_f0ea80b_COMPLETE`, all five services healthy, engine untouched).

- **Address:** Cloudflare `unraid-tunnel` gained `noevia.daserver.work → http://10.69.0.130:8021`;
  `cowork.daserver.work` stays routed (it must: it serves `/.well-known/webauthn`, which keeps
  passkeys made under that name working at the new address). noevia's address was switched
  with the Settings → Web address code path (`auth.changeOrigin`), so `public_origin_admin` in
  the settings table now wins over `PUBLIC_ORIGIN` in `.env`; `passkey_rp_id` = `cowork.daserver.work`.
- **Google Drive (D24):** `GOOGLE_OAUTH_CLIENT_ID/SECRET` added to `config/.env` (backup
  `.env.bak.before-google-oauth`) and wired in the live `docker-compose.override.yml` (backup
  `.bak.before-google-oauth`); `OFFSITE_BACKUP_MIRROR` removed. Google Cloud project `noevia`:
  Drive API on, OAuth client "noevia device sign-in" (TVs and Limited Input), scopes
  `drive.file openid email` (non-sensitive), home `/about`, privacy `/privacy`, **In production**.
- **Still to do:** an admin clicks Connect Google Drive in Settings → Backups; after the first
  in-app copy succeeds, remove the host rclone cron (`/boot/config/plugins/dynamix/*.cron`
  entry for `rclone-sync.sh`, then `update_cron`) and the old rclone-made `noevia-offsite` folder.

## Releases 3d1470d and 5f3f73c — 2026-09-18 morning (passkey fix, storage form)

Appdata backups `ab_20260918_043305` and `ab_20260918_043756` first; web-only overlays, all
services healthy. **3d1470d:** passkeys store their own `rp_id`; the live passkey was migrated to
`cowork.daserver.work`; new passkeys are made for `noevia.daserver.work` (setup had asked for the
old RP ID and browsers refused it). **5f3f73c:** the Diary storage form explains locked fields and
offers Try again after 10 s.

## Release 35ed364 — 2026-09-18 (UI overhaul release 1: Foundation)

Appdata backup `ab_20260918_060944` first (no errors). Web-only overlay `385f04a → 35ed364`
(`overlay-release.sh`, `RELEASE_35ed364_COMPLETE`; web, diary, ocr, llama and model-loader
healthy with restarts=0; engine container ID unchanged). Public site serves `index-TGNR7wbl.js`
and `/lens.js`. Ships the noevia M3 palette, `tokens.css`/`materials.css`, `lens.js` in place of
`glass.js`, `SegmentedControl`, and the four materials in Settings → Appearance (Soft default).
Rollback: release `385f04a` and `.env.bak.before-35ed364`.

## Release ab2720a — 2026-09-18 (UI overhaul release 2: shell, primitives, Connectors)

Appdata backup `ab_20260918_092222` first. Web-only overlay `35ed364 → ab2720a`
(`RELEASE_ab2720a_COMPLETE`; all five services healthy, restarts=0, engine untouched). Public site
serves `index-CGLJNnWj.js`; `/api/connectors` answers. Ships in-app Settings, the pane shell,
shared primitives, and Google Drive chat tools with per-tool Allow/Ask/Block (the new
`tool_policies` table is created on start; per-user tokens go to `google-drive-users/`).
**Correction:** release folder `35ed364` had been extracted from a `git archive` run inside
`apps/web` (web app only); it was replaced with the full tree before this release. Always run
`git archive` from the repo root (now noted in `overlay-release.sh`). Rollback: `35ed364` and
`.env.bak.before-ab2720a`.

## Release d11cfac — 2026-09-18 (UI overhaul release 3 plus phone-review fixes)

Latest application rollout: **`d11cfac`**, replacing `ab2720a`. Carries release 3 (`4e32b22`:
menus, dialogs/bottom sheets, confirm dialogs, cards, banners, empty states, chat bubbles, the
tool-call list and write-approval card) and the fixes from the phone review of `ab2720a`.
No dependency changes. Local gate: 861/861 tests, typecheck and design lint clean, fresh build
into an emptied `/tmp/noevia-qa-dist`. Appdata backup `ab_20260918_112354` first (log clean;
web, Diary and extra-files archives gzip-verified; web and Diary restarted healthy). Web-only
overlay `ab2720a → d11cfac` over Tailscale (`RELEASE_d11cfac_COMPLETE`; web, diary, ocr, llama
and model-loader healthy with restarts=0; engine untouched; model-loader still `ca5d2f6`).
`noevia.daserver.work` serves `index-Bzvm1y5j.js`, matching the local build.
**Browser verification was partial:** the authenticated desktop session loaded the new shell
(Customize/Explore gone from the sidebar, the new model popup and tool list). No model was
loaded, so the first synthetic message failed with "no model selected". The live write-approval
card, phone width, light/dark and accent repaint were **not** checked; they are still owed. A
synthetic chat "QA deploy check: use the drive_create_file…" was left in Recent chats (it ran
no tools) and should be deleted. `cowork.daserver.work` did not resolve through Tailscale DNS
at the time. Rollback: `ab2720a` and `.env.bak.before-d11cfac`.

Phone-width follow-up (same day, Chrome window at 500 px, the narrowest it allows; not touch
emulation). Works: Settings is a full-width list opening full-screen pages with a back arrow;
reload returns to the open view; the phone composer is pinned to the bottom and the inference
strip is one line; the confirm dialog and model picker are bottom sheets with a grabber and name
the right item; the accent palettes repaint live and survive a reload (stored per theme); light
and dark both apply. The synthetic QA chat was deleted. **Defects found:** (1) the phone drawer
opened from the Diary view renders the collapsed icon rail (no labels, no lists) inside the full
drawer; (2) from a chat, the drawer scrolls as one block and the Diary/Plugins pane is clipped
under the MCP line before scrolling; the three lists do not scroll independently at this size;
(3) a row's "⋯" menu opens clipped at the drawer edge (icons only), away from its row, and resets
the drawer scroll; (4) Escape does not close the model bottom sheet; (5) the Light and Dark theme
thumbnails both draw in the current theme; the selected-theme ring stays purple whatever the
accent; (6) Settings → Profile row labels start at inconsistent indents on a phone. **Still owed:**
the live write-approval card (a permission check blocked the synthetic write test) and a
real touch device for the 16px-field check.

## Releases 3d20de0, a2a1c8e, e777259 — 2026-09-18 (phone review fixes of d11cfac)

Three web-only overlays in a row, each after a clean backup (`ab_20260918_122108`,
`ab_20260918_123033`, `ab_20260918_123652`; logs clean, all archives gzip-verified) and
with no dependency changes. Every one ended `RELEASE_<sha>_COMPLETE` with web, diary, ocr,
llama and model-loader healthy, restarts=0, engine untouched.

Latest application rollout: **`e777259`**, replacing `a2a1c8e` (which replaced `3d20de0`,
which replaced `d11cfac`). Public site serves `index-s66ywTmP.js` / `index-DTbLz5or.css`.
- **3d20de0:** the phone drawer opened from Diary is the full sidebar (the legacy rail rules
  now apply only to the closed sidebar); the sticky footer is measured, not assumed 60px, and
  owns the drawer's bottom inset, so Diary/Plugins are never under it and no rows show below
  it; row menus render into `<body>` and are placed before paint (no clipping, no offset, no
  scroll reset); theme previews show their own theme and the selected ring follows the
  accent; stacked Settings rows share one left edge.
- **a2a1c8e:** before its first reading the inference strip shows the model with a neutral
  dot instead of a red "Inference offline" (the poll waits while the page is hidden).
- **e777259:** on a desktop each sidebar list keeps its heading in view while it scrolls.
`qa/phone-drawer-settings.cjs` covers all of it. Gate each time: 861/861 tests, typecheck,
design lint, fresh build; `sidebar-reachability`, `mobile-viewport`, `mobile-approvals`,
`tool-calls`, `appearance-system`, `general-settings`, `touch-targets` and
`short-phone-composer` pass. `mobile-surfaces` and `live-stats` fail identically on the
unchanged `d11cfac` build (pre-existing: they look for a pre-release-3 flow and the old
"Inference details" region). Verified live in Chrome at 500 px and 1360 px: the drawer from
chat and from Diary, a row menu, Profile alignment, Appearance previews/ring/accents, the
strip, independent desktop lists with sticky headings. The escape-key "bug" noted earlier
was an artefact of the browser extension's key events; Escape closes the sheet. Appearance
was restored to Dark + Warm. **Still owed:** the live write-approval card (a permission
check blocks a synthetic Nextcloud write) and a real touch device for 16px fields.
Rollback: `a2a1c8e` with `.env.bak.before-e777259` (further back: `3d20de0`, `d11cfac`).

## Releases 265c650 and 6930549 — 2026-09-18 (Material 3, more phone fixes)

Latest application rollout: **`6930549`**, replacing `265c650`, which replaced `e777259`.
Backups `ab_20260918_130856` and `ab_20260918_131641` first (clean, gzip-verified); both
overlays ended `RELEASE_<sha>_COMPLETE`, five services healthy, restarts=0, engine untouched,
no dependency changes. Public site serves `index-pxDeVw0P.css`.
- **Material 3** ("doesn't actually look like material3"): `styles/material3.css`, scoped to
  `[data-material='material']`, gives each component its M3 counterpart (navigation drawer
  with pill destinations, extended FAB, search-bar composer, filled icon send, assist chips,
  M3 menus, elevated cards, outlined fields, primary tabs, dialogs/bottom sheets, segmented
  buttons with the check, elevation and state layers, Roboto). It fixes the sticky list
  headings and drawer footer showing as bands in that material. Roboto rides the existing
  Google Fonts request (CSP already allows it) and downloads only when used.
- **Phone:** fields on touch are 16px everywhere (iOS zoom was back on Security, Data,
  Appearance, Diary & storage); the Material track scrolls at 320px with the choice in view
  and a thumb that follows label changes; theme previews and accents each fit one row;
  Projects counts active projects and its filter spans the row.
- **6930549:** on a short desktop no sidebar list collapses to its heading (seen live in M3).
`qa/live-stats.cjs` updated to the release-3 strip and passes. Verified live: M3 with
Roboto loaded, list rows visible; material restored to Liquid glass, Dark, Warm.
Rollback: `265c650` with `.env.bak.before-6930549` (then `e777259`).

## Releases 4ea3282 and 95eacd6 — 2026-09-18 (sidebar as one plane, like ChatGPT)

Latest application rollout: **`95eacd6`**, replacing `4ea3282`, which replaced `6930549`.
Backups `ab_20260918_133651` and `ab_20260918_134540` first (clean, gzip-verified); both
overlays `RELEASE_<sha>_COMPLETE`, five services healthy, restarts=0, engine untouched.
User review ("the whole sidebar needs to be a single scrollable plane", with ChatGPT as the
reference): the independently scrolling lists are gone at every width; the rail scrolls as
one surface; Diary and Plugins moved up with Projects into the top destinations; Projects,
Pinned and Recent chats are flat labelled lists (no tree line); only the account row stays
pinned; Recent chats no longer stops at twelve. Verified live: no nested scrollers, all 10
recent chats present, Diary in the top group. Rollback `4ea3282` with
`.env.bak.before-95eacd6` (then `6930549`).

## Release 4152d15 — 2026-09-18 (Settings and sidebar organised like ChatGPT)

Latest application rollout: **`4152d15`**, replacing `95eacd6`. Backup `ab_20260918_141325`
first (clean, gzip-verified); `RELEASE_4152d15_COMPLETE`, five services healthy, restarts=0.
Sidebar sections now follow ChatGPT's order: Pinned, Projects, Recent chats (no destinations
added). Settings was reorganised after reading all 17 sections of ChatGPT's settings: one
flat list without group headings, General first and Account last, using only pages noevia
has — General (was Appearance), Personalization, Capabilities, Connectors, AI providers,
Usage (was Usage & activity), Data controls (was Data), Diary & storage, Security and login
(was Security), Account (was Profile); admin pages stay under Server. Section ids are
unchanged. QA suites follow the new labels; `data-export` fails identically on the previous
build (pre-existing). Rollback `95eacd6` with `.env.bak.before-4152d15`.

## Release 94909d3 — 2026-09-18 (collapsed sidebar like ChatGPT's)

Latest application rollout: **`94909d3`**, replacing `4152d15`. Backup `ab_20260918_142829`
first (clean, gzip-verified); `RELEASE_94909d3_COMPLETE`, five services healthy, restarts=0.
ChatGPT's collapse was studied live (DOM and computed CSS: a separate 52px rail of 36px icon
buttons over an inert, hidden 260px panel; state remembered; empty rail expands it). noevia's
collapsed rail had leaked headings, rows and the MCP line; it is now one column of equal
icons with the avatar at the bottom (M3: navigation rail with the FAB), remembered per device
(`noevia:sidebar-collapsed`), and its empty space expands it. No buttons were added. Verified
live: no leaks, icons only, state stored; left expanded. Rollback `4152d15` with
`.env.bak.before-94909d3`.

## Release 91a89ba — 2026-09-18 (account menu and Search like Claude; rail and Code fixes)

Latest application rollout: **`91a89ba`**, replacing `94909d3`. Backup `ab_20260918_145036`
first (clean, gzip-verified); `RELEASE_91a89ba_COMPLETE`, five services healthy, restarts=0.
Claude's account menu and bottom bar, and Claude's and ChatGPT's Settings, were inspected in
the browser (DOM and computed styles). Light/dark moved from the sidebar head into the
account menu (Chat and Code); Search sits beside the account. The account menu renders into
`<body>` (it was clipped to icons in the collapsed rail) and opens beside the avatar there.
The rail's Chat/Code switch is two stacked icon buttons. Entering Code no longer blanks the
page while the lazy chunk loads (50 blank frames → 0 with an 800 ms chunk). Verified live:
head holds only Collapse; footer is account + Search. Nextcloud had deleted tracked files
under `.claude/skills/impeccable/` again; restored from git, not committed as deletions.
Rollback `94909d3` with `.env.bak.before-91a89ba`.

## Release 350050e — 2026-09-18 (composer like Claude's, SVG icons, Code keeps sidebar state)

Latest application rollout: **`350050e`**, replacing `91a89ba`. Backup `ab_20260918_155238`
first (clean, gzip-verified); `RELEASE_350050e_COMPLETE`, five services healthy, restarts=0.
Claude's composer (+ menu, model/effort control) was inspected in the DOM. The + is a
centred SVG in a liquid-glass circle; its menu is Add files or photos, then tools ticked when
on — the duplicate Model and routing entry is gone. Thinking is a glass pill opening an aero
menu (Auto, Low, Standard, High with descriptions and a check); Settings keeps the select.
The Code sidebar collapses and shares `noevia:sidebar-collapsed`, so a closed sidebar stays
closed across Chat and Code. All text-glyph icons became Lucide SVGs (paperclip, brain,
wrench added from Iconify's Lucide set); icon-only buttons centre a block SVG. A DOM audit
of 21 views at desktop and phone width finds no glyph icons and no off-centre icon buttons.
`qa/reasoning.cjs` and `qa/touch-targets.cjs` follow the new control. Verified live: + SVG
offset 0/0, Thinking is a button, no glyph buttons. Rollback `91a89ba` with
`.env.bak.before-350050e`.

## Release 5a0e026 — 2026-09-18 (icon centring scoped; row options beside the title)

Latest application rollout: **`5a0e026`**, replacing `350050e`. Backup `ab_20260918_163539`
first (clean, gzip-verified); `RELEASE_5a0e026_COMPLETE`, five services healthy, restarts=0.
The 350050e rule centring "an SVG that is the only child element" also caught icon + text
buttons (CSS cannot see text nodes); only labelled icon-only buttons centre now, icon + text
keep the icon at the start, vertically centred. Sidebar row options were drawn over the
title on a transparent background; as in ChatGPT (inspected) they are in the row's flow,
shown on hover/focus, and the title fades out before them; one hover highlight per row.
Verified live: options static and hidden until hover, no icon+text button centred.
Rollback `350050e` with `.env.bak.before-5a0e026`.

## Release 5cd033b — 2026-09-18 (Diary in the bottom bar; sliding Chat/Code; phone Code drawer; project colours)

Latest application rollout: **`5cd033b`**, replacing `5a0e026`. Backup `ab_20260918_170210`
first (clean, gzip-verified); `RELEASE_5cd033b_COMPLETE`, five services healthy, restarts=0.
Diary moved to the bottom bar beside Search (above the avatar on the collapsed rail). The
Chat/Code switch (`ModeSwitch.tsx`) has the liquid-glass thumb and slides both ways across the
sidebar swap. On phones the Code sidebar's toggle opens/closes a drawer (it only flipped the
desktop collapse before), and the chat drawer toggle clears the notch. Project colours were
forced grey/black with `!important` in the sidebar and on cards; the chosen colour now shows
everywhere, and the chat breadcrumb/greeting carry the project icon. Also fixes the project
row layout 5a0e026 had spread apart. Verified live: footer = account, Diary, Search; thumb
present; sidebar project icons red and blue. Rollback `5a0e026` with `.env.bak.before-5cd033b`.

## Release 4c151be — 2026-09-18 (sidebar header and phone drawer like Claude's)

Latest application rollout: **`4c151be`**, replacing `5cd033b`. Backup `ab_20260918_172155`
first (clean, gzip-verified); `RELEASE_4c151be_COMPLETE`, five services healthy, restarts=0.
Claude's sidebar was measured at desktop and phone width. The Chat/Code switch is a small
icon-only track (70×28, 34×26 segments) at the end of the header row after the logo, keeping
the liquid-glass thumb; it stacks under the expand button on the collapsed rail. The phone
drawer is full width with the search field under its header, and switching Chat/Code closes
it in both directions. `sidebar-reachability` closes the full-width drawer from its header
(no backdrop to tap) and `mobile-viewport` uses the drawer's search field on phones.
Verified live: switch 70×28 in the header. Rollback `5cd033b` with `.env.bak.before-4c151be`.

## Release 7326ac0 — 2026-09-18 (visual pass: legibility sweep and fixes)

Latest application rollout: **`7326ac0`**, replacing `4c151be`. Backup `ab_20260918_180551`
first (clean, gzip-verified); `RELEASE_7326ac0_COMPLETE`, five services healthy, restarts=0.
A legibility sweep of every main view at 375/390/768/1280 px × four materials × light/dark,
with real iPhone/iPad user agents (they get `data-layout="mobile"`), measured text size and
pixel-sampled contrast against HIG thresholds: no remaining failures. Fixed: the composer row
spilled its send button at 375 px (fixed 32 px columns vs 44 px touch buttons); phone Settings
on real iPhones was pinned to a 155 px column of 11 px labels by leftover two-column rules;
project and chat rows started their titles 3–11 px apart (one shared geometry now, 44 px touch
target kept); a heading's options sat 6 px high. Verified live at 375 px: Settings list 375 px
wide, 15 px labels; composer fits. Rollback `4c151be` with `.env.bak.before-7326ac0`.

## Release d995cd9 — 2026-09-18 (composer focus, iOS keyboard, phone Settings list)

Latest application rollout: **`d995cd9`**, replacing `7326ac0`. Backup `ab_20260918_183012`
first (clean, gzip-verified); `RELEASE_d995cd9_COMPLETE`, five services healthy, restarts=0.
The composer's text area no longer draws the global `!important` focus ring as a square inside
the rounded composer (the composer shows a soft rounded ring). On iOS the app now follows
`visualViewport.offsetTop` as well as its height (`public/viewport.js`), so an open keyboard
no longer leaves a blank band. `shell.css` carried a second copy of the old 155 px phone
Settings list rules; removed. Note: `viewport.js` is served with `max-age=14400`, so a phone
may run the previous copy for up to four hours. Rollback `7326ac0` with
`.env.bak.before-d995cd9`.

## Release 41cb2aa — 2026-09-19 (tool routing scope and more_tools; routing still off)

Latest application rollout: **`41cb2aa`**, replacing `363171c`. Backup `ab_20260919_032607`
first (gzip-verified); `RELEASE_41cb2aa_COMPLETE`, five services healthy, restarts=0.
Before turning on Settings → Features → Tool routing: the llama service runs `--models-max 1`,
so `nomic-embed-text-v1` would unload the chat model per message. Raise it to 2 (the 2026-09-17
router measurement used 2) or point `EMBEDDING_BASE_URL` at a separate embedding server first.
Rollback: repoint `current` to `releases/363171c`, restore `.env.bak.before-41cb2aa`, run
preflight `up.sh … web diary ocr`.

## Release 363171c — 2026-09-19 (re-fit after zoom)

Latest application rollout: **`363171c`**, replacing `c71a30d`. Backup `ab_20260919_025713`
first (gzip-verified); `RELEASE_363171c_COMPLETE`, services healthy. `viewport.js?v=3`.
Rollback: repoint `current` to `releases/c71a30d`, restore `.env.bak.before-363171c`, run
preflight `up.sh … web diary ocr`.

## Release c71a30d — 2026-09-19 (tall screens)

Latest application rollout: **`c71a30d`**, replacing `70631b0`. Backup `ab_20260919_023204`
first (gzip-verified); `RELEASE_c71a30d_COMPLETE`, five services healthy, restarts=0.
Rollback: repoint `current` to `releases/70631b0`, restore `.env.bak.before-c71a30d`, run
preflight `up.sh … web diary ocr`.

## Release 70631b0 — 2026-09-19 (shrink-to-fit)

Latest application rollout: **`70631b0`**, replacing `f87b157`. Backup `ab_20260919_021208`
first (gzip-verified); `RELEASE_70631b0_COMPLETE`, five services healthy, restarts=0.
Rollback: repoint `current` to `releases/f87b157`, restore `.env.bak.before-70631b0`, run
preflight `up.sh … web diary ocr`.

## Release f87b157 — 2026-09-19 (shared Chat/Code sidebar; Plugins page)

Latest application rollout: **`f87b157`**, replacing `027bd00`. Backup `ab_20260919_015611`
first (gzip-verified); `RELEASE_f87b157_COMPLETE`, five services healthy, restarts=0; web image
8 layers. New authenticated route `GET /api/plugins/directory` fetches only
registry.modelcontextprotocol.io and api.github.com (anthropics/skills), read-only, cached 1h.
Rollback: repoint `current` to `releases/027bd00`, restore `.env.bak.before-f87b157`, run
preflight `up.sh … web diary ocr`.

## Release 027bd00 — 2026-09-18 (iOS keyboard fix; web image flattened; layer check)

Latest application rollout: **`027bd00`**, replacing `d995cd9`. Backup `ab_20260918_224023`
first (clean, gzip-verified); `RELEASE_027bd00_COMPLETE`, five services healthy, restarts=0.
- **iOS keyboard:** on phones and tablets the app shell is `position: fixed` to the visible
  viewport and the document cannot scroll, so iOS has nothing to push up; `viewport.js` resets
  any document scroll on focus/blur and keeps following `visualViewport` height and offset.
  `viewport.js` and `fonts.js` are version-stamped (`?v=2`) in `index.html` so phones do not wait
  out the 4-hour cache.
- **Layer limit:** release `96371d5` failed with "max depth exceeded" — `cowork-web:d995cd9` had
  127 layers, Docker's maximum, from a day of overlays each building on the last. Nothing live
  changed. `overlay-release.sh` now flattens OLD when it has more than 100 layers: it builds
  `cowork-web:<OLD>-flat` (FROM scratch + COPY of OLD's filesystem, settings regenerated with
  `jq`), checks env/workdir/ports/user/entrypoint/cmd/healthcheck field by field against OLD,
  and builds the release on it. OLD's image and tag are untouched (rollback unaffected:
  `d995cd9` is still 127 layers). Result: `cowork-web:027bd00` has 5 layers.
- A first attempt (`d06a1bd`) stopped after the flatten because the new block reused `$base`
  (the appdata directory); it failed before the symlink, `.env` or containers changed. Fixed in
  `027bd00`; the leftover release directory, env backup and image tags were removed.
- Housekeeping for later: 52 `cowork-web:*` image tags are kept on the host; old ones can be
  pruned once rollback targets are agreed.
Rollback `d995cd9` with `.env.bak.before-027bd00`.

