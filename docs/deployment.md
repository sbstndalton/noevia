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
