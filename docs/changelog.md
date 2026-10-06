## Format

From 2026-09-24 each release entry starts with a `### Services` list with one line per service:
Web, Diary, Model manager, Code sandbox, OCR, Docling, Deploy/infra. Each line names the PRs
that touched that service and the image tag deployed for it (for example `cowork-web:958022b`),
"merged, not yet deployed" when the code is on main but the running image predates it, or
"no change". Sidecar image tags are pinned separately from `COWORK_VERSION`, so a web-only
release leaves the other services on their previous tags. The prose, deploy evidence and rollback
notes follow as before. Entries before release 7b6942c keep their original free-form layout.

## Release eee0dc93 — 2026-10-06 (web only: ChatGPT sign-in failed retry marks only the failed sign-in)

### Services

- **Web:** [#935](https://github.com/sbstndalton/noevia/pull/935) (closes [#934](https://github.com/sbstndalton/noevia/issues/934): a failed 401 retry marks only the ChatGPT sign-in that failed as needing reconnect, so a freshly signed-in account is no longer flagged). Only `apps/web/server/chatgpt-oauth.cjs` and its test changed; everything else between `e9efa32e` and `eee0dc93` is docs. Now `cowork-web:eee0dc93` (`sha256:63105d05...`, 82 layers, previous `cowork-web:e9efa32e`), `readlink current` is `releases/eee0dc93`, `COWORK_VERSION=eee0dc93`.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change (`cowork-diary:f6885a55`, `cowork-model-loader:227903da`, `cowork-code-sandbox:pi-0.87.0-f6885a55`, `cowork-ocr:227903da`, `cowork-docling:f6885a55`). None was restarted.
- **Deploy/infra:** no change. `overlay-release.sh` was not run (web-only manual recipe). The release-assembly tooling merged in [#936](https://github.com/sbstndalton/noevia/pull/936) is after this release and not part of it.

PRs: #935. Issues: #934.

**Database migration.** None. No schema change in this release, so no database backup was taken and the previous image runs on the same database.

No feature flag was changed. No model run, tune, benchmark or download, no Code task, no private Diary access. The Diary overlay (still pending) was not touched.

Exact source `eee0dc933789cda0b3b973060d9c0b066f80a631` (main CI green on that commit). Built on the Mac from a clean detached worktree: `STAMP_VERSION=eee0dc93 npm run build` in `apps/web`, then `COPYFILE_DISABLE=1 tar -h --no-xattrs` of `dist server contracts` (without `server/node_modules` and `server/ui-data`), and a `git archive` of the repo root into `releases/eee0dc93`. Dependencies gate against `e9efa32e`: no change to `apps/web/package.json`, `apps/web/package-lock.json`, `apps/web/server/package.json` or `apps/web/server/package-lock.json`, so `node_modules` came from the old image.

**Order and results.**

1. **Web.** Layered `dist/`, `server/` and `contracts/` onto `cowork-web:e9efa32e` with the standard overlay Dockerfile (78 to 82 layers, under the 100-layer flatten limit). Before cutover the image was checked to contain `/app/contracts/project-icons.json` and `/app/contracts/project-limits.json`, `dist/version.json` `eee0dc93` and a `dist/index.html` sha256 equal to the Mac build. Synthetic candidate in a throwaway `--network none` container with a tmpfs data dir: server booted on a fresh database, healthy, `/api/ready` 200, `/version.json` `eee0dc93`; the container was removed. `config/.env.bak.before-eee0dc93` taken, `current` and `COWORK_VERSION` repointed; started alone with `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (preflight passed, `Healthy`). Cutover 2026-10-06 12:31:09Z to 12:31:26Z; the new `cowork-web-1` `StartedAt` is 12:31:20Z.

**Verify.** Web: healthy, `RestartCount` 0; `127.0.0.1:8021/version.json` and `https://noevia.daserver.work/version.json` both `eee0dc93`; `/api/ready` 200 locally and publicly; `/app/dist/index.html` sha256 `6b8342b2...` (Mac build before the worktree was removed: identical; was `8ccb5bd7...`), 67 files in `dist/assets`; the 60-line log tail shows the known `TRUST_PROXY` warning, MCP discovery (noevia 10, nextcloud 181, tavily 5 tools), `egress.listening` and `codenet.guarding` on `172.28.0.3` and no error or failure line. Container snapshot (id, `StartedAt`, `RestartCount`, state of all 40 containers on the host, `docker ps -a`) before and after: only `cowork-web-1` differs (id and `StartedAt`); every sidecar, the engine, Laya, embed, Kiwix and the Nextcloud and media containers kept id, `StartedAt` and restart count. `sidecar-restart-alert.sh --ack` run; a following `--dry-run` was clean.

Rollback (web only). On DaServer with `B=/mnt/docker/appdata/cowork`: `ln -sfn $B/releases/e9efa32e $B/current && sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=e9efa32e/' $B/config/.env && bash $B/tools/preflight/up.sh --env-file $B/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web` (or restore `$B/config/.env.bak.before-eee0dc93` instead of the `sed`). The `cowork-web:e9efa32e` image is retained and there is no schema difference. Run `sidecar-restart-alert.sh --ack` afterwards. No other service needs rolling back.

## Release e9efa32e — 2026-10-06 (web only: capped response reads, sign-in limits and credential epoch, SSRF and egress hardening)

### Services

- **Web:** [#924](https://github.com/sbstndalton/noevia/pull/924) (closes [#920](https://github.com/sbstndalton/noevia/issues/920): 32 more response reads are capped, plus a guard test and allowlist so a new uncapped read fails CI), [#929](https://github.com/sbstndalton/noevia/pull/929) (closes [#927](https://github.com/sbstndalton/noevia/issues/927), [#928](https://github.com/sbstndalton/noevia/issues/928) and [#933](https://github.com/sbstndalton/noevia/issues/933): sign-in limits count failures only, account recovery revokes every credential, and `users.credential_epoch` ties sessions and app passwords to the credential generation) and [#931](https://github.com/sbstndalton/noevia/pull/931) (closes [#930](https://github.com/sbstndalton/noevia/issues/930) and [#932](https://github.com/sbstndalton/noevia/issues/932): SSRF range fixes, egress proxy header stripping, connection caps 256/64 and a 10-minute tunnel idle timeout). Now `cowork-web:e9efa32e` (`sha256:0648ac13...`, 78 layers, previous `cowork-web:cf662822`), `readlink current` is `releases/e9efa32e`, `COWORK_VERSION=e9efa32e`.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change (`cowork-diary:f6885a55`, `cowork-model-loader:227903da`, `cowork-code-sandbox:pi-0.87.0-f6885a55`, `cowork-ocr:227903da`, `cowork-docling:f6885a55`). None was restarted.
- **Deploy/infra:** no change. `overlay-release.sh` was not run (web-only manual recipe).

PRs: #924 #929 #931. Issues: #920 #927 #928 #930 #932 #933.

**Database migration.** First start of the new image runs `ALTER TABLE users ADD COLUMN credential_epoch INTEGER NOT NULL DEFAULT 0` on `state/web/cowork.db` (host path `/mnt/docker/appdata/cowork/state/web/`). The old code ignores the column, so the previous image runs on the migrated database. Before cutover a consistent copy was taken with the host `sqlite3 <db> ".backup '<db>.bak.before-e9efa32e'"`: `/mnt/docker/appdata/cowork/state/web/cowork.db.bak.before-e9efa32e` (282624 bytes, `PRAGMA integrity_check` ok, 2 user rows). It is a belt-and-braces copy; rollback does not need it. Verified afterwards with a read-only `PRAGMA table_info(users)`: the column list now ends in `credential_epoch`.

No feature flag was changed. No model run, tune, benchmark or download, no Code task, no private Diary access. The Diary overlay (still pending) was not touched.

Exact source `e9efa32e514aa23e43187fb9a7cfde0455de9cb0` (main CI green on that commit). Built on the Mac from a clean detached worktree: `STAMP_VERSION=e9efa32e npm run build` in `apps/web`, then `COPYFILE_DISABLE=1 tar -h --no-xattrs` of `dist server contracts` (without `server/node_modules` and `server/ui-data`), and a `git archive` of the repo root into `releases/e9efa32e`. Dependencies gate against `cf662822`: no change to `apps/web/package-lock.json`, `apps/web/server/package.json` or `apps/web/server/package-lock.json`, and the `dependencies`, `devDependencies`, `overrides` and `engines` fields of `apps/web/package.json` are identical, so `node_modules` came from the old image.

**Order and results.**

1. **Web.** Layered `dist/`, `server/` and `contracts/` onto `cowork-web:cf662822` with the standard overlay Dockerfile (74 to 78 layers, under the 100-layer flatten limit). Before cutover the image was checked to contain `/app/contracts/project-icons.json` and `/app/contracts/project-limits.json` and `dist/version.json` `e9efa32e`. Synthetic candidate in a throwaway `--network none` container with a tmpfs data dir: server booted on a fresh database (the migration ran there too, `credential_epoch` present), `/api/ready` 200, `/version.json` `e9efa32e`; the container was removed. Database backup taken, `config/.env.bak.before-e9efa32e` taken, `current` and `COWORK_VERSION` repointed; started alone with `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (preflight passed, `Healthy`). Cutover 2026-10-06 09:03:58Z to 09:04:15Z; the new `cowork-web-1` `StartedAt` is 09:04:09Z.

**Verify.** Web: healthy, `RestartCount` 0; `127.0.0.1:8021/version.json` and `https://noevia.daserver.work/version.json` both `e9efa32e`; `/api/ready` 200 locally and publicly; `/app/dist/index.html` sha256 `8ccb5bd7...` (was `a0828ba7...`), 67 files in `dist/assets`; the 60-line log tail shows MCP discovery (noevia 10, nextcloud 181, tavily 5 tools), `egress.listening` and `codenet.guarding` on `172.28.0.3` and no error or failure line. Container snapshot (id, `StartedAt`, `RestartCount` of all 40 containers on the host) before and after: only `cowork-web-1` differs (id and `StartedAt`); every sidecar, the engine, Laya, embed, Kiwix and the Nextcloud and media containers kept id, `StartedAt` and restart count. `sidecar-restart-alert.sh --ack` run; a following `--dry-run` was clean.

**New startup warning (action for the owner, not changed here).** The log now carries `WARNING: the public address uses https but TRUST_PROXY is off. If noevia runs behind a reverse proxy or tunnel, every visitor shares the proxy's address, so sign-in limits and audit-log addresses apply to everyone at once. Set TRUST_PROXY=true when the proxy sets X-Forwarded-For.` The live deployment is behind the tunnel with `TRUST_PROXY` off, so the new per-address sign-in limits are shared by all visitors until the owner decides to set it. No setting was changed in this release.

Rollback (web only). On DaServer with `B=/mnt/docker/appdata/cowork`: `ln -sfn $B/releases/cf662822 $B/current && sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=cf662822/' $B/config/.env && bash $B/tools/preflight/up.sh --env-file $B/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web` (or restore `$B/config/.env.bak.before-e9efa32e` instead of the `sed`). The `cowork-web:cf662822` image is retained and runs on the migrated database (the extra column is ignored); `cowork.db.bak.before-e9efa32e` is only a safety copy. Run `sidecar-restart-alert.sh --ack` afterwards. No other service needs rolling back.

## Release cf662822 — 2026-10-06 (web only: capped storage/provider reads and the project-bound chat grant)

### Services

- **Web:** [#915](https://github.com/sbstndalton/noevia/pull/915) (closes [#902](https://github.com/sbstndalton/noevia/issues/902) and [#903](https://github.com/sbstndalton/noevia/issues/903), plus [#918](https://github.com/sbstndalton/noevia/issues/918): storage and provider reply bodies are read under a byte cap, upstream errors map to fixed error text instead of the raw body, and retries `discardBody` the reply they abandon), [#921](https://github.com/sbstndalton/noevia/pull/921) (closes [#917](https://github.com/sbstndalton/noevia/issues/917): the "Allow for this chat" grant is bound to the project it was given in and fails closed in any other scope), and two web changes that were already on main and had not shipped: [#911](https://github.com/sbstndalton/noevia/pull/911) (closes [#905](https://github.com/sbstndalton/noevia/issues/905): cached account preferences are scoped to the signed-in account) and the web-side 2-line `pdf-reduce.cjs` change in [#916](https://github.com/sbstndalton/noevia/pull/916) (its OCR service half shipped in release 227903da). Now `cowork-web:cf662822` (`sha256:97d260af...`, 74 layers, previous `cowork-web:8cbced50`), `readlink current` is `releases/cf662822`, `COWORK_VERSION=cf662822`.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change (`cowork-diary:f6885a55`, `cowork-model-loader:227903da`, `cowork-code-sandbox:pi-0.87.0-f6885a55`, `cowork-ocr:227903da`, `cowork-docling:f6885a55`). None was restarted.
- **Deploy/infra:** no change. `overlay-release.sh` was not run (web-only manual recipe). [#919](https://github.com/sbstndalton/noevia/pull/919) and [#923](https://github.com/sbstndalton/noevia/pull/923) are docs/Docling-build only and ship nothing to web.

PRs: #911 #915 #916 (web half) #921. Issues: #902 #903 #905 #917 #918.

No feature flag was changed. No model run, tune, benchmark or download, no Code task, no private Diary access. The Diary overlay (still pending) was not touched.

Exact source `cf662822fee73a5ca838a2ca82338af5d89e72d9` (main CI green on that commit). Built on the Mac from a clean detached worktree: `STAMP_VERSION=cf662822 npm run build` in `apps/web`, then `COPYFILE_DISABLE=1 tar -h --no-xattrs` of `dist server contracts` (without `server/node_modules` and `server/ui-data`), and a `git archive` of the repo root into `releases/cf662822`. Dependencies gate: no change to `apps/web/package-lock.json`, `apps/web/server/package.json` or `apps/web/server/package-lock.json` since `8cbced50`, and the `dependencies`, `devDependencies`, `overrides` and `engines` fields of `apps/web/package.json` hash identically, so `node_modules` came from the old image.

**Order and results.**

1. **Web.** Layered `dist/`, `server/` and `contracts/` onto `cowork-web:8cbced50` with the standard overlay Dockerfile (70 to 74 layers, under the 100-layer flatten limit). Before cutover the image was checked to contain `/app/contracts/project-icons.json` and `/app/contracts/project-limits.json` and `dist/version.json` `cf662822`. Synthetic candidate in a throwaway `--network none` container with a tmpfs data dir: server booted, `/api/ready` 200, `/version.json` `cf662822`; the container was removed. `config/.env.bak.before-cf662822` taken; `current` and `COWORK_VERSION` repointed; started alone with `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (preflight passed, `Healthy`). Cutover 2026-10-06 08:01:17Z to 08:01:34Z; the new `cowork-web-1` `StartedAt` is 08:01:28Z.

**Verify.** Web: healthy, `RestartCount` 0; `127.0.0.1:8021/version.json` and `https://noevia.daserver.work/version.json` both `cf662822`; `/api/ready` 200 locally and publicly; `/app/dist/index.html` sha256 `a0828ba7...` and `dist/assets/index-BpE6GXsI.js` sha256 `d2230063...` identical to the Mac build; in the container `contracts/project-icons.json` sha256 `bce8d2a2...` and `project-limits.json` `aa1ed3fc...` (unchanged from 8cbced50); the 60-line log tail shows MCP discovery (noevia 10, nextcloud 181, tavily 5 tools), `codenet.guarding` on `172.28.0.3` and no error, warning or failure line. Container snapshot (id, `StartedAt`, `RestartCount` of all 40 containers on the host, cowork and non-cowork) before and after: only `cowork-web-1` differs (id and `StartedAt`); every sidecar, the engine, Laya, embed, Kiwix and the Nextcloud and media containers kept id, `StartedAt` and restart count. `sidecar-restart-alert.sh --ack` run; a following `--dry-run` was clean.

Rollback (web only). On DaServer with `B=/mnt/docker/appdata/cowork`: `ln -sfn $B/releases/8cbced50 $B/current && sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=8cbced50/' $B/config/.env && bash $B/tools/preflight/up.sh --env-file $B/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web` (or restore `$B/config/.env.bak.before-cf662822` instead of the `sed`). The `cowork-web:8cbced50` image is retained. Run `sidecar-restart-alert.sh --ack` afterwards. No other service needs rolling back.

## Release 227903da — 2026-10-06 (sidecars only: model-manager and OCR)

### Services

- **Web:** no change (`cowork-web:8cbced50`). Not restarted.
- **Diary:** no change (`cowork-diary:f6885a55`). Not restarted; the Diary overlay is still pending.
- **Model manager:** [#907](https://github.com/sbstndalton/noevia/pull/907) (closes [#901](https://github.com/sbstndalton/noevia/issues/901): NaN/Infinity float GGUF metadata becomes `null` instead of a 500), [#908](https://github.com/sbstndalton/noevia/pull/908) (closes [#904](https://github.com/sbstndalton/noevia/issues/904): telemetry attributes requests to the stored instance after the spawn line leaves the log tail, gated on log overlap and model match, with `watermark`/`continuous_since`) and [#912](https://github.com/sbstndalton/noevia/pull/912) (closes [#909](https://github.com/sbstndalton/noevia/issues/909): the image also carries `/usr/local/bin/gguf-meta`, built from sbstndalton/noevia-rs at `751c2d71868e782de33558cf00f805cc74758ecb` and checked by sha256 in the Dockerfile; dark, `GGUF_PARSER` is not set so it stays `python`). Now `cowork-model-loader:227903da` (`sha256:c9709bc9...`, previous `cowork-model-loader:8e96d876`), `MODEL_MANAGER_VERSION=227903da`.
- **OCR:** [#916](https://github.com/sbstndalton/noevia/pull/916) (closes [#914](https://github.com/sbstndalton/noevia/issues/914): `pdf_reduce` runs under one 160 s deadline, below the web's 180 s abort, so it no longer holds the single OCR slot). Now `cowork-ocr:227903da` (`sha256:d986f55a...`, previous `cowork-ocr:5004b50`), `OCR_VERSION=227903da`.
- **Code sandbox (and code-verify), Docling:** no change (`cowork-code-sandbox:pi-0.87.0-f6885a55`, `cowork-docling:f6885a55`). [#919](https://github.com/sbstndalton/noevia/pull/919) only changes how the Docling image is rebuilt; it is merged, not deployed, and the running image is unchanged.
- **Deploy/infra:** no change. `readlink current` is still `releases/8cbced50`; `releases/227903da` holds the source the two images were built from.

PRs: #907 #908 #912 #916. Issues: #901 #904 #909 #914.

No feature flag was changed, and `GGUF_PARSER` was not set. No model was loaded, unloaded, downloaded, benchmarked or tuned, no Code task ran, and nothing touched the private Diary. The engine's loaded model stayed loaded.

Exact source `227903da965c54666cf5c4aca65604341736a266` (main CI green on that commit). A `git archive` from the Mac checkout went to `releases/227903da`. Both images were built on DaServer with plain `docker build` from that tree (`services/ocr`, `services/model-manager`) under `nice`, tagged `227903da-candidate`, tested, then retagged `227903da`; `current` was not repointed because only sidecars changed. The model-manager build runs a Rust builder stage that fetches the noevia-rs tarball from codeload.github.com, verifies its sha256 and builds `gguf-meta`; it succeeded on DaServer without any network workaround.

**Order and results.**

1. **Candidate checks (before any cutover).** Model-manager: a throwaway `--network none` container with a synthetic token and a synthetic 4-key GGUF file (including a NaN float). `gguf-meta --help` printed its usage line (exit 2, by design), `gguf-meta <file>` exited 0 with a JSON summary, the app imported (`app.main`), `settings.gguf_parser` and `parser_choice()` both returned `python`, and `summarize_path` returned the Python summary. OCR: a throwaway `--network none --read-only` container, `/health` 200 `{"service": "ocr"}`, `pdf_reduce` and `server` import, `REDUCE_DEADLINE_SECONDS` present. Both containers were removed.
2. **Model-manager.** `config/.env.bak.before-sidecars-227903da` taken (it also covers the OCR line), `MODEL_MANAGER_VERSION` set, started alone with `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 model-loader` (preflight passed, `Healthy`). Cutover 2026-10-06 07:50:39Z to 07:51:10Z; the new `cowork-model-loader-1` `StartedAt` is 07:50:39Z.
3. **OCR.** `OCR_VERSION` set, started alone with the same `up.sh` line for `ocr`. Cutover 07:51:14Z to 07:51:30Z; the new `cowork-ocr-1` `StartedAt` is 07:51:24Z.

**Verify.** Model-loader: healthy, `RestartCount` 0, `/api/v1/health` 200 `{"ok":true}`, web's `GET /api/v1/backends` calls return 200 in its log, `/usr/local/bin/gguf-meta` present (sha256 `aa262b77...`), `parser_choice()` is `python`. OCR: healthy, `RestartCount` 0, `/health` 200 and web reaches `http://ocr:8030/health` with 200; `/app/pdf_reduce.py` sha256 `2d07bffb...`. The 60-line log tails of both are clean. `sidecar-restart-alert.sh --ack` was run and `--dry-run` afterwards reported nothing. Diffing a full container snapshot (name, image, status, `StartedAt`, restart count, id) before and after: only `cowork-model-loader-1` and `cowork-ocr-1` changed. Web, Diary, Docling, Code sandbox, code-verify, llama, embed, Laya, Kiwix, DAV relay, the tunnel and every non-noevia container kept id and `StartedAt`.

Rollback (each service on its own). On DaServer with `B=/mnt/docker/appdata/cowork`, `E=$B/config/.env`: for model-manager, `sed -i 's/^MODEL_MANAGER_VERSION=.*/MODEL_MANAGER_VERSION=8e96d876/' $E && bash $B/tools/preflight/up.sh --env-file $E -- -d --no-build --no-deps --wait --wait-timeout 180 model-loader`; for OCR, `sed -i 's/^OCR_VERSION=.*/OCR_VERSION=5004b50/' $E && bash $B/tools/preflight/up.sh --env-file $E -- -d --no-build --no-deps --wait --wait-timeout 180 ocr`. Restoring `$E.bak.before-sidecars-227903da` reverts both tags at once. `cowork-model-loader:8e96d876` and `cowork-ocr:5004b50` are retained. Nothing else needs rolling back; `GGUF_PARSER` was never set.

## Release 8cbced50 — 2026-10-06 (web only: round-3 server fixes and the `contracts/` move)

### Services

- **Web:** [#898](https://github.com/sbstndalton/noevia/pull/898) (closes [#891](https://github.com/sbstndalton/noevia/issues/891) deep research search tools refuse instead of falling back to name routing, [#892](https://github.com/sbstndalton/noevia/issues/892) `google/connect` no longer leaks another admin's pending sign-in, [#893](https://github.com/sbstndalton/noevia/issues/893) chat export counts only wrapper bytes, [#894](https://github.com/sbstndalton/noevia/issues/894) a failed Diary-job write is retried by `finish()`, [#895](https://github.com/sbstndalton/noevia/issues/895) sweep `adopt()` retries with capped backoff) and [#899](https://github.com/sbstndalton/noevia/pull/899) (closes [#897](https://github.com/sbstndalton/noevia/issues/897): `project-icons.json` and `project-limits.json` moved from `apps/web/server/` to `apps/web/contracts/`, runtime expects `/app/contracts/*.json`; test split, `check:boundaries`). Now `cowork-web:8cbced50` (`sha256:aff619ce...`, 70 layers, previous `cowork-web:8e96d876`), `readlink current` is `releases/8cbced50`, `COWORK_VERSION=8cbced50`.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change (`cowork-diary:f6885a55`, `cowork-model-loader:8e96d876`, `cowork-code-sandbox:pi-0.87.0-f6885a55`, `cowork-ocr:5004b50`, `cowork-docling:f6885a55`). None was restarted.
- **Deploy/infra:** [#899](https://github.com/sbstndalton/noevia/pull/899) changes `overlay-release.sh` to pack and replace `contracts/`; the script was not run (web-only manual recipe).

PRs: #898 #899. Issues: #891 #892 #893 #894 #895 #897.

No feature flag was changed. No model run, tune, benchmark or download, no Code task, no private Diary access. The Diary overlay (still pending since 8e96d876) was not touched.

Exact source `8cbced50c7ba13d2c6f9dc8366100815d4e8cf9b` (main CI green on that commit). Built on the Mac from a clean detached worktree: `STAMP_VERSION=8cbced50 npm run build` in `apps/web`, then `COPYFILE_DISABLE=1 tar -h --no-xattrs` of `dist server contracts` (without `server/node_modules` and `server/ui-data`), and a `git archive` of the repo root into `releases/8cbced50`. `apps/web/package.json` changed since `8e96d876` only in its `scripts` block (the dependencies, devDependencies, overrides and engines fields hash identically); no lockfile and no `apps/web/server/package*.json` changed, so `node_modules` came from the old image.

**Order and results.**

1. **Web.** Layered `dist/`, `server/` and `contracts/` onto `cowork-web:8e96d876` with the standard overlay Dockerfile (66 to 70 layers, under the 100-layer flatten limit). Before cutover the image was checked to contain `/app/contracts/project-icons.json` and `/app/contracts/project-limits.json`, `dist/version.json` `8cbced50` and the 52 server dependencies. Synthetic candidate in a throwaway `--network none` container with a tmpfs data dir: server booted, `/api/ready` 200 (`8cbced50`), `/version.json` 200. `config/.env.bak.before-8cbced50` taken; `current` and `COWORK_VERSION` repointed; started alone with `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (preflight passed, `Healthy`). Cutover 2026-10-06 07:21:24Z to 07:21:41Z; the new `cowork-web-1` `StartedAt` is 07:21:35Z.

**Verify.** Web: healthy, `RestartCount` 0; `127.0.0.1:8021/version.json` and `https://noevia.daserver.work/version.json` both `8cbced50`; `/api/ready` 200 `{"ready":true,"version":"8cbced50"}` locally and publicly; `/app/dist/index.html` sha256 `54526d90...` identical to the candidate image; in the container `contracts/project-icons.json` sha256 `bce8d2a2...` and `project-limits.json` `aa1ed3fc...`; the log shows MCP discovery (noevia 10, nextcloud 181, tavily 5 tools), `codenet.guarding` on `172.28.0.3` and no error line. Sidecars: diary, ocr, docling, model-loader, llama, embed and laya kept container id, `StartedAt` and restart count against the pre-cutover snapshot; code-sandbox and code-verify (missing from that snapshot because of a template error in the snapshot command) show `StartedAt` 2026-10-05T23:12:36Z, before the cutover. Only `cowork-web-1` changed.

Rollback (web only). On DaServer with `B=/mnt/docker/appdata/cowork`: `ln -sfn $B/releases/8e96d876 $B/current && sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=8e96d876/' $B/config/.env && bash $B/tools/preflight/up.sh --env-file $B/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web` (or restore `$B/config/.env.bak.before-8cbced50` instead of the `sed`). The `cowork-web:8e96d876` image is retained and carries the two JSON files under `server/`, so it does not need `contracts/`. No other service needs rolling back.

## Release 8e96d876 — 2026-10-05 (repo sweep release 4, final: web and model-manager; Diary not deployed)

### Services

- **Web:** [#889](https://github.com/sbstndalton/noevia/pull/889) (closes [#845](https://github.com/sbstndalton/noevia/issues/845): S3 listing decodes XML entities and follows `IsTruncated`/`NextContinuationToken` with page and entry caps, permitted-tools cache clears on Drive sign-in and in the MCP OAuth callback `finally`; [#876](https://github.com/sbstndalton/noevia/issues/876): model chip reads the default provider id from `/api/providers`; [#887](https://github.com/sbstndalton/noevia/issues/887): approval card shows a "via <server>" line; [#843](https://github.com/sbstndalton/noevia/issues/843): stale `qa/mobile-approvals.cjs` repaired, a QA script that is not part of the image). Now `cowork-web:8e96d876` (`sha256:1907df5a...`, previous `cowork-web:f6885a55`), `readlink current` is `releases/8e96d876`, `COWORK_VERSION=8e96d876`.
- **Diary:** [#888](https://github.com/sbstndalton/noevia/pull/888) ([#885](https://github.com/sbstndalton/noevia/issues/885): an aborted backup run is logged with counts and seconds only; the unread `embed_batch_size` is dropped from `config/config.yaml`). **Merged, not deployed.** `diary-overlay.sh 8e96d876` stopped at its backup gate (below) before changing anything; `cowork-diary:f6885a55` and `DIARY_VERSION=f6885a55` are unchanged. The `config.yaml` line is not part of the `agent/` overlay in any case.
- **Model manager:** [#888](https://github.com/sbstndalton/noevia/pull/888) ([#886](https://github.com/sbstndalton/noevia/issues/886): sweep containers carry the label `noevia.model-manager.bench=1`, and `bench.reap_orphans()` at startup removes only labelled leftovers; [#884](https://github.com/sbstndalton/noevia/issues/884): symmetric telemetry de-dupe plus an additive `req_timing_dedupe` index; [#841](https://github.com/sbstndalton/noevia/issues/841): `download_targets` uses mountinfo so same-device bind mounts are offered). Now `cowork-model-loader:8e96d876` (`sha256:8171933f...`, previous `cowork-model-loader:f6885a55`), `MODEL_MANAGER_VERSION=8e96d876`.
- **Code sandbox (and code-verify), OCR, Docling:** no change (`cowork-code-sandbox:pi-0.87.0-f6885a55`, `cowork-ocr:5004b50`, `cowork-docling:f6885a55`).
- **Deploy/infra:** [#888](https://github.com/sbstndalton/noevia/pull/888) ([#841](https://github.com/sbstndalton/noevia/issues/841): `overlay-release.sh` `container_id` accepts only a line that is exactly a 64-hex id) is in the release tree; the script was not run. No live compose or override edit.

PRs: #888 #889. Issues: #841 #843 #845 #876 #884 #885 #886 #887 (#885 is closed on GitHub, but its fix does not run until the Diary overlay is re-run).

No feature flag was changed and `TRUST_PROXY` was not touched. No model run, tune, calibration, benchmark or download, no Code task, no private Diary access and nothing POSTed to the Diary by this release.

Exact source `8e96d87615894b7d55653c7ae49dc8d5c279f4b8` (main CI green on that commit: every job including `CI required`, plus the offline skills contract). A `git archive` from a throwaway worktree (SHA-256 `82bd1af4...`, matched on the server) went to `releases/8e96d876`. No `package.json`, lockfile, Diary or model-manager `requirements.txt`/Dockerfile changed since `f6885a55`. Evidence is in `/root/release-evidence-8e96d876/` on DaServer (snapshots of all containers before and after each step, build logs, models lists before and after).

**Order and results.**

1. **Web.** `dist/` built on DaServer (`npm ci` with an identical lockfile, `npm run build`, `STAMP_VERSION=8e96d876`, `node:22-bookworm-slim`, 4 GiB cap, from a copy of `apps/web`) and layered onto `cowork-web:f6885a55` with the same Dockerfile as before (66 layers). Synthetic candidate in a throwaway `--network none` read-only container with an empty data dir: healthy, `/` 200, `/api/ready` 200 (`8e96d876`), `/api/profile` 401, the changed server modules load. Backups `config/.env.bak.before-8e96d876` and `docker-compose.yml`/`docker-compose.override.yml` `.bak.before-8e96d876`; only `COWORK_VERSION` differs in `.env`. Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (three preflight checks passed).
2. **Diary: not deployed.** `deploy/examples/diary-overlay.sh 8e96d876` ran its mandatory appdata backup, which was cancelled by the plugin when the `Jellyfin` tar step failed with an empty error message (`ab_20261005_193735-failed`; no OOM, 8.8 TB free). The script exited at that gate before any tag, `.env` edit or recreate: `DIARY_VERSION` is still `f6885a55`, no `cowork-diary:8e96d876` image exists, `diary` was not touched by it. The failed backup did stop and start the Gluetun/Jellyfin/Profilarr/Seerr/bazarr group before it failed. Re-run `diary-overlay.sh 8e96d876` when a backup can complete.
3. **Model-loader.** Read-only check from the web container first (token never printed): `/downloads` had no jobs, `/benchmark/progress` `idle` and `active: false`, no labelled bench container, llama at 0% CPU. `models.ini` backed up as `config/llamacpp/models.ini.bak.before-8e96d876`, `.env` as `config/.env.bak.before-model-loader-8e96d876`; `cowork-model-loader:8e96d876` built with `docker compose build model-loader` (pip layer cached; candidate import check passed), recreated alone.

**Verify.** Web: healthy; `dist/version.json` `8e96d876`; `index.html` sha256 `b9c28030...` identical in the build, the image, `127.0.0.1:8021` and the public page; the served `index-DMgsd6_1.js` and `index-Cl1i6_9h.css` exist in the image's `dist/assets` (67 files); `/` 200, `/api/ready` 200 (`8e96d876`), unauthenticated `/api/profile`, `/api/diary/exchanges` and `/api/diary/storage-status` 401 locally and publicly (not 502); the log shows `codenet.guarding` with `["172.28.0.3"]`, the same address as before, and no error line. Diary: healthy on `f6885a55`, `/api/health` 200 with the token and 401 without. Model-loader: healthy on `8e96d876`, `RestartCount` 0; `GET /api/v1/models` lists the same 7 models and is byte-identical to the list before (`cmp`); `models.ini` is byte-identical to its backup; `/health`, `/overview`, `/downloads`, `/sections`, `/download-targets` and `/benchmark/progress` 200, the last `idle`, `active: false`; startup log has no warning, and the reaper logs only when it removes or fails to stop something, so its silence is expected: a read-only check from inside the container found the Docker client reachable and 0 containers with the label, and the unlabelled `llama-vulkan-test` and `model-loader-test` containers are unchanged. `cowork-llama-1` kept id, `StartedAt` (2026-10-01T06:39:59Z) and restart count.

**Not caused by this release.** Two server events overlapped the work and are recorded so the snapshots are not misread. (a) An appdata backup started outside this release at 19:17 stopped `cowork-web-1` and `cowork-diary-1` at 19:35:32 and restarted diary at 19:35:44, while the web cutover was running; `cowork-diary-1` therefore shows a new `StartedAt` (23:35:44Z) with the same container and image, and that backup's web copy was taken as the new web container started. (b) After the failed overlay backup, `CloudflaredTunnel`, `GluetunVPN`, `Jellyfin`, `Seerr`, `prowlarr`, `qbittorrent`, `radarr`, `sonarr` and `nextcloud-mcp` were recreated on newer images between 23:46Z and 23:53Z, and `nextcloud-borg-replica` was replaced by `nextcloud-borg-replica-check`. No release command touched them and the plugin's `updateContainer` is `no`; the cause was not identified. No `cowork-*` container other than web and model-loader changed id or image.

Rollback, one service at a time; use `sed` on the single `.env` key. All commands run on DaServer with `B=/mnt/docker/appdata/cowork` and `UP="bash $B/tools/preflight/up.sh --env-file $B/config/.env"`.

- **Web** (previous `f6885a55`): `ln -sfn $B/releases/f6885a55 $B/current && sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=f6885a55/' $B/config/.env && $UP -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:f6885a55` image is retained.
- **Model-loader** (previous `f6885a55`): `sed -i 's/^MODEL_MANAGER_VERSION=.*/MODEL_MANAGER_VERSION=f6885a55/' $B/config/.env`, then the same `up.sh` ending in `model-loader`. The only schema change is `CREATE INDEX IF NOT EXISTS req_timing_dedupe`, which the old image ignores. `models.ini` was not changed (byte-identical to `config/llamacpp/models.ini.bak.before-8e96d876`). The `cowork-model-loader:f6885a55` image is retained.
- **Diary:** nothing to roll back; it was not changed.

## Release f6885a55 — 2026-10-05 (repo sweep release 3: web, Diary, model-manager, Code sandbox and Docling)

### Services

- **Web:** [#851](https://github.com/sbstndalton/noevia/pull/851) (closes [#848](https://github.com/sbstndalton/noevia/issues/848), [#849](https://github.com/sbstndalton/noevia/issues/849)), [#875](https://github.com/sbstndalton/noevia/pull/875) ([#861](https://github.com/sbstndalton/noevia/issues/861), [#862](https://github.com/sbstndalton/noevia/issues/862), [#863](https://github.com/sbstndalton/noevia/issues/863)), [#878](https://github.com/sbstndalton/noevia/pull/878) (web refuses UI and file-sharing requests that arrive on its code-network address, [#853](https://github.com/sbstndalton/noevia/issues/853)), [#879](https://github.com/sbstndalton/noevia/pull/879) ([#866](https://github.com/sbstndalton/noevia/issues/866), [#867](https://github.com/sbstndalton/noevia/issues/867), [#868](https://github.com/sbstndalton/noevia/issues/868)), [#880](https://github.com/sbstndalton/noevia/pull/880) ([#864](https://github.com/sbstndalton/noevia/issues/864), [#865](https://github.com/sbstndalton/noevia/issues/865)) and [#883](https://github.com/sbstndalton/noevia/pull/883) ([#871](https://github.com/sbstndalton/noevia/issues/871), [#872](https://github.com/sbstndalton/noevia/issues/872), [#873](https://github.com/sbstndalton/noevia/issues/873), [#874](https://github.com/sbstndalton/noevia/issues/874) web side). Now `cowork-web:f6885a55` (previous `cowork-web:023ddcb5`), `readlink current` is `releases/f6885a55`, `COWORK_VERSION=f6885a55`.
- **Diary:** [#851](https://github.com/sbstndalton/noevia/pull/851) (storage 401 mapping), [#881](https://github.com/sbstndalton/noevia/pull/881) (closes [#857](https://github.com/sbstndalton/noevia/issues/857), [#858](https://github.com/sbstndalton/noevia/issues/858), [#859](https://github.com/sbstndalton/noevia/issues/859), [#860](https://github.com/sbstndalton/noevia/issues/860): backup snapshot check, reindex outside the write lock, bounded S3 reads) and [#850](https://github.com/sbstndalton/noevia/pull/850) (test only, closes [#847](https://github.com/sbstndalton/noevia/issues/847)). Now `cowork-diary:f6885a55` (previous `cowork-diary:023ddcb5`), `DIARY_VERSION=f6885a55`.
- **Model manager:** [#877](https://github.com/sbstndalton/noevia/pull/877) (closes [#869](https://github.com/sbstndalton/noevia/issues/869), [#870](https://github.com/sbstndalton/noevia/issues/870): bounded GGUF parsing, `block_count` cap, telemetry/hf/bench hardening) and the model-manager part of [#883](https://github.com/sbstndalton/noevia/pull/883). Now `cowork-model-loader:f6885a55` (previous `cowork-model-loader:023ddcb5`), `MODEL_MANAGER_VERSION=f6885a55`.
- **Code sandbox (and code-verify):** [#878](https://github.com/sbstndalton/noevia/pull/878) (closes [#852](https://github.com/sbstndalton/noevia/issues/852), [#853](https://github.com/sbstndalton/noevia/issues/853), [#855](https://github.com/sbstndalton/noevia/issues/855): pi exit refuses the pending prompt, verifier path check). Now `cowork-code-sandbox:pi-0.87.0-f6885a55` (`sha256:3cdb2d35...`) for both containers. Previous: `.env` `CODE_SANDBOX_VERSION` was `pi-0.87.0-c526350` (code-verify was running it), while `cowork-code-sandbox-1` was still running `pi-0.87.0-3c7e527`; both images are retained.
- **Docling:** [#882](https://github.com/sbstndalton/noevia/pull/882) (closes [#854](https://github.com/sbstndalton/noevia/issues/854): per-document kill limit for every input type, `isolation.py`/`isolated_worker.py`; the OCR fixture half is test-only). Now `cowork-docling:f6885a55` (`sha256:e3980cb3...`, previous `cowork-docling:9debec6`), `DOCLING_VERSION=f6885a55`, with `init: true` in the live override.
- **OCR:** [#882](https://github.com/sbstndalton/noevia/pull/882) generated real-engine fixtures and tests only ([#856](https://github.com/sbstndalton/noevia/issues/856)); merged, not deployed, `cowork-ocr:5004b50` unchanged.
- **Deploy/infra:** two live-override edits (below). Issues closed by this sweep range: [#847](https://github.com/sbstndalton/noevia/issues/847) to [#874](https://github.com/sbstndalton/noevia/issues/874) (#847 #848 #849 #852 #853 #854 #855 #856 #857 #858 #859 #860 #861 #862 #863 #864 #865 #866 #867 #868 #869 #870 #871 #872 #873 #874). PRs: #850 #851 #875 #877 #878 #879 #880 #881 #882 #883.

No feature flag was changed and `TRUST_PROXY` was not touched. No model run, tune, calibration, benchmark or download, no real document sent to Docling, no Code task, no private Diary access and nothing POSTed to the Diary by this release.

Exact source `f6885a55e2fddb9d59272f6e1cf4230b6382af49` (main CI green on that commit, all 12 jobs). A `git archive` from a throwaway worktree (SHA-256 `c9c56492...`, matched on the server) went to `releases/f6885a55`. No `package.json`, lockfile, Diary or model-manager `requirements.txt`/Dockerfile changed since `023ddcb5`; only `compose.docling.yaml` and `services/docling/Dockerfile` did. Evidence is in `/root/release-evidence-f6885a55/` on DaServer (snapshots of all 46 containers before and after every step, build logs, models lists).

**Order and results.**

1. **Web.** `dist/` built on DaServer (`npm ci`, `npm run build`, `STAMP_VERSION=f6885a55`, `node:22-bookworm-slim`, 4 GiB cap, from a copy of `apps/web`; CI is authoritative for tests) and layered onto `cowork-web:023ddcb5` with the same Dockerfile as before (63 layers, `sha256:a113faab...`). Synthetic candidate in a throwaway `--network none` container with an empty data dir: `/` 200, `/api/ready` 200 (`f6885a55`), `/api/profile` 401, `chat`, `projects`, `public-fetch`, `llamacpp-tune-spec` load. Backups `config/.env.bak.before-f6885a55`, `docker-compose.yml.bak.before-f6885a55`, `docker-compose.override.yml.bak.before-f6885a55`; only `COWORK_VERSION` differs in `.env`. Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (three preflight checks passed).
2. **Live override edits** (edited locally, copied back; no python on the host). (a) `web.environment` gained `COWORK_CODE_NET_ADDR: ${COWORK_CODE_NET_ADDR:-egress}`. Before recreating, `getent hosts egress` in web returned exactly one address, `172.28.0.3`, equal to the `egress.listening` bind; no other container has the `egress` alias. Web was recreated alone; the log shows `codenet.guarding` with `["172.28.0.3"]`, and public and local `/` 200, `/api/profile` 401, `/api/diary/exchanges` and `/api/diary/storage-status` 401 (not 403 or 502). A one-off read-only GET from `cowork-code-sandbox-1` to web's UI port on the code network returned 403 (`codenet.refused` logged once), which is the intended effect; the host path to the DAV port answered 421, not 403. (b) `docling` gained `init: true` next to `restart: unless-stopped`; `compose config` differed from before by that one line only, and it took effect at step 6.
3. **Diary.** `deploy/examples/diary-overlay.sh f6885a55` took appdata backup `ab_20261005_190839` (verified), built `cowork-diary:f6885a55` (`sha256:ab3981a1...`) `FROM` `023ddcb5` with `agent/` replaced, passed the candidate import test, recreated only `diary`; its own checks passed (model-loader unresolvable from Diary, health through web 200). `cowork-diary:rollback-before-diary-overlay` now points at `023ddcb5`, which is retained. Backup `config/.env.bak.before-diary-f6885a55`. The appdata backup stops and starts web and diary, so web restarted once more (`StartedAt` 23:08:53Z); that is the only reason web has a second start.
4. **Model-loader.** Read-only check from the web container first (token never printed): `/downloads` had no jobs, benchmark `idle`, no autotune or calibration log lines in 40 minutes, llama at 0.3% CPU. `models.ini` backed up as `config/llamacpp/models.ini.bak.before-f6885a55`, `.env` as `config/.env.bak.before-model-loader-f6885a55`; `cowork-model-loader:f6885a55` (`sha256:cb773503...`) built with `docker compose build model-loader` (pip layer cached; candidate import test passed), recreated alone.
5. **Code sandbox.** `docker top` showed only the supervisor (no task) and the logs were empty for 60 minutes. Built from `releases/f6885a55/services/code-sandbox` with `--network host --build-arg HARNESS_PACKAGE=@earendil-works/pi-coding-agent --build-arg HARNESS_VERSION=0.87.0` (pi 0.87.0, git 2.39.5; `pi-acp-bridge.cjs`, `verifier.cjs`, `supervisor.cjs` SHA-256 identical to the source). Backup `config/.env.bak.before-f6885a55` (taken at step 1) covers `CODE_SANDBOX_VERSION`. `code-sandbox` and `code-verify` recreated together with `up.sh --profile code -- -d --no-build --no-deps --wait`.
6. **Docling.** Idle first (no log lines for 10 minutes, 0.01% CPU). A plain `docker build` of `services/docling` missed the layer cache and began re-running `apt-get`, which would also have re-resolved unpinned `torch` and re-downloaded the models, so it was stopped after 90 seconds with nothing built. The image was instead built `FROM cowork-docling:9debec6` with only the six application files (`server.py extract.py isolation.py isolated_worker.py selftest.py synthetic_pdfs.py`) replaced, the same files the Dockerfile's final `COPY` places; user, workdir, cmd and healthcheck are inherited and identical. Candidate (`--network none`, read-only, tmpfs `/tmp`, `--init`): imports ok, `/health` 200; no document converted. Backup `config/.env.bak.before-docling-f6885a55`. Recreated alone.

**Verify.** Final state, all on their new tags with `RestartCount` 0: web, diary, model-loader and docling healthy; code-sandbox and code-verify up (no healthcheck defined). Web: `dist/version.json` `f6885a55`; `index.html` sha256 `3660d48d...` identical in the build, the image, `127.0.0.1:8021` and the public page; the served `index-BjIIgMol.js` and `index-Cl1i6_9h.css` exist in the image's `dist/assets` (67 files); `/` 200, `/api/ready` 200 (`f6885a55`), unauthenticated `/api/profile` 401, locally and publicly; no error or failure line in the web log. Diary: `/api/health` 200 with the token and 401 without; unauthenticated Diary endpoints through web 401, locally and publicly. Model-loader: `GET /api/v1/models` lists the same 7 models and is byte-identical to the list before (`cmp`), `models.ini` is byte-identical to its backup, `/health`, `/overview`, `/downloads`, `/sections`, `/benchmark/progress` 200, `llama` untouched. Code: web connects to `code-sandbox:8030`, the verifier socket exists on both sides, `pi --version` 0.87.0; the authenticated Code status endpoint was not called (no session). `CODE_VERIFY` is empty in `.env`, so `code-verify` logs `0 repositories configured` (verification off, unchanged by this release). Docling: `docker top` shows `/sbin/docker-init` as PID 1 with `python server.py` under it, `HostConfig.Init` true, `/health` 200 from web. Before and after snapshots of all 46 containers: only `cowork-web-1`, `cowork-diary-1`, `cowork-model-loader-1`, `cowork-code-sandbox-1`, `cowork-code-verify-1` and `cowork-docling-1` changed id and `StartedAt`; `cowork-llama-1` (`ae3235547379`, started 2026-10-01T06:39:59Z), embed, laya, ocr, kiwix, dav-tailscale, CloudflaredTunnel, nextcloud-mcp and every other container kept id, `StartedAt` and restart count. During step 6 Unraid pulled newer `:latest` images for some unrelated containers (an update check, not this release), so their `docker ps` image column changed from a tag to an image id; none was recreated. The restart-alert baseline was re-acked after the last step (state file backed up as `sidecar-restart-alert.tsv.before` in the evidence folder).

Rollback, one service at a time; use `sed` on the single `.env` key, not a whole-file restore, because the backups were taken at different points. All commands run on DaServer with `B=/mnt/docker/appdata/cowork` and `UP="bash $B/tools/preflight/up.sh --env-file $B/config/.env"`.

- **Web** (previous `023ddcb5`): `ln -sfn $B/releases/023ddcb5 $B/current && sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=023ddcb5/' $B/config/.env && $UP -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:023ddcb5` image is retained. The old web ignores `COWORK_CODE_NET_ADDR`, so the override line can stay.
- **Diary** (previous `023ddcb5`): `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=023ddcb5/' $B/config/.env`, then the same `up.sh` ending in `diary`. `cowork-diary:023ddcb5` is retained.
- **Model-loader** (previous `023ddcb5`): `sed -i 's/^MODEL_MANAGER_VERSION=.*/MODEL_MANAGER_VERSION=023ddcb5/' $B/config/.env`, then `up.sh` ending in `model-loader`. `models.ini` was not changed (byte-identical to `config/llamacpp/models.ini.bak.before-f6885a55`).
- **Code sandbox and code-verify** (previous `.env` value `pi-0.87.0-c526350`; the sandbox container itself had run `pi-0.87.0-3c7e527`): `sed -i 's/^CODE_SANDBOX_VERSION=.*/CODE_SANDBOX_VERSION=pi-0.87.0-c526350/' $B/config/.env`, then `$UP --profile code -- -d --no-build --no-deps --wait code-sandbox code-verify` (only if no Code task is running; recreating the sandbox ends one). Use `pi-0.87.0-3c7e527` instead to restore the sandbox exactly.
- **Docling** (previous `9debec6`): `sed -i 's/^DOCLING_VERSION=.*/DOCLING_VERSION=9debec6/' $B/config/.env`, then `$UP -- -d --no-build --no-deps --wait docling`. `cowork-docling:9debec6` is retained.
- **Live override:** `cp -p /boot/config/plugins/compose.manager/projects/Cowork/docker-compose.override.yml.bak.before-f6885a55 /boot/config/plugins/compose.manager/projects/Cowork/docker-compose.override.yml`, then recreate web (and docling, if `init: true` should go) with the guarded `up.sh`. If any legitimate path ever returns 403 from the code-network guard, delete only the `COWORK_CODE_NET_ADDR` line and recreate web; unset means no check.

## Release 023ddcb5 — 2026-10-05 (web low follow-ups, Diary and model-manager UI removal)

### Services

- **Web:** [#840](https://github.com/sbstndalton/noevia/pull/840) (closes [#826](https://github.com/sbstndalton/noevia/issues/826), [#829](https://github.com/sbstndalton/noevia/issues/829), [#831](https://github.com/sbstndalton/noevia/issues/831), [#833](https://github.com/sbstndalton/noevia/issues/833), [#836](https://github.com/sbstndalton/noevia/issues/836): orphan sweep limit, permitted-tools cache clears, linear S3 list parse, QA script repairs) and [#846](https://github.com/sbstndalton/noevia/pull/846) (closes [#808](https://github.com/sbstndalton/noevia/issues/808), [#809](https://github.com/sbstndalton/noevia/issues/809): dormant durable-chat seam removed, `chat-turns.cjs` and `selection-constraint.cjs` gone from `server/`, experiments archived). Now `cowork-web:023ddcb5` (previous `cowork-web:c6702509`), recreated alone; `readlink current` is `releases/023ddcb5`, `COWORK_VERSION=023ddcb5`.
- **Diary:** [#842](https://github.com/sbstndalton/noevia/pull/842) (closes [#807](https://github.com/sbstndalton/noevia/issues/807): the sidecar's own UI and `/api/chat`, `/api/relog`, `/v1/models` removed; `services/diary/agent` only). Now `cowork-diary:023ddcb5` (previous `cowork-diary:c6702509`), `DIARY_VERSION=023ddcb5`.
- **Model manager:** [#844](https://github.com/sbstndalton/noevia/pull/844) (closes [#806](https://github.com/sbstndalton/noevia/issues/806): HTML UI removed, `main.py` split into `helpers.py`, `jinja2` and `python-multipart` dropped, the Dockerfile no longer downloads vendor assets) and the model-manager part of [#839](https://github.com/sbstndalton/noevia/pull/839) (If-Range strength, mountinfo mount points). Now `cowork-model-loader:023ddcb5` (previous `cowork-model-loader:c6702509`), `MODEL_MANAGER_VERSION=023ddcb5`.
- **Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** [#839](https://github.com/sbstndalton/noevia/pull/839) (closes [#832](https://github.com/sbstndalton/noevia/issues/832), [#838](https://github.com/sbstndalton/noevia/issues/838): overlay engine probe, rclone json escape) is in the release tree; `diary-overlay.sh` ran from this tree. The installed `tools/preflight/up.sh` was not refreshed. `overlay-release.sh` was not used because it recreates diary and ocr.

No feature flag was changed and `TRUST_PROXY` was not touched. No model run, tune, download, private Diary access or prompt to the Diary.

Exact source `023ddcb5e020d42db7224d58cb2b50ea45f1116b` (main CI green on that commit, all 14 checks). A `git archive` from a throwaway worktree (SHA-256 `eb4c3c8d...`, matched on the server) went to `releases/023ddcb5`. No web dependency file (`package.json`, lockfile) or Diary `requirements.txt`/Dockerfile changed since `c6702509`, so web reused the previous image's `node_modules` and Diary ran no `pip install`. The model-manager `requirements.txt` and Dockerfile did change (dependencies and vendor downloads removed), so that image was a real build.

**Web.** `dist/` was built on DaServer (`npm ci`, `npm run build` with `STAMP_VERSION=023ddcb5`, in `node:22-bookworm-slim`, 4 GiB cap, from a copy of `apps/web` outside the release dir; the Dockerfile's `node --test` step was not run, CI is authoritative) and layered onto `cowork-web:c6702509` with the same Dockerfile `overlay-release.sh` generates (60 layers, no flattening). That Dockerfile deletes every application-owned entry in `/app/server` (keeping `node_modules` and `ui-data`) and `/app/dist` before copying, so removed files do not linger: `chat-turns.cjs` and `selection-constraint.cjs` are present in `cowork-web:c6702509` and absent in `cowork-web:023ddcb5`. Synthetic candidate check in a throwaway `--network none` container with an empty data dir: `/` 200, `/api/ready` 200 (`version 023ddcb5`), `/api/profile` 401, `chat.cjs`, `projects.cjs`, `public-fetch.cjs` and `llamacpp-tune-spec.cjs` load. Backups: `config/.env.bak.before-023ddcb5`, `docker-compose.yml.bak.before-023ddcb5`, `docker-compose.override.yml.bak.before-023ddcb5`; only `COWORK_VERSION` differs in `.env`. Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`); all three preflight checks passed.

**Diary.** `deploy/examples/diary-overlay.sh 023ddcb5` took appdata backup `ab_20261005_181633` (verified by the script as created by that run), built `cowork-diary:023ddcb5` (`sha256:5b710875...`) `FROM` the running `c6702509` image (`sha256:a6ca877c...`) with `agent/` replaced, passed its candidate import test, recreated only `diary`, and its own checks passed (model-loader unresolvable from Diary, health through web 200). `cowork-diary:c6702509` is retained, and `cowork-diary:rollback-before-diary-overlay` now points at that same image. Backup: `config/.env.bak.before-diary-023ddcb5`. The appdata backup plugin stops and starts web and diary, so web restarted once more (`StartedAt` 22:16:59Z) and came back healthy on `023ddcb5`; that is the only reason web has a second start.

**Model-loader.** First checked read-only (from the web container, token never printed): `/api/v1/downloads` returned no jobs, `activeDownloads` 0, benchmark `idle`, no autotune or calibration activity, llama at 0% CPU. `models.ini` was backed up as `config/llamacpp/models.ini.bak.before-023ddcb5`, `.env` as `config/.env.bak.before-model-loader-023ddcb5`; `cowork-model-loader:023ddcb5` (`sha256:4413c199...`) was built with `MODEL_MANAGER_VERSION=023ddcb5 docker compose build model-loader` from `services/model-manager` (candidate import test passed: `jinja2`, `multipart`, `app/templates` and `/srv/vendor` absent, `app.main` imports), then recreated alone with `up.sh ... --no-build --no-deps --wait --wait-timeout 180 model-loader`.

- **Verify:** web, diary and model-loader are healthy with `RestartCount` 0, each on its new tag. Web: `dist/version.json` reads `023ddcb5`; `index.html` sha256 `fbc58e5d...` is identical in the build, the image, the local `127.0.0.1:8021` page and the public page; the served `index-w31B0G5S.js` and `index-Cl1i6_9h.css` exist in the image's `dist/assets` (67 files); `/` 200, `/api/ready` 200 (`version 023ddcb5`) and unauthenticated `/api/profile` 401, locally and publicly. The web log has no error or startup failure after the final restart (one `[mcp:tavily] discovery failed` line in the first start was outbound-only; the endpoint answered from the container minutes later). Diary: `/api/health` 200 with the token and 401 without; `/api/chat`, `/api/relog`, `/v1/models`, `/` and `/static/app.js` return 404 inside the network (read-only GETs only, nothing POSTed); unauthenticated `/api/diary/exchanges` and `/api/diary/storage-status` return 401 (not 502), locally and publicly. Model-loader: `GET /api/v1/models` lists the same 7 models and is byte-identical to the list before, `models.ini` is byte-identical to its backup (`cmp`), `/api/v1/health` 200, `/api/v1/overview`, `/downloads` and `/sections` 200; `GET /` and `/dashboard` return 404 with the token (the HTML UI is gone), and 401 without it because the token check runs first. Before and after snapshots of all 45 containers (`docker ps -a` ids and images plus `StartedAt` and restart counts): only `cowork-web-1`, `cowork-diary-1` and `cowork-model-loader-1` changed; `cowork-llama-1` (`ae3235547379`, started 2026-10-01T06:39:59Z), embed, laya, ocr, docling, code-sandbox, code-verify, kiwix, dav-tailscale, CloudflaredTunnel, nextcloud-mcp and every other container kept id, `StartedAt` and restart count.

Rollback, one service at a time. Use `sed` on the single key rather than copying a whole `.env` backup back, because the backups were taken at different points and a whole-file restore would also revert the other services' tags.

- **Web** (previous `c6702509`): `ln -sfn /mnt/docker/appdata/cowork/releases/c6702509 /mnt/docker/appdata/cowork/current && sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=c6702509/' /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:c6702509` image is retained.
- **Diary** (previous `c6702509`): `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=c6702509/' /mnt/docker/appdata/cowork/config/.env` and the same `up.sh` command ending in `diary`. The `cowork-diary:c6702509` image is retained.
- **Model-loader** (previous `c6702509`): `sed -i 's/^MODEL_MANAGER_VERSION=.*/MODEL_MANAGER_VERSION=c6702509/' /mnt/docker/appdata/cowork/config/.env` and the same `up.sh` command ending in `model-loader`. If `models.ini` were ever damaged, copy `config/llamacpp/models.ini.bak.before-023ddcb5` back over it (it is byte-identical to the live file today).

## Release c6702509 — 2026-10-05 (web sweep batch, Diary overlay, model-loader image)

### Services

- **Web:** [#820](https://github.com/sbstndalton/noevia/pull/820) (closes [#788](https://github.com/sbstndalton/noevia/issues/788)), [#821](https://github.com/sbstndalton/noevia/pull/821) ([#797](https://github.com/sbstndalton/noevia/issues/797), [#818](https://github.com/sbstndalton/noevia/issues/818)), [#823](https://github.com/sbstndalton/noevia/pull/823) ([#796](https://github.com/sbstndalton/noevia/issues/796)), [#824](https://github.com/sbstndalton/noevia/pull/824) (#781-#787), [#825](https://github.com/sbstndalton/noevia/pull/825) ([#794](https://github.com/sbstndalton/noevia/issues/794), [#795](https://github.com/sbstndalton/noevia/issues/795)), [#828](https://github.com/sbstndalton/noevia/pull/828) (#810-#817), [#834](https://github.com/sbstndalton/noevia/pull/834) (#789-#793) and [#837](https://github.com/sbstndalton/noevia/pull/837) ([#835](https://github.com/sbstndalton/noevia/issues/835): Diary preview renders sidecar markdown escapes as literal text; ships with, and before, the Diary escaping change). Now `cowork-web:c6702509` (previous `cowork-web:29732472`), recreated alone; `readlink current` is `releases/c6702509`, `COWORK_VERSION=c6702509`.
- **Diary:** [#830](https://github.com/sbstndalton/noevia/pull/830) (closes [#802](https://github.com/sbstndalton/noevia/issues/802), [#803](https://github.com/sbstndalton/noevia/issues/803), [#804](https://github.com/sbstndalton/noevia/issues/804), [#805](https://github.com/sbstndalton/noevia/issues/805): real pre-stream statuses, escaped entry prose, lock-free tenant delete; `services/diary/agent` only). Now `cowork-diary:c6702509` (previous `cowork-diary:9debec6`), `DIARY_VERSION=c6702509`.
- **Model manager:** [#827](https://github.com/sbstndalton/noevia/pull/827) (closes [#798](https://github.com/sbstndalton/noevia/issues/798), [#799](https://github.com/sbstndalton/noevia/issues/799), [#800](https://github.com/sbstndalton/noevia/issues/800), [#801](https://github.com/sbstndalton/noevia/issues/801): safe nested/HF deletes, verified download resume, comment-preserving `models.ini` writes). Now `cowork-model-loader:c6702509` (previous `cowork-model-loader:3c7e527`), `MODEL_MANAGER_VERSION=c6702509`. [#839](https://github.com/sbstndalton/noevia/pull/839) (If-Range strength, merged after `c6702509`) is merged, not yet deployed.
- **Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** [#822](https://github.com/sbstndalton/noevia/pull/822) (closes [#819](https://github.com/sbstndalton/noevia/issues/819): script hardening, docs, CI coverage) is in the release tree; `diary-overlay.sh` ran from this tree. The installed `tools/preflight/up.sh` was not refreshed. `overlay-release.sh` was not used because it recreates diary and ocr. [#839](https://github.com/sbstndalton/noevia/pull/839) (overlay engine probe, rclone json escape, mountinfo) is merged, not yet deployed.

No feature flag was changed and `TRUST_PROXY` was not touched. The live `.env` has no `DIARY_SOURCE` key, which the new web requires (it throws at startup for anything but `sidecar`); web started and stayed healthy. No model run, tune, download, private Diary access or prompt to the Diary.

Exact source `c6702509a0358d56808bb10106031a5405b2c931` (main CI green on that commit, all 12 jobs; `d97e6c20`, `b2b5b0a6`, `415c8f0c` and `e11accb1` are ancestors). A `git archive` from a throwaway worktree (SHA-256 `843d2113...`, matched on the server) went to `releases/c6702509`. No dependency file (`package.json`, lockfiles, `requirements.txt`, any Dockerfile) changed since `29732472`/`9debec6`, so web reused the previous image's `node_modules`.

**Web.** `dist/` was built on DaServer (`npm ci`, `npm run build` with `STAMP_VERSION=c6702509`, in `node:22-bookworm-slim`, 4 GiB cap; the Dockerfile's `node --test` step was not run, CI is authoritative) and `dist/` plus `server/` were layered onto `cowork-web:29732472` (57 layers, no flattening). Synthetic candidate check in a throwaway `--network none` container with an empty data dir: `/` 200, `/api/ready` 200, `/api/profile` 401, and `public-fetch.cjs` and `llamacpp-tune-spec.cjs` load. Backups: `config/.env.bak.before-c6702509`, `docker-compose.yml.bak.before-c6702509`, `docker-compose.override.yml.bak.before-c6702509`; only `COWORK_VERSION` differs in `.env`. Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`); all three preflight checks passed.

**Diary.** `deploy/examples/diary-overlay.sh c6702509` took appdata backup `ab_20261005_141455` (verified by the script as created by that run), built `cowork-diary:c6702509` (`sha256:a6ca877c...`) `FROM` the running `9debec6` image (`sha256:8775aed1...`) with `agent/` replaced, passed its candidate import test, recreated only `diary`, and its own checks passed (model-loader unresolvable from Diary, health through web 200). `cowork-diary:rollback-before-diary-overlay` and `cowork-diary:9debec6` are both retained. Backup: `config/.env.bak.before-diary-c6702509`. The appdata backup plugin stops and starts web and diary, so web restarted once more (`StartedAt` 18:15:21Z) and came back healthy on `c6702509`; that is the only reason web has a second start.

**Model-loader.** First checked read-only (from the web container, token never printed): no download jobs, benchmark idle, `activeDownloads` 0, no autotune or calibration log lines in the last 30 minutes (web had also just restarted). `cowork-model-loader:c6702509` was built with `docker compose build model-loader` from `services/model-manager` (candidate import test passed), `models.ini` backed up as `config/llamacpp/models.ini.bak.before-c6702509`, `.env` as `config/.env.bak.before-model-loader-c6702509`, then recreated alone with `up.sh ... --no-build --no-deps --wait --wait-timeout 180 model-loader`.

- **Verify:** web, diary and model-loader are healthy with `RestartCount` 0, each on its new tag. Web: `dist/version.json` reads `c6702509`; `index.html` sha256 `c1e32b17...` is identical in the build, the image, the local `127.0.0.1:8021` page and the public page; the served `index-CT8-xxIA.js` and `index-Cl1i6_9h.css` exist in the image's `dist/assets` (67 files); `/` 200, `/api/ready` 200 (`version c6702509`) and unauthenticated `/api/profile` 401, locally and publicly; the web log has no error or startup failure. Diary: `escape_entry_text("a\n### b")` returns `'a\n\\### b'` in the container; unauthenticated `/api/diary/exchanges` and `/api/diary/storage-status` return 401 (not 502), locally and publicly. Model-loader: `GET /api/v1/models` returns the same 7 models, byte-identical to the list before (key, size, sections), overview shows 8 sections, and `models.ini` is byte-identical to its backup after the start (the comment-preserving cache-ram migration made no change). Before and after snapshots of all 45 containers (`docker ps -a` ids and images plus `StartedAt`): only `cowork-web-1`, `cowork-diary-1` and `cowork-model-loader-1` changed; `cowork-llama-1` (`ae3235547379`, started 2026-10-01T06:39:59Z), embed, laya, ocr, docling, code-sandbox, code-verify, kiwix, dav-tailscale, CloudflaredTunnel, nextcloud-mcp and every other container kept id, `StartedAt` and restart count.

Rollback, one service at a time. Use `sed` on the single key rather than copying a whole `.env` backup back, because the three backups were taken at different points and a whole-file restore would also revert the other services' tags.

- **Web** (previous `29732472`): `ln -sfn /mnt/docker/appdata/cowork/releases/29732472 /mnt/docker/appdata/cowork/current && sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=29732472/' /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:29732472` image is retained.
- **Diary** (previous `9debec6`): `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=9debec6/' /mnt/docker/appdata/cowork/config/.env` and the same `up.sh` command ending in `diary`.
- **Model-loader** (previous `3c7e527`): `sed -i 's/^MODEL_MANAGER_VERSION=.*/MODEL_MANAGER_VERSION=3c7e527/' /mnt/docker/appdata/cowork/config/.env` and the same `up.sh` command ending in `model-loader`. If `models.ini` were ever damaged, copy `config/llamacpp/models.ini.bak.before-c6702509` back over it (it is byte-identical to the live file today).

## Release 29732472 — 2026-10-05 (web: routing modes, flag off)

### Services

- **Web:** [#779](https://github.com/sbstndalton/noevia/pull/779) (`29732472`, closes [#778](https://github.com/sbstndalton/noevia/issues/778): local / cloud / hybrid routing modes with a sensitivity card, router chunks default to 1). Now `cowork-web:29732472` (previous `cowork-web:3e7bbed8`), recreated alone; `readlink current` is `releases/29732472`, `COWORK_VERSION=29732472`. The `routingModes` flag stays off; `NOEVIA_ROUTER_CHUNKS` was not added.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Reviewed head `f43ee95e` was already up to date with main (0 behind), and CI was green there (10/10). It was squash-merged with `--match-head-commit`, the branch was deleted, and there were no phantom deletions. Dependencies were unchanged since 3e7bbed8. `dist/` and `server/` were built from a `git archive` of `29732472` (`npm ci`, `npm run build` with `STAMP_VERSION=29732472`, in `node:22-bookworm-slim` on DaServer) and layered onto `cowork-web:3e7bbed8` (54 layers, with the image's `server/node_modules` kept), web only. Synthetic candidate check in a throwaway `--network none` container: unauthenticated `GET` and `PUT /api/routing-mode` returned 401, and `/` and `/api/ready` returned 200. Backup: `config/.env.bak.before-29732472`; only `COWORK_VERSION` differs from it. Web was started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`), and the preflight checks passed.

- **Verify:** web is healthy with `RestartCount` 0, and `dist/version.json` reads `29732472`. `index.html` sha256 `93a21169...` is identical in the build, the image and the served page (local and public), and the served entry bundle is `index-CrDS_RvT.js`. All 44 other containers kept their ID, StartedAt, restart count, status and image; only web changed. Live: `/` and `/api/ready` returned 200 (`version 29732472`), both locally and publicly. An unauthenticated `GET /api/routing-mode` returned 401, both locally and publicly. The web log was clean for 2 minutes. No flag flip, model run, tune, settings change or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/3e7bbed8 /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-29732472 /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:3e7bbed8` image is retained.

## Release 3e7bbed8 — 2026-10-04 (web: consistent project chat counts, storage redirect label)

### Services

- **Web:** [#777](https://github.com/sbstndalton/noevia/pull/777) (`3e7bbed8`, closes [#775](https://github.com/sbstndalton/noevia/issues/775): project chat counts agree across views, and [#776](https://github.com/sbstndalton/noevia/issues/776): storage redirects are labelled). Now `cowork-web:3e7bbed8` (previous `cowork-web:1eb8bbad`), recreated alone; `readlink current` is `releases/3e7bbed8`, `COWORK_VERSION=3e7bbed8`. No flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Reviewed head `1e513616` already contained main (0 behind), so no branch update was needed; CI was green there (10/10). It was squash-merged with `--match-head-commit`, the branch was deleted, and there were no phantom deletions. Dependencies were unchanged since 1eb8bbad. `dist/` and `server/` were built from a `git archive` of `3e7bbed8` (`npm ci`, `npm run build` with `STAMP_VERSION=3e7bbed8`, in `node:22-bookworm-slim` on DaServer) and layered onto `cowork-web:1eb8bbad` (51 layers), web only. Synthetic candidate checks with no network: `storage-login-check-770` and `project-chat-count-768` passed 14/14 in a throwaway candidate container with the candidate `src/`, `tests/` and `typescript` mounted. Backup: `config/.env.bak.before-3e7bbed8`. Web was started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`), and the preflight checks passed. No storage settings were saved or changed on the live server.

- **Verify:** web is healthy with `RestartCount` 0, and `dist/version.json` reads `3e7bbed8`. `index.html` sha256 `0b9f2fb3...` is identical in the build, the image and the served page (local and public), and the served bundle is `index-MfwL2DU5.js`. All 44 other containers kept their ID, StartedAt, restart count, status and image; only web changed. Live: `/` and `/api/ready` returned 200 (`version 3e7bbed8`), both locally and publicly. An unauthenticated `PUT /api/integrations/storage` returned 401, both locally and publicly. The web log was clean for 2 minutes. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/1eb8bbad /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-3e7bbed8 /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:1eb8bbad` image is retained.

## Release 1eb8bbad — 2026-10-04 (web: storage warning wording, project card count)

### Services

- **Web:** [#774](https://github.com/sbstndalton/noevia/pull/774) (`1eb8bbad`, closes [#773](https://github.com/sbstndalton/noevia/issues/773): a reached server's non-401 status is named in the storage warning, and [#768](https://github.com/sbstndalton/noevia/issues/768): project card chat count excludes archived chats). Now `cowork-web:1eb8bbad` (previous `cowork-web:b653843c`), recreated alone; `readlink current` is `releases/1eb8bbad`, `COWORK_VERSION=1eb8bbad`. No flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Reviewed head `bf339c68` already contained main (0 behind), so no branch update was needed; CI was green there (10/10). It was squash-merged with `--match-head-commit`, the branch was deleted, and there were no phantom deletions. Dependencies were unchanged since b653843c. `dist/` and `server/` were built from a `git archive` of `1eb8bbad` (`npm ci`, `npm run build` with `STAMP_VERSION=1eb8bbad`, in `node:22-bookworm-slim` on DaServer) and layered onto `cowork-web:b653843c` (49 layers), web only. Synthetic candidate checks with no network: `storage-login-check-770` and `project-chat-count-768` passed 11/11 in a throwaway copy of the image with the candidate `server/`, `src/`, `tests/` and `typescript` added. The root `npm ci` lacks `better-sqlite3`, and the image lacks `src/` and `typescript`, so neither runs these alone. Backup: `config/.env.bak.before-1eb8bbad`. Web was started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`), and the preflight checks passed. No storage settings were saved or changed on the live server.

- **Verify:** web is healthy with `RestartCount` 0, and `dist/version.json` reads `1eb8bbad`. `index.html` sha256 `5d0dac3e...` is identical in the build, the image and the served page (local and public), and the served bundle is `index-BNTz3DkA.js`. All 44 other containers kept their ID, StartedAt, restart count, status and image; only web changed. Live: `/` and `/api/ready` returned 200 (`version 1eb8bbad`), both locally and publicly. An unauthenticated `PUT /api/integrations/storage` returned 401, both locally and publicly. The web log was clean for 2 minutes. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/b653843c /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-1eb8bbad /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:b653843c` image is retained.

## Release b653843c — 2026-10-04 (web: storage login check)

### Services

- **Web:** [#772](https://github.com/sbstndalton/noevia/pull/772) (`b653843c`, closes [#770](https://github.com/sbstndalton/noevia/issues/770): check the storage login on save and explain refresh 401s). Now `cowork-web:b653843c` (previous `cowork-web:6f59ba82`), recreated alone; `readlink current` is `releases/b653843c`, `COWORK_VERSION=b653843c`. No flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Reviewed head `3f1e187e` already contained main, so no branch update was needed; CI was green there (10/10). It was squash-merged with `--match-head-commit`, the branch was deleted, and there were no phantom deletions. Dependencies were unchanged since 6f59ba82. `dist/` and `server/` were built from a `git archive` of `b653843c` (`npm ci`, `npm run build` with `STAMP_VERSION=b653843c`) and layered onto `cowork-web:6f59ba82` (43 layers, so no flattening was needed), web only. Synthetic candidate checks: `storage-login-check-770` and `manual-source-sync-toast` passed 9/9 against the archived build. The image has no `typescript`, so that test cannot run inside it. Backup: `config/.env.bak.before-b653843c`. Web was started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`). No storage settings were saved or changed on the live server.

- **Verify:** web is healthy with `RestartCount` 0, and `dist/version.json` reads `b653843c`. `index.html` sha256 `426801d2...` is identical in the local build, the image and the served page (local and public), and the served bundle is `index-DvadeUnb.js`. All 44 other containers kept their ID, StartedAt, restart count, status and image; only web changed. Live: `/` and `/api/ready` returned 200 (`version b653843c`), both locally and publicly. An unauthenticated `PUT /api/integrations/storage` returned 401, both locally and publicly. The web log was clean for 2 minutes. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/6f59ba82 /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-b653843c /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:6f59ba82` image is retained.

## Release 6f59ba82 — 2026-10-04 (web: tool-layer provenance policy, flag off)

### Services

- **Web:** [#771](https://github.com/sbstndalton/noevia/pull/771) (`6f59ba82`, closes [#769](https://github.com/sbstndalton/noevia/issues/769): tool-layer provenance policy, the hard injection boundary, `provenance-policy.cjs`). Now `cowork-web:6f59ba82` (previous `cowork-web:17b477dd`), recreated alone; `readlink current` is `releases/6f59ba82`, `COWORK_VERSION=6f59ba82`. The `provenancePolicy` flag stays OFF; no flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Main had moved 2 commits past reviewed head `578c91de`, so the branch was updated (merge-only, same files as main's delta) to `44827dad`; CI was green there (10/10). It was squash-merged with `--match-head-commit`, the branch was deleted, there were no phantom deletions, and main CI was green on `6f59ba82`. Dependencies were unchanged since 17b477dd. `dist/` and `server/` were built from a `git archive` of `6f59ba82` (`npm ci`, `npm run build` with `STAMP_VERSION=6f59ba82`) and layered onto `cowork-web:17b477dd`, web only. Synthetic candidate checks: the `provenance-policy` and `approval-card-provenance-769` tests passed 17/17 in the build; inside the image with no network, the server provenance tests passed 15/15. Backup: `config/.env.bak.before-6f59ba82`; no appdata backup was run. Web was started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`), and the preflight checks passed.

- **Verify:** web is healthy with `RestartCount` 0, and `dist/version.json` reads `6f59ba82`. `index.html` sha256 `d56487e0...` is identical in the local build, the image and the served page (local and public), and the served bundle is `index-ByB_ZG1o.js`. `server/provenance-policy.cjs` is in the image. All 44 other containers kept their ID, StartedAt, restart count, status and image; only web changed. Live: `/` returned 200 and `/api/ready` returned 200 (`version 6f59ba82`), both locally and publicly. The web log was clean for 2 minutes. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/17b477dd /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-6f59ba82 /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:17b477dd` image is retained.

## Release 17b477dd — 2026-10-04 (web: vault mirror orphan note, skipped list-save ids)

### Services

- **Web:** [#766](https://github.com/sbstndalton/noevia/pull/766) (`17b477dd`, closes [#764](https://github.com/sbstndalton/noevia/issues/764), [#765](https://github.com/sbstndalton/noevia/issues/765): the vault mirror trashes the orphaned old note, and list saves report skipped ids). Now `cowork-web:17b477dd` (previous `cowork-web:25cabfb4`), recreated alone; `readlink current` is `releases/17b477dd`, `COWORK_VERSION=17b477dd`. No flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Main had not moved since head `5c0be2d1` (0 behind, CI green), so no branch update was needed. The PR was squash-merged with `--match-head-commit`, the branch was deleted on the remote and locally, and main CI was green on `17b477dd`. Dependencies were unchanged since 25cabfb4. `dist/` and `server/` were built from a `git archive` of `17b477dd` (`npm ci`, `npm run build` with `STAMP_VERSION=17b477dd`) and layered onto `cowork-web:25cabfb4` (37 layers), web only. Synthetic candidate checks ran with no network: locally, `chat-lists-routes`, `routes/chat-lists`, `chat-vault-mirror`, `projects` and `list-save-skipped-765` passed 64/64; inside the image, the server tests passed 62/62. Backup: `config/.env.bak.before-17b477dd`; no appdata backup was run. Web was started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`), and the preflight checks passed.

- **Verify:** web is healthy with `RestartCount` 0, and `dist/version.json` reads `17b477dd`. `index.html` sha256 `866d7c5d...` is identical in the local build, the image and the served page (local and public), and the served bundle is `index-Bogab6hw.js`. All 44 other containers kept their ID, StartedAt, restart count, status and image; only web changed. Live: `/` returned 200 and `/api/ready` returned 200 (`version 17b477dd`), both locally and publicly. The web log was clean for 2 minutes. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/25cabfb4 /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-17b477dd /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:25cabfb4` image is retained.

## Release 25cabfb4 — 2026-10-04 (web: chat lists, suggest rate limit, vault mirror fixes)

### Services

- **Web:** [#763](https://github.com/sbstndalton/noevia/pull/763) (`e2efeef2`, closes [#755](https://github.com/sbstndalton/noevia/issues/755), [#756](https://github.com/sbstndalton/noevia/issues/756), [#759](https://github.com/sbstndalton/noevia/issues/759): no chat-list resurrection by stale saves, brain note removed on delete, invalid move frame refused), [#762](https://github.com/sbstndalton/noevia/pull/762) (`253e3c5d`, closes [#760](https://github.com/sbstndalton/noevia/issues/760): per-user suggest rate limit, in-flight work aborted at the deadline), [#761](https://github.com/sbstndalton/noevia/pull/761) (`25cabfb4`, closes [#757](https://github.com/sbstndalton/noevia/issues/757), [#758](https://github.com/sbstndalton/noevia/issues/758): vault mirror never overwrites a foreign note on rename, failed syncs back off). Now `cowork-web:25cabfb4` (previous `cowork-web:b31d0075`), recreated alone; `readlink current` is `releases/25cabfb4`, `COWORK_VERSION=25cabfb4`. No flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Each PR was updated onto main (#763 already current at 281b3832; #762 to 36ee13b9; #761 to 9ea63d34), CI green on the new head, squash-merged with `--match-head-commit`, branch deleted, and main CI green after each merge. Dependencies unchanged since b31d0075. `dist/` and `server/` were built from a `git archive` of `25cabfb4` (`npm ci`, frontend tests, `npm run build` with `STAMP_VERSION=25cabfb4`) and layered onto `cowork-web:b31d0075`, web only. Candidate checked with no network: `chat-framing`, `chat-lists-routes`, `routes/chat-lists`, `chat-vault-mirror` and `projects` tests 76/76. Backup: `config/.env.bak.before-25cabfb4`; no appdata backup run. Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`); preflight checks passed.

- **Verify:** web healthy, `RestartCount` 0, `dist/version.json` `25cabfb4`, `index.html` sha256 `fdaac876...` identical to the built image and the served page, served bundle `index-BuQ7JZPD.js`. All 44 other containers kept ID, StartedAt, restart count, status and image; only web changed. Live: `/` 200, `/api/ready` 200 (`version 25cabfb4`) and unauthenticated `POST /api/chat-framing/suggest` 401 (local and public); web log clean for 2 minutes. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/b31d0075 /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-25cabfb4 /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:b31d0075` image is retained.

## Release b31d0075 — 2026-10-02 (web: each chat as a small brain note, flags off)

### Services

- **Web:** [#751](https://github.com/sbstndalton/noevia/pull/751) (chat framing phase 6, closes [#742](https://github.com/sbstndalton/noevia/issues/742): each chat as a small brain note, `chat-brain.cjs`). Now `cowork-web:b31d0075` (previous `cowork-web:58b4bffb`), recreated alone; `readlink current` is `releases/b31d0075`, `COWORK_VERSION=b31d0075`. No flag was changed; the feature stays off.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Exact source `b31d0075` (squash of PR #751, tested head 455be68b, up to date with main, all CI green; squash-merged with `--match-head-commit`, branch deleted, no phantom deletions). `dist/` and `server/` were built from a `git archive` of that SHA (`npm ci` + `npm run build`, dependencies unchanged) and layered onto `cowork-web:58b4bffb` by hand, web only. Candidate checked with no network: `chat-brain`, `chat-framing` and `chat-vault-mirror` tests 51/51. Backup: `config/.env.bak.before-b31d0075`; no appdata backup run. Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`); all three preflight checks passed.

- **Verify:** web healthy, `RestartCount` 0, `index.html` sha256 `202f5a5b...` identical to the local build, `chat-brain.cjs` present in the image, served bundle `index-CZgxErvH.js` (in the local build). All 44 other containers kept ID, StartedAt, restart count and image; only web changed. `/` and `/api/ready` 200 locally and publicly; web log clean for 2 minutes. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/58b4bffb /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-b31d0075 /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:58b4bffb` image is retained.

## Release 58b4bffb — 2026-10-02 (web: per-user chat mirror into the Diary vault, inert)

### Services

- **Web:** [#748](https://github.com/sbstndalton/noevia/pull/748) (completes [#741](https://github.com/sbstndalton/noevia/issues/741) with #747: opt-in per-user mirror of chats into the Diary vault, `chat-vault-mirror.cjs`, `/api/chat-vault-mirror/preferences`; includes the reviewed trash-safety fix). Now `cowork-web:58b4bffb` (previous `cowork-web:23841302`), recreated alone; `readlink current` is `releases/58b4bffb`, `COWORK_VERSION=58b4bffb`. The mirror stays inert: it needs the `chatFraming` flag plus a per-user opt-in, and both are OFF; no flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Exact source `58b4bffb` (squash of PR #748, tested head 3ee31b5 = d46cfb3 updated onto main after #747, all CI re-run green; squash-merged with `--match-head-commit`). `dist/` and `server/` were built from a `git archive` of that SHA (`npm ci` + `npm run build`, dependencies unchanged) and layered onto `cowork-web:23841302` by hand, web only. Backup: `config/.env.bak.before-58b4bffb`; no appdata backup run. Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`); all three preflight checks passed.

- **Verify:** web healthy, `RestartCount` 0, `dist/version.json` `0.2.0+muqnwkyw`, `index.html` sha256 `77a03167...` identical to the local build, `chat-vault-mirror.cjs` present in the image. All 44 other containers kept ID, StartedAt, restart count, status and image; only web changed. Live: `/` 200, `/api/ready` 200 and unauthenticated `GET /api/chat-vault-mirror/preferences` 401 (local and public), served bundle `index-BKHnIpBQ.js` (in the local build); web log clean for 2 minutes with no `workspace-ops` calls. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/23841302 /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-58b4bffb /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:23841302` image is retained.

## Release 23841302 — 2026-10-02 (web: chat framing phase 5 organise, flag off)

### Services

- **Web:** [#747](https://github.com/sbstndalton/noevia/pull/747) (with #748 closes [#741](https://github.com/sbstndalton/noevia/issues/741): in-app chat organisation, `ChatLinks.tsx`). #748 is not merged and not part of this release. Now `cowork-web:23841302` (previous `cowork-web:e5cd0443`), recreated alone; `readlink current` is `releases/23841302`, `COWORK_VERSION=23841302`. The `chatFraming` and `framingReasoner` flags stay OFF; no flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Exact source `23841302` (squash of PR #747; tested head b85b4e0, branch updated onto main as 3af0c64 with an identical diff, all CI re-run green on the fresh base). `dist/` and `server/` were built from a `git archive` of that SHA (`npm ci` + `npm run build`) and layered onto `cowork-web:e5cd0443` by hand, web only. Backup: `config/.env.bak.before-23841302`; no appdata backup run. Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`); all three preflight checks passed.

- **Verify:** web healthy, `RestartCount` 0, `dist/version.json` `0.2.0+muqnne2u`, `index.html` sha256 `9085464e...` identical to the local build. All 44 other containers kept ID, StartedAt, restart count, status and image; only web changed. Live: `/` 200, `/api/ready` 200 (local and public), served bundle `index-DXwCEmWd.js` (in the local build); web log clean for 2 minutes. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/e5cd0443 /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-23841302 /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:e5cd0443` image is retained.

## Release e5cd0443 — 2026-10-02 (web: chat framing phase 4, flag off)

### Services

- **Web:** [#746](https://github.com/sbstndalton/noevia/pull/746) (closes [#740](https://github.com/sbstndalton/noevia/issues/740): task packet `task-packet.cjs` and framing reasoner `framing-reasoner.cjs`). Now `cowork-web:e5cd0443` (previous `cowork-web:fe6fb292`), recreated alone; `readlink current` is `releases/e5cd0443`, `COWORK_VERSION=e5cd0443`. The `chatFraming` and `framingReasoner` flags stay OFF; no flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Exact source `e5cd0443` (squash of PR #746, head 23eaec4, all CI green). `dist/` and `server/` were built from a `git archive` of that SHA (`npm ci` + `npm run build`) and layered onto `cowork-web:fe6fb292` by hand, web only. Backup: `config/.env.bak.before-e5cd0443`; no appdata backup run. Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (absolute `--env-file`); all three preflight checks passed.

- **Verify:** web healthy, `RestartCount` 0, `dist/version.json` `0.2.0+muqmpi8z`, `index.html` sha256 `364058a2...` identical to the local build, `task-packet.cjs` and `framing-reasoner.cjs` present in the image. All 44 other containers kept ID, StartedAt, restart count, status and image; only web changed. Live: `/` 200, `/api/ready` 200 (local and public), served bundle `index-ByRDLbtN.js` (in the local build); web log clean for 2 minutes. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/fe6fb292 /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-e5cd0443 /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:fe6fb292` image is retained.

## Release fe6fb292 — 2026-10-02 (web: chat framing phase 3, flag off)

### Services

- **Web:** [#745](https://github.com/sbstndalton/noevia/pull/745) (closes [#739](https://github.com/sbstndalton/noevia/issues/739): a confirmed frame steers the answer, `chat-frame-steering.cjs`). Now `cowork-web:fe6fb292` (previous `cowork-web:90390780`), recreated alone; `readlink current` is `releases/fe6fb292`, `COWORK_VERSION=fe6fb292`. The `chatFraming` flag stays OFF; no flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Exact source `fe6fb292` (squash of PR #745, head b9157e0, all CI green). `dist/` and `server/` were built from a `git archive` of that SHA (`npm ci` + `npm run build`) and layered onto `cowork-web:90390780` with the overlay Dockerfile steps by hand, web only. Backup: `config/.env.bak.before-fe6fb292`; no appdata backup run (it would stop containers). Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web` (run with the absolute `--env-file` path); all three preflight checks passed.

- **Verify:** web healthy, `RestartCount` 0, `dist/version.json` `0.2.0+muqm4tw7`, `index.html` sha256 `1f4ad879...` identical to the local build, `chat-frame-steering.cjs` present in the image. All 44 other containers kept ID, StartedAt, restart count and status; only web changed. Live: `/` 200, `/api/ready` 200, served bundle `index-DBzDG8eN.js`. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/90390780 /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-fe6fb292 /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:90390780` image is retained.

## Release 90390780 — 2026-10-02 (web: chat framing phase 2 confirm UI, flag off)

### Services

- **Web:** [#744](https://github.com/sbstndalton/noevia/pull/744) (closes [#738](https://github.com/sbstndalton/noevia/issues/738): frame confirm UI, `POST /api/chats/:id/move`, `/api/chat-framing/preferences`). Now `cowork-web:90390780` (previous `cowork-web:7635054`), recreated alone; `readlink current` is `releases/90390780`, `COWORK_VERSION=90390780`. The `chatFraming` flag stays OFF; no flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Exact source `90390780` (squash of PR #744, head b17944c, all CI green). `dist/` and `server/` were built from a `git archive` of that SHA (`npm ci` + `npm run build`) and layered onto `cowork-web:7635054` (17 layers) with the overlay Dockerfile steps by hand, web only. Backup: `config/.env.bak.before-90390780`; no appdata backup run (it would stop containers). Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web`; all three preflight checks passed.

- **Verify:** web healthy, `RestartCount` 0, `dist/version.json` `0.2.0+muqlizbx`, `index.html` sha256 `11840e8c...` identical to the local build, `chat-framing.cjs` present in the image. All 35 other running containers (sidecars and unrelated) kept ID, StartedAt and restart count; only web changed. Live: `/` 200, `/api/ready` 200, unauthenticated `POST /api/chats/x/move` 401 and `GET /api/chat-framing/preferences` 401, served bundle `index-g3lXclSp.js`. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/7635054 /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-90390780 /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:7635054` image is retained.

## Release 7635054 — 2026-10-02 (web: chat framing phase 1, flag off)

### Services

- **Web:** [#743](https://github.com/sbstndalton/noevia/pull/743) (closes [#737](https://github.com/sbstndalton/noevia/issues/737): frame data model and the `/api/chat-framing/suggest` route). Now `cowork-web:7635054` (previous `cowork-web:6d7ae96`), recreated alone; `readlink current` is `releases/7635054`, `COWORK_VERSION=7635054`. The `chatFraming` flag stays OFF; no flag was changed.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. `overlay-release.sh` was not used because it recreates diary and ocr.

Exact source `7635054` (squash of PR #743, head 0a0a80e, all CI green). The web `dist/` and `server/` were built locally from `git archive` of that SHA and layered onto `cowork-web:6d7ae96` (17 layers) with the overlay Dockerfile steps by hand, web only. Backup: `config/.env.bak.before-7635054`; no appdata backup run (it would stop containers). Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web`; all three preflight checks passed.

- **Verify:** web healthy, `RestartCount` 0, `dist/version.json` `0.2.0+muqkih4y`, `index.html` sha256 `63fa58b8...` identical to the local build, `chat-framing.cjs` present in the image. The 12 other containers checked (diary, ocr, llama, model-loader, docling, code-sandbox, code-verify, laya, embed, dav-tailscale, kiwix, cloudflared) kept ID, StartedAt and restart count. Live: `/` 200, `/api/ready` 200, unauthenticated `POST /api/chat-framing/suggest` 401, served bundle `index-FeAYKJ4d.js`. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/6d7ae96 /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-7635054 /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:6d7ae96` image is retained.

## Release 6d7ae96 — 2026-10-01 (web: Security hint hidden when the account can't connect)

### Services

- **Web:** [#736](https://github.com/sbstndalton/noevia/pull/736) (closes [#735](https://github.com/sbstndalton/noevia/issues/735): the Security "Connect a device" hint is hidden when the account can't connect, and the ineligible text is reworded). Now `cowork-web:6d7ae96` (previous `cowork-web:448531e`), recreated alone; `readlink current` is `releases/6d7ae96`, `COWORK_VERSION=6d7ae96`.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. Laya, llama, embed, kiwix and the dav-tailscale relay were not touched.

Exact source `6d7ae96` (CI green on PR #736). Built with `deploy/tools/build-web-release.sh` (stamp check passed). Backups: `config/.env.bak.before-6d7ae96`, `docker-compose.override.yml.bak.before-6d7ae96` and `docker-compose.yml.bak.before-6d7ae96` in the Compose Manager project directory. Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

- **Verify:** web healthy, `RestartCount` 0, `dist/version.json` is `6d7ae96`. The 11 other cowork containers kept ID, StartedAt and restart count (before/after lists in `state/nonweb.{before,after}-6d7ae96.txt`, identical). `https://noevia.daserver.work/` returned 200 and `/api/profile` 401. The served `index-l3TWrmjh.js` and `index-Dd9SpLmJ.css` exist in the container's `dist/assets`, and the JS contains "only works when your Diary is turned on". Web still listens on 127.0.0.1:8021 and 127.0.0.1:8031. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/448531e /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-6d7ae96 /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:448531e` image is retained.

## Release 448531e — 2026-10-01 (web: Connect a device)

### Services

- **Web:** [#734](https://github.com/sbstndalton/noevia/pull/734) (Connect a device: one flow for DAV file access, #733). Now `cowork-web:448531e` (previous `cowork-web:3c7e527`), recreated alone; `readlink current` is `releases/448531e`, `COWORK_VERSION=448531e`.
- **Diary, Model manager, Code sandbox (and code-verify), OCR, Docling:** no change.
- **Deploy/infra:** no change. Laya, llama, embed, kiwix and the dav-tailscale relay were not touched.

Exact source `448531e` (CI green). Built with `deploy/tools/build-web-release.sh` (stamp check passed). Backups: `config/.env.bak.before-448531e`, `docker-compose.override.yml.bak.before-448531e` and `docker-compose.yml.bak.before-448531e` in the Compose Manager project directory. Started alone with the guarded `up.sh -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

- **Verify:** web healthy, `RestartCount` 0, `dist/version.json` is `448531e`. The 11 other cowork containers kept ID, StartedAt and restart count (before/after lists in `state/nonweb.{before,after}-448531e.txt`). `https://noevia.daserver.work/` returned 200 and `/api/profile` 401. The served `index-DTWsQOrw.js` and `index-Dd9SpLmJ.css` exist in the container's `dist/assets`, and the JS contains "Connect a device". Web still listens on 127.0.0.1:8021 and 127.0.0.1:8031; the DAV relay answered on 100.70.173.74:8031 (HTTP 400, not 000). No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/3c7e527 /mnt/docker/appdata/cowork/current && cp -p /mnt/docker/appdata/cowork/config/.env.bak.before-448531e /mnt/docker/appdata/cowork/config/.env && bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. The `cowork-web:3c7e527` image is retained.

## Release c526350 — 2026-10-01 (code-sandbox image for code-verify, restart-alert tool)

### Services

- **Code verify:** [#726](https://github.com/sbstndalton/noevia/pull/726) (the startup sweep lists `/verify/run` through the test uid, so the `EACCES` line is gone). Only `cowork-code-verify-1` was recreated, on image `cowork-code-sandbox:pi-0.87.0-c526350` (`sha256:7d62a3b8efbac76c43f52b5aa0135d7ec64b112d5086f4c080b45931e5808820`), built from `services/code-sandbox` with the pi 0.87.0 build args and `--network host`. The image's `verifier.cjs` matches the c526350 source, and the global npm tree and git 2.39.5 are unchanged.
- **Code sandbox:** not recreated and still running `pi-0.87.0-3c7e527` (`bd58b3d5e66f`). `.env` `CODE_SANDBOX_VERSION` is now `pi-0.87.0-c526350`, so the next sandbox recreate picks up the new image; the only code change since 3c7e527 is `verifier.cjs`.
- **Tooling:** `/mnt/docker/appdata/cowork/tools/sidecar-restart-alert.sh` replaced by the c526350 version (SHA-256 prefix `e1b23472c9ad1e45`). One-shot services (default `code-verify`) no longer alert for same-container, same-image, exit-0 restarts. The cron entry is unchanged.
- **Web, model-loader, Diary, Docling, Laya, OCR, llama, embed:** no change.

Exact source `c526350` (PR CI green). Backups: `config/.env.bak.before-c526350`, `tools/sidecar-restart-alert.sh.bak.before-c526350`. Started alone with the guarded `up.sh --profile code -- -d --no-build --no-deps --wait code-verify`.

- **Verify:** `code-verify` came up healthy and its startup log has no `EACCES` line. A probe from web (`reachability-probe`, valid nonce) got `not_configured` with the nonce echoed, and the container restarted. Two earlier malformed probes (wrong request shape) were refused and also restarted it, so `RestartCount` went 0 → 4 over four probes (two malformed, two valid, the last one after `--ack`).
- **Restart alert:** after `--ack` and the last probe, a `--dry-run` and a real run were both silent.
- **Snapshot:** 46 containers before and after; the only difference is code-verify (`671bdab4c6c7` → `c54a91c132bd`, new image). All others keep ID, StartedAt and restart count, including the `sg716-*` evaluation containers and `cowork-llama-1`. No model run, tune or Diary access.

Rollback: `cp -p config/.env.bak.before-c526350 config/.env`, then `bash tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env --profile code -- -d --no-build --no-deps --wait code-verify`; restore the alert script from `tools/sidecar-restart-alert.sh.bak.before-c526350` and run it with `--ack`. The previous image `pi-0.87.0-3c7e527` is retained.

## Release 3c7e527 — 2026-10-01 (web, model-loader, code-sandbox, new code-verify)

### Services

- **Web:** [#717](https://github.com/sbstndalton/noevia/pull/717) (Code task pipeline UI, #706), [#718](https://github.com/sbstndalton/noevia/pull/718) (selector: reasoning off, JSON-constrained call, #716), [#721](https://github.com/sbstndalton/noevia/pull/721) (embed parity tool, #720), [#724](https://github.com/sbstndalton/noevia/pull/724) (no prompt cache in embed/rerank estimates, #723). The web side of #710 is now wired to a verifier: `CODE_VERIFY_ENDPOINT` is set. Image `cowork-web:3c7e527` (`sha256:5d4f81fed9eb2d174de9221b0e091dfc7daeec643f6aada1fbf0bb62cf637cbe`).
- **Model manager:** [#724](https://github.com/sbstndalton/noevia/pull/724) (the migration writes `cache-ram = 0` for embedding and reranking sections). Image `cowork-model-loader:3c7e527` (`sha256:f7a38470ceef2278e1b60ebd0a92b94fa4b500b653209898eae4d5aad8c4360a`). It is an overlay `FROM cowork-model-loader:9debec6` with `app/` replaced; `requirements.txt` and the Dockerfile are unchanged.
- **Code sandbox:** [#710](https://github.com/sbstndalton/noevia/pull/710) (`verifier.cjs` and Dockerfile socket/tmpfs directories) and [#711](https://github.com/sbstndalton/noevia/pull/711) (`pi-acp-bridge.cjs` passes noevia's refusal reason to pi). Image `cowork-code-sandbox:pi-0.87.0-3c7e527` (`sha256:a3b660854b0f1c319b67b8e0dd7d0f4f46d51f9a4735c4b8e4ffbf030d20b129`), built from `services/code-sandbox` with the pi 0.87.0 build args. The apt/npm layer was rebuilt, but the global npm tree (341 package.json files with identical versions) and git 2.39.5 match `pi-0.87.0-9b532a8`. Deployed bridge SHA-256 `bb4b90ee99ed4b5193e66682a3697856457bccd55f758dc31d768632f0721f9b`.
- **Code verify (new):** `cowork-code-verify-1` runs the same sandbox image with `node verifier.cjs`.
- **Diary, Docling, Laya, OCR:** no change (`cowork-diary:9debec6`, `cowork-docling:9debec6`, `cowork-laya:0.3.5-noevia2`, `cowork-ocr:5004b50`).
- **Deploy/infra:**
  - Live `docker-compose.override.yml` gains, from `deploy/examples/code-sandbox.override.yml`, the `code-verify` service (profile `code`), the `code-verify-socket` volume, web's `code-verify-socket:/run/noevia-verify` mount and web's `CODE_VERIFY_ENDPOINT`. That is 40 added lines and none removed.
  - `.env`: `MODEL_MANAGER_VERSION`, `CODE_SANDBOX_VERSION` and `COWORK_VERSION` are bumped. `CODE_VERIFY` (empty) and `CODE_VERIFY_ENDPOINT` are added. `CODE_REPOS_GID` is not set, so it defaults to 1005.
  - The source repository `scratch` is now group 1005 (`chgrp -R 1005`, `chmod -R g+rX`). No "other" bits changed.

Exact source `3c7e5277468d50329c20efa7baa70ba51ba4779d` (main CI green, including the `sudo` `code-verify-root.test.cjs` run from #710). The `git archive` of the fresh clone has SHA-256 `119ded8af61ab4ddfed69208c171481fe397908edded4e90098a436e9d4e3efd`, matched on the server, and was extracted to `releases/3c7e527`. The release started after appdata backup `ab_20261001_041001` (plugin log `DONE` at 04:10:18) with all containers back up; no new backup was taken. Backups: `config/.env.bak.before-3c7e527`, `docker-compose.yml.bak.before-3c7e527`, `docker-compose.override.yml.bak.before-3c7e527`. Each service was started alone with the guarded `up.sh ... --no-build --no-deps --wait` (with `--profile code` for the Code services), in this order: model-loader, code-sandbox, code-verify, web.

- **Model manager:** no model was loaded. The start-up migration logged `set an explicit bounded cache-ram in 2 section(s): nomic-embed-text-v1, qwen3-reranker-0.6b-q8_0`. `models.ini` went from `5bd15b66…6173` to `4397b3b32ce00566a8b1fb7154a5d151248a0676640d04a152804cafb18cced5`; the pre-write copy is `models.ini.bak-20261001-084609`. Parsed section by section, the only change is `cache-ram = 0` added to those two sections; the writer also reordered lines and dropped blank lines. The app's `read_ini` reads it (8 sections). Healthy, `/api/v1/health` 200, zero restarts.
- **Code sandbox:** before the recreate, the sandbox ran only `node supervisor.cjs`, with no harness child and no established connection, so no Code task was running. After the recreate: read-only root, `cap_drop ALL`, uid 1000, only on `cowork_code`, listening on 8030, zero restarts.
- **Code verify:**
  - Container settings: `network_mode none` (only `lo`), read-only root, user `0:0` with CapEff `0xc0` (SETUID/SETGID only), NoNewPrivs 1, `group_add` 1005, pids 256, 2 GiB, 2 CPUs, `restart: always`. It mounts workspaces read-only and the socket volume. git runs as `1002:1005` and the test command as `1003:1003`. The socket directory is `root:root 0770` and the socket is `0660`.
  - Log: `listening on /run/noevia-verify/verify.sock (one request) ... 0 repositories configured`.
  - **`CODE_VERIFY` is empty.** `scratch`, the only entry in `CODE_REPOS`, has no `package.json` test script, pytest setup or Makefile; its test is a bare `node test.js`. So no repository has a command, and the pipeline would stop at verify (its flags are off).
- **Synthetic verify:** a throwaway repository `repos/verify-synthetic-3c7e527` (one `test.sh`, group 1005) was checked by a throwaway candidate verifier with the same image and hardening, its own socket volume and `CODE_VERIFY=synthverify|sh test.sh`. The result: `ok:true`, exit 0, nonce echoed, 49 ms. The test ran as uid/gid 1003, the copy was owned by 1002 and read-only to the test, `$TMPDIR` was writable, and the verifier then served its one request and exited. The candidate, its volume and the repository were removed.
- **Web:**
  - Built with `deploy/tools/build-web-release.sh`; the in-build tests and build step passed and the stamp was verified. Standalone loopback candidate: `/` 200, `/api/profile` 401, `version.json` `3c7e527`, 82 dist files.
  - Live: healthy, zero restarts. Public `/` 200, `/api/profile` 401, `/version.json` `3c7e527`. Served `index-Cya8YG3M.js`, `index-Cds-u3b1.css`, `theme.js`, `manifest.webmanifest`, `icon.svg`, `apple-touch-icon.png` and `index.html` are byte-identical to the image `dist`.
  - Mounts: `/llamacpp-config` RW=false, and `/run/noevia-verify` is mounted (the sandbox does not mount it). Web has no `CODE_VERIFY`. The web log shows no errors and no `[inference-budget]` line.
- **Read-only checks through web's modules** (DB opened read-only):
  - Decision deadline is 2000 ms; the budget is 16 GiB.
  - Estimates: `nomic-embed-text-v1` 1.27 GiB (model 0.14 + KV 0.07 + 1 GiB runtime, cache-ram 0) and `qwen3-reranker-0.6b-q8_0` 2.59 GiB (model 0.6 + KV 0.88 + 1 GiB, cache-ram 0). Before #723 each also counted 8 GiB of prompt cache. Chat estimates are unchanged (10.0, 11.15, 9.76, 7.42, 8.5 GiB).
  - `createCodeVerify().available()` is true. One raw probe from web to the live socket (`repo: reachability-probe`) got `not_configured` with the nonce echoed, and the verifier restarted as designed (code-verify RestartCount 1). `sidecar-restart-alert.sh --ack` was run afterwards.

Before/after snapshot of all containers (43 → 44): the only differences are model-loader `d7dda8e7ef3f` → `6a5ac490465a`, code-sandbox `563d1201582b` → `bd58b3d5e66f`, web `8a45208a9b65` → `b7826605665c`, and the new code-verify `671bdab4c6c7`. Llama, embed, diary, docling, laya, ocr, kiwix and every non-noevia container keep the same ID, StartedAt and restart count. There was no model run or tune and no Diary access.

Known follow-ups:
- Every verification restarts `code-verify` by design, so the sidecar restart alert will report each one.
- At each start the verifier logs `could not read /verify/run to sweep it: EACCES`. The server lacks DAC_OVERRIDE and `/verify/run` is 1003's 0700 tmpfs; it is fresh on every restart, so this is harmless.

Rollback, per service. Set `ENV=/mnt/docker/appdata/cowork/config/.env` and `UP="bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file $ENV --profile code -- -d --no-build --no-deps --wait --wait-timeout 180"`, and run the `cp` commands in the Compose Manager project directory. Previous images are retained.
- **Web:** `ln -sfn /mnt/docker/appdata/cowork/releases/9debec6 /mnt/docker/appdata/cowork/current`, then `sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=9debec6/' $ENV` and `$UP web`.
- **Code verify:** `docker compose --env-file $ENV --profile code rm -sf code-verify`, then `cp -p docker-compose.override.yml.bak.before-3c7e527 docker-compose.override.yml`, delete the `CODE_VERIFY` and `CODE_VERIFY_ENDPOINT` lines from `$ENV`, and run `$UP web` to drop the socket mount. Optionally remove the `cowork_code-verify-socket` volume.
- **Code sandbox:** `sed -i 's/^CODE_SANDBOX_VERSION=.*/CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8/' $ENV`, then `$UP code-sandbox`. This ends any running Code task. The repository group change can stay; to undo it, use `releases/3c7e527/.deploy-evidence/scratch-perms-before.txt` (the group was 1000).
- **Model manager:** `sed -i 's/^MODEL_MANAGER_VERSION=.*/MODEL_MANAGER_VERSION=9debec6/' $ENV`, then `$UP model-loader`. The old code accepts `cache-ram = 0`; the pre-write `models.ini` is `models.ini.bak-20261001-084609`.

## Diary overlay 9debec6 — 2026-10-01 (Diary embeds through the `embed` sidecar, #720)

### Services

- **Diary:** [#709](https://github.com/sbstndalton/noevia/pull/709) (`LLM_EMBED_BASE_URL`, #697) — `cowork-diary:9debec6`, image `sha256:8775aed1b6b7d63e2b9b858fded3fe90c3bec654cfdcd52da2e51ac776aae53e`, built by `deploy/examples/diary-overlay.sh 9debec6` (`FROM cowork-diary:f6444b4`, `agent/` replaced). `services/diary/agent` in `9debec6` is identical to main `be794ca`. Since `f6444b4`, `requirements.txt` only lost its test-only packages (#538) and the Dockerfile is unchanged.
- **Web, Model manager, Docling, Laya, OCR, Code sandbox:** no change.
- **Deploy/infra:** live `docker-compose.override.yml` gains `diary: environment: LLM_EMBED_BASE_URL: http://embed:8080/v1` (backup `docker-compose.override.yml.bak.before-720`). The rendered Compose config differs from the backup by exactly that one line. `.env`: `DIARY_VERSION` `f6444b4` → `9debec6` (backup `config/.env.bak.before-diary-9debec6`).

**Parity (#720).** The single-string check of release 9debec6 gave cosine 0.99887, below its 0.999 threshold. The owner delegated the decision, and the broader sample was run with the multi-string `tools/embed-parity-check.cjs` ([#721](https://github.com/sbstndalton/noevia/pull/721)). Before running it, the router had no model loaded. The sample was 40 synthetic documents and 10 synthetic queries, no user data. Results for the router's `nomic-embed-text-v1` (Vulkan) against the `embed` sidecar (CPU, same GGUF, `--pooling mean`): min cosine 0.99863, median 0.99909, mean 0.99913, max 0.99962. Mean overlap@5 was 0.96: 8 of the 10 queries had identical top 5, and the other 2 differed by one document. The rule (min ≥ 0.997, overlap@5 ≥ 0.9) passes, so the vectors are the same model up to float noise and the existing Diary index stays valid without re-embedding. `nomic-embed-text-v1` was unloaded through the router afterwards.

**Deploy.** `diary-overlay.sh` took appdata backup `ab_20261001_024731` (02:47 server time, about 20 s, verified). That backup stopped and restarted web, so web is the same container `8a45208a9b65` with a new StartedAt (06:47:45Z) and zero restarts. The script's candidate imports passed. Diary was recreated alone with the guarded `up.sh ... --no-build --no-deps --wait`; it was healthy and `/api/health` through web returned 200. After the override edit Diary was recreated alone a second time: healthy, zero restarts, container `721fb8e0f26c`.

**Verification.** Diary's own `LLMClient` was built from its live config, without opening the journal or the storage backend. Its embedding client points at `http://embed:8080/v1/`, separate from the engine client, and a synthetic string returned 768 dimensions. A second synthetic call moved the sidecar's slot task id from 90 to 93. Afterwards the router reports `nomic-embed-text-v1` unloaded, and the Diary log has no errors. Llama, model-loader, docling, embed, laya, ocr, code-sandbox and kiwix keep the same IDs and start times. No model run, tune or private Diary access.

Rollback: `cp config/.env.bak.before-diary-9debec6 config/.env` (`DIARY_VERSION=f6444b4`; that image is also tagged `cowork-diary:rollback-before-diary-overlay`), `cp docker-compose.override.yml.bak.before-720 docker-compose.override.yml`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 diary`.

## Release 9debec6 — 2026-10-01 (Docling native-text fallback, one model within a 16 GiB inference budget, web)

### Services

- **Docling:** [#714](https://github.com/sbstndalton/noevia/pull/714) (native-text fallback, #700) — `cowork-docling:9debec6`, image `sha256:52493948a3c72ad5acaf6c256f778f0d2244e7724d18e19045718c9db3819af5`. Deployed before web.
- **Model manager:** [#709](https://github.com/sbstndalton/noevia/pull/709) (cache-ram bound and start-up migration, budget-sized autoconfig, #697) — `cowork-model-loader:9debec6`, image `sha256:7093d0ed85076cfb92b141128e7463cde8df5ed382742bad72b9a5b09e876c04`, built as an overlay (`FROM cowork-model-loader:381760c`, `app/` replaced; `requirements.txt` and Dockerfile unchanged).
- **Web:** [#709](https://github.com/sbstndalton/noevia/pull/709) (inference budget, one resident model, reranker refused on the engine), [#714](https://github.com/sbstndalton/noevia/pull/714) (partial status for native-fallback pages), #694, #695/#696, #699 (seasonal logo/favicon), and behind default-off flags #708, #711, #712, #713, #715; #710's web side (inert, no code-verify container) — `cowork-web:9debec6`, image `sha256:95783d72f36aadb732c5ccd476bc55e835bf53cbe1b5d5e01245cd8806e6c9cd`.
- **Diary:** no change — stays `cowork-diary:f6444b4`. #709's `LLM_EMBED_BASE_URL` support is merged, not yet deployed (see the parity result below).
- **Laya, OCR, Code sandbox:** no change (`cowork-laya:0.3.5-noevia2`, `cowork-ocr:5004b50`, `cowork-code-sandbox:pi-0.87.0-9b532a8`). The code-verify container was not deployed.
- **Deploy/infra:** live `docker-compose.override.yml`: llama `--models-max 2` → `1`; web `NOEVIA_FEATURE_RAG_RERANK` `"true"` → `"false"` and `RERANK_BASE_URL` removed. No Diary or embed change. `.env`: `DOCLING_VERSION`, `MODEL_MANAGER_VERSION` and `COWORK_VERSION` set to `9debec6`.

Exact source `9debec6fb6d591d0821e5c17705480e07a02664c` (main CI green), `git archive` of a fresh clone (SHA-256 `78ae835513949c809fea6b1cb5dc30e6349ccc36c6a7e3442e1333dfb49d3a51`, matched on the server), to `releases/9debec6`. #717 and #718 were merged after this SHA and are not in this release. The last appdata backup before the release was `ab_20260930_041001`; no new backup was started. Backups: `config/.env.bak.before-9debec6`, `docker-compose.yml.bak.before-9debec6`, `docker-compose.override.yml.bak.before-9debec6`. Each service was recreated alone with the guarded `up.sh ... --no-build --no-deps --wait`, in this order: docling, model-loader, llama, web.

- **Docling:** all dependency and model layers came from cache, and the first 10 layers are identical to `2026-09-21`; only the final `COPY` differs. Synthetic selftest, first in a throwaway candidate with `--network none` and then in `cowork-docling-1`: `synthetic-picture-text.pdf` page 1 `native` with the widget-audit text (not `blank`), `synthetic-blank.pdf` `blank`. Healthy, zero restarts.
- **Model manager:** start-up migration logged nothing because all five chat sections already had `cache-ram = 1024` (the 2026-10-01 ops change on #697). `models.ini` is unchanged at `5bd15b66c852affae28976a3685a51551c97b53be2cae359106987fa399b6173`. `/api/v1/health`, `/sections` (8 sections) and `/backends` all return 200, and `/backends` now reports `mem_anon_gb`. Healthy, zero restarts.
- **Embedding parity (`tools/embed-parity-check.cjs`, from the release directory through `cowork-web-1`): FAILED.** Cosine 0.99887 between the router's `nomic-embed-text-v1` (Vulkan) and the `embed` sidecar (CPU, `--pooling mean`), 768 dimensions each, against the 0.999 threshold. So Diary was not switched and its overlay was not shipped. Diary still embeds through the engine, and under `--models-max 1` a Diary embedding request evicts the resident chat model. The `embed` command already had `--pooling mean`, so it was not changed.
- **Llama:** recreated with no model loaded; `nomic-embed-text-v1`, which the parity check had loaded, was unloaded first through the router. Args show `--models-max 1`. Still on `cowork_code`, `cowork_default`, `cowork_models` and `nextcloud-aio`. Healthy, zero restarts.
- **Web:** built with `deploy/tools/build-web-release.sh` (in-build tests and build passed on the first attempt, stamp verified). Standalone candidate on a loopback port with no production mounts: `/` 200, `/api/profile` 401, `version.json` `9debec6`, 82 dist files. Live checks:
  - Healthy, zero restarts. Public `/` 200, `/api/profile` 401, `/version.json` `9debec6`.
  - Served `index-CysxSA0D.js`, `index-DPcIRKIs.css`, `theme.js`, `manifest.webmanifest`, `icon.svg?v=9debec6` and `apple-touch-icon.png?v=9debec6` are byte-identical to the image `dist`.
  - `/llamacpp-config` RW=false. `NOEVIA_FEATURE_RAG_RERANK=false`, and `RERANK_BASE_URL` is absent.
  - Web log has no errors and no `[inference-budget]` line.
- **Budget and decision deadline**, read-only through the settings modules (DB opened read-only):
  - Decision deadline is 2000 ms.
  - Inference budget is 16 GiB (source `deployment`, range 2–25 GiB, host 29 GiB).
  - Chat-model estimates with no model loaded: Qwen3.5-4B 10.0, Qwen3.5-9B 11.15, gemma-3-12b 9.76, gemma-4-E2B 7.42, gemma-4-E4B 8.5 GiB. All fit within 16 GiB.

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only differences are the four recreated containers. Docling `f1a6ff85ffe0` → `96efde0f9a1a`, model-loader `d538e06f3613` → `d7dda8e7ef3f`, llama `c5af278a1b3d` → `ae3235547379`, web `573fe84af9b3` → `8a45208a9b65`. Diary, embed, laya, ocr, code-sandbox, kiwix and every non-noevia container are identical. No model run, tune or Diary access beyond the parity check's single synthetic embedding.

Rollback, per service. `ENV=/mnt/docker/appdata/cowork/config/.env`; `UP="bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file $ENV -- -d --no-build --no-deps --wait --wait-timeout 180"`. Previous images are retained.
- Web: `ln -sfn /mnt/docker/appdata/cowork/releases/c70d1a9 /mnt/docker/appdata/cowork/current`, `sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=c70d1a9/' $ENV`, then `$UP web`. Roll back docling as well, or documents re-read meanwhile keep the new cache key.
- Llama and the web rerank setting: `cp -p docker-compose.override.yml.bak.before-9debec6 docker-compose.override.yml` in the Compose Manager project, then, with no model loaded, `$UP llama`, and `$UP web` for the rerank variables.
- Model-loader: `sed -i 's/^MODEL_MANAGER_VERSION=.*/MODEL_MANAGER_VERSION=381760c/' $ENV`, then `$UP model-loader`.
- Docling: `sed -i 's/^DOCLING_VERSION=.*/DOCLING_VERSION=2026-09-21/' $ENV`, then `$UP docling`.

## Release web c70d1a9 — 2026-09-30 (auto-tune relative quality gate, Tune panel fixes)

### Services

- **Web:** [#691](https://github.com/sbstndalton/noevia/pull/691) (auto-tune judges settings against the model's own baseline; Tune panel status and counts fixed, #328); image `cowork-web:c70d1a9`.
- **Laya, Diary, Model manager, Code sandbox, OCR, Docling:** no change (Laya stays `cowork-laya:0.3.5-noevia2`).
- **Deploy/infra:** no Compose change; `.env` only `COWORK_VERSION=c70d1a9`.

Exact source `c70d1a9` (CI green on that commit), `git archive` of a fresh clone, extracted to `releases/c70d1a9`. Built with `deploy/tools/build-web-release.sh` (first attempt, no hang; stamped `c70d1a9`) and started with the guarded web-only `up.sh ... --no-build --no-deps --wait web`. Web healthy, zero restarts, `/` 200 locally and publicly, `/api/profile` 401, `/llamacpp-config` RW=false, public `index-DlCSqcVV.js` and `index-CHiiGa9G.css` byte-identical to the container. Every other container kept its ID, `StartedAt` and restart count. Stored decision deadline read back read-only through the settings module: 2000 ms. No model run, tune or Diary access.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/53da4ce /mnt/docker/appdata/cowork/current`, restore `config/.env.bak.before-c70d1a9` (or set `COWORK_VERSION=53da4ce`), then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web` (image `cowork-web:53da4ce` retained).

## Release 53da4ce — 2026-09-30 (web + Laya: configurable decision deadline)

### Services

- **Web:** [#690](https://github.com/sbstndalton/noevia/pull/690) (web decision deadline cap raised to 2000 ms); image `cowork-web:53da4ce`.
- **Laya:** configurable worker deadline `LAYA_DECISION_TIMEOUT_S` (0.5 to 2.0 s, default 1.3); image `cowork-laya:0.3.5-noevia2`, set to 1.8 s.
- **Diary, Model manager, Code sandbox, OCR, Docling:** no change.
- **Deploy/infra:** live Compose `laya` service gains `LAYA_DECISION_TIMEOUT_S: ${LAYA_DECISION_TIMEOUT_S:-1.3}`, new image tag and build context `laya/noevia2-53da4ce`; `.env` gains `LAYA_DECISION_TIMEOUT_S=1.8` and `COWORK_VERSION=53da4ce`.

Exact source `53da4cee498d4b973024c332935aca9540b00175` (CI green on that commit), `git archive` of a fresh clone, extracted to `releases/53da4ce`. The running Laya was actually `cowork-laya:0.3.5-recovery-2ffd153` (the worker-recovery build), not `noevia1`; `noevia2` uses the same pattern (`FROM cowork-laya:0.3.5-noevia1` plus `services/laya/server.py` from the release), so dependencies and model files are unchanged and the recovery behaviour is kept. Laya was recreated alone with the guarded `up.sh --profile laya --no-build --no-deps --wait laya`: healthy, zero restarts, `/health` 200, no `LAYA_DECISION_TIMEOUT_S` warning in its log (the service logs only on a refused value), `LAYA_DECISION_TIMEOUT_S=1.8` present in the container environment.

Web was built with `deploy/tools/build-web-release.sh` (first attempt hung in the in-build Vite test `request-cache-cap.test.cjs` for 27 minutes on an I/O-loaded host and was killed before any cutover; the rerun passed) and started with the guarded web-only `up.sh`. Web healthy, zero restarts, `/` 200, `/api/profile` 401, `/llamacpp-config` RW=false, served `index-*.js` and `index-CHiiGa9G.css` byte-identical to the container. Every other container kept its ID, `StartedAt` and restart count.

Web decision deadline: stored `decision:configuration` changed from 1500 to 2000 ms (URL unchanged) through `createDecisionSettings().save` against the app's own settings store. The running process caches the value at startup, so web was restarted once afterwards and reads back 2000. Zero supervise records since the restart at the time of writing.

Rollback: Laya: restore `docker-compose.yml` from `docker-compose.yml.bak.before-53da4ce` in the Compose Manager project, remove `LAYA_DECISION_TIMEOUT_S` from `.env` (or restore `.env.bak.before-53da4ce`), then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env --profile laya -- -d --no-build --no-deps --wait laya` (image `cowork-laya:0.3.5-recovery-2ffd153` retained). Web: `ln -sfn /mnt/docker/appdata/cowork/releases/2c1aee7 /mnt/docker/appdata/cowork/current`, set `COWORK_VERSION=2c1aee7`, same `up.sh` with `web`; to restore the old web deadline store `timeoutMs` 1500 the same way and restart web.

## Release web 2c1aee7 — 2026-09-30 (Create-project dialog files stored in connected storage)

### Services

- **Web:** [#688](https://github.com/sbstndalton/noevia/pull/688) (fixes #687: files added in the Create-project dialog are stored in connected storage; legacy dialog files move to the project folder on the first approved edit, bound to the storage account) — `cowork-web:2c1aee7`, image `sha256:14d2ada5ac8ab0a7a06f7c3f194f1bb95af6266e8dc51d7535e17426c12bc3a1`.
- **Diary, Model manager, Code sandbox, OCR, Docling:** no change.
- **Deploy/infra:** no compose, override or `.env` key change.

Exact source `2c1aee79436f1f8140b4f015345516820dfe71f0`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `488ce821357c739a4714c6fe8bd0e49b96bb19655b4ed434e0fe30e6c5602d48`, matched on the server), to `releases/2c1aee7`. Main CI on `2c1aee7` was green before cutover. Web was built with `deploy/tools/build-web-release.sh 2c1aee7 apps/web` (stamp verified). `COWORK_VERSION` set to `2c1aee7` (`.env.bak.before-2c1aee7` kept).

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, targeting `web` only.

Checks: web healthy, zero restarts; zero error markers in web logs; `/llamacpp-config` RW=false; public root 200, `/api/profile` 401; the served `index-D3jigXrH.js` and `index-CHiiGa9G.css` are byte-identical to the image `dist`. Before/after snapshot of all 34 running containers (id, StartedAt, restart count): the only difference is the recreated web container (started 2026-09-30T10:18:19Z). Snapshots kept as `snap-before-2c1aee7.txt` / `snap-after-2c1aee7.txt`; older `.snap-*-92dfd2a` and `snap/*b4bed07*` files removed.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/92dfd2a /mnt/docker/appdata/cowork/current`, restore `.env` from `.env.bak.before-2c1aee7` (or set `COWORK_VERSION=92dfd2a`), then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. Previous images are retained.

---

## Release web 92dfd2a — 2026-09-30 (Auto-tune link in Advanced mode, System-One gate fits Laya limits, reload mid-reply keeps the turn)

### Services

- **Web:** [#683](https://github.com/sbstndalton/noevia/pull/683) (fixes #680: Go to Auto-tune works in Advanced mode), [#685](https://github.com/sbstndalton/noevia/pull/685) (fixes #682: System-One tool gate fits Laya's option limits; fallback `cause` codes in decision logs; "unsupported" status), [#684](https://github.com/sbstndalton/noevia/pull/684) (fixes #679: reload mid-reply keeps the turn; the server appends an interrupted reply to the chat history file on disconnect) — `cowork-web:92dfd2a`, image `sha256:0bc9061c28a0bf8b6030d6bb5770cff3b1dec3fcab54185be18f54e0e6d67e09`.
- **Diary, Model manager, Code sandbox, OCR, Docling:** no change.
- **Deploy/infra:** no compose, override or `.env` key change.

Exact source `92dfd2af56947c0aad314230c8c22c1d0e6287dd`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `5bf46b606d14b3eb3c259a98f9c876a7467286c91fd1d762c70a1bd3fa3d3622`, matched on the server), to `releases/92dfd2a`. Main CI on `92dfd2a` was green before cutover. Web was built with `deploy/tools/build-web-release.sh 92dfd2a apps/web` (stamp verified). `COWORK_VERSION` set to `92dfd2a` (`.env.bak.before-92dfd2a` kept).

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, targeting `web` only.

Checks: web healthy, zero restarts; zero error markers and no `[system-one]` lines in web logs; `/llamacpp-config` RW=false; public root 200, `/api/profile` 401; the served `index-JW8NVv0e.js` and `index-CHiiGa9G.css` are byte-identical to the image `dist`. Before/after snapshot of all 34 running containers (id, StartedAt, restart count, image): the only difference is the recreated web container (started 2026-09-30T09:43:46Z). `system-one-decisions.jsonl` had no records appended since cutover (no `cause` records yet); the new `cause` field is not yet exercised live.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/b4bed07 /mnt/docker/appdata/cowork/current`, restore `.env` from `.env.bak.before-92dfd2a` (or set `COWORK_VERSION=b4bed07`), then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. Previous images are retained.

---

## Release web b4bed07 — 2026-09-30 (provider capabilities are data, roles renamed Planner/Executor/Laya/Auditor, plannerReview flag)

### Services

- **Web:** [#676](https://github.com/sbstndalton/noevia/pull/676) (fixes #675: provider capabilities are data, no vendor host or model literals in `reasoning-effort.cjs`), [#678](https://github.com/sbstndalton/noevia/pull/678) (roles renamed Planner/Executor/Laya/Auditor; feature flag `astraReview` renamed `plannerReview` with one-release back-compat: a stored DB key is copied on boot, `NOEVIA_FEATURE_ASTRA_REVIEW` env fallback, API alias) — `cowork-web:b4bed07`, image `sha256:73ce1c622a109af64901bd6ea627f7ef6c58eaf6a583b8858e28c2d447eed4fa`.
- **Diary, Model manager, Code sandbox, OCR, Docling:** no change.
- **Deploy/infra:** no compose or override change.

Exact source `b4bed07d4b217ce51f6e5a4c6c71fb047cb3e194`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `2527bab6065aa451f203a36270abf30ebefaa2a4cbb74084410207b6e02c124c`, matched on the server), to `releases/b4bed07`. Main CI on `b4bed07` was green before cutover. Web was built with `deploy/tools/build-web-release.sh b4bed07 apps/web` (stamp verified). `.env` did not set `NOEVIA_FEATURE_ASTRA_REVIEW`, so no `NOEVIA_FEATURE_PLANNER_REVIEW` line was added. `COWORK_VERSION` set to `b4bed07` (`.env.bak.before-b4bed07` kept).

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, targeting `web` only.

Checks: web healthy, zero restarts; no `[features]` lines and no errors in web logs (no legacy key was stored, so no migration line); `/llamacpp-config` RW=false; public root 200, `/api/profile` 401; the served `index-CeEP-Mhh.js` and `index-CHiiGa9G.css` are byte-identical to the image `dist`; the features registry in the container lists `plannerReview` and no `astraReview`. Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only difference is the recreated web container (started 2026-09-30T08:45:34Z).

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/b6fda27 /mnt/docker/appdata/cowork/current`, restore `.env` from `.env.bak.before-b4bed07` (or set `COWORK_VERSION=b6fda27`), then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. Previous images are retained.

---

## Release web b6fda27 — 2026-09-29 (model-loader is the models.ini writer, read-only preset mount, declined-write note, auto-tune arithmetic replies, Diary retry records)

### Services

- **Web:** [#669](https://github.com/sbstndalton/noevia/pull/669) (fixes #668: localized tok/s units in Models Benchmarks), [#670](https://github.com/sbstndalton/noevia/pull/670) (fixes #664: Diary retries keep applied-write records), [#672](https://github.com/sbstndalton/noevia/pull/672) (fixes #328: auto-tune shows the mismatched answer and accepts "a - b = n" replies), [#673](https://github.com/sbstndalton/noevia/pull/673) (fixes #269: model-loader is the default models.ini writer and web mounts the preset directory read-only), [#674](https://github.com/sbstndalton/noevia/pull/674) (fixes #666, #667: declined write ends the reply with a fixed note, text-less replies keep Regenerate) — `cowork-web:b6fda27`, image `sha256:c5d5cf73cd50d17822623c3ee35789042ce3396bfb19b7c336c854c673a66082`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:381760c`. No `services/` diff from `4dc8ccf`, so no model-loader image was built.
- **Code sandbox, OCR, Docling:** no change.
- **Deploy/infra:** one edit to the live Compose Manager override (#269), see below.

Exact source `b6fda2728bbe90176a79f9d42439aa0d732087fc`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `049147c6b14935184a9a0d5a8145ba67b7c188861d3e8e6aafa645d03dd74964`, matched on the server), to `releases/b6fda27`. Main CI on `b6fda27` was green before cutover. Web was built with `deploy/tools/build-web-release.sh b6fda27 apps/web` (stamp verified).

Override edit (#269): in the web service of `/boot/config/plugins/compose.manager/projects/Cowork/docker-compose.override.yml`, `MODELS_INI_WRITER` default changed from `web` to `model-loader` and the `/llamacpp-config` mount gained `:ro`. Only those two lines differ from `docker-compose.override.yml.bak.before-b6fda27`. `.env` already set `MODELS_INI_WRITER=model-loader`. `COWORK_VERSION` set to `b6fda27` (`.env.bak.before-b6fda27` kept).

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, targeting `web` only.

Checks: web healthy, zero restarts; `docker inspect` shows `/llamacpp-config` RW=false and `touch /llamacpp-config/.probe` in web fails with "Read-only file system"; no `[models-ini]` lines in web logs; `version.json` `b6fda27`; public root 200, `/api/profile` 401; the served `index-Di65Hgdx.js` and `index-CHiiGa9G.css` are byte-identical to the image `dist` (82 files). Model-loader answers `GET /api/v1/health` and `GET /api/v1/sections` (200) from web with its token. Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only difference is the recreated web container (`68b8b502537c` to `1aebaea3b64f`, started 2026-09-29T18:23:10Z).

Rollback: restore the override (`cp -p .../Cowork/docker-compose.override.yml.bak.before-b6fda27 .../Cowork/docker-compose.override.yml`, or remove `:ro` and set the default back to `web`), `ln -sfn /mnt/docker/appdata/cowork/releases/4dc8ccf /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=4dc8ccf` in `.env` (or restore `.env.bak.before-b6fda27`), then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. Previous images are retained.

---

## Release web 4dc8ccf — 2026-09-29 (storage edit messages, no retry of conditional writes, phone chat header, unit wording, write-safety cards)

### Services

- **Web:** [#662](https://github.com/sbstndalton/noevia/pull/662) (fixes #655, #660, #661: in-place edit failure messages and no retry of conditional PUTs, phone chat header crumbs, tokens-per-second wording), [#663](https://github.com/sbstndalton/noevia/pull/663) (fixes #658, #659: saved writes are never shown as a failed request or replayed, project uploads get project tools, Drive writes are named and conditional) — `cowork-web:4dc8ccf`, image `sha256:fb17d48f274c3bbe1ff121f10d337c9d1ce18b612f51c2c4d29f1eb4e379195d`. [#657](https://github.com/sbstndalton/noevia/pull/657) was the previous changelog.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:381760c`. `git diff --stat ffdcd9b 4dc8ccf -- services/` is empty, so no model-loader image was built.
- **Code sandbox, OCR, Docling:** no change.
- No feature flag was changed and `TRUST_PROXY` was not touched.

Exact source `4dc8ccf00e9a9fad66b76937eaf2b90db24ddbd0`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `a400a24024010fc9b7796b28ab75478c5c2a36fdc3a6447ba74d59827243e006`, matched on the server), to `releases/4dc8ccf`. #663 had all checks green (head `4f1a695`) before its squash merge as `4dc8ccf`, and main CI on `4dc8ccf` was green before cutover. Web was built with `deploy/tools/build-web-release.sh 4dc8ccf apps/web` (stamp verified). Standalone web candidate on a loopback port with no production mounts and a synthetic token: `/` 200, `/api/profile` 401, `/api/auth/device/code` 404, `version.json` `4dc8ccf`, 82 dist files.

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, targeting `web` only; `.env` and the Compose YAMLs were backed up as `*.bak.before-4dc8ccf`. The restart-alert baseline was re-acked.

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `4dc8ccf`; all 82 files served publicly are byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply; the device-code route returns 404).

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only difference is the recreated web container (`9750cf4a77b1` to `68b8b502537c`, started 2026-09-29T12:38:36Z). Diary (`cowork-diary:f6444b4`), model-loader, laya and every other container are identical.

Rollback: web, `ln -sfn /mnt/docker/appdata/cowork/releases/ffdcd9b /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=ffdcd9b` in `.env`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. `.env.bak.before-4dc8ccf` and the Compose backups were kept; previous images are retained.

---

## Release web ffdcd9b — 2026-09-29 (project tools edit uploads in place, phone-preview stacking, Code header inset, French wording, byte plural)

### Services

- **Web:** [#654](https://github.com/sbstndalton/noevia/pull/654) (fixes #648: project tools edit uploaded files in place, with conditional writes pinned to the approved path), [#656](https://github.com/sbstndalton/noevia/pull/656) (fixes #650, #651, #652, #653: phone-preview project stacking, Code header inset, French wording and role names, byte plural) — `cowork-web:ffdcd9b`, image `sha256:9ae2ff183175e0eb5f0884960ff8337f6f034ec5d6c5fb24bac63a6e35b34b01`. [#649](https://github.com/sbstndalton/noevia/pull/649) was the previous changelog.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:381760c`. `git diff --stat 6e7eeba ffdcd9b -- services/` is empty, so no model-loader image was built.
- **Code sandbox, OCR, Docling:** no change.
- No feature flag was changed and `TRUST_PROXY` was not touched.

Exact source `ffdcd9b6da2f91d46138ff7911bab9da41813708`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `b16d8abe82130fb21571dbb8cef1c368bdabe39850439c325cb55a8e9079ab19`, matched on the server), to `releases/ffdcd9b`. Both PRs had all checks green before their squash merges (#654 as `3b1443c`, then #656 as `ffdcd9b`, still MERGEABLE after #654), and main CI on `ffdcd9b` was green before cutover. Web was built with `deploy/tools/build-web-release.sh ffdcd9b apps/web` (stamp verified). Standalone web candidate on a loopback port with no production mounts and a synthetic token: `/` 200, `/api/profile` 401, `/api/auth/device/code` 404, `version.json` `ffdcd9b`, 82 dist files.

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, targeting `web` only; `.env` and the Compose YAMLs were backed up as `*.bak.before-ffdcd9b`. The restart-alert baseline was re-acked.

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `ffdcd9b`; all 82 files served publicly are byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply; the device-code route returns 404).

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only difference is the recreated web container (`f7fb5a43b12e` to `9750cf4a77b1`, started 2026-09-29T11:24:00Z). Diary (`cowork-diary:f6444b4`), model-loader, laya and every other container are identical.

Rollback: web, `ln -sfn /mnt/docker/appdata/cowork/releases/6e7eeba /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=6e7eeba` in `.env`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. `.env.bak.before-ffdcd9b` and the Compose backups were kept; previous images are retained.

---

## Release web 6e7eeba — 2026-09-29 (project files by bare name, phone-preview drawer, English size sentences, Auto label, timer start)

### Services

- **Web:** [#646](https://github.com/sbstndalton/noevia/pull/646) (fixes #642: project files readable by their listed or bare name; write tools refuse connected uploads with an accurate message), [#647](https://github.com/sbstndalton/noevia/pull/647) (fixes #640, #643, #644, #645: phone-preview drawer, English size sentences, pending Auto label, reply timer start, wording leftovers) — `cowork-web:6e7eeba`, image `sha256:4cd9dd4d1d74744c371b8c5344d1c167e1c2462a50a6bcacf58532a417d6189f`. [#641](https://github.com/sbstndalton/noevia/pull/641) was the previous changelog.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:381760c`. `git diff --stat 5e904b7 6e7eeba -- services/` is empty, so no model-loader image was built.
- **Code sandbox, OCR, Docling:** no change.
- No feature flag was changed and `TRUST_PROXY` was not touched.

Exact source `6e7eebad39f312663f09742f727bbb97e3117480`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `b83aad0fac80a42407a31a58c0cfbf260f632c3bbdc1441697751298cfd05e59`, matched on the server), to `releases/6e7eeba`. Both PRs had all checks green before their squash merges (#646 as `eeafa4b`, then #647 as `6e7eeba`, still MERGEABLE after #646), and main CI on `6e7eeba` was green before cutover. Web was built with `deploy/tools/build-web-release.sh 6e7eeba apps/web` (stamp verified). Standalone web candidate on a loopback port with no production mounts and a synthetic token: `/` 200, `/api/profile` 401, `/api/auth/device/code` 404, `version.json` `6e7eeba`, 82 dist files.

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, targeting `web` only; `.env` and the Compose YAMLs were backed up as `*.bak.before-6e7eeba`. The restart-alert baseline was re-acked.

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `6e7eeba`; all 82 served asset files byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply).

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only difference is the recreated web container. Diary (`cowork-diary:f6444b4`), model-loader, laya and every other container are identical.

Rollback: web, `ln -sfn /mnt/docker/appdata/cowork/releases/5e904b7 /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=5e904b7` in `.env`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. `.env.bak.before-6e7eeba` and the Compose backups were kept; previous images are retained.

---

## Release web 5e904b7 — 2026-09-29 (remaining English and de/fr wording, composer toolset names, Stopped placeholder, French byte units, Diary phone preview)

### Services

- **Web:** [#638](https://github.com/sbstndalton/noevia/pull/638) (#624 remaining English: server ids for status, decision and gdrive messages, de/fr wording and the other locales), [#639](https://github.com/sbstndalton/noevia/pull/639) (fixes #615 reopen, #634-#637: in-app toolset names in the composer menu, Stopped placeholder language, stale locale, French byte units, Diary phone preview) — `cowork-web:5e904b7`, image `sha256:7aa048b5c293e1af90bbfa6a2d795631822ea703bf05641bad4ae435e5ef57b5`. [#633](https://github.com/sbstndalton/noevia/pull/633) was the previous changelog.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:381760c`. `git diff --stat 3007ae5 5e904b7 -- services/` is empty, so no model-loader image was built.
- **Code sandbox, OCR, Docling:** no change.
- No feature flag was changed and `TRUST_PROXY` was not touched.

Exact source `5e904b731d194fad472cf2003bd9db859717f6e7`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `8db76c9eca25c4ed1d87280fe5283cd84464b34136436664d4bcede324060b62`, matched on the server), to `releases/5e904b7`. #639 had all checks green before its squash merge, and main CI on `5e904b7` was green before cutover. Web was built with `deploy/tools/build-web-release.sh 5e904b7 apps/web` (stamp verified). Standalone web candidate on a loopback port with no production mounts: `/` 200, `/api/profile` 401, `/api/auth/device/code` 404, `version.json` `5e904b7`.

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, targeting `web` only; `.env` and the Compose YAMLs were backed up as `*.bak.before-5e904b7`. The restart-alert baseline was re-acked.

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `5e904b7`; all 82 served asset files byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply).

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only difference is the recreated web container. Diary (`cowork-diary:f6444b4`), model-loader, laya and every other container are identical.

Rollback: web, `ln -sfn /mnt/docker/appdata/cowork/releases/3007ae5 /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=3007ae5` in `.env`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. `.env.bak.before-5e904b7` and the Compose backups were kept; previous images are retained.

---

## Release web 3007ae5 — 2026-09-29 (toolbox and chat chrome translations, offsite-backup qa, hardware answer, phone theme cards)

### Services

- **Web:** [#631](https://github.com/sbstndalton/noevia/pull/631) (fixes #623, #629, #630: offsite-backup qa script, `/api/models/hardware` answers 200 when unsupported, phone-layout theme cards), [#632](https://github.com/sbstndalton/noevia/pull/632) (fixes #615 reopen, #626-#628, #624 item 1: toolbox translations by in-app id, chat header and plurals, MCP footer, Code architect options, Backups bytes) — `cowork-web:3007ae5`, image `sha256:92ad12c4d56c9e29af810bd1f6f029954415c1bc0e52bbd17d7e08f7a931eabd`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:381760c`. `git diff --stat a8a953a 3007ae5 -- services/` is empty, so no model-loader image was built.
- **Code sandbox, OCR, Docling:** no change.
- No feature flag was changed and `TRUST_PROXY` was not touched.

Exact source `3007ae57e5a12a64f35691d3bdf99c778a634581`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `f755634cb10c7538d46a1533db243cb1af29f47e84bb514cbdaefcccae6fe3aa`, matched on the server), to `releases/3007ae5`. Both PRs had all checks green before their squash merges (#631 as `7ef30f6`, then #632 as `3007ae5`, still MERGEABLE after #631), and main CI on `3007ae5` was green before cutover. Web was built with `deploy/tools/build-web-release.sh 3007ae5 apps/web` (stamp verified). Standalone web candidate on a loopback port with no production mounts: `/` 200, `/api/profile` 401, `/api/auth/device/code` 404, `version.json` `3007ae5`, 82 dist files.

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, targeting `web` only; `.env` and the Compose YAMLs were backed up as `*.bak.before-3007ae5`. The restart-alert baseline was re-acked.

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `3007ae5`; all 82 served asset files byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply).

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only difference is the recreated web container. Diary (`cowork-diary:f6444b4`), model-loader, laya and every other container are identical.

Rollback: web, `ln -sfn /mnt/docker/appdata/cowork/releases/a8a953a /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=a8a953a` in `.env`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. `.env.bak.before-3007ae5` and the Compose backups were kept; previous images are retained.

---

## Release web a8a953a — 2026-09-29 (Code landing, admin Settings and Diary calendar localised, round-7 leftovers)

### Services

- **Web:** [#622](https://github.com/sbstndalton/noevia/pull/622) (fixes #617, #618, #619: localised Code landing and tab, four admin Settings pages, Diary calendar locale; `features.cjs` and `offsite-service.cjs`), [#621](https://github.com/sbstndalton/noevia/pull/621) (fixes #613-#616, #620: round-7 English leftovers translated, the space kept at a label cut) — `cowork-web:a8a953a`, image `sha256:d3ab41f91df79d343d9123ef702bd0410fd8c5674bb0bae7397f1b08b8705ab1`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:381760c`. `git diff --stat 381760c a8a953a -- services/` shows only `services/model-manager/tests/test_api.py` (23 lines added), so no model-loader image was built.
- **Code sandbox, OCR, Docling:** no change.
- No feature flag was changed and `TRUST_PROXY` was not touched.

Exact source `a8a953a8e3fd43a1eafeafeec211b3af62a1fb0c`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `8edeea548fae661c5bf03ff5a40a4ca3562deeb31746ec2ddb5cc69cf89dbe27`, matched on the server), to `releases/a8a953a`. Both PRs had all checks green before their squash merges (#622 as `ecc0975`, then #621 as `a8a953a`, still MERGEABLE after #622), and main CI on `a8a953a` was green before cutover. Web was built with `deploy/tools/build-web-release.sh a8a953a apps/web` (stamp verified). Standalone web candidate on a loopback port with no production mounts: `/` 200, `/api/profile` 401, `version.json` `a8a953a`, 82 dist files.

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, targeting `web` only; `.env` and the Compose YAMLs were backed up as `*.bak.before-a8a953a`. The restart-alert baseline was re-acked.

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `a8a953a`; all 82 served asset files byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply).

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only difference is the recreated web container. Diary (`cowork-diary:f6444b4`), model-loader, laya and every other container are identical.

Rollback: web, `ln -sfn /mnt/docker/appdata/cowork/releases/381760c /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=381760c` in `.env`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. `.env.bak.before-a8a953a` and the Compose backups were kept; previous images are retained.

---

## Release web + model-loader 381760c — 2026-09-29 (round 6 fixes, stopped-backend uptime, field ids)

### Services

- **Web:** [#604](https://github.com/sbstndalton/noevia/pull/604) (changelog), [#605](https://github.com/sbstndalton/noevia/pull/605) (fixes #600, #603: localised Advanced field text, compact counts, chat meta, Code context line), [#611](https://github.com/sbstndalton/noevia/pull/611) (fixes #586 reopen, #606-#610: context panel unreadable source, upload row size, de/fr gaps, byte sizes) — `cowork-web:381760c`, image `sha256:c16dbee3b29310a0b94e12d6e97a6e3ae3eecae4e10010999b1a156b1b5a7893`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** [#605](https://github.com/sbstndalton/noevia/pull/605) (`uptime_s` only for running containers, field `id` in the schema, locale) — `cowork-model-loader:381760c`, image `sha256:1bd762685514ac339f88730b257ceea303caabce8af84cbe9674cac2f832ffc2`, built as an overlay (`FROM cowork-model-loader:435ba54`, `COPY app /srv/app`, import check).
- **Code sandbox, OCR, Docling:** no change.
- No feature flag was changed and `TRUST_PROXY` was not touched.

Exact source `381760c3b1d58724c06bd8de61a6b7a86501cbec`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `7b80192f8d851a10a576c595945fbbf8efe63f958d0ed4bdba71d2b5af672229`, matched on the server), to `releases/381760c`. PR #611 (head `238aaab`) had all checks green before the squash merge, and main CI on `381760c` was green before cutover. Web was built with `deploy/tools/build-web-release.sh 381760c apps/web` (stamp verified). Standalone web candidate on a loopback port with no production mounts: `/` 200, `/api/profile` 401, `version.json` `381760c`, 82 dist files. Model-loader candidate: `app.api/main/discover/services` import cleanly.

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, one service at a time (`web`, then `model-loader`); `.env` and Compose YAMLs were backed up as `*.bak.before-381760c`. The restart-alert baseline was re-acked.

Checks: web and model-loader healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `381760c`; all 82 served asset files byte-identical to the image `dist`; web and model-loader logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set, defaults apply). Model-loader `/api/v1/health` 200; `/api/v1/backends` reports `uptime_s` 10256 and 14832 for the two running backends and `null` for the exited `llama-vulkan-test`; the `/api/v1/sections` schema carries `id` on all 98 fields (read from inside the web container with the token header). This closes [#603](https://github.com/sbstndalton/noevia/issues/603).

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only differences are the two recreated containers (web, model-loader). Diary (`cowork-diary:f6444b4`), laya and every other container are identical.

Rollback: web, `ln -sfn /mnt/docker/appdata/cowork/releases/435ba54 /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=435ba54` in `.env`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. Model-loader: `MODEL_MANAGER_VERSION=435ba54` and the same command for `model-loader`. `.env.bak.before-381760c` and the Compose backups were kept; previous images are retained.

---

## Release web + model-loader 435ba54 — 2026-09-29 (locale gaps, backend uptime_s, tierId)

### Services

- **Web:** [#602](https://github.com/sbstndalton/noevia/pull/602) (changelog), [#599](https://github.com/sbstndalton/noevia/pull/599) (fixes #592, #596, #597, #598, #601: locale gaps left after #587 for numbers, percents, uptime, statuses and server-supplied words) — `cowork-web:435ba54`, image `sha256:51c831f9c5ac3586e036056a7ecaaced8481ae95ec298d3a5f115d7f8b6246cd`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** [#599](https://github.com/sbstndalton/noevia/pull/599) (`uptime_s` on backends, `tierId` in the llama.cpp schema) — `cowork-model-loader:435ba54`, image `sha256:c53b88c6c34783abe7363e2914715e9e820a2bc44e355ee48bcc5ce7ecca102c`, built as an overlay (`FROM cowork-model-loader:b8755fb`, `COPY app /srv/app`, import check).
- **Code sandbox, OCR, Docling:** no change.
- No feature flag was changed and `TRUST_PROXY` was not touched.

Exact source `435ba5419f2b448f8d78a208bbe58b474888aee7`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `366325c94b60002e4bc7fd43f03ff13875b72a103bbcf676198a0aa60fbf7413`, matched on the server), to `releases/435ba54`. All PR #599 checks were green before the squash merge. Web was built with `deploy/tools/build-web-release.sh 435ba54 apps/web` (stamp verified). Standalone web candidate on a loopback port with no production mounts: `/` 200, `/api/profile` 401, `version.json` `435ba54`, 82 dist files. Model-loader candidate: `app.api/main/discover/services` import cleanly.

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180`, one service at a time (`web`, then `model-loader`); `.env` and Compose YAMLs were backed up as `*.bak.before-435ba54`. The restart-alert baseline was re-acked.

Checks: web and model-loader healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `435ba54`; 53 served asset files (including `index-*.js`/`index-f8aq2N0j.css`, `theme.js`, `lens.js`, `glass-highlight.js`) byte-identical to the image `dist`; web and model-loader logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off. Model-loader `/api/v1/health` 200, `/api/v1/backends` includes `uptime_s` for every backend, and the `/api/v1/sections` schema carries `tierId` on all 10 tiers (read from inside the web container with the token header). Follow-up: [#603](https://github.com/sbstndalton/noevia/issues/603) (exited backends report an uptime).

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only differences are the two recreated containers (web, model-loader). Diary (`cowork-diary:f6444b4`), laya and every other container are identical.

Rollback: web, `ln -sfn /mnt/docker/appdata/cowork/releases/ef6a83f /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=ef6a83f` in `.env`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. Model-loader: `MODEL_MANAGER_VERSION=b8755fb` and the same command for `model-loader`. `.env.bak.before-435ba54` and the Compose backups were kept; previous images are retained.

---

## Release web ef6a83f — 2026-09-29 (unreadable sources excluded, Sources typography, lazy project folders)

### Services

- **Web:** [#595](https://github.com/sbstndalton/noevia/pull/595) (changelog), [#593](https://github.com/sbstndalton/noevia/pull/593) (fixes #586, #588, #589: unreadable uploads kept out of retrieval and sources, Sources typography, delete-dialog copy, lazy storage folder with name reservation) — `cowork-web:ef6a83f`, image `sha256:12c84baa4f4f2d7744f4d77df50e46e579571abbaa8835c702f5c7a99c296c42`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change (`git diff --stat b8755fb ef6a83f -- services/model-manager` is empty); model-loader stays on `b8755fb`.
- **Code sandbox, OCR, Docling:** no change.
- **Not released:** [#599](https://github.com/sbstndalton/noevia/pull/599) (#592/#596/#597/#598, plus model-manager `uptime_s` and `tierId`) had no CI checks and conflicts with main in `ProjectView.tsx`; see [#601](https://github.com/sbstndalton/noevia/issues/601). No feature flag was changed and `TRUST_PROXY` was not touched.

Exact source `ef6a83fc4d42742f85ca73528f4e8a74c92ccf00`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `542b546ae96a41fb119a467f1d64bc2899cac6cd07b587e47c93b9ebeb3a923b`, matched on the server), to `releases/ef6a83f`. Main CI on that SHA was green. Web was built with `deploy/tools/build-web-release.sh ef6a83f apps/web` (stamp verified). Standalone candidate on a loopback port with no production mounts: `/` 200, `/api/profile` 401, `version.json` `ef6a83f`.

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180 web`; `.env` and Compose YAMLs were backed up as `*.bak.before-ef6a83f`. The restart-alert baseline was re-acked.

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/version.json` `ef6a83f`; served `index-BK7x-LxY.js`, `index-f8aq2N0j.css`, `theme.js`, `lens.js` and `glass-highlight.js` byte-identical to the image `dist`; web logs clean. `/api/auth/device/code` returns 404. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off.

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only difference is the recreated web container. Diary, model-loader and every other container are identical.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/a70f5a0 /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=a70f5a0` in `.env`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. `.env.bak.before-ef6a83f` and the Compose backups were kept; the previous image is retained.

---

## Release web a70f5a0 — 2026-09-29 (locale-aware model numbers; native-client device sign-in, flag off)

### Services

- **Web:** [#585](https://github.com/sbstndalton/noevia/pull/585) (changelog), [#584](https://github.com/sbstndalton/noevia/pull/584) (native client device sign-in, RFC 8628, flag `NOEVIA_FEATURE_NATIVE_CLIENT_AUTH`, default off and unavailable without `TRUST_PROXY=true`; adds `device_authorizations`, `device_grants` and `device_tokens` SQLite tables on start), [#591](https://github.com/sbstndalton/noevia/pull/591) (fixes #587, locale number formatting) — `cowork-web:a70f5a0`, image `sha256:4c54738a17c51b9b23a3a8385b4c5a69ae057ce955e91509b7cfe1ae8e5c68ee`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change (`git diff --stat b8755fb a70f5a0 -- services/` is empty); model-loader stays on `b8755fb`.
- **Code sandbox, OCR, Docling:** no change.
- **Not released:** [#593](https://github.com/sbstndalton/noevia/pull/593) (#586/#588/#589) failed the required "Node tests, typecheck, frontend build" check (`same-name projects receive distinct storage folders`), so it was skipped; see [#594](https://github.com/sbstndalton/noevia/issues/594). No feature flag was changed and `TRUST_PROXY` was not touched.

Exact source `a70f5a0ee7c5c974ac0dbdf5593c8a88c7d61ae7`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `72ebf8f4fd7ca25ea95715470382e5470500535c014bcf9b5cf9c416dcad04ed`, matched on the server), to `releases/a70f5a0`. Main CI on that SHA was green. #591 was merged first after all its checks passed. Web was built with `deploy/tools/build-web-release.sh a70f5a0 <context>` (stamp verified). Standalone candidate on a loopback port with no production mounts: `/` 200, `/api/profile` 401, `version.json` `a70f5a0`, 68 asset files.

Cutover used the guarded `up.sh` with `--no-build --no-deps --wait --wait-timeout 180 web`; `.env` and Compose YAMLs were backed up as `*.bak.before-a70f5a0`. The restart-alert baseline was re-acked.

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/version.json` `a70f5a0`; served `index-BnZjcwNG.js`, `index-DSXrbO3N.css`, `theme.js`, `lens.js` and `glass-highlight.js` byte-identical to the image `dist`; web logs clean and the three `device_*` tables (plus indexes) exist. `/api/auth/device/code` returns 404 (flag off). `astraReview` and `constrainedPlanDecoding` off, `nativeClientAuth` and `browserExecutor` unavailable.

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only difference is the recreated web container. Diary, model-loader, laya, llama, embed, ocr, docling, code-sandbox and every other container are identical.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/b8755fb /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=b8755fb` in `.env`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. `.env.bak.before-a70f5a0` and the Compose backups were kept. The new `device_*` tables are additive and can stay; the previous image is retained.

---

## Release web + model-loader b8755fb — 2026-09-28 (md uploads, model-switch race, embed loaded model, delete guard; preflight wrapper refreshed)

### Services

- **Web:** [#572](https://github.com/sbstndalton/noevia/pull/572) (changelog), [#576](https://github.com/sbstndalton/noevia/pull/576) (#571 follow-ups), [#582](https://github.com/sbstndalton/noevia/pull/582) (#579, #580, #581 i18n), [#583](https://github.com/sbstndalton/noevia/pull/583) (fixes #577 `.md` uploads under Docling and #578 first-try model-switch 503) — `cowork-web:b8755fb`, image `sha256:5f9f0832d74d9ec32da84044ff12561a1ddb83cd26d41fb1eda4f3d175d8c559`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** [#576](https://github.com/sbstndalton/noevia/pull/576) (delete guard, #336), [#582](https://github.com/sbstndalton/noevia/pull/582) (backend probe reports the embed loaded model, #580) — `cowork-model-loader:b8755fb`, image `sha256:85623589b3fe9f63d25e595b5111b6f92caa6b54bdc4e4bcad895991951afaf6`.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** [#575](https://github.com/sbstndalton/noevia/pull/575) (`deploy/tools/build-web-release.sh`; `up.sh` resolves its own project directory). The installed `/mnt/docker/appdata/cowork/tools/preflight/{up.sh,check.php,web-env-keys.txt,README.md,test_check.php}` were refreshed from this release; the old copies are kept as `*.bak.before-b8755fb`. #584 is under security review and was not merged or deployed. No feature flag was changed.

Exact source `b8755fb120de140606b66be0fec18a31d8a253ff`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `823022895659ed0faa359de2b2ddbd63034f9d59f734bb9f1820b3025ff0a566`, matched on the server), to `releases/b8755fb`. PR #583 was merged first after all its checks passed. Web was built with `deploy/tools/build-web-release.sh b8755fb <context>` (stamp verified by the script); model-loader from `services/model-manager`. `test_check.php` passes on the server; `test_wrapper.py` could not run there (no python3 on the host) and passed in CI. Candidates: web standalone `/` 200, `/api/profile` 401, `version.json` `b8755fb`, 65 asset files; model-loader `app.api/main/discover/services` import cleanly.

Cutover used the refreshed guarded `up.sh`, one service at a time (`web`, then `model-loader`), each with `--no-build --no-deps --wait --wait-timeout 180`. It was run from `/` and worked, which confirms the cwd-independent project lookup from #575. It re-acked the restart-alert baseline.

Checks: web and model-loader healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/version.json` `b8755fb`, served `index-B10eD_gz.js`, `index-NW1foXSN.css`, `theme.js`, `lens.js` and `glass-highlight.js` byte-identical to the image `dist`; web and model-loader logs clean. `astraReview` and `constrainedPlanDecoding` false, `browserExecutor` false and unavailable (no Playwright in the image); `nativeClientAuth` is not in the feature registry. Model-loader `/api/v1/health` 200; `/api/v1/backends` lists `cowork-embed-1` running with loaded model `nomic-embed-text-v1` (#580) and llama running `gemma-4-E2B_q4_0-it`. Delete guard, read-only check (nothing deleted): `model_holders` on the `nomic-embed-text-v1` entry returns `cowork-embed-1 (its command runs nomic-embed-text-v1/nomic-embed-text-v1.Q8_0.gguf)` plus `cowork-web-1 (EMBEDDING_MODEL is set to nomic-embed-text-v1)`.

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only differences are the two recreated containers (web, model-loader). Diary, laya, llama, embed, ocr, docling, code-sandbox, kiwix and every other container are identical.

Rollback: web, `ln -sfn /mnt/docker/appdata/cowork/releases/682a45e /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=682a45e` in `.env`, then `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`. Model-loader: `MODEL_MANAGER_VERSION=682a45e` and the same command for `model-loader`. Preflight: copy each `*.bak.before-b8755fb` back over its file in `tools/preflight/`. `.env.bak.before-b8755fb` and the Compose backups `*.bak.before-b8755fb` were kept; previous images are retained.

---

## Release web + model-loader 682a45e — 2026-09-28 (embed status, Browser-mode flag, model-loader rope fixes, live round 2 fixes; embed on the models network)

### Services

- **Web:** [#557](https://github.com/sbstndalton/noevia/pull/557), [#558](https://github.com/sbstndalton/noevia/pull/558), [#559](https://github.com/sbstndalton/noevia/pull/559), [#560](https://github.com/sbstndalton/noevia/pull/560), [#561](https://github.com/sbstndalton/noevia/pull/561), [#570](https://github.com/sbstndalton/noevia/pull/570) (fixes #562-#567) — `cowork-web:682a45e`, image `sha256:5b863e479d077318a99c3e478455b0f5cabea10b6db77d630afb1c38d9020e21`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** [#557](https://github.com/sbstndalton/noevia/pull/557) (embed status) and [#569](https://github.com/sbstndalton/noevia/pull/569) (never write rope keys the GGUF owns; duplicate-section rejection, #568) — `cowork-model-loader:682a45e`, image `sha256:4c1da884df83acebd56051e02ee844b4dfd3bf849c8bad2ab300d63815bec785`.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** live `docker-compose.override.yml` `embed.networks` is now `[default, models]` (#549; `models` was already declared); no image change. #556 (NoeviaKit macOS client) is on main and not deployed. No feature flag or `MODELS_INI_WRITER` was set.

Exact source `682a45e7c5b9696e3854d02fa672052179230658`, `git archive` of a fresh clone of `origin/main` (archive SHA-256 `62e777b19247d79aa377ba77185e4016fc056f2658143ee4a8ce8c676b67536d`, matched on the server), to `releases/682a45e`. PR #570 was merged first after all its checks passed. Web was built from `apps/web` with the repo Dockerfile and **`--build-arg COWORK_VERSION=682a45e`**; without the build arg `dist/version.json` says `0.2.0+<hash>` (the first build had this and was replaced before cutover). Model-loader was built from `services/model-manager`. Candidates: web standalone returned `/` 200, `/api/profile` 401, `version.json` `682a45e`, 65 asset files; model-loader `app.api/main/services/discover` import cleanly.

Cutover used the installed guarded `up.sh` one service at a time (`web`, then `model-loader`, then `embed`), each with `--no-build --no-deps --wait`. `up.sh` must be run from the Compose Manager project directory (`/boot/config/plugins/compose.manager/projects/Cowork`); run from elsewhere it fails closed with "could not validate Compose JSON". `up.sh` re-acked the restart-alert baseline.

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/version.json` `682a45e`, served `index-ChIYCx9M.js` and `index-CmIqOpBa.css` byte-identical to the image `dist`; web and model-loader logs clean (MCP discovery only). `astraReview`, `constrainedPlanDecoding` and `browserExecutor` all report false. Model-loader healthy, zero restarts; `/api/v1/health` 200; `/api/v1/sections` and `/api/v1/backends` return 200 from inside the web container using the `X-Model-Loader-Token` header (token never printed); backends lists `cowork-embed-1` as running, no "connection refused". Embed recreated on both `cowork_default` and `cowork_models`, healthy, zero restarts (its old restart count was 4463); `POST http://embed:8080/v1/embeddings` from web returns a vector and model-loader reaches `embed:8080/health` (200).

models.ini (#568): backed up as `models.ini.bak.20260928-214146-before-568`, then exactly `rope-scaling = linear` and `rope-scale = 8.0` removed from `[gemma-3-12b-it-qat-Q4_0]`; no duplicate section names. `cowork-llama-1` was deliberately **not restarted** (owner offline), so its running 12B args still reflect the old file until the next restart; the file itself is fixed.

Before/after snapshot of all 43 containers (id, StartedAt, restart count, image): the only differences are the three recreated containers (web, model-loader, embed). Diary, laya, llama, ocr, docling, code-sandbox, kiwix and every other container are identical.

Rollback: web, `ln -sfn /mnt/docker/appdata/cowork/releases/349a450 /mnt/docker/appdata/cowork/current`, `COWORK_VERSION=349a450` in `.env`, then the guarded `up.sh` (from the project directory) for `web`. Model-loader: `MODEL_MANAGER_VERSION=1c87ab0` and `up.sh ... model-loader`. Embed: restore `docker-compose.override.yml.bak.before-embed-models-net` and `up.sh ... embed`. `.env.bak.before-682a45e` and the Compose backups `*.bak.before-682a45e` were kept; previous images are retained.

---

## Release web 349a450 — 2026-09-28 (sampling recommendations, Skills revocation, Astra review behind a flag)

### Services

- **Web:** [#539](https://github.com/sbstndalton/noevia/pull/539), [#540](https://github.com/sbstndalton/noevia/pull/540), [#541](https://github.com/sbstndalton/noevia/pull/541), [#542](https://github.com/sbstndalton/noevia/pull/542), [#543](https://github.com/sbstndalton/noevia/pull/543), [#544](https://github.com/sbstndalton/noevia/pull/544) — `cowork-web:349a450`.
- **Diary:** no change. #538 (`0867ec9`, Diary requirements) is on main but was not rolled out; Diary stays on `cowork-diary:f6444b4` until the owner authorises it.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** web-only build and activation through the installed preflight (`--no-build --no-deps --wait web`); the generic overlay script was not used.

Includes the optional llama.cpp constrained-decoding module for the plan artifact (#517, flag reports unavailable), the web to model-loader `/api/v1` contract doc and tests (#269), per-model sampling recommendations and the auto-tune Sampling phase with i18n (#308), in-flight Skills revocation and web pinning (#272), and the Astra review step in Code mode (#519, `NOEVIA_FEATURE_ASTRA_REVIEW`, default off). The persona-swap experiments harness (#518) is not part of the image. No feature flag was set or changed.

Exact source `349a45080fa1514281d14759630e46134941954d`, archived from a fresh clone of `origin/main` (archive SHA-256 `2aff03974eeb5c22d4fbf2d29cdfa08db4fcda5df08f94ce56f16ea79b977f88` matched locally and on the server). Lockfiles were unchanged since `ad71baf`. The image was built from the release directory with the repository Dockerfile (the in-build unit tests ran and passed; `npm ci` was cached), tagged `cowork-web:349a450`, image `sha256:f3916685fcb8a30d71c88c9bc69be264a07bf6e8c2dc0a3f2038399b461ba5f6`. A network-disabled candidate container reported version `349a450`, `/api/profile` 401, `dist/index.html` plus 65 asset files, and both `server/sampling-recommendation.cjs` and `server/code-review.cjs` present before cutover.

Web is healthy with zero restarts, started `2026-09-29T00:20:10Z`. Public root returned 200 three times, unauthenticated `/api/profile` returns 401 and `/version.json` says `349a450`. The served `index-BTdwnJ6-.js` and `index-sYzZaw8b.css` exist in the image `dist/assets`. Web logs since start are clean (MCP discovery only). In the container `astraReview` and `constrainedPlanDecoding` both report false. A before/after snapshot of the 42 non-web containers (id, StartedAt, restart count, image) is identical, including the known embed crash loop (#336). The restart-alert baseline was re-acked by `up.sh`. No model runs, tune, private Diary access or new harness installation.

Rollback: restore `config/.env.bak.before-349a450`, point `current` at `releases/ad71baf`, and use the installed web-only no-build preflight. Previous releases, images (`cowork-web:ad71baf`) and the Compose Manager backups `docker-compose.yml.bak.before-349a450` and `docker-compose.override.yml.bak.before-349a450` remain available.

## Release web ad71baf — 2026-09-28 (provider edit in place and hosted context size)

### Services

- **Web:** [#537](https://github.com/sbstndalton/noevia/pull/537) — `cowork-web:ad71baf`.
- **Diary:** no change.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** web-only build and activation through the installed preflight (`--no-build --no-deps --wait web`); the generic overlay script was not used.

Providers can be edited in place, and a hosted provider can state its context size (whole tokens, 2048 to 2,000,000). Closes #535 and #536. Server and frontend only.

Exact source `ad71baf1fb299f250ad9f673a063052216ecd43d`. A candidate check in the built image returned `parseContextTokens('65536')` = `{value:65536}` before cutover. Web is healthy with zero restarts, started `2026-09-28T22:28:36Z`, image `sha256:b2a07e0b6ff0`. Public root returns 200 and unauthenticated `/api/profile` returns 401. The served `index-YXY0J30A.js` and `index-PT_ypkNu.css` exist in the image `dist/assets`. Saved providers were preserved: the shared file still holds the default and NVIDIA Build rows (ids unchanged), and the server workspace module loads both from a copy of the file without printing keys. Non-web containers kept their IDs and start times; the only change is the known embed crash loop (#336), which is unrelated. No model runs.

Rollback: restore `config/.env.bak.before-ad71baf`, point `current` at `releases/0f5d9f2`, and use the installed web-only no-build preflight. Previous releases, images and the Compose backup `docker-compose.yml.bak.before-ad71baf` remain available.

## Release web 0f5d9f2 — 2026-09-28 (NVIDIA Build provider preset)

### Services

- **Web:** [#534](https://github.com/sbstndalton/noevia/pull/534) — `cowork-web:0f5d9f2`.
- **Diary:** no change.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** web-only build and activation through the installed preflight (`--no-build --no-deps --wait web`); the generic overlay script was not used.

Adds an NVIDIA Build (free trial) provider preset. Egress rules classify a provider as external by its URL, so `https://integrate.api.nvidia.com/v1` is treated as an external provider while local endpoints stay internal. Server and frontend only.

Exact source `0f5d9f22ad0f0c9368c7b182852f722c5c29be5a`; all PR #534 CI checks were green. Archive SHA-256 `1b9fb96cbad6c4132c930532533f862483fcbcde401917d69320529a41879de9` matched locally and remotely. A network-disabled candidate container returned `isExternalProvider` true for the NVIDIA URL and false for a local llama URL before cutover.

Web is healthy with zero restarts, started `2026-09-28T22:05:11Z`, image `sha256:218f617c8a74`. Public root returns 200 and unauthenticated `/api/profile` returns 401. The served `index-CDPEbze5.js` and `index-DblQT3ZR.css` exist in the image `dist/assets`. The in-container check returned true for the NVIDIA URL. All non-web container IDs, start times and restart counts were unchanged except the known embedding crash loop (already at 4,361 restarts before the release, 4,371 after). No sidecar, model, tune, private Diary access or real provider request was performed.

Rollback: restore `config/.env.bak.before-0f5d9f2`, point `current` at `releases/8f92a01`, and use the installed web-only no-build preflight. Previous releases, images and the Compose backup `docker-compose.yml.bak.before-0f5d9f2` remain available.

## Release web ab70db5 — 2026-09-28 (portable Skills contract and sampling provenance)

### Services

- **Web:** [#507](https://github.com/sbstndalton/noevia/pull/507), [#508](https://github.com/sbstndalton/noevia/pull/508) — `cowork-web:ab70db5`.
- **Diary:** no deployed change; #480 remains merged but undeployed.
- **Model manager:** no deployed change; #483 remains merged but undeployed, model-loader stays `1c87ab0`.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** web-only build and activation through the installed preflight.

Projects expose portable Skill manifests and an exact-version content read while retaining the existing Sources review UI contract. Tenant ownership, reviewed/enabled state, stale-version rejection and core tool approvals remain enforced. Source sampling recommendations now come from a bounded, commit-pinned `generation_config.json` fetch and carry provenance and artifact scope. They are reported metadata only, without a new UI, automatic application or model qualification. #272 and #308 remain open for their later client/invocation and sampling-quality work.

Exact source `ab70db58f664cf85562c93daa302f8d9392ae57b` passed 2,528 combined tests with no failures or skips, typecheck, production build and design lint. The individual slices also passed synthetic tenant-isolation HTTP checks and source-removal/artifact-staleness checks. Both PRs passed root exact-SHA reviews before push and merge plus all CI checks. Archive SHA-256 matched locally/remotely: `d5fe9581460954c1eeda974903afbdb8623230cc9d870eb8a44ab04e7dc60762`.

Web is healthy with zero restarts, started at `2026-09-28T02:26:31.396294407Z`. Public root returns 200, unauthenticated profile and new API routes 401, version `ab70db5`; `index-DRDnsqcu.js` and `index--htmrLTo.css` return 200 and exist in the image. The deployed server contains both new API implementations. Available memory remained about 9.0 GiB. All non-web IDs/images remained unchanged; all start times/restart counts stayed unchanged except the known missing-GGUF embedding crash loop (#336), from 3,198 to 3,199. No sidecar, model, corpus, preset or tuning action was performed.

Dedicated Luna Chrome verification, reviewed by root, confirmed the deployed version and rendered authenticated desktop shell and Appearance settings in its own tab. Logo colors remained Default leaves; no preferences, native selector options or palette test were changed. The owned tab was closed and the user’s existing tab left untouched. Mobile-specific rendering and physical Safari were not re-verified for this backend-only release.

Rollback: restore `config/.env.bak.before-ab70db5`, point `current` at `releases/b272746`, and use the installed web-only no-build preflight. Previous releases, images and Compose backups remain available.

## Release web b272746 — 2026-09-28 (calendar logo and tuner answer handling)

### Services

- **Web:** [#505](https://github.com/sbstndalton/noevia/pull/505), [#506](https://github.com/sbstndalton/noevia/pull/506) — `cowork-web:b272746`.
- **Diary:** no deployed change; #480 remains merged but undeployed.
- **Model manager:** no deployed change; #483 remains merged but undeployed, model-loader stays `1c87ab0`.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** web-only build and activation through the installed preflight; no sidecar or model action.

Appearance now offers per-device default, seasonal and monthly logo palettes, with an explicit hemisphere choice. Default geometry and favicon stay unchanged. The admin preview cycles palettes temporarily and clears when leaving Appearance. GPT-OSS quality probes request low reasoning effort with a bounded answer budget; strict final-answer scoring accepts harmless formatting wrappers but rejects empty or reasoning-only responses. Throughput probes retain their separate handling of capped output. No live tune or model inference was run.

Exact source `b272746d00217f88025809ebcaadae8c6b331310` passed 2,517 combined tests with no failures or skips, typecheck, build and design lint. Logo synthetic browser coverage passed 507 assertions across 1440/768/390 widths, light/dark, all three themes, admin/member, persistence and preview cleanup. Both PRs passed CI and root exact-SHA reviews. Source archive SHA-256 matched locally and remotely: `fb435cbc500dd0e1dbbf906a3fdb3d5c9717805d23cd76eac272ade9f3979c52`.

Web is healthy with zero restarts, started at `2026-09-28T02:11:30.068581928Z`. Public root returns 200, unauthenticated profile 401, version `b272746`; `index-DrBXtR_7.js` and `index--htmrLTo.css` return 200 and exist in the image. Available memory remained about 9.3 GiB. Every non-web container retained its ID and image. Start times and restart counts also stayed unchanged except the existing embedding crash loop: its count advanced from 3,183 to 3,184 while the same container reported its missing Nomic GGUF (#336). Embedding recovery was not attempted.

Dedicated Luna Chrome verification observed the deployed version and authenticated desktop Appearance controls: Default leaves, Test next palette, and the preview-only explanation. The user supplied a screenshot confirming the native macOS menu displays Default leaves, Seasonal and Monthly; the open popup is confirmed by that screenshot rather than an agent capture. No preference or palette test was changed. Current-release mobile verification and physical Safari remain unverified; synthetic responsive coverage is recorded separately above.

Rollback: restore `config/.env.bak.before-b272746`, point `current` at `releases/c90046e`, and use the installed web-only no-build preflight. Prior releases, images and Compose backups remain available.

## Release web c90046e — 2026-09-28 (server memory recovery and sidebar corrections)

### Services

- **Web:** [#499](https://github.com/sbstndalton/noevia/pull/499), [#500](https://github.com/sbstndalton/noevia/pull/500), [#501](https://github.com/sbstndalton/noevia/pull/501), [#504](https://github.com/sbstndalton/noevia/pull/504) — `cowork-web:c90046e`.
- **Diary:** no deployed change; #480 remains merged but undeployed.
- **Model manager:** no deployed change; #483 remains merged but undeployed, model-loader stays `1c87ab0`.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** gracefully unloaded an idle 9B chat-model child through the native router API, then activated web only through the installed preflight. No host or sidecar restart, model preset change, or swap configuration change.

The host had about 2.3 GiB available while two chat-model children held about 14.3 GiB of GPU-backed system memory, largely absent from Docker's memory display. Both reported no active or deferred requests; the 9B child also reported zero processed prompt/generated tokens. Rechecking those idle gauges and gracefully unloading that child raised available memory to about 9.7 GiB and reduced GTT from 15.3 GB to 7.7 GB. The 4B child remained loaded. This establishes the source of the current pressure, not the sole cause of the earlier OOM incident.

Web-mediated native model admission now serializes eviction/loading, verifies successful eviction, and refuses a conflicting load. This does not impose a host-wide memory limit on other router clients. The release also versions the core browser API contract, reduces static Brotli warmup cost, fixes Chat/Code selection shape and hidden-drawer indicator geometry, and keeps sidebar rows above the account footer without opaque heading bands.

Exact source: `c90046e29407e6d6be01e97db706d1e533248ca1`. Required local verification passed: 2,508 tests, typecheck, production build, design lint, 206 sidebar checks, 416 mode-switch checks, and existing phone drawer/settings QA. An initial performance timing assertion failed under heavy concurrent load; the bounded full rerun passed without changing that assertion. All PR CI checks passed, including the image build. Deployment required more than 8 GiB available before building; archive SHA-256 matched locally/remotely (`20f85743cb095fdfe00f28d8e7dba059d5d38afc857d72523b3c0fa0756b09d1`).

Verified `current` → `releases/c90046e`, healthy web with zero restarts, public root 200, unauthenticated profile 401, version c90046e, and served `index-BARUzto6.js` / `index-CeuNTAQ0.css` both 200 and present in the image. Every non-web container retained its ID, start time, image and restart count. Available memory remained about 9.7 GiB after deployment. Environment and Compose backups are retained as `*.bak.before-c90046e`.

Dedicated Luna live Chrome verification was dispatched immediately after activation and reviewed by root. Desktop Chat → Code → Chat, rounded inset selection and separate sidebar footer passed in the current Contemporary dark/sage theme. Mobile Chrome emulation reached 393×852, but CUA input timed out before the navigation drawer opened; live mobile drawer behavior remains unverified. Root corrected the report’s unsupported inference that Chat/Code was absent on mobile. Synthetic mobile coverage above remains separate. Physical Safari and real inference were not tested.

Rollback: point `current` at `releases/7a3f736`, restore `config/.env.bak.before-c90046e`, and run the same installed web-only no-build preflight. Model files were not changed; normal later demand can reload the unloaded model.

## Release web 7a3f736 — 2026-09-27 (theme consistency, navigation search, backup memory)

### Services

- **Web:** [#494](https://github.com/sbstndalton/noevia/pull/494), [#495](https://github.com/sbstndalton/noevia/pull/495), [#496](https://github.com/sbstndalton/noevia/pull/496), closes #139, #491, #492 and #493 — `cowork-web:7a3f736`.
- **Diary:** no deployed change; #480 remains merged but undeployed.
- **Model manager:** no deployed change; #483 remains merged but undeployed, model-loader stays `1c87ab0`.
- **Code sandbox, OCR, Docling:** no change.
- **Deploy/infra:** web-only activation through the installed preflight wrapper.

Theme families now control shared corner roles across controls, fields, cards, menus and dialogs, including sign-in/setup. Glass foreground overlays use a denser tint so underlying labels do not compete with menu text; translucent panes remain. Sidebar search finds available app destinations alongside chats and projects. Offsite backups stream consistent SQLite snapshots from temporary files instead of loading the full database into one Buffer, with cleanup on success, failure and cancellation. A synthetic 67 MB database demonstrates removal of the full snapshot Buffer allocation; this is not a total-process memory or throughput claim.

Root reviewed exact heads before push and again before matching-head squash merge; all PR CI gates passed. Combined main passed 2,497 tests, typecheck, an explicit temporary-output build and design lint, plus destination-search browser QA. Theme regressions passed 613 shape/material checks and 452 authentication/setup checks, with baseline failures reproduced, plus 216 reading states. Root inspected all theme/reading/authentication contact sheets and focal captures at 1440/768/390 in light/dark. These are synthetic Chrome fixtures; native WebKit, physical devices and actual credentials/inference are outside that coverage.

Deployed from main `7a3f736d9a47eaac3bc14d5ee675d272365d1a51` using git archive/scp and a DaServer build. Environment and both Compose files backed up as `*.bak.before-7a3f736`. Verified current→releases/7a3f736, healthy web with zero restarts, `/` 200, unauthenticated `/api/profile` 401, `/version.json` 7a3f736, and served `index-CDVCXJFu.js` / `index-CsXTtFAF.css` present in the image. All 42 non-web containers retained identical IDs, StartedAt, images and restart counts. No flags or sidecars changed.

Dedicated Luna Chrome workers tested immediately after activation; root reviewed both reports. Current Contemporary appearance/settings/menu navigation and sidebar destination search, keyboard activation, clearing, no-results and browser Back passed the tested desktop paths. No settings were saved. Other live themes, light/mobile views, real authentication, backup execution and inference remain untested; synthetic theme matrices are separate evidence.

Rollback: point `current` to `releases/e51c5b1`, restore `config/.env.bak.before-7a3f736`, and run the same web-only preflight command from the Cowork Compose Manager directory.

## Release web e51c5b1 — 2026-09-27 (tool policy after approval)

### Services

- **Web:** [#490](https://github.com/sbstndalton/noevia/pull/490), closes #489 — `cowork-web:e51c5b1`.
- **Diary, model manager, Code sandbox, OCR, Docling:** no deployed change. Diary #480 and model-manager #483 remain merged but undeployed; model-loader stays `1c87ab0`.
- **Deploy/infra:** web-only activation through the installed preflight wrapper.

Chat now rechecks the account's current tool policy immediately before dispatch. If a tool was changed to Block while its approval card was pending, submitting that old approval refuses the call and records a denial. The original issue still required the owner to approve the displayed arguments; this fixes stale policy enforcement, not an unauthenticated or silent write bypass.

Root reviewed the exact head before push and again before matching-head squash merge; all eight CI checks passed. Combined main passed 2,494 tests with zero failures or skips. Branch typecheck, explicit build to a unique /tmp output, and design lint passed. Synthetic tests exercise the real approval gate and owner decision route with fake provider/Drive execution, covering blocked reads/writes and unchanged ask behavior.

Deployed from main `e51c5b1454850af7054359f7c7a699620d046005` with git archive/scp and a DaServer web build. Environment and both Compose files backed up as `*.bak.before-e51c5b1`. Verified current→releases/e51c5b1, healthy web with zero restarts, `/` 200, unauthenticated `/api/profile` 401, and served `index-BVAVsQI9.js` / `index-CLfPZER_.css` present in the image. All 42 non-web containers retained identical IDs, StartedAt, images and restart counts. No flags or sidecars changed.

Rollback: point `current` to `releases/c01f303`, restore `config/.env.bak.before-e51c5b1`, and run the same web-only preflight command from the Cowork Compose Manager directory.

## Release web c01f303 — 2026-09-27 (bounded passkey challenges)

### Services

- **Web:** [#488](https://github.com/sbstndalton/noevia/pull/488), closes #487 — `cowork-web:c01f303`.
- **Diary, model manager, Code sandbox, OCR, Docling:** no deployed change. Previously merged Diary #480 and model-manager #483 fixes remain undeployed; model-loader stays `1c87ab0`.
- **Deploy/infra:** web-only activation through the installed preflight wrapper.

Passkey challenge issuance now prunes expired rows transactionally and limits active challenges to 4,096. Capacity rejects new requests without invalidating existing ceremonies, with uniform public responses for known and unknown usernames. Registration and sign-in resume when challenges expire or are consumed. This bounds challenge records; it does not claim general HTTP/CPU denial-of-service protection or immediate SQLite file compaction.

Root reviewed the exact implementation before push and again before matching-head squash merge; all eight CI checks passed. Local focused auth tests, typecheck, build and design lint passed. Full local tests passed 2,491/2,491 on rerun; the first run had one unrelated chat-drafts LRU assertion failure that also passed in isolation. Synthetic real-route/SQLite tests cover concurrent issuance, cleanup, capacity errors and preservation of existing tokens.

Deployed from main `c01f303c4a797ccac429a5d1d010c732d1d67fb5` through git archive/scp and a DaServer web build. Environment and both Compose files were backed up as `*.bak.before-c01f303`. Verified current→releases/c01f303, healthy web with zero restarts, `/` 200, unauthenticated `/api/profile` 401, and served `index-ogJdHrHD.js` / `index-CLfPZER_.css` in the image. All 42 non-web containers retained identical IDs, StartedAt, images and restart counts.

Rollback: point `current` to `releases/69a40a7`, restore `config/.env.bak.before-c01f303`, and run the same web-only preflight command from the Cowork Compose Manager directory.

## Release web 69a40a7 — 2026-09-27 (account deletion persistence)

### Services

- **Web:** [#481](https://github.com/sbstndalton/noevia/pull/481), [#484](https://github.com/sbstndalton/noevia/pull/484), closes #478 and #482 — `cowork-web:69a40a7`.
- **Diary:** deployed service unchanged. Session erasure fix [#486](https://github.com/sbstndalton/noevia/pull/486) (#480) is merged but **not deployed**.
- **Model manager:** deployed `cowork-model-loader:1c87ab0` unchanged. Download integrity fix [#485](https://github.com/sbstndalton/noevia/pull/485) (#483) is merged but **not deployed**.
- **Code sandbox, OCR, Docling:** no deployed change.
- **Deploy/infra:** web-only activation through the installed preflight wrapper.

Captured workspaces now guard chat-context observations, summaries, meter snapshots and optional context logs after account deletion. Late reply and tool usage updates also refuse to recreate the deleted account directory. These changes cover the named persistence paths, not every possible detached writer. Synthetic regressions pause manager/summarizer responses across deletion and verify active and other-tenant writes still work.

All PR heads were independently reviewed before push and again before matching-head squash merge; CI passed. Combined web source passed 2,489 tests with zero failures or skips; the final main delta after that run changes only the undeployed Diary service. Branch typecheck, build and design lint passed. The separately merged sidecar fixes passed their applicable CI, but this release does not activate them.

Deployed from main `69a40a7f020df373737f9bfa9ae5824ba97da34c` using git archive/scp and a DaServer image build. Backed up the environment and both Compose files as `*.bak.before-69a40a7`, then ran only the owner's web preflight command. Verified current→releases/69a40a7, healthy web with zero restarts, `/` 200, unauthenticated `/api/profile` 401, and served `index-DRiaLDMn.js` / `index-CLfPZER_.css` present in the image. All 42 non-web containers retained identical IDs, StartedAt, images and restart counts. No flags, model jobs or sidecars changed.

Rollback: point `current` to `releases/f8a83f0`, restore `config/.env.bak.before-69a40a7`, and run the same web-only preflight command from the Cowork Compose Manager directory.

## Release web f8a83f0 — 2026-09-27 (model states, provider validation, source deletion)

### Services

- **Web:** [#472](https://github.com/sbstndalton/noevia/pull/472), [#476](https://github.com/sbstndalton/noevia/pull/476), [#477](https://github.com/sbstndalton/noevia/pull/477), [#479](https://github.com/sbstndalton/noevia/pull/479), closes #466, #473, #474, #475, #471 — `cowork-web:f8a83f0`.
- **Diary:** no change.
- **Model manager:** no change; `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no code change; web-only activation through the installed preflight wrapper.

Model loader checks and installed-model panels now distinguish initial loading from unavailable or empty results. Removing a provider clears its associated model selection in the current workspace, and explicit unknown provider IDs are rejected while the legacy alias remains supported. Shared-provider references in other workspaces remain a separate lifecycle gap. Account deletion now revokes captured workspaces and fences project/source persistence, detached source journals, and RAG work before and after asynchronous boundaries. The separate chat-context persistence path remains tracked in #478; this release makes no universal account-erasure claim.

Each exact PR head was independently reviewed before push and again before squash merge with a matching-head guard. All applicable CI passed. Combined main passed all 2,484 Node tests with zero skips after linking the worktree to existing server dependencies; no package installation was needed. Typecheck, builds and design lint passed on the implementation branches. Synthetic Playwright checks fail on their bases and pass the UI fixes at 1440/768/390 in light/dark, covering pending and settled responses; root inspected the screenshot matrices. Deletion regressions pause extraction, storage and synthetic embedding across revocation and preserve active/other-tenant behavior.

Deployed from main `f8a83f0af6c2ade08eaf77cf3cfe1814c24fbf8a` using git archive/scp and a DaServer image build. Backed up `.env` and both Compose files as `*.bak.before-f8a83f0`; ran only the required web preflight activation. Verified current→releases/f8a83f0, healthy web with zero restarts, `/` 200, unauthenticated `/api/profile` 401, and served `index-BkrNM4Vo.js` / `index-CLfPZER_.css` present in the image. All 42 non-web containers retained identical IDs, StartedAt, images and restart counts. No flags, model jobs or sidecars changed.

Rollback: point `current` to `releases/e2f1e0a`, restore `config/.env.bak.before-f8a83f0`, and run the same web-only preflight command from the Cowork Compose Manager directory.

## Release web e2f1e0a — 2026-09-27 (project validation and UI navigation)

### Services

- **Web:** [#468](https://github.com/sbstndalton/noevia/pull/468), [#469](https://github.com/sbstndalton/noevia/pull/469), [#470](https://github.com/sbstndalton/noevia/pull/470), closes #465, #467, #463, #464 — `cowork-web:e2f1e0a`.
- **Diary:** no change.
- **Model manager:** no change; `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no code change; web-only activation through the installed preflight wrapper.

Rejected project configuration patches preserve the live sampling override. Chat turns and metadata requests explicitly targeting a deleted project return 404 instead of continuing without project context or reporting a discarded save as successful. Admin Settings deep links focus the requested section after profile loading unless the user has moved focus, including moving away and back. Code → Plugins opens Plugins; the main Customise default remains Connectors.

Root independently reviewed each exact local commit before push and again before squash merge with matching-head guards. All applicable CI checks passed. The combined project/chat regression suite passed 67 tests. Both UI Playwright scripts fail on the original base and pass on the reviewed branch at 1440/768/390 in light/dark; the focus-away-and-back regression also fails on the intermediate implementation. Root inspected the screenshot matrices. Local typecheck/build/design lint passed; full local npm test did not complete due baseline-matching missing server dependencies and a RAG stall, so no full local pass is claimed.

Built on DaServer from main `e2f1e0ae3a55e28a7146c9ddf973f719d4e43e8a` using git archive/scp. Backed up `.env` and both Compose files as `*.bak.before-e2f1e0a`; activated only web through the required preflight command. Verified current→releases/e2f1e0a, healthy web with zero restarts, `/` 200, unauthenticated `/api/profile` 401, and served `index-BRTYQITs.js` / `index-kv_iUv4Y.css` present in the image. All 42 non-web containers retained identical IDs, StartedAt, images and restart counts. No flags, models or sidecars changed; embedding restore #336 remains owner-blocked.

Rollback: point `current` to `releases/d8f510d`, restore `config/.env.bak.before-e2f1e0a`, and run the same web-only preflight command from the Cowork Compose Manager directory.

## Release web d8f510d — 2026-09-27 (duplicate request fixes, #462)

### Services

- **Web:** [#462](https://github.com/sbstndalton/noevia/pull/462), closes #456, #457, #459 — `cowork-web:d8f510d`.
- **Diary:** no change.
- **Model manager:** no change; `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no code change; web-only activation through the installed preflight wrapper.

Diary directory listings and Archived workspace reads now share requests. Chat context refreshes on chat changes and reply completion, avoiding the extra read caused by initial history hydration. Mutation, background-source completion and session invalidation preserve fresh reads. The request cache retains at most 128 keys and shares slow in-flight requests.

The reviewed PR head was `f16905dab654591f61fc00059b4014edf54c28cf`, squash-merged with a matching-head guard to `d8f510de4c2f646c83f5cadf4d7a42a17d264170`. Required CI is green, including Node tests/typecheck/build and Docker images; 754 frontend tests pass locally. Synthetic browser QA fails on main d0f9750 (two initial requests per endpoint) and passes on the fix (one, then one more after a mutation). The 1440/768/390 light/dark matrix was inspected before the final cache-only follow-up; final-head 1440-light request-count QA and cache regressions pass. Full local suites stalled at the same server RAG test after about 22 minutes with baseline missing-dependency failures; no full local pass is claimed.

Deployed from main using git archive/scp and a DaServer image build. Backed up `.env` and both Compose files as `*.bak.before-d8f510d`, then used only `up.sh --env-file ... -- -d --no-build --no-deps --wait --wait-timeout 180 web`. Verified current→releases/d8f510d, web healthy with zero restarts, public `/` 200, unauthenticated `/api/profile` 401, and served `index-N4w7_lzO.js` / `index-kv_iUv4Y.css` present in the image. All 42 non-web containers retained identical IDs, StartedAt, images and restart counts across activation. No feature flags, models or sidecars changed; embed's existing crash loop (#336) remains owner-blocked.

Rollback: point `current` to `releases/b61a914`, restore `config/.env.bak.before-d8f510d`, and run the same web-only preflight command from the Cowork Compose Manager directory.

## Release web b61a914 — 2026-09-27 (merge #451, deploy #449 #460 #461 #451)

### Services

- **Web:** [#449](https://github.com/sbstndalton/noevia/pull/449) closes #446, #401 —
  `focus-utils.ts`'s `isFocusable` now also rejects `disabled` controls, `visibility:hidden`
  elements and non-interactive (`tabIndex < 0`) elements, not just disconnected/`display:none`/
  `inert` ones; `SettingsShell`'s close-time focus fallback is the account trigger, then the
  always-focusable `.nav-drawer-toggle` (skipping the composer on a coarse-pointer device so
  closing Settings never pops the on-screen keyboard); `ProvidersCard`'s "Connect a provider"
  Cancel/Add now returns focus to the opening button or the new row's remove button.
  [#460](https://github.com/sbstndalton/noevia/pull/460) closes #450, #458 — `useCodeAccess` is
  tri-state (`checking`/`allowed`/`denied`) and never probes the placeholder project id, so an
  admin with real Code access no longer sees a flash of the "not connected yet" stub while the
  project list loads (`CodingWorkspace` shows a neutral loading skeleton instead); a new cached
  `fetchCodeAccess` (reusing the `request-cache.ts` mechanism from #425) makes `CodingWorkspace`
  and `Sidebar` share one `/api/projects/<id>/code` request instead of firing one each.
  [#461](https://github.com/sbstndalton/noevia/pull/461) closes #448 — the Glass sidebar's sticky
  strips (`.side-new`, `.side-permanent`, `.side-footer`, sticky section heads) get an
  unconditional translucent tint (`color-mix` of `--md-surface-container-low` and
  `--glass-sheet`) instead of relying on a `backdrop-filter` that silently no-ops as a nested
  backdrop root inside `.sidebar.pane`'s own blur, so scrolled chat titles no longer bleed through
  the footer/status strips. [#451](https://github.com/sbstndalton/noevia/pull/451) (refs #447,
  closes #452, #453, #454, #455) adds Sign in with ChatGPT as a private, per-user AI provider
  (`server/chatgpt-oauth.cjs`, ported from openai-oauth/openai-codex, Apache-2.0, no new npm
  dependency) behind the `chatgptOAuth` feature flag (`NOEVIA_FEATURE_CHATGPT_OAUTH`), off by
  default: device-code login, tokens stored per user as `secrets.cjs` v2 ciphertext, a
  `/chat/completions` ⇄ Codex `/responses` adapter, and `server/provider-egress.cjs` rules that
  keep Diary text, the Diary toolbox and project images from ever reaching this provider. The
  three review-fix commits inside #451 close #452 (Diary-ancestor tree-search scopes refused,
  fail closed), #453 (refresh writes compare-and-set against the ciphertext it started from),
  #454 (Cancel/Disconnect during the device-code exchange wins over a pending login) and #455
  (`x-noevia-provider-message` honoured only for the ChatGPT adapter). #447 itself stays open —
  #451 only references it, and its own open question (a live sign-in test) is still outstanding.
  Deployed as `cowork-web:b61a914`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env schema changes — `chatgptOAuth` reads its own env var with a
  `false` default and needed no new required key; `.env` backup `.env.bak.before-b61a914`, live
  Compose file backup `docker-compose.yml.bak.before-b61a914`. Image tag and release directory
  use the 7-character short SHA (`b61a914`), matching the existing convention.

#449 (`5ccdd9d`), #460 (`a350d4f`) and #461 (`ea1ed04`) were already merged into `main` by a
previous release agent but not yet deployed; this release ships them for the first time. #451
(`feat/447-chatgpt-oauth-provider`, head `5985b35`) already had `main` merged in and was pushed
with CI running; `gh pr checks 451 --watch` finished 8/8 green (including "CI required"). Head
SHA confirmed as `5985b353c7ad589fd159b8b37610c298d8da0188`, `mergeStateStatus: CLEAN`. Marked
ready and squash-merged (`--match-head-commit 5985b353c7ad589fd159b8b37610c298d8da0188`) to
`b61a914b6f0bf974588b399096e31d109da48fdd`; `origin/main` advanced `ea1ed04` → `b61a914`. Remote
branch `feat/447-chatgpt-oauth-provider` deleted on merge. #452–#455 closed automatically on
merge; GitHub also auto-closed #447 despite the PR only saying "Refs #447" (no "Closes" keyword
against it) — reopened with an explanatory comment, since #451's own open questions call out that
a live sign-in test is still needed before #447 can close. Diff for this release limited to
`apps/web`, `THIRD_PARTY_NOTICES.md` and `docs/`, no `services/`, so this stayed a web-only
release; no other sidecar was touched. Worktrees/branches `/tmp/noevia-fix-446`,
`/tmp/noevia-fix-450`, `/tmp/noevia-fix-448` and `/tmp/noevia-feat-447` (and the matching local
branches `fix/448-glass-sticky-strips`, `fix/450-code-access-flash`,
`feat/447-chatgpt-oauth-provider`) removed after merge; `/tmp/noevia-fix-456`
(`fix/456-457-459-dup-fetches`, unfinished) was left alone.

Archived `main`@`b61a914` with `git archive`, scp'd to `releases/b61a914` (no git creds on the
box); built only `cowork-web:b61a914` with `COWORK_VERSION=b61a914`. `.env` backed up to
`.env.bak.before-b61a914` first. Candidate verification used synthetic in-image checks before
cutover: `docker run --rm --entrypoint cat cowork-web:b61a914 /app/dist/version.json` returned
`{"version":"b61a914"}`, the built `index.html`'s asset references (`index-CCKOIjC1.js`,
`index-kv_iUv4Y.css`) were confirmed present in the same image's `/app/dist/assets`, and
`grep chatgptOAuth /app/server/features.cjs` inside the candidate confirmed the flag is
registered with `env: 'NOEVIA_FEATURE_CHATGPT_OAUTH'`. `current` symlink and `COWORK_VERSION`
updated; every other `*_VERSION` left untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`,
`MODEL_MANAGER_VERSION=1c87ab0`, `DOCLING_VERSION=2026-09-21`,
`CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Applied with the installed preflight, web-only: `bash
/mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

`cowork-web-1` came up healthy, `RestartCount` 0, `Image=cowork-web:b61a914`,
`StartedAt=2026-09-27T03:40:45Z`. `cowork-diary-1`, `cowork-ocr-1`, `cowork-model-loader-1`,
`cowork-code-sandbox-1`, `cowork-laya-1`, `cowork-docling-1`, `cowork-llama-1` and `cowork-kiwix-1`
all kept their pre-release container `Id` and `StartedAt` unchanged, confirming `--no-deps` did
not recreate them. (`cowork-embed-1` is the same pre-existing, unrelated crash-loop noted in the
`b84b3b8` entry below — its `Id` is unchanged; its `RestartCount` continued climbing through the
deploy window, not caused by this release.) `https://noevia.daserver.work/` returned `200`,
`/api/profile` returned `401`, and the served `index.html` referenced
`index-CCKOIjC1.js`/`index-kv_iUv4Y.css`, both confirmed present in the deployed image's
`dist/assets` via `docker exec`. A read-only, unauthenticated check inside `cowork-web-1`
(`node -e "require('/app/server/features.cjs').createFeatures({env:process.env}).enabled('chatgptOAuth')"`)
returned `false`; no env var was set and the flag was not flipped.

Rollback (not needed — release succeeded): `ln -sfn /mnt/docker/appdata/cowork/releases/b84b3b8
/mnt/docker/appdata/cowork/current`, restore `.env` from `.env.bak.before-b61a914`, then re-run
the same guarded `up.sh --no-build --no-deps --wait web`.

## Release web b84b3b8 — 2026-09-26 (merge #445, deploy #445)

### Services

- **Web:** [#445](https://github.com/sbstndalton/noevia/pull/445) closes #442, #443 — the Vision
  routing role now only offers vision-capable chat models in its picker; the server-side `PUT
  /api/auto-roles` handler rejects a Vision role assignment for a non-chat model (for example
  Laya) instead of silently accepting it. A role that was previously saved with a model that is no
  longer suitable for that role (removed, or no longer chat/vision-capable) now renders with a
  labelled, disabled placeholder instead of a blank/empty selector. Model sizes are now formatted
  with a single shared one-decimal-GB formatter (`apps/web/src/model-size.ts`) used consistently
  across the composer model picker, the Library tab and the Your Models settings list, closing the
  size-unit mismatch between those surfaces — deployed as `cowork-web:b84b3b8`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup
  `.env.bak.before-b84b3b8`. Image tag and release directory use the 7-character short SHA
  (`b84b3b8`), matching the existing convention.

PR #445 (`fix/442-443-vision-role-size-units`) was draft with CI green (8/8, including "CI
required") at head `210c451a766200f8756d6e1b4938bdf556d5807a`, which already included `main` after
#444 (`origin/main` was still at `6d7f8e7`, the Batch 14 changelog commit, when this release
began — no re-merge was needed). Diff limited to `apps/web` (server routes + frontend), no
`services/`, so this was a web-only release; no other sidecar was touched. Marked ready and
squash-merged (`--match-head-commit 210c451a766200f8756d6e1b4938bdf556d5807a`) to `b84b3b8`;
`main`'s tree hash was confirmed identical to the PR head's tree hash post-merge
(`cad4f0554a4858032fbd309fbcf2b640418936dd`). Remote branch `fix/442-443-vision-role-size-units`
and its local worktree (`/tmp/noevia-fix-442`, registered under
`~/.noevia-deps/noevia-base/.git/worktrees`) deleted/removed after merge.

Archived `main`@`b84b3b8` with `git archive`, scp'd to `releases/b84b3b8` (no git creds on the
box); built only `cowork-web:b84b3b8` with `COWORK_VERSION=b84b3b8`. `.env` backed up to
`.env.bak.before-b84b3b8` first. Candidate verification used synthetic in-image checks before
cutover: `docker run --rm --entrypoint cat cowork-web:b84b3b8 /app/dist/version.json` returned
`{"version":"b84b3b8"}`, and the built `index.html`'s asset references
(`index-CIjrmDNW.js`, `index-Cd6S8biF.css`) were confirmed present in the same image's
`/app/dist/assets`. `current` symlink and `COWORK_VERSION` updated; every other `*_VERSION` left
untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`,
`DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Applied with the
installed preflight, web-only: `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

`cowork-web-1` came up healthy, `RestartCount` 0, `Image=cowork-web:b84b3b8`,
`StartedAt=2026-09-26T13:24:11Z`. `cowork-diary-1`, `cowork-ocr-1`, `cowork-model-loader-1`,
`cowork-code-sandbox-1`, `cowork-laya-1`, `cowork-docling-1`, `cowork-llama-1` and `cowork-kiwix-1`
all kept their pre-release container `Id` and `StartedAt` unchanged, confirming `--no-deps` did
not recreate them. (`cowork-embed-1` was already crash-looping before this deploy, unrelated and
untouched — its `Id` is unchanged; its `RestartCount` continued climbing during the deploy window
consistent with its ongoing restart loop, not this release.) `https://noevia.daserver.work/`
returned `200`, `/api/profile` returned `401`, and the served `index.html` referenced
`index-CIjrmDNW.js`/`index-Cd6S8biF.css`, both confirmed present in the deployed image's
`dist/assets` via `docker exec`. A read-only, unauthenticated `GET /api/auto-roles` from inside
`cowork-web-1` (`docker exec cowork-web-1 curl … http://localhost:8021/api/auto-roles`) returned
`401`; no `PUT` was issued against the endpoint.

Rollback (not needed — release succeeded): `ln -sfn /mnt/docker/appdata/cowork/releases/97bf1eb
/mnt/docker/appdata/cowork/current`, restore `.env` from `.env.bak.before-b84b3b8`, then re-run
the same guarded `up.sh --no-build --no-deps --wait web`.

## Release web 97bf1eb — 2026-09-26 (merge #444, deploy #444)

### Services

- **Web:** [#444](https://github.com/sbstndalton/noevia/pull/444) closes #439, #440 — the sidebar
  search field now supports arrow-key navigation through its results (`ArrowDown` from the field
  moves into the list, `ArrowDown`/`ArrowUp` move between results), `Enter` opens the active
  result, and `Escape` from a result returns focus to the search field rather than closing search
  outright (a second `Escape`, from the field itself, keeps the existing clear/close behaviour); a
  polite `aria-live` region announces the result count, and the matched substring is highlighted
  (`<mark class="sidebar-search-highlight">`), including queries built from regex metacharacters,
  which match literally rather than throwing; nested (in-project) chat rows now open the same
  right-click context menu as top-level rows, including the archive+undo path from #432 — deployed
  as `cowork-web:97bf1eb`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup
  `.env.bak.before-97bf1eb`. Image tag and release directory use the 7-character short SHA
  (`97bf1eb`), matching the existing convention.

PR #444 (`fix/439-440-sidebar-search-nested-menu`) was draft with CI green (7/7) at head
`e7d9b87c852c2c4cc948bf50d66c06c888a68c50`, based on `origin/main` at `8b07148` — by the time of
this release `origin/main` had advanced to `7fc3fa5` (Batch 13's #441, which also touched every
`apps/web/src/i18n/*.ts` file). `git merge origin/main` in the PR worktree resolved automatically
with no manual conflict markers (the two PRs' `i18n` key additions and CSS landed on different
lines; #441 touched `ChatView.tsx`/`ComposerActions.tsx`/`ComposerTextarea.tsx`, #444 touched only
`Sidebar.tsx`, so neither PR's component edits overlapped) — merge commit `2029b90`. Full
verification against a fresh `npm run build` of the merged tree (`apps/web`) found one adjacency
regression the file-level merge couldn't catch: `qa/composer-434.cjs` passed, but
`qa/sidebar-search-nested-menu.cjs` failed a strict-mode Playwright assertion because #441 added
its own `sr-only role="status" aria-live="polite"` span to `ChatView` (#437's drop-hint
announcement) that now coexists with #444's sidebar result-count live region, and the QA suite's
locator matched both. Fixed by scoping the suite's locator to `.sidebar` (commit `3c54c3d`,
QA-only, no application code changed) rather than changing either live region's behaviour. `npm
test` (2368/2368), `npm run typecheck`, `npm run build` and `npm run lint:design` all passed on
the final tree; `qa/sidebar-search-nested-menu.cjs` (11/11) and `qa/composer-434.cjs` (8/8) both
passed against a fresh build of the final commit. CI went green (7/7) again at the new head after
pushing the QA fix. Marked ready and squash-merged (`--match-head-commit
3c54c3d9d908eb7838d131e5761933ac886c2f82`) to `97bf1eb`; `main`'s tree hash was confirmed identical
to the PR head's tree hash post-merge. Remote branch `fix/439-440-sidebar-search-nested-menu` and
its local worktree (`/tmp/noevia-fix-439-440`) deleted after merge. The already-stale
`/tmp/noevia-fix-434` worktree entry (Batch 13 had already merged and removed the directory, but
left a dangling `git worktree` registration) was pruned in the same pass.

Built `cowork-web:97bf1eb` on DaServer from `releases/97bf1eb` (git archive of `main`@`97bf1eb`,
scp'd — no git creds on the box); the Dockerfile's own `node --test tests/*.test.cjs` gate passed
before `vite build`. Before cutover, the freshly built candidate image was smoke-tested standalone
(`docker run`, loopback-only port, no production volumes/network): `/api/setup/status` → `200`,
`/api/profile` → `401`, and the served index referenced `index-BeW2mCs9.js`, matching the build
output; the candidate container was then removed without touching any live container. `current`
symlink and `COWORK_VERSION` updated; every other `*_VERSION` left untouched
(`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`,
`DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Applied with the installed
preflight, web-only: `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

`cowork-web-1` came up healthy, `RestartCount` 0, `Image=cowork-web:97bf1eb`,
`Started=2026-09-26T13:00:23Z`. `cowork-diary-1`, `cowork-ocr-1`, `cowork-model-loader-1`,
`cowork-code-sandbox-1`, `cowork-laya-1`, `cowork-docling-1`, `cowork-llama-1` and `cowork-kiwix-1`
all kept their pre-release container `Id` and `StartedAt` unchanged, confirming `--no-deps` did
not recreate them. (`cowork-embed-1` was already crash-looping before this deploy, unrelated and
untouched — its `Id` is unchanged; its `RestartCount` continued climbing during the deploy window
consistent with its ongoing restart loop, not this release.) `https://noevia.daserver.work/`
returned `200`, `/api/profile` returned `401`, and the served `index.html` referenced
`index-BeW2mCs9.js`/`index-Cd6S8biF.css`, both confirmed present in the deployed image's
`dist/assets` via `docker exec`.

Rollback (not needed — all checks passed): `ssh daserver 'ln -sfn
/mnt/docker/appdata/cowork/releases/69712fb /mnt/docker/appdata/cowork/current && cp
/mnt/docker/appdata/cowork/config/.env.bak.before-97bf1eb
/mnt/docker/appdata/cowork/config/.env && cd /boot/config/plugins/compose.manager/projects/Cowork
&& bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web'`.

## Release web 69712fb — 2026-09-26 (merge #441, deploy #441)

### Services

- **Web:** [#441](https://github.com/sbstndalton/noevia/pull/441) closes #434, #435, #436, #437 —
  the composer textarea now syncs its own height to content on every value change (typing, draft
  restore, edit-message load, and the clear right after send), growing up to each surface's own
  CSS `max-height` and then scrolling internally, and shrinking back down after send; focus now
  returns to the composer textarea after Stop and after a completed Send on desktop, without
  stealing focus the user has since moved elsewhere (not on touch, where nothing was disabled);
  "Jump to latest" gets a `min-height: 44px` touch target under `@media (pointer: coarse)`, with
  the fine-pointer pill unchanged; and dropping files onto the composer or the whole chat pane now
  runs through the existing attachment pipeline (`uploadAttachments`, extracted out of
  `ComposerActions` so there is one implementation, not two), with the same size limits and error
  copy as the picker, a visible drag-over state, and an `aria-live` announcement in every locale —
  deployed as `cowork-web:69712fb`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup
  `.env.bak.before-69712fb`. Image tag and release directory use the 7-character short SHA
  (`69712fb`), matching the convention from before release 11911da07a6512a39f2aa6347dda5ee5ac8bbd03
  (Batch 12), which had used the full 40-character SHA.

PR #441 was draft with CI green (7/7) at head `8894080`, based on `origin/main` at `8b07148`
(already current, so no main-merge or worktree rebase was needed). Marked ready and squash-merged
(`--match-head-commit 88940809a164df61652d0ee00ea7c260def7644e`) to `69712fb`. Remote branch
`fix/434-437-composer` and its local worktree/clone (`/tmp/noevia-fix-434`) deleted after merge.

Built `cowork-web:69712fb` on DaServer from `releases/69712fb` (git archive of `main`@`69712fb`,
scp'd — no git creds on the box). The build ran all 687 server/unit tests (687 pass, 0 fail) before
`vite build`. `current` symlink and `COWORK_VERSION` updated; every other `*_VERSION` left
untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`,
`DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Applied with the installed
preflight, web-only: `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

`cowork-web-1` came up healthy, `RestartCount` 0, `Image=cowork-web:69712fb`,
`Started=2026-09-26T12:37:40Z`. `cowork-diary-1`, `cowork-ocr-1`, `cowork-model-loader-1`,
`cowork-code-sandbox-1`, `cowork-laya-1`, `cowork-docling-1`, `cowork-llama-1` and `cowork-kiwix-1`
all kept their pre-release container `Id` and `StartedAt` unchanged, confirming `--no-deps` did
not recreate them. (`cowork-embed-1` was already crash-looping before this deploy, unrelated and
untouched — its `Id` is unchanged; its `StartedAt` moved during the deploy window consistent with
its ongoing restart loop, not this release.) `https://noevia.daserver.work/` returned `200`,
`/api/profile` returned `401`, and the served `index.html` referenced
`index-Cny5uga5.js`/`index-s3O06YwV.css`, both present in the built image's `dist/assets`.

Rollback (not needed — all checks passed): `ssh daserver 'ln -sfn
/mnt/docker/appdata/cowork/releases/11911da07a6512a39f2aa6347dda5ee5ac8bbd03
/mnt/docker/appdata/cowork/current && cp
/mnt/docker/appdata/cowork/config/.env.bak.before-69712fb
/mnt/docker/appdata/cowork/config/.env && cd /boot/config/plugins/compose.manager/projects/Cowork
&& bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web'`.

## Release web 11911da — 2026-09-26 (merge #438, deploy #438)

### Services

- **Web:** [#438](https://github.com/sbstndalton/noevia/pull/438) closes #387, #431 —
  `useChatScroll`'s auto-scroll effect now compares the live `scrollTop` against the value it
  itself last wrote, synchronously, before deciding whether to pin again, so a fast enough token
  stream can no longer overwrite a real scroll-up from the reader (any input method, including a
  scrollbar drag) with a stale pin-to-bottom write; chat/Diary Markdown lists (`MarkdownPreview`'s
  `buildList` in `DiaryModal.tsx`) now parse a contiguous run of list-item lines into a real,
  nested `<ul>`/`<ol>`/`<li>` tree instead of flat `<p class="md-bullet">` lines — nested lists
  nest structurally, ordered lists keep their model-given start number via `<ol start>`, and task
  items render as real disabled checkboxes with correct checked state — deployed as
  `cowork-web:11911da`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup
  `.env.bak.before-11911da07a6512a39f2aa6347dda5ee5ac8bbd03`.

PR #438 was draft with CI green (7/7) at head `8521c95`, based on `origin/main` at `25fa6a6`
(already current, so no main-merge or worktree rebase was needed). Marked ready and
squash-merged (`--match-head-commit 8521c959520d6e6abfcdb7afdf0c44b167de2916`) to `11911da`.
Remote branch `fix/387-431-stream-scroll-md-lists` and its local worktree/branch (under
`noevia-fix-387`) deleted after merge.

Built `cowork-web:11911da` on DaServer from `releases/11911da` (git archive of `main`@`11911da`,
scp'd — no git creds on the box). Before cutover, the candidate image was smoke-tested standalone
(container run without `--network` changes, removed after): served `200` on `/`, and
`dist/index.html`'s asset references matched `dist/assets` in the image. `current` symlink and
`COWORK_VERSION` updated; every other `*_VERSION` left untouched (`DIARY_VERSION=f6444b4`,
`OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`, `DOCLING_VERSION=2026-09-21`,
`CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Applied with the installed preflight, web-only:
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

`cowork-web-1` came up healthy, `RestartCount` 0, `Image=cowork-web:11911da...`,
`Started=2026-09-26T12:04:45Z`. `cowork-diary-1`, `cowork-ocr-1`, `cowork-model-loader-1`,
`cowork-code-sandbox-1`, `cowork-laya-1` and `cowork-docling-1` all kept their pre-release `Id`
and `StartedAt` unchanged, confirming `--no-deps` did not recreate them. (`cowork-embed-1` was
already crash-looping before this deploy, unrelated and untouched — its restart count moved from
973 to 975 across the deploy window, consistent with its ongoing loop, not this release.)
`https://noevia.daserver.work/` returned `200`, `/api/profile` returned `401` (both via the public
tunnel and directly on the box), and the served `index.html` referenced
`index-F2PShjwy.js`/`index-DUixMTw4.css`, both present in the built image's `dist/assets`.

Rollback (not needed — all checks passed): `ssh daserver 'ln -sfn
/mnt/docker/appdata/cowork/releases/63d1187 /mnt/docker/appdata/cowork/current && cp
/mnt/docker/appdata/cowork/config/.env.bak.before-11911da07a6512a39f2aa6347dda5ee5ac8bbd03
/mnt/docker/appdata/cowork/config/.env && cd /boot/config/plugins/compose.manager/projects/Cowork
&& bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web'`.

## Release web 63d1187 — 2026-09-26 (merge #432 #433, deploy #432 #433)

### Services

- **Web:** [#432](https://github.com/sbstndalton/noevia/pull/432) closes #362, refs #355 (kept open — the
  project-row rename Escape/Enter focus fix is hardened defensively but not confirmed reproduced/fixed
  live) — `returnFocusToRow` now forces the CSS properties that actually gate `.row-actions` visibility
  (`opacity`/`pointer-events` at desktop width, `width`/`overflow` at `<=700px`) instead of the irrelevant
  `display`, and falls back to the row's own always-visible button so focus can never silently drop to
  `<body>`, across all three inline-rename call sites; the row's own "…" menu **Archive** item now routes
  through the same `archiveChat()` + undo-toast path as the hover quick-archive icon at every width, not
  just desktop, fixing the only reachable archive path on narrow/touch layouts. [#433](https://github.com/sbstndalton/noevia/pull/433)
  closes #428, #316, #429, #430, #333 — the Projects toolbar's filter/Sort/New row is vertically centered
  and the tab-row divider has clearance at every width again (`.projects-head`'s `padding-bottom:0` had
  zeroed it); the no-active-project model sheet's "Open a project…" text no longer clips its first glyph
  (`.mp-col`'s inset now also applies to the no-project early-return path); the home (`/`) empty state is
  promoted to a real `<h1>`, and `/models` gained a visually-hidden `<h2>` ("Your models") so neither page
  skips a heading level; and `qa/mtp.cjs` no longer fails against Diary — its MTP-acceptance check now
  sends one synthetic message first instead of asserting on a footer that #365 deliberately hides until a
  chat has content — deployed together as `cowork-web:63d1187`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-63d1187`.

Both PRs were draft with CI green (7/7 each) against `origin/main` at `e8123c9`; `gh pr diff --name-only`
confirmed disjoint files (#432: `Sidebar.tsx` + its qa script/test; #433: `ChatView.tsx`, `LibraryTab.tsx`,
CSS, four qa scripts) and neither touched `services/`, so this was a web-only release. Marked ready and
squash-merged #432 first (`--match-head-commit 122ad7e`) to `c35266f`, which auto-closed #362 and left
#355 open as intended. #433's worktree (`/tmp/noevia-fix-428`) then merged `origin/main` (`c35266f`) with
no conflicts (disjoint files), pushed the new head `af10341`, waited for CI green again, then squash-merged
(`--match-head-commit af10341`) to `63d1187`. Remote/local branches for both and worktrees
`/tmp/noevia-fix-355b` and `/tmp/noevia-fix-428` deleted after merge.

Built `cowork-web:63d1187` on DaServer from `releases/63d1187` (git archive of `main`@`63d1187`, scp'd —
no git creds on the box). `current` symlink and `COWORK_VERSION` updated; every other `*_VERSION` left
untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`,
`DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Applied with the installed
preflight, web-only: `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

`cowork-web-1` came up healthy, `RestartCount` 0, `Image=cowork-web:63d1187`,
`Started=2026-09-26T11:53:07Z`. `cowork-diary-1`, `cowork-ocr-1`, `cowork-model-loader-1`,
`cowork-code-sandbox-1`, `cowork-laya-1`, `cowork-docling-1`, `cowork-llama-1` and `cowork-kiwix-1` all
kept their pre-release `Id` and `StartedAt` unchanged, confirming `--no-deps` did not recreate them.
(`cowork-embed-1` was already crash-looping before this deploy, unrelated and untouched.)
`https://noevia.daserver.work/` returned `200`, `/api/profile` returned `401`, and the served
`index.html` referenced `index-Ny00E2FY.js`/`index-jJp6eGxJ.css`, both present in the built image's
`dist/assets`.

Rollback (not needed — all checks passed): `ssh daserver 'ln -sfn /mnt/docker/appdata/cowork/releases/778f855
/mnt/docker/appdata/cowork/current && cp /mnt/docker/appdata/cowork/config/.env.bak.before-63d1187
/mnt/docker/appdata/cowork/config/.env && cd /boot/config/plugins/compose.manager/projects/Cowork &&
bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env
-- -d --no-build --no-deps --wait --wait-timeout 180 web'`.

## Release web 778f855 — 2026-09-26 (merge #427, deploy #427: header/container parity #413 #414 #415)

### Services

- **Web:** [#427](https://github.com/sbstndalton/noevia/pull/427) closes #413, #414, #415 (#426 already closed) — one shared `.settings-title` page header across Settings, Customise and Projects (Diary keeps its compact top bar via a new `--diary-gutter` token); the four remaining borderless `.card-list` panels that logically belong to a grouped settings list (Service status, the Diary toggle, Users, Models summary) now render on `.set-rows`; `CodingSidebarLists`/`useActiveCodeTasks` list real workspace Code tasks in the sidebar instead of a placeholder hint; and `/api/models/*` responses missing an expected array/record field (`downloads`, `models/updates`, `backends`, `host`) now default to `[]`/`{}` instead of crashing on the partial body — deployed as `cowork-web:778f855`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-778f855`.

PR #427 (head `215d400`) was draft with CI green (7/7) against `origin/main` at `6db20fc`. No
`services/` changes, so this was a web-only release. Marked ready, squash-merged (`--match-head-commit
215d400`) to `778f855`; `origin/main` was still at `6db20fc` at merge time so GitHub applied the
PR's own 27-file diff cleanly (`mergeStateStatus: CLEAN`) with no unrelated main advancement to
reconcile. Worktree `/tmp/noevia-fix-413` and both copies of `fix/413-415-headers-containers`
deleted after merge.

Built `cowork-web:778f855` on DaServer from `releases/778f855` (git archive of `main`@`778f855`,
scp'd — no git creds on the box). `current` symlink and `COWORK_VERSION` updated; every other
`*_VERSION` left untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`,
`MODEL_MANAGER_VERSION=1c87ab0`, `DOCLING_VERSION=2026-09-21`,
`CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Applied with the installed preflight, web-only: `bash
/mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env
-- -d --no-build --no-deps --wait --wait-timeout 180 web`.

`cowork-web-1` came up healthy, `RestartCount` 0, `Image=cowork-web:778f855`,
`Started=2026-09-26T10:59:27Z`. `cowork-diary-1`, `cowork-ocr-1` and `cowork-model-loader-1` kept
their pre-release `Id` and `StartedAt` unchanged, confirming `--no-deps` did not recreate them.
`https://noevia.daserver.work/` returned `200`, `/api/profile` returned `401`, and the served
`index.html` referenced `index-B47VqTZu.js`/`index-Dq9bnOZC.css`, both present in the built
image's `dist/assets`.

Rollback: `ssh daserver 'ln -sfn /mnt/docker/appdata/cowork/releases/39bf823
/mnt/docker/appdata/cowork/current && cp /mnt/docker/appdata/cowork/config/.env.bak.before-778f855
/mnt/docker/appdata/cowork/config/.env && bash
/mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web'`,
then re-verify health, `RestartCount` and the `39bf823` asset hashes.

## Release web 39bf823 — 2026-09-26 (a11y focus/labels #418–#421 #345 #362; settings nav/summary/dedup #374 #422 #423)

### Services

- **Web:** [#424](https://github.com/sbstndalton/noevia/pull/424) closes #418–#421 and #345 (plus reopened #362 toast-keyboard) — `phone.css` row-actions focusable outside hover/focus-within, `ModelPopup` focus restore, `ToolCatalogue` sync-focus on close, `GeneralSettings` theme-tile `aria-labelledby`, `LibraryTab` named action buttons, `Sidebar` quick-archive/undo focus, i18n, 5 new qa scripts — and [#425](https://github.com/sbstndalton/noevia/pull/425) closes #374, #422, #423 — `shell-v2.css` nav head padding, `noevia.css` summary wrap, new `request-cache.ts` de-duplicating `fetchProfile`/`fetchFeatureFlags` with invalidations, `MtpControl`, `SecurityCard` refresh, qa scripts and tests — deployed together as `cowork-web:39bf823`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-39bf823`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-39bf823` (no `docker-compose.override.yml` present to back up).

PR #424 (head `3d88930`) and PR #425 (head `46d0f01`) were both draft with CI green against
`origin/main` at `2c53d24`. #424 was already up to date with `2c53d24` (no local merge needed);
`apps/web`: `npm test` 2296/2296, `typecheck`, `build`, `lint:design` all clean; CI green (7/7);
`qa/sidebar-focus-undo.cjs`, `qa/model-popup-focus.cjs`, `qa/appearance-family-labels.cjs`,
`qa/model-card-labels.cjs` and `qa/tool-catalogue-escape-focus.cjs` each **PASS** against the
built `dist` with `PLAYWRIGHT_MODULE`. Marked ready, squash-merged to `06f1c45`; `git diff`
against `origin/main` empty (tree invariance). Worktree and both copies of
`fix/418-421-345-a11y` deleted.

#425 was then merged against the new `origin/main` (`06f1c45`, i.e. #424) — `ort` auto-merge, no
conflicts across the anticipated overlap in `Sidebar.tsx`, `ModelPopup.tsx`, `GeneralSettings.tsx`,
`ToolCatalogue.tsx` and CSS, keeping both PRs' changes — to `48dde0e`. `npm test` 2303/2303,
`typecheck`, `build`, `lint:design` all clean; CI green (7/7) on the merged branch;
`qa/settings-nav-edge-and-summary-wrap.cjs` and `qa/profile-features-dedup.cjs` each **PASS**
against the built `dist`. Marked ready, squash-merged to `39bf823` (final `main` SHA); `git diff`
against `origin/main` empty. Worktree and both copies of `fix/374-422-423-small` deleted.

Built `cowork-web:39bf823` on DaServer from `releases/39bf823` (git archive of `main`@`39bf823`,
scp'd — no git creds on the box). The candidate image's `dist/version.json` reported `39bf823`
and `dist/assets` contained the expected hashed `index-5ytF-2y4.js`/`index-CdP5s8pR.css` bundles;
a synthetic, isolated candidate container (no live network attach, no real credentials) started
cleanly before cutover. `current` symlink and `COWORK_VERSION` updated; every other `*_VERSION`
left untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`,
`DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Applied with the installed
preflight, web-only: `bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

`cowork-web-1` came up healthy, `RestartCount` 0, `Image=cowork-web:39bf823`,
`Started=2026-09-26T10:25:21Z`. Every other `cowork-*` container and `CloudflaredTunnel` kept
its pre-release `Id` and `StartedAt` unchanged (model-loader, diary, code-sandbox, laya, ocr,
docling, llama, kiwix, Cloudflared) — confirming `--no-deps` did not recreate them.
`cowork-embed-1` kept its pre-existing `Id` through its ongoing crash-loop (#336, unrelated to
this release; `RestartCount` continued climbing on its own schedule during the window).
`https://noevia.daserver.work/` returned `200`, `/api/profile` returned `401`, and the served
`index.html` referenced the same `index-5ytF-2y4.js`/`index-CdP5s8pR.css` hashes baked into the
image.

Rollback: `ssh daserver 'ln -sfn /mnt/docker/appdata/cowork/releases/584bdba
/mnt/docker/appdata/cowork/current && cp /mnt/docker/appdata/cowork/config/.env.bak.before-39bf823
/mnt/docker/appdata/cowork/config/.env && bash
/mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file
/mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web'`,
then re-verify health, `RestartCount` and the `584bdba` asset hashes.

## Release web 584bdba — 2026-09-26 (spacing rhythm: #417)

### Services

- **Web:** [#417](https://github.com/sbstndalton/noevia/pull/417) closes #371–#381 (Apple HIG spacing scale restored across Settings and panes — CSS tokens/families/`noevia.css`/`app.css`/`phone.css`, `SettingsShell` focus-on-deep-link one-liner, density rows, new `qa/spacing-rhythm.cjs`, a `design-lint` rule) — deployed as `cowork-web:584bdba`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-584bdba`, live `docker-compose.yml`/`docker-compose.override.yml` backups `*.bak.before-584bdba`.

PR #417 (head `627f216`) was draft with CI green against an earlier `origin/main`. Main had since
advanced to `6c7fafb` (#412, #416 plus their changelogs); merged `origin/main` into the branch in a
worktree (`ort` auto-merge, no conflicts — including `Sidebar.tsx`, which kept both #416's row-actions
focus fix and this PR's phone touch-target/spacing rules) to `95463ac`. From `apps/web`: `npm test`
2295/2295, `typecheck`, `build`, `lint:design` all clean; CI green (7/7 checks); `qa/spacing-rhythm.cjs`
(180 screenshots, flush=0 clipped=0 small=0 zoom=0 overflow=0 nav-error=0 probe-error=0 — 9 unrelated
`pageerror`s only in the Editorial family, pre-existing and not part of this script's flush/overflow
gate), `qa/sidebar-focus-undo.cjs` (4/4) and `qa/settings-focus-deep-links.cjs` (all scenarios) each
**PASS** against the built `dist` with `PLAYWRIGHT_MODULE`. Marked ready, squash-merged to `584bdba`
(final `main` SHA); `git diff` against `origin/main` is empty, confirming tree invariance. The worktree
and both local+remote copies of `fix/spacing-apple-rhythm` were deleted after merge.

Built `cowork-web:584bdba` on DaServer from `releases/584bdba` (git archive of `main`@`584bdba`, scp'd —
no git creds on the box); the in-image build ran all 622 tests before `npm run build`, and
`stamp-icons` reported `version=584bdba`. The candidate image's `version.json` reported `584bdba` and
`dist/assets` contained the expected hashed `index-*.js`/`index-*.css` bundles before cutover. `current`
symlink and `COWORK_VERSION` updated; every other `*_VERSION` left untouched (`DIARY_VERSION=f6444b4`,
`OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`, `DOCLING_VERSION=2026-09-21`,
`CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Deployed with the guarded `tools/preflight/up.sh --env-file
config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/`
**200**; `/api/profile` **401**; served `index-B_EOWjkW.css` / `index-CPLXOJtR.js` match the image's
`dist/assets`. Every other `cowork-*` container and `CloudflaredTunnel` kept identical container `Id`
and `State.StartedAt` (model-loader, diary, code-sandbox, laya, ocr, docling, llama, kiwix).
`cowork-embed-1` remains in its pre-existing crash loop (#336, unrelated, untouched — same container
`Id`, `RestartCount` rose 786→788 from its own ongoing restarts, not recreated). No chat sends, model
tunes, or Diary access were performed; no other container was rebuilt or recreated.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/3cf7233 /mnt/docker/appdata/cowork/current &&
cp /mnt/docker/appdata/cowork/config/.env.bak.before-584bdba /mnt/docker/appdata/cowork/config/.env &&
bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env
-- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release web 3cf7233 — 2026-09-26 (two reviewed fixes: #412, #416)

### Services

- **Web:** [#412](https://github.com/sbstndalton/noevia/pull/412) fix #410 (`server/routes/plugin-directory.cjs` gives MCP starter servers distinct, readable titles instead of a shared fallback; test), [#416](https://github.com/sbstndalton/noevia/pull/416) fix #355 #362 #406 (`Sidebar.tsx` restores focus into hover-hidden row actions after search Escape and inline rename Escape/Enter, and fires a `workspace-changed` event after archive/Undo so other mounted readers refresh; `server/spa-routes.cjs` serves the SPA shell for `/c`, `/c/`, `/p`, `/p/` instead of a raw 404; new `qa/sidebar-focus-undo.cjs`, extended `qa/url-history.cjs`; tests) — deployed as `cowork-web:3cf7233`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-3cf7233`, live `docker-compose.yml`/`docker-compose.override.yml` backups `*.bak.before-3cf7233`.

Both PRs were draft with CI green against `origin/main` at `2c7488d` at the start of this release.
#412 (`c70ce3d`) merged `origin/main` cleanly (`ort` auto-merge, no conflicts) to `0639102`; `npm test`
2291/2291, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `4b38263`. #416
(`faa6b1c`) then merged `origin/main` (the merge had been started against `2c7488d`, before #412 landed)
cleanly — `ort` auto-merge, no conflicts, only `docs/changelog.md` — to `39ee9a6`; `npm test` 2289/2289,
`typecheck`, `build`, `lint:design` clean; `qa/sidebar-focus-undo.cjs` (4/4) and `qa/url-history.cjs`
(11/11, including the `/c`, `/c/`, `/p`, `/p/` SPA-shell fallback) both **PASS** against the built `dist`
with `PLAYWRIGHT_MODULE`; CI green (including `offline-contract`); squash-merged to `3cf7233` (final
`main` SHA — this squash lands cleanly on top of #412's already-merged `plugin-directory.cjs` change,
which is why `git diff` against `origin/main` shows exactly that file). All worktrees and their
local+remote branches were deleted after merge. The pre-existing spacing branch (`fix/spacing-apple-rhythm`)
was left untouched, as scoped.

Built `cowork-web:3cf7233` on DaServer from `releases/3cf7233` (git archive of `main`@`3cf7233`, scp'd —
no git creds on the box). A disposable, network-isolated candidate container confirmed `/` **200**,
`/api/profile` **401**, `/c` and `/p/` **200** `text/html`, `/api/nope` JSON, and that the image's
`dist/assets` contains the exact `index-CfeaRzvk.js` / `index-CW-35hg6.css` referenced by `index.html`
and `version.json` reporting `3cf7233`, before cutover. `current` symlink and `COWORK_VERSION` updated;
every other `*_VERSION` left untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`,
`MODEL_MANAGER_VERSION=1c87ab0`, `DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`).
Deployed with the guarded `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait
--wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**
`text/html`; `/api/profile` **401**; `/c` and `/p/` **200** `text/html`; `/api/nope` JSON. Served
`index-CfeaRzvk.js` / `index-CW-35hg6.css` match both the public page and the image's `dist/assets`.
Every other `cowork-*` container and `CloudflaredTunnel` kept identical container `Id` and
`State.StartedAt` (model-loader, diary, code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1`
remains in its pre-existing crash loop (#336, unrelated, untouched — same container `Id`, `RestartCount`
rose 762→776 from its own ongoing restarts, not recreated). No chat sends, model tunes, or Diary access
were performed; no other container was rebuilt or recreated.

Rollback: `ln -sfn releases/0a8cc31 current`, restore `.env.bak.before-3cf7233` (`COWORK_VERSION=0a8cc31`),
re-run `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release web 0a8cc31 — 2026-09-26 (three reviewed fixes: #407, #411, #408)

### Services

- **Web:** [#407](https://github.com/sbstndalton/noevia/pull/407) fix #399 (repair remaining stale `qa/` account-popover locators, no app code), [#411](https://github.com/sbstndalton/noevia/pull/411) fix #409 (`ModelPopup`/`ModelsSettings` filter out non-chat models, `routes/projects.cjs` rejects a non-chat model with 400, `chat.cjs` returns 409 for a stale non-chat manual project model via `chat-model-kind.cjs`, `index.cjs` wiring, tests), [#408](https://github.com/sbstndalton/noevia/pull/408) fix #401 #403 #404 #405 (`settings-focus.ts` + `SettingsShell`/`AccountMenu`/`Sidebar`/`App.tsx` return focus to whatever opened Settings, `routes.ts` gives every section its own `/settings/<id>` alias, truthful status dots, `auth.cjs` `listSessions` now takes the caller's own `session.id_hash` and marks that row `current`, one date formatter shared across Settings/models components, i18n, `qa/settings-focus-deep-links.cjs`) — deployed as `cowork-web:0a8cc31`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-0a8cc31`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-0a8cc31`.

All three PRs were draft with CI green against `origin/main` at `2c0d59c` at the start of this release.
#407 (`511f8a7`) merged `origin/main` cleanly (`ort` auto-merge, no conflicts) to `0b59fdd`; `npm test`
2262/2262, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `aead398`. #411
(`db447ce`) then merged `origin/main` (now carrying #407): clean `ort` auto-merge, no conflicts, to
`e563658`; `npm test` 2273/2273, `typecheck`, `build`, `lint:design` clean; CI green (including
`offline-contract`); squash-merged to `637f003`. #408 (`2472e3e`) then merged `origin/main` (now carrying
#411's `chat.cjs`/`ModelsSettings` changes): the anticipated conflicts in `ModelsSettings.tsx`,
`App.tsx` and `Sidebar.tsx` did not materialize — `ort` auto-merged cleanly, both sides kept, to
`bb4a63c`; `npm test` 2289/2289, `typecheck`, `build`, `lint:design` clean, and
`qa/settings-focus-deep-links.cjs` (run against the built `dist` with `PLAYWRIGHT_MODULE`) **PASS**; CI
green; squash-merged to `0a8cc31` (final `main` SHA). `git diff --quiet <head> origin/main` confirmed
tree-identical after each squash. All three worktrees and their local+remote branches were deleted
after merge. The pre-existing spacing branch and #410 were left untouched, as scoped.

Built `cowork-web:0a8cc31` on DaServer from `releases/0a8cc31` (git archive of `main`@`0a8cc31`, scp'd —
no git creds on the box). Candidate image confirmed to contain the served `dist/assets/index-*.js`/
`index-*.css` bundle before cutover. `current` symlink and `COWORK_VERSION` updated; every other
`*_VERSION` left untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`,
`MODEL_MANAGER_VERSION=1c87ab0`, `DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`).
Deployed with the guarded `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait
--wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**
`text/html`; `/api/profile` **401**; `/settings/account` **200** `text/html`. Served `index-kKb03zeT.js` /
`index-CW-35hg6.css` match both the public page and the image's `dist/assets`. Every other `cowork-*`
container and `CloudflaredTunnel` kept identical container `Id` and `State.StartedAt` (model-loader, diary,
code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its pre-existing crash loop
(#336, unrelated, untouched — same container `Id`, `RestartCount` rose 755→756 from its own ongoing
restarts, not recreated). No chat sends, model tunes, or Diary access were performed; no other container
was rebuilt or recreated.

Rollback: `ln -sfn releases/592c4d3 current`, restore `.env.bak.before-0a8cc31` (`COWORK_VERSION=592c4d3`),
re-run `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release web 592c4d3 — 2026-09-26 (three reviewed fixes: #400, #395, #402)

### Services

- **Web:** [#400](https://github.com/sbstndalton/noevia/pull/400) fix #392 (repair stale `qa/` phone/sidebar/workspace scripts only, no app code), [#395](https://github.com/sbstndalton/noevia/pull/395) fix #393 (per-chat composer drafts via `chat-drafts.ts`, `ChatView.tsx`, tests), [#402](https://github.com/sbstndalton/noevia/pull/402) fix #396 #397 #398 (`EditProjectModal` focus restore, `ProjectView` delete-chat confirm, project name length shared by `server/project-limits.json` and the client, `ProjectsView`, `noevia.css`, i18n) — deployed as `cowork-web:592c4d3`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-592c4d3`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-592c4d3`, live `docker-compose.override.yml` backup `docker-compose.override.yml.bak.before-592c4d3`.

All three PRs were draft with CI green against `origin/main` at `ff0d4ea` at the start of this release.
#400 (`74bb630`) merged `origin/main` cleanly (`ort` auto-merge, no conflicts) to `e67370e`; `npm test`
2221/2221, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `edcf18d`. #395 (`9cab4ca`)
then merged `origin/main` (now carrying #400): the expected `ChatView.tsx` conflict materialized as a
two-line import-order conflict against #394's already-merged `edit-focus.ts` import — resolved by keeping
both import lines (`chat-drafts.ts` and `edit-focus.ts`), no logic conflict, to `10d6f8a`; `npm test`
2240/2240, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `fff2a02`. #402 (`c284a4d`)
then merged `origin/main` (now carrying #395's `chat-drafts.ts`): clean `ort` auto-merge, no conflicts, to
`e37d7d8`; `npm test` 2262/2262, `typecheck`, `build`, `lint:design` clean; CI green (including
`offline-contract`); squash-merged to `592c4d3` (final `main` SHA). `git diff --quiet <head> origin/main`
confirmed tree-identical after each squash. All three worktrees and their local+remote branches were
deleted after merge. The pre-existing spacing branch and the #399 QA PR were left untouched, as scoped.

Built `cowork-web:592c4d3` on DaServer from `releases/592c4d3` (git archive of `main`@`592c4d3`, scp'd — no
git creds on the box). Candidate image confirmed to contain `server/project-limits.json` and the served
`dist/assets/index-*.js`/`index-*.css` bundle before cutover. `current` symlink and `COWORK_VERSION`
updated; every other `*_VERSION` left untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`,
`MODEL_MANAGER_VERSION=1c87ab0`, `DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`).
Deployed with the guarded `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait
--wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**
`text/html`; `/api/profile` **401**; `/c/abc123` **200** `text/html`. Served `index-C2mIAJXk.js` /
`index-CW-35hg6.css` match both the public page and the image's `dist/assets`. Every other `cowork-*`
container and `CloudflaredTunnel` kept identical container `Id` and `State.StartedAt` (model-loader, diary,
code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its pre-existing crash loop
(#336, unrelated, untouched — same container `Id`, `RestartCount` rose 700→701 from its own ongoing
restarts, not recreated). No chat sends, model tunes, or Diary access were performed; no other container
was rebuilt or recreated.

Rollback: `ln -sfn releases/f70e969 current`, restore `.env.bak.before-592c4d3` (`COWORK_VERSION=f70e969`),
re-run `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

---

## Release web f70e969 — 2026-09-26 (two reviewed fixes: #394, #391)

### Services

- **Web:** [#394](https://github.com/sbstndalton/noevia/pull/394) fix #387 #388 #389 #390 #355 (`useChatScroll` follow guard + "Jump to latest" while streaming; Markdown h2–h6/blockquote grouping and remote images rendered as new-tab links via `markdown-image.ts`; edit-cancel focus restore via `edit-focus.ts`; `ChatView.tsx`, `DiaryModal.tsx`, `app.css`, `diary-tab.css`, i18n), [#391](https://github.com/sbstndalton/noevia/pull/391) feat #359 shareable chat/project/Settings URLs with working Back/Forward (`routes.ts`, `server/spa-routes.cjs` static fallback, `AuthGate` `safeReturnPath` sign-in return, `App.tsx`, `SettingsShell`, `ProjectView`, `PluginsView`, i18n, `qa/url-history.cjs`) — deployed as `cowork-web:f70e969`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-f70e969`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-f70e969`, live `docker-compose.override.yml` backup `docker-compose.override.yml.bak.before-f70e969`.

Both PRs were draft with CI green and `MERGEABLE` against `origin/main` at `d805cfd` at the start of this
release. #394 (`fa0f63f`) already had `d805cfd` as an ancestor, so `git merge origin/main` was a no-op and no
new merge commit was needed; squash-merged directly to `532b049` (`npm test` 2208/2208, `typecheck`, `build`,
`lint:design` clean; GitHub Actions CI green). #391 (`5a00528`) then merged `origin/main` (now at `532b049`,
carrying #394) — the expected `App.tsx`/`ChatView`-adjacent conflict did not materialize; the `ort` merge
strategy auto-merged `ChatView.tsx`, `DiaryModal.tsx`, `useChatScroll.ts`, i18n and the new `edit-focus.ts`/
`markdown-image.ts` files cleanly, keeping both PRs' changes intact, producing `704d569`. `npm test`
(2221/2221), `typecheck`, `build`, `lint:design` all clean on the merged worktree; GitHub Actions CI green
on the pushed head. `qa/url-history.cjs` ran against the built dist with a real Chromium
(`PLAYWRIGHT_MODULE` pointed at the codex-runtime `playwright` package, synthetic `page.route` API mocks,
no inference/storage/Diary/network) — all 10 scenarios passed, including the sign-in-returns-to-deep-link
case. Squash-merged #391 → `f70e969` (final `main` SHA). `git diff --quiet <head> origin/main` confirmed
tree-identical after each squash. Both worktrees and their local+remote branches were deleted after merge.

Built `cowork-web:f70e969` on DaServer from `releases/f70e969` (git archive of `main`@`f70e969`, scp'd — no
git creds on the box). `current` symlink and `COWORK_VERSION` updated; every other `*_VERSION` left
untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`,
`DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`; confirmed the `.env` diff before/after
is exactly the one `COWORK_VERSION` line). Deployed with the guarded
`tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**
`text/html`, `/api/profile` **401** `application/json`; served `index-CtQ_CHX0.js`/`index-CeaH-H3n.css` match
the image's `dist/assets` (confirmed from the public page and inside the running container). New SPA fallback
checked directly: `/c/abc123` and `/settings/appearance` both **200** `text/html`; `/api/nope` **401**
`application/json` (never HTML); `/definitely-not-a-route` **404** `application/json` (never HTML). Every
other `cowork-*` container and `CloudflaredTunnel` kept identical container `Id` and `State.StartedAt`
(model-loader, diary, code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its
pre-existing crash loop (#336, unrelated, untouched — `RestartCount` rose 663→671 across the deploy window
from its own ongoing restarts, same container `Id`, not recreated). No chat sends, model tunes, or Diary
access were performed; no other container was rebuilt or recreated.

Rollback: `ln -sfn releases/5430d25 current`, restore `.env.bak.before-f70e969` (`COWORK_VERSION=5430d25`),
re-run `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

---

## Release web 5430d25 — 2026-09-26 (two reviewed fixes: #384, #365/#356)

### Services

- **Web:** [#386](https://github.com/sbstndalton/noevia/pull/386) fix #384 [P1] (`ModelPopup.tsx` sends `{model, routing:'manual'}`; `routes/projects.cjs` model-only PATCH now pins `routing:'manual'` and sets `routingChosen`, so picking a model from the popup atomically pins it instead of leaving it on Auto), [#385](https://github.com/sbstndalton/noevia/pull/385) fix #365 + feat #356 (StatsBar scoped to chat views only via `statsbar-visibility.ts`; Regenerate + Copy reply added to `ChatView` message actions via `regenerate.ts`, `App.tsx` wiring, i18n) — deployed as `cowork-web:5430d25`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-5430d25`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-5430d25`, live `docker-compose.override.yml` backup `docker-compose.override.yml.bak.before-5430d25`.

Both PRs were draft with CI green and `MERGEABLE` at the start of this release (`origin/main` unmoved at
`16ba52d` since the orchestrator's review). #386 (`f599869`) already had `16ba52d` as an ancestor, so no
merge commit was needed; #385 (`1bc6756`) merged `origin/main` cleanly (auto-merge, no conflicts) to pick
up #386's `ModelPopup.tsx`/`routes/projects.cjs` changes, producing `e9c5c53`. `npm test`
(2162→2181 passing), `npm run typecheck` and `npm run build`/`lint:design` were green on both worktrees;
GitHub Actions CI was green on both heads and re-verified after #385's merge commit was pushed. Squash-merged
in order: #386→`443396d`, #385→`5430d25` (final `main` SHA). `git diff --quiet <head> origin/main` confirmed
tree-identical after each squash. Both worktrees and their local+remote branches were deleted after merge.

Built `cowork-web:5430d25` on DaServer from `releases/5430d25` (git archive of `main`@`5430d25`, scp'd — no
git creds on the box). Candidate verified before cutover: `version.json` reports `5430d25`; the built
`dist/assets/*.js` contain the new `msg.regenerate` i18n key; `server/routes/projects.cjs` in the image
contains `routingChosen`. `current` symlink and `COWORK_VERSION` updated; every other `*_VERSION` left
untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`,
`DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Deployed with the guarded
`tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**,
`/api/profile` **401**; served `index-N4RSCO_q.js`/`index-Bj6_HXWs.css` match the image's `dist/assets`
(confirmed both from the public page and inside the running container). In-container check: the built
bundle contains `msg.regenerate` and the live `server/routes/projects.cjs` contains `routingChosen`. Every
other `cowork-*` container and `CloudflaredTunnel` kept identical container `Id` and `State.StartedAt`
(model-loader, diary, code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its
pre-existing crash loop (#336, unrelated, untouched — `RestartCount` rose 611→617 across the deploy window
from its own ongoing restarts, same container `Id`, not recreated). No chat sends, model tunes, or Diary
access were performed; no other container was rebuilt or recreated.

Rollback: `ln -sfn releases/1c87ab0 current`, restore `.env.bak.before-5430d25` (`COWORK_VERSION=1c87ab0`),
re-run `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

---

## Release web + model-loader 1c87ab0 — 2026-09-26 (five reviewed a11y/UX fixes: #345 #346 #352–#363 #366–#368, and deploying #347/#348)

### Services

- **Web:** [#351](https://github.com/sbstndalton/noevia/pull/351) fix #345 #346 (AccountMenu/ToolCatalogue menu semantics, onBlur + mousedown keep-focus, `menu-nav.ts`, scrim tokens, lint rule), [#370](https://github.com/sbstndalton/noevia/pull/370) fix #353 #355 #358 #360 #362 #363 (ToolCatalogue placement via `placeCatalogue()`, Sidebar focus/rename/undo toast, ChatView edit buttons + focus, `useModalDialog` initial focus), [#369](https://github.com/sbstndalton/noevia/pull/369) fix #352 #354 #357 (projects routing heal, selectedToolboxIds, toolbox summaries with connected connectors, ModelPopup/ComposerActions, reply-telemetry fallback, ChatView label), [#364](https://github.com/sbstndalton/noevia/pull/364) fix #361 (Diary active flag; App.tsx `Diary.View` active prop), [#382](https://github.com/sbstndalton/noevia/pull/382) fix #366 #367 #368 (mcp-status directory flag, Sidebar MCP label via `mcp-summary.ts`, PluginsView empty state, CodingWorkspace project picker, App.tsx wiring, i18n) — deployed as `cowork-web:1c87ab0`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** [#347](https://github.com/sbstndalton/noevia/pull/347) fix #342 (discover.py stops offering imatrix files as models) and [#348](https://github.com/sbstndalton/noevia/pull/348) model-loader half — fix #341 (services.py/config.py: probe llama on its real port, honest unknown-model state), both already on `main` since `7a72713` but undeployed — deployed now as `cowork-model-loader:1c87ab0` (built on the box from `releases/1c87ab0/services/model-manager`).
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION` and `MODEL_MANAGER_VERSION`; `.env` backup `.env.bak.before-1c87ab0`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-1c87ab0`, live `docker-compose.override.yml` backup `docker-compose.override.yml.bak.before-1c87ab0`.

All five PRs merged one at a time into `main` from base `31973d5`, each re-merged with the moving
`origin/main` tip and re-verified before squash-merge: #351→`74436e1`, #370→`b13250f` (conflict in
`ToolCatalogue.tsx` — kept #351's no-dialog-role/keepFocusOnMouseDown behaviour together with #370's
inline `placeCatalogue()` layout style), #369→`0b0b88e` (ChatView.tsx auto-merged both edit-action and
reply-telemetry/label changes cleanly), #364→`98641b0`, #382→`1c87ab0` (final `main` SHA; auto-merged
cleanly). Node/TS/build/lint:design green on every merge (2105→2155 tests passing as files were added);
`npm run typecheck` and `npm run lint:design` clean on every merge. GitHub Actions CI green on every
head before merge and again on every re-merged commit before squash.

Built `cowork-web:1c87ab0` and `cowork-model-loader:1c87ab0` on DaServer from `releases/1c87ab0` (git
archive of `main`@`1c87ab0`, scp'd — no git creds on the box). Candidates verified before cutover:
web — `isSidecarModel('nomic-embed-text-v1')` is `true` with `--env-file config/.env`, `routes/health.cjs`
loads; model-loader — `app.api`/`app.main`/`app.services`/`app.discover` import cleanly and the router
exposes `/api/v1/models-ini`, `/api/v1/backends`, `/api/v1/search/repo`. `current` symlink and
`COWORK_VERSION`/`MODEL_MANAGER_VERSION` updated; every other `*_VERSION` left untouched. Deployed with
the guarded `tools/preflight/up.sh --no-build --no-deps --wait`, model-loader first per docs/deployment.md
("models.ini writer"), then web.

Verification: `cowork-model-loader-1` recreated, healthy, `RestartCount=0`; from inside `cowork-web-1`
(the `models` network), `GET /api/v1/backends` reports `cowork-llama-1` `loaded_model:
"gemma-4-E2B_q4_0-it"`; `GET /api/v1/search/repo?repo=bartowski/Qwen_Qwen3.5-4B-GGUF` returned 26 groups,
none an imatrix file; an unauthenticated `PUT /api/v1/models-ini` returned **401** (single-writer endpoint
intact). `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**,
`/api/profile` **401**; served `index-ADr6npT9.js`/`index-zUZs3-6Q.css` match the image's `dist/assets`.
Every other `cowork-*` container and `CloudflaredTunnel` kept identical container `Id` and
`State.StartedAt` (diary, code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its
pre-existing crash loop (#336, unrelated, untouched — `RestartCount` rose 584→587 across the deploy window
from its own ongoing restarts, same container `Id`, not recreated). No chat sends, model tunes, or model
operations were performed; no other container was rebuilt or recreated.

Rollback (web): `ln -sfn releases/7a72713 current`, restore `.env.bak.before-1c87ab0`
(`COWORK_VERSION=7a72713`, `MODEL_MANAGER_VERSION=f6444b4`), re-run
`tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
Rollback (model-loader only): restore `.env.bak.before-1c87ab0`'s `MODEL_MANAGER_VERSION=f6444b4` line and
re-run the same `up.sh ... model-loader`.

---

## Release web 7a72713 — 2026-09-26 (five reviewed fixes: #339–#343)

### Services

- **Web:** [#344](https://github.com/sbstndalton/noevia/pull/344) fix #339 (models-ini-writer.cjs, llamacpp-manager.cjs), [#349](https://github.com/sbstndalton/noevia/pull/349) fix #340 (rag.cjs, routes/health.cjs, GeneralSettings/SettingsView, i18n settings, css), [#350](https://github.com/sbstndalton/noevia/pull/350) fix #343 + #336 guard (routes/models.cjs, models.cjs, model-system.cjs, LibraryTab.tsx, i18n models), [#348](https://github.com/sbstndalton/noevia/pull/348) web half — fix #341 (HardwareTab.tsx, i18n models) — deployed as `cowork-web:7a72713`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** [#347](https://github.com/sbstndalton/noevia/pull/347) fix #342 (discover.py stops offering imatrix files as models) and [#348](https://github.com/sbstndalton/noevia/pull/348) model-loader half — fix #341 (services.py/config.py: probe llama on its real port, honest unknown-model state) — merged, not yet deployed; still `cowork-model-loader:f6444b4`. A model-loader release needs the owner's go.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-7a72713`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-7a72713`.

All five PRs merged one at a time into `main` from base `cfe2fae`, each re-merged with the moving
`origin/main` tip and re-verified before squash-merge: #344→`a2cfb16`, #349→`3a10074`, #350→`9908192`,
#348→`791a17d`, #347→`7a72713` (final `main` SHA). Node/TS/build/lint:design green on every merge
(2052→2091 tests passing as files were added); model-manager pytest green on #348 (91 passed) and #347
(102 passed). Clean i18n-model-file and `noevia.css`/`app.css` auto-merges across #348/#350/#347, no
conflict markers. One local-only false alarm: `apps/web` `npm test` hung/failed intermittently on
`rag.test.cjs` in the #347 worktree due to a concurrent unrelated agent process contending for the
same Mac (a `noevia-fix-366` test run observed live); isolated GitHub Actions CI for #347 (unaffected by
local contention) passed clean, including the actually-changed Model manager suite, and was treated as
authoritative.

Built `cowork-web:7a72713` on DaServer from `releases/7a72713` (git archive of `main`@`7a72713`, scp'd —
no git creds on the box). Candidate verified before cutover with a synthetic read-only check
(`docker run --env-file config/.env cowork-web:7a72713`): `model-system.cjs`'s
`isSidecarModel('nomic-embed-text-v1')` is `true` and `routes/health.cjs` loads. `current` symlink and
`COWORK_VERSION` updated; every other `*_VERSION` left untouched. Deployed with the guarded
`tools/preflight/up.sh --no-build --no-deps --wait web` (web only).

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; every other `cowork-*` container and
`CloudflaredTunnel` kept identical container `Id` and `State.StartedAt` (model-loader, diary,
code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its pre-existing crash loop
(#336, unrelated, untouched — `RestartCount` rose from 560→562 across the deploy window from its own
ongoing restarts, same container `Id`, not recreated). `https://noevia.daserver.work/` **200**,
`/api/profile` **401**; served `index-Cg--Likw.js`/`index-CbJQZWX2.css` match the image's `dist/assets`.
Re-ran the same `isSidecarModel`/`routes/health.cjs` check inside the live `cowork-web-1` container:
same result. No chat sends, model tunes, or model operations were performed.

Rollback if needed: `ln -sfn releases/f6444b4 current`, restore `.env.bak.before-7a72713`
(`COWORK_VERSION=f6444b4`), re-run
`tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

---

## Release model-loader f6444b4 — 2026-09-25 (M3: model-loader is the single writer of models.ini)

### Services

- **Web:** no code change — `cowork-web:f6444b4` recreated once with `MODELS_INI_WRITER=model-loader` ([#319](https://github.com/sbstndalton/noevia/pull/319) web side now active: preset saves, calibration and autotune go through model-loader's CAS endpoint).
- **Diary:** no change — `cowork-diary:f6444b4` (M2, earlier today).
- **Model manager:** [#319](https://github.com/sbstndalton/noevia/pull/319) `PUT /api/v1/models-ini` compare-and-swap endpoint, WRITE_LOCK, immutable `models.ini.noevia-backup-<rev>`, dir fsync (closes #295) — deployed as `cowork-model-loader:f6444b4` (built on the box from `releases/f6444b4/services/model-manager`).
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** `MODEL_MANAGER_VERSION=f6444b4` and `MODELS_INI_WRITER=model-loader` in `config/.env` (backup `.env.bak.before-m3`); the live Compose Manager override gained `MODELS_INI_WRITER: ${MODELS_INI_WRITER:-web}` on the `web` service (it was not passed through before; backup `docker-compose.override.yml.bak.before-m3`). Web's `/llamacpp-config` mount is still read-write; the `:ro` follow-up PR is pending.

Order per docs/deployment.md "models.ini writer": model-loader recreated first (healthy, `RestartCount=0`;
from the web container an unauthenticated `PUT /api/v1/models-ini` returned **401**, proving the endpoint
exists and is token-gated; the previous `5b6d9b6` image had no such route), then the flag added and `web`
recreated (healthy; `MODELS_INI_WRITER=model-loader` confirmed inside the container). Every other `cowork-*`
container and Cloudflared kept identical container IDs; public `/` 200. `cowork-embed-1` stays in its
pre-existing restart loop (#336, untouched).

Not verified here (needs an authenticated session): a preset save through the UI and the resulting
`models.ini.noevia-backup-<rev>` file. No calibration or autotune run was started.

Rollback: set `MODELS_INI_WRITER=web` (or delete the line) in `config/.env` and recreate `web`; to return the
sidecar, restore `.env.bak.before-m3` and recreate `model-loader` with `tools/preflight/up.sh ... model-loader`.

---

## Release diary f6444b4 — 2026-09-25 (M2: Diary tenant assertion + month-file protection)

### Services

- **Web:** no code change — `cowork-web:f6444b4` recreated once so it holds `DIARY_TENANT_KEY` ([#321](https://github.com/sbstndalton/noevia/pull/321) web side now active).
- **Diary:** [#321](https://github.com/sbstndalton/noevia/pull/321) per-request tenant assertion + scoped storage credentials (M2, closes #291 #292), [#326](https://github.com/sbstndalton/noevia/pull/326) month-file protection fix (closes #324) — deployed as `cowork-diary:f6444b4` via `deploy/examples/diary-overlay.sh f6444b4` (agent/ overlay on the running image; `requirements.txt` and `Dockerfile` unchanged since `9b532a8`).
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** live Compose Manager `docker-compose.yml` gained `DIARY_TENANT_KEY: ${DIARY_TENANT_KEY:-}` on both the `diary` and `web` services; `DIARY_TENANT_KEY` (32 random bytes, hex, generated on the host, never printed) added to `config/.env`. Backups: `.env.bak.before-m2`, `.env.bak.before-m2-key`, `.env.bak.before-diary-f6444b4`, `docker-compose.yml.bak.before-m2`, `docker-compose.override.yml.bak.before-m2`; image `cowork-diary:rollback-before-diary-overlay`.

Order followed per docs/deployment.md "Diary tenant key (M2)": (1) compose wiring added, `compose config` clean
with the key empty; (2) diary overlay to `f6444b4` with the key unset (appdata backup
`ab_20260925_170701` verified first; diary logged "DIARY_TENANT_KEY is unset: accepting tenant requests
without X-Cowork-Tenant-Assertion"; health via web 200); (3) key generated into `.env`, `web` recreated
(healthy, `RestartCount=0`, env contains the key, no tenant warning); (4) `diary` recreated with the key.

Verification after step 4: `cowork-diary-1` healthy, `RestartCount=0`; an unsigned tenant request from the
web container (`GET /api/diary/status` with only the bearer + `X-Cowork-User-ID`) returned **401** and diary
logged "tenant assertion rejected: missing or malformed assertion"; `/api/health` via web 200; every other
`cowork-*` container and Cloudflared kept identical container IDs; public `/` 200, `/api/profile` 401.
Not verified here (needs an authenticated browser session, `LEGACY_AUTH_COMPAT=false`): a real Diary tab
read/write through the signed path, covered by the unit suites (diary pytest 415, web
`diary-tenant-assertion.test.cjs`). Direct sidecar clients using `DIARY_LEGACY_USER_ID` stop working now that
the key is set.

Rollback, in this order only: remove `DIARY_TENANT_KEY` from `config/.env` (or restore
`.env.bak.before-m2-key`) and recreate `diary` with `tools/preflight/up.sh ... diary`; then recreate `web` the
same way. Never roll the diary image back to `9b532a8` while web still holds the key; once the key is gone,
`.env.bak.before-diary-f6444b4` + `up.sh ... diary` returns the previous image.

---

## Release f6444b4 — 2026-09-25 (web-only: fix boot crash from 0d602d6 retry)

### Services

- **Web:** [#338](https://github.com/sbstndalton/noevia/pull/338) copies `/app/package.json` into the runtime image and adds a CI boot smoke test; also carries [#322](https://github.com/sbstndalton/noevia/pull/322) `/api/ready` + independent auth tokens + egress bind, [#325](https://github.com/sbstndalton/noevia/pull/325) Docling header-safe names, [#319](https://github.com/sbstndalton/noevia/pull/319) `MODELS_INI_WRITER` at default, [#321](https://github.com/sbstndalton/noevia/pull/321) inert without `DIARY_TENANT_KEY`, [#320](https://github.com/sbstndalton/noevia/pull/320) docs, i18n [#288](https://github.com/sbstndalton/noevia/pull/288)/[#289](https://github.com/sbstndalton/noevia/pull/289)/[#299](https://github.com/sbstndalton/noevia/pull/299)/[#300](https://github.com/sbstndalton/noevia/pull/300), QA [#332](https://github.com/sbstndalton/noevia/pull/332)/[#334](https://github.com/sbstndalton/noevia/pull/334) — deployed as `cowork-web:f6444b4`.
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-f6444b4`; compose files backed up as `docker-compose.yml.bak.before-f6444b4` / `docker-compose.override.yml.bak.before-f6444b4`.

This is a retry of an earlier same-day attempt to deploy `0d602d6`, which crash-looped on a missing
`/app/package.json` in the built image and was rolled back to `2037ffd`; `f6444b4` fixes that build
regression and CI now boots the image before merge.

Source shipped via `git archive` of `origin/main` at `f6444b4` (full:
`f6444b42538d362336b78da0d77d385bb097095a`) to `releases/f6444b4`. Only `cowork-web:f6444b4` was
built; no other image was touched. Candidate verification: `docker run --rm --entrypoint ls
cowork-web:f6444b4 /app/package.json` returned the file (the exact defect that broke `0d602d6`).

Cutover used the installed host preflight: `current` repointed at `releases/f6444b4`, `COWORK_VERSION`
set to `f6444b4`, then `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait
--wait-timeout 180 web`. Only `cowork-web-1` was recreated (image `2037ffd` → `f6444b4`, healthy,
`RestartCount=0`); every other `cowork-*` container and all unrelated containers (Nextcloud AIO, arr
stack, Jellyfin, Cloudflared, etc.) kept identical container ID and `StartedAt` in a before/after
`docker ps`/`inspect` diff. `cowork-embed-1` remained in its pre-existing restart loop (known, issue
#336, untouched).

Verification: internal `GET /api/ready` on the container's `UI_PORT` (8021) returned `200
{"ready":true,"version":"0.2.0"}`; logs since deploy showed `egress.listening` on `172.28.0.4:8040`
and the expected `DIARY_TENANT_KEY` warning, no auth-token warnings; `https://noevia.daserver.work/`
returned 200 and `/api/profile` returned 401; the served `index-pLXervss.js` / `index-CY0nLBZh.css`
matched the hashes in `cowork-web:f6444b4`'s `/app/dist/assets`.

Rollback (not needed — deploy succeeded): restore `current` to `releases/2037ffd`, restore
`config/.env` from `.env.bak.before-f6444b4`, restore the two compose file backups, then re-run
`tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

---

## Release 2037ffd — 2026-09-25 (web-only: theme families + cursor-pull hover)

### Services

- **Web:** [#315](https://github.com/sbstndalton/noevia/pull/315) Three distinct theme families — Material 3 Contemporary, Liquid Glass, ruled Editorial — plus cursor-pull hover, all frontend-only (`apps/web/src`) — deployed as `cowork-web:2037ffd` (full build FROM release source; `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-2037ffd`.

No open PRs against `sbstndalton/noevia` were merged for this release (PR #315 was merged as part of this deploy; `gh pr list --state open` after merge showed only other unrelated work). `origin/main` was confirmed at `2037ffd` (full: `2037ffdbe211990d436b95a12b3927951b57be87`) with no trailing non-docs commits, and `git diff --stat 2037ffd origin/main -- apps/` was empty. CI on that SHA (`2037ffdbe211990d436b95a12b3927951b57be87`, workflow `CI`) completed success, including "Docker images build" (2m25s) and "Node tests, typecheck, frontend build" (1m31s).

Source shipped via `git archive` of `2037ffdbe211990d436b95a12b3927951b57be87` to `releases/2037ffd`. Only `apps/web/src` changed, so a full web build was required; it produced `index-Ck6gpNmS.js` / `index-CY0nLBZh.css`.

Candidate release was archived to `releases/2037ffd`, `.env` backed up to `.env.bak.before-2037ffd`, and `cowork-web:2037ffd` was built with `COWORK_VERSION=2037ffd`. Candidate verification used a synthetic in-image check: `docker run --rm --entrypoint cat cowork-web:2037ffd /app/dist/version.json` returned `{"version":"2037ffd"}` before cutover. The served `index.html` referenced `/assets/index-Ck6gpNmS.js` and `/assets/index-CY0nLBZh.css`, matching the hashes baked into `cowork-web:2037ffd`'s `/app/dist/assets`. An in-container grep confirmed the served CSS contained 335 occurrences of `data-family`, including `contemporary`, `editorial` and `glass` family selectors.

Cutover used the installed host preflight: `current` repointed at `releases/2037ffd`, then `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`, followed by `tools/sidecar-restart-alert.sh --ack`. Only `cowork-web-1` was recreated (image `58b340c` → `2037ffd`); every other `cowork-*` container and all unrelated containers (Nextcloud AIO, arr stack, Jellyfin, etc.) kept their prior image, identity and start time in a before/after `docker ps`/`inspect` diff.

Post-cutover verification: `cowork-web-1` healthy, 0 restarts; `https://noevia.daserver.work/` returned 200 on 3/3 requests; `/api/profile` returned 401; `/version.json` returned `{"version":"2037ffd"}`; the served `index.html` referenced `/assets/index-Ck6gpNmS.js` and `/assets/index-CY0nLBZh.css`, matching the built dist; `docker logs cowork-web-1` showed only normal startup lines (MCP discovery, UI listening), no errors.

Rollback (not needed — verification passed): restore `.env.bak.before-2037ffd`, `ln -sfn releases/58b340c current`, then rerun the same `up.sh … --no-build --no-deps --wait web` command.



## Release 58b340c — 2026-09-25 (favicon/app-shell cache-busting, stamp-test fix)

### Services

- **Web:** [#314](https://github.com/sbstndalton/noevia/pull/314) Favicon/app-shell cache-busting (`STAMP_VERSION`), stale-shell guard, `no-store` on `index.html`, and a mark in Appearance previews (#311, #312); [#318](https://github.com/sbstndalton/noevia/pull/318) fix stamp-icons tests to be independent of ambient `STAMP_VERSION` (#317) — deployed as `cowork-web:58b340c` (full build FROM release source; `apps/web/Dockerfile` and `compose.yaml` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** the live Compose file (`/boot/config/plugins/compose.manager/projects/Cowork/docker-compose.yml`) lacked `web.build.args.COWORK_VERSION`, which the Dockerfile needs to bake `STAMP_VERSION` into the image. It was backed up as `docker-compose.yml.bak.before-58b340c` and patched to add `args: COWORK_VERSION: ${COWORK_VERSION:-dev}` under `web.build`, keeping the existing `context:`. This is now required for every web release; it stays in place going forward (see the "compose-copies" note in `docs/deployment.md`). `.env` backed up as `.env.bak.before-58b340c`.

Preflight: `gh pr list --repo sbstndalton/noevia --state open` showed only #315 (theme families work, not part of this release) — nothing was merged. `origin/main` was confirmed at `58b340c` (full: `58b340c1553fd42ec40a14bc9c1a6728b7f7a370`) with no trailing non-docs commits ahead of it for `apps/`, `compose.yaml`, `.github/` (`git diff --stat` empty against the prior release SHA `20a24c2`... verified against 58b340c as tip). CI on `58b340c1553fd42ec40a14bc9c1a6728b7f7a370` (workflow `CI`, run 36112669958) completed success, including "Docker images build" (2m19s) and "Node tests, typecheck, frontend build" (1m24s), plus Diary test suite, Docling extraction contract and Model manager test suite.

Source shipped via `git archive` of `58b340c1553fd42ec40a14bc9c1a6728b7f7a370` to `releases/58b340c` (the stale `releases/29d2d1d` directory, left over from an aborted attempt that failed the Dockerfile's test stage — fixed by #318 — was removed first). The compose build-arg patch above was required for the `STAMP_VERSION` build arg to resolve; `docker compose ... config` was used to confirm `args: COWORK_VERSION: 20a24c2` resolved correctly before the version bump, and `COWORK_VERSION: 58b340c` after. Building `cowork-web:58b340c` with `COWORK_VERSION=58b340c` completed cleanly, with `stamp-icons: version=58b340c stamped=index.html, manifest.webmanifest wrote version.json` in the build log.

Candidate verification used a synthetic in-image check: `docker run --rm --entrypoint cat cowork-web:58b340c /app/dist/version.json` returned `{"version":"58b340c"}` (not `0.2.0` or `dev`) before cutover. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `https://noevia.daserver.work/` returned 200 three times, `/api/profile` returned 401, `curl .../version.json` returned `{"version":"58b340c"}`, response headers carried `cache-control: no-store`, and the served `index.html` referenced `icon.svg?v=58b340c` / `icon.png?v=58b340c`. Served container asset filenames under `dist/assets` matched the built image's assets exactly. Logs since start were clean. Before/after `docker ps`/`docker inspect` snapshots of every container on the host showed only `cowork-web-1` changed (new container id, new `StartedAt`, restart count unchanged at 0); every other `cowork-*` sidecar (Laya, llama, embed, ocr, docling, kiwix, model-loader, diary, code-sandbox) and unrelated container (Nextcloud AIO stack, media stack) kept its identity and start time. Restart-alert baseline re-acked. No real tune, private Diary access, new harness installation, broader exposure or other production action was part of this release.

Rollback (untaken): restore `.env.bak.before-58b340c`, point `current` at `releases/20a24c2`, then rerun the same guarded no-build `web`-only `up.sh` command. The compose build-arg patch is left in place (harmless, and required going forward).

## Release 20a24c2 — 2026-09-25 (new leaf logo)

### Services

- **Web:** [#310](https://github.com/sbstndalton/noevia/pull/310) New noevia mark: three leaves emerging at the tip of a bare twig (#306) — deployed as `cowork-web:20a24c2` (full build FROM release source; `apps/web/src` and public icons changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-20a24c2`.

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `20a24c2` (full: `20a24c28b34865480aa83e7075c122f9abdcc3ff`) with no trailing non-docs commits, and `git diff --stat 20a24c2 origin/main -- apps/` was empty. CI on that SHA (workflow `CI`) completed success, including "Docker images build" and "Node tests, typecheck, frontend build".

Source shipped via `git archive` of `20a24c28b34865480aa83e7075c122f9abdcc3ff` to `releases/20a24c2`. `apps/web/src` and the public icon assets changed, so a full web build was required; it produced `index-3BnUMor0.js` / `index-DqhxSEgr.css`.

Candidate verification used synthetic checks only, no live inference or real Diary access: the candidate image was run standalone on a scratch port and checked directly — `/` returned 200, `/icon.svg` had 12 `<path>` elements, `/icon-512.png` was 41,683 bytes (old icon was 4,725 bytes), and `/api/profile` returned 401 — before it was removed. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `https://noevia.daserver.work/` returned 200 three times, `/api/profile` returned 401, `/icon.svg` had 12 `<path>` elements, `/icon-512.png` was 41,683 bytes with `Content-Length` matching, the served `index.html` asset references (`index-3BnUMor0.js` / `index-DqhxSEgr.css`) matched the built dist inside the container, and logs since start were clean. Before/after `docker ps`/`docker inspect` snapshot of all 43 containers on the host showed only `cowork-web-1` changed (new container id, new `StartedAt`, restart count unchanged at 0); every other `cowork-*` sidecar and unrelated container (Laya, llama, embed, ocr, docling, kiwix, model-loader, diary, code-sandbox, Nextcloud AIO, media stack) kept its identity and start time. Restart-alert baseline re-acked. No real tune, private Diary access, new harness installation, broader exposure or other production action was part of this release.

Rollback (untaken): restore `.env.bak.before-20a24c2`, point `current` at `releases/2ab7c99`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release 2ab7c99 — 2026-09-25 (Settings back/close loop fix, new chats default to Auto)

### Services

- **Web:** [#307](https://github.com/sbstndalton/noevia/pull/307) Fix Settings back/close loop through Models & routing; new chats default to Auto when roles are configured; Back-to-app removed (#304, #305) — deployed as `cowork-web:2ab7c99` (full build FROM release source, both `apps/web/server` and `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-2ab7c99`.

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `2ab7c99` (full: `2ab7c991d81e4b52d8bc724bdbbb5e434e2f2e6c`) with no trailing docs-only commits, and `git diff --stat 2ab7c99 origin/main -- apps/` was empty. CI on that SHA ("Fix Settings back/close loop through Models & routing; new chats default to Auto (#307)", workflow `CI`, plus "Offline skills MCP contract") completed success, including "Docker images build" and the "Node tests, typecheck, frontend build" job.

Source shipped via `git archive` of `2ab7c991d81e4b52d8bc724bdbbb5e434e2f2e6c` to `releases/2ab7c99`. Both `apps/web/server` and `apps/web/src` changed, so a full web build was required; it produced `index-Bwxxo8tc.js` / `index-DqhxSEgr.css`.

Candidate verification used synthetic checks only, no live inference or real Diary access: an in-container grep confirmed the built image's `server/chat.cjs` contains `project ? project.routing === 'auto' : true`. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, the served `index.html` asset references matched the built dist, and logs since start were clean. `diary` and `ocr` (spot-checked; other sidecars unchanged) kept identical container ids, `StartedAt` and zero restarts (before/after `docker inspect`/`docker ps` snapshot diff showed only `cowork-web-1` changed). Restart-alert baseline re-acked. No real tune, private Diary access, new harness installation, broader exposure or other production action was part of this release.

Rollback (untaken): restore `.env.bak.before-2ab7c99`, point `current` at `releases/4e19d28`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release 4e19d28 — 2026-09-25 (model delete now unloads, clears auto-router roles)

### Services

- **Web:** [#303](https://github.com/sbstndalton/noevia/pull/303) Fix: deleting a model now unloads it, clears auto-router roles, invalidates caches, and removes the card (#302) — deployed as `cowork-web:4e19d28` (full build FROM release source, both `apps/web/server` and `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-4e19d28`.

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `4e19d28` (full: `4e19d2850f49a6671f472a0b2d24ea02aebddff4`) with no trailing docs-only commits, and `git diff --stat 4e19d28 origin/main -- apps/` was empty. CI on that SHA (workflow `CI`, plus "Offline skills MCP contract") completed success, including "Docker images build" and the "Node tests, typecheck, frontend build" job.

Source shipped via `git archive` of `4e19d2850f49a6671f472a0b2d24ea02aebddff4` to `releases/4e19d28`. Both `apps/web/server` and `apps/web/src` changed, so a full web build was required; it produced `index-C3C3OjXI.js` / `index-DqhxSEgr.css`.

Candidate verification used synthetic checks only, no live inference or real Diary access. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, the served `index.html` asset references matched the built dist, and an in-container grep confirmed `server/models.cjs` contains `clearRoleReferences`. Logs since start were clean. `diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero restarts (before/after `docker inspect` snapshot diff showed only `cowork-web-1` changed). Restart-alert baseline re-acked. No real tune, private Diary access, new harness installation, broader exposure or other production action was part of this release.

Rollback (untaken): restore `.env.bak.before-4e19d28`, point `current` at `releases/cfdb5b3`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release cfdb5b3 — 2026-09-25 (Laya tool gate, experimental, off by default)

### Services

- **Web:** [#301](https://github.com/sbstndalton/noevia/pull/301) Tool gate: make small models use tools when the prompt needs them (experimental, off) — deployed as `cowork-web:cfdb5b3` (full build FROM release source, both `apps/web/server` and `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-cfdb5b3`.

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `cfdb5b3` (full: `cfdb5b30c483cfe39596cd80ccd8e7b43bd2231f`) with no trailing docs-only commits, and `git diff --stat cfdb5b3 origin/main -- apps/` was empty. CI on that SHA ("Tool gate: make small models use tools when the prompt needs them (experimental, off) (#301)", workflow `CI`, plus "Offline skills MCP contract") completed success, including "Docker images build" and the Node tests/typecheck/frontend-build job.

Source shipped via `git archive` of `cfdb5b30c483cfe39596cd80ccd8e7b43bd2231f` to `releases/cfdb5b3`. Both `apps/web/server` and `apps/web/src` changed, so a full web build was required; it produced `index-C8b5Zts7.js` / `index-DqhxSEgr.css` (unchanged locale chunks).

Candidate verification ran the built image standalone: an in-container listing confirmed `server/tool-gate.cjs` was present, and `server/features.cjs` showed the `toolGate` feature flag defaults to `enabled: false` (`NOEVIA_FEATURE_TOOL_GATE` was left unset in `.env`) — synthetic checks only, no live inference or real Diary access. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, the served `index.html` asset references matched the built dist, and logs since start were clean. `diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero restarts (before/after `docker inspect` snapshot diff showed only `cowork-web-1` changed). Restart-alert baseline re-acked. `NOEVIA_FEATURE_TOOL_GATE` was not set — the tool gate stays off. No real tune, private Diary access, new harness installation, broader exposure or other production action was part of this release.

Rollback (untaken): restore `.env.bak.before-cfdb5b3`, point `current` at `releases/8454694`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release 8454694 — 2026-09-25 (i18n catalogues, QA scripts, docs)

### Services

- **Web:** [#287](https://github.com/sbstndalton/noevia/pull/287) live browser-service Chromium QA run and dark-mode task banner check, [#288](https://github.com/sbstndalton/noevia/pull/288) i18n Settings catalogue chunk and remaining Settings screens, [#289](https://github.com/sbstndalton/noevia/pull/289) i18n translate account menu, Projects and Diary screens, [#290](https://github.com/sbstndalton/noevia/pull/290) docs: versioned service boundaries and migration contracts, [#299](https://github.com/sbstndalton/noevia/pull/299) i18n Customise segment, chat-shell footer, Thinking control and view loading names, [#300](https://github.com/sbstndalton/noevia/pull/300) i18n model manager segment, Diary & storage and Service status — deployed as `cowork-web:8454694` (full build FROM release source, `apps/web/src` changed; no `apps/web/server` or sidecar changes).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-8454694`.

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `8454694` (full: `84546946e4b3460e95e1f608ab5d75c77b117549`). CI on that SHA (`i18n: model manager segment, Diary & storage and Service status (#300)`, workflow `CI`) completed success.

Source shipped via `git archive origin/main` to `releases/8454694`. Only `apps/web/src` changed, so a full web build was required (no server changes); it produced `index-C5ea3Cp-.js` plus refreshed locale chunks (e.g. `de-DE-CJsuIpcy.js`).

Candidate verification ran the built image standalone: `dist/index.html` referenced the freshly built `index-C5ea3Cp-.js`, an in-container listing confirmed the de-DE locale chunks were present, and every pinned sidecar tag (`cowork-diary:9b532a8`, `cowork-ocr:5004b50`, `cowork-model-loader:5b6d9b6`, `cowork-code-sandbox:pi-0.87.0-9b532a8`, `cowork-docling:2026-09-21`) already existed locally — synthetic checks only, no live inference or real Diary access. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, the served `index.html` asset reference matched the built dist, a locale chunk (`de-DE-CJsuIpcy.js`) served 200, and logs since start were clean. `diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero restarts (before/after `docker ps`/`inspect` snapshot diff showed only `cowork-web-1` changed). Restart-alert baseline re-acked. No model runs, real Diary data, new harness installation or broader exposure were part of this release.

Rollback (untaken): restore `.env.bak.before-8454694`, point `current` at `releases/5a47942`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release 5a47942 — 2026-09-24 (Projects/Cowork task status, connector permissions, usage drilldown, Customise UI; MCP custom-server preview)

### Services

- **Web:** [#282](https://github.com/sbstndalton/noevia/pull/282) integrate UI inspiration work for [#256](https://github.com/sbstndalton/noevia/issues/256)–[#260](https://github.com/sbstndalton/noevia/issues/260) (task status, connector permissions, usage drilldown, Customise UI) with review fixes, plus server routes `GET /api/code/active` and the MCP custom-server preview step — deployed as `cowork-web:5a47942` (full build FROM release source, `apps/web/src` and `apps/web/server` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-5a47942`.

No open PRs against `sbstndalton/noevia` were merged for this release (a PR touching #283 was open but explicitly out of scope). `origin/main` was confirmed at `5a47942` followed only by docs-only changelog commits (`037cc23`, `b247bfa`), and `git diff --stat 5a47942 origin/main -- apps/` was empty. CI on `5a47942` (Detect changed areas, Docker images build, Diary test suite, Model manager test suite, Docling extraction contract, Node tests/typecheck/frontend build, CI required) was all green before release.

Source shipped via `git archive 5a47942` to `releases/5a47942`. Both `apps/web/src` and `apps/web/server` changed, so a full web build was required; it produced `index-BHPy9b1M.js` / `index-Cf_aeTgD.css` plus the unchanged locale chunks.

Candidate verification ran the built image standalone: `dist/index.html` referenced the freshly built `index-BHPy9b1M.js`/`index-Cf_aeTgD.css`, and an in-container `grep` confirmed `server/routes/mcp-directory.cjs` contains the `custom/preview` route — synthetic checks only, no live inference or real Diary access. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, `/api/code/active` returned 401 unauthenticated, the served `index.html` asset references matched the built dist, and logs since start were clean. `diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero restarts (snapshot diff before/after showed only `cowork-web-1` changed). Restart-alert baseline re-acked. No model runs, real Diary data, new harness installation or broader exposure were part of this release.

Rollback (untaken): restore `.env.bak.before-5a47942`, point `current` at `releases/9a8f29e`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release 9a8f29e — 2026-09-24 (i18n interface translations)

### Services

- **Web:** [#281](https://github.com/sbstndalton/noevia/pull/281) translate the interface: i18n layer and nine catalogues (closes [#231](https://github.com/sbstndalton/noevia/issues/231)) — deployed as `cowork-web:9a8f29e` (full build FROM release source, `apps/web/src` changed heavily).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-9a8f29e`.

`origin/main` was confirmed at `9a8f29e` followed only by a docs-only changelog commit (`b247bfa`,
`git diff --stat 9a8f29e origin/main -- apps/` empty) and no open PRs were merged. CI on `9a8f29e`
(Detect changed areas, Docling extraction contract, Node tests/typecheck/frontend build, Model
manager test suite, Diary test suite, Docker images build, CI required) was all green before release.
Source shipped via `git archive 9a8f29e` to `releases/9a8f29e`. `apps/web/src` changed heavily, so a
full web build was required; it produced `index-DLVIslzU.js` / `index-hZUNMXvd.css` plus separate
locale chunks for all nine catalogues (`de-DE-Cv76COWg.js`, `fr-FR-CVCTYCXG.js`, `es-ES-k7TGcfPb.js`,
`it-IT-Cr3AnigY.js`, `nl-NL-DRkttd5-.js`, `pt-BR-5roZJfo7.js`, `sv-SE-CkBFoZrU.js`,
`nb-NO-pn-W27bk.js`).

Candidate verification ran the built image standalone: `/` served index.html, `/api/profile` returned
401, and `dist/assets` contained the locale chunks — synthetic checks only, no live inference or real
Diary access. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It
recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile`
returned 401, the served `index.html` matched the container's `dist/index.html` byte-for-byte, the
served `index-*.js/css` names matched the built dist, and `de-DE-Cv76COWg.js` / `fr-FR-CVCTYCXG.js`
both returned 200 from the public URL. Logs since start were clean. `diary`, `code-sandbox`,
`model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids,
`StartedAt` and zero restarts (snapshot diff before/after showed only `cowork-web-1` changed).
Restart-alert baseline re-acked. No model runs, real Diary data, new harness installation or broader
exposure were part of this release.

Rollback (untaken): restore `.env.bak.before-9a8f29e`, point `current` at `releases/e35ab29`, then
rerun the same guarded no-build `web`-only `up.sh` command.

## Release e35ab29 — 2026-09-24 (browser executor wired into managed jobs)

### Services

- **Web:** [#280](https://github.com/sbstndalton/noevia/pull/280) wire the browser executor into managed jobs and approval cards (closes [#274](https://github.com/sbstndalton/noevia/issues/274)) — deployed as `cowork-web:e35ab29` (full build FROM release source, `apps/web/server` and `apps/web/src` changed). `NOEVIA_FEATURE_BROWSER_EXECUTOR` was left unset, so the feature stays off by default.
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-e35ab29`.

`origin/main` was confirmed at `e35ab29` (only #281, unrelated, open against it) and every check-run
on that commit (CI: Detect changed areas, Model manager test suite, Diary test suite, Docker images
build, Node tests/typecheck/frontend build, Docling extraction contract, CI required; plus Offline
skills MCP contract) was completed/success before release. `apps/web/server` and `apps/web/src` both
changed since the live `c09ee38`, so a full web build was required. Source shipped via
`git archive e35ab29` to `releases/e35ab29`. The in-image test suite ran as part of the build
(334/334 passing) and produced `index-ClOM-B3G.js` / `index-hZUNMXvd.css`.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero
restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, the
served `index-*.js/css` names matched the web image's `dist/assets` byte-for-byte by filename,
`server/browser-service.cjs` and `server/routes/browser.cjs` were confirmed present in the container,
and logs since start were clean (no `[egress]` or `[browser]` errors). `diary`, `code-sandbox`,
`model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids,
`StartedAt` and zero restarts (snapshot diff before/after showed only `cowork-web-1` changed).
Restart-alert baseline re-acked. No model runs, real Diary data, new harness installation or broader
exposure were part of this release; only synthetic candidate checks were used.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-e35ab29 config/.env`, `ln -sfn releases/c09ee38 current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release c09ee38 — 2026-09-24 (model evidence import)

### Services

- **Web:** [#279](https://github.com/sbstndalton/noevia/pull/279) import attributable model evidence alongside downloads (closes [#266](https://github.com/sbstndalton/noevia/issues/266)) — deployed as `cowork-web:c09ee38` (full build FROM release source, `apps/web/server` and `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-c09ee38`.

`origin/main` was confirmed at `c09ee38` (no PRs open against it besides unrelated #280) and every
check-run on that commit (CI: Detect changed areas, Model manager test suite, Docker images build,
Diary test suite, Node tests/typecheck/frontend build, Docling extraction contract, CI required;
plus Offline skills MCP contract) was completed/success before release. `apps/web/server` and
`apps/web/src` both changed since the live `d5cf1ea`, so a full web build was required. Source
shipped via `git archive c09ee38` to `releases/c09ee38`. The in-image test suite ran as part of the
build (334/334 passing) and produced `index-CNbsCH0G.js` / `index-hZUNMXvd.css`.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero
restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401,
the served `index-*.js/css` names matched the web image's `dist/assets` byte-for-byte by filename,
`server/model-evidence-import.cjs` was confirmed present in the container, and logs since start were
clean. `diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and
`kiwix` kept identical container ids, `StartedAt` and zero restarts (snapshot diff before/after
showed only `cowork-web-1` changed). Restart-alert baseline re-acked. No model runs, real Diary
data, new harness installation or broader exposure were part of this release.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-c09ee38 config/.env`, `ln -sfn releases/d5cf1ea current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release d5cf1ea — 2026-09-24 (theme families, visual and motion system batch J)

### Services

- **Web:** [#278](https://github.com/sbstndalton/noevia/pull/278) theme families Editorial/Contemporary/Glass replace materials with migration, unified elevation/radius/type tokens, motion system with reduced-motion support (closes [#245](https://github.com/sbstndalton/noevia/issues/245), [#247](https://github.com/sbstndalton/noevia/issues/247), [#249](https://github.com/sbstndalton/noevia/issues/249)) — deployed as `cowork-web:d5cf1ea` (full build FROM release source, `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env`/Compose backed up as `*.bak.before-d5cf1ea`.

`origin/main` was confirmed at `d5cf1ea` and every check-run on that commit (Docling extraction
contract, Docker images build, Node tests/typecheck/frontend build, Model manager test suite,
Diary test suite, Detect changed areas, CI required) was completed/success before release.
Only `apps/web/src` changed since the live `c7f7999`. Source shipped via `git archive d5cf1ea`
to `releases/d5cf1ea`. Web required a full build (frontend changed); the in-image test suite ran
as part of the build and passed, producing `index-DNSqOhiT.js` / `index-CsqE8JA1.css`.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero
restarts and reported healthy. Public `/` returned 200, `/api/profile` returned 401, the served
`index-*.js/css` names matched the web image's `dist/assets` byte-for-byte by filename, and the
served `/theme.js` contained `data-family`. `diary`, `code-sandbox`, `model-loader`, `ocr`,
`docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero
restarts. Restart-alert baseline re-acked. No model runs, real Diary data, new harness installation
or broader exposure were part of this release.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-d5cf1ea config/.env`, `ln -sfn releases/c7f7999 current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release c7f7999 — 2026-09-24 (settings reorganisation, notifications, memory, response style, keyboard, archived chats, Customise, home recents)

### Services

- **Web:** [#277](https://github.com/sbstndalton/noevia/pull/277) batch G settings split, notifications, memory, response style, keyboard, language, archived chats, Customise, home recents (closes [#226](https://github.com/sbstndalton/noevia/issues/226), [#227](https://github.com/sbstndalton/noevia/issues/227), [#228](https://github.com/sbstndalton/noevia/issues/228), [#229](https://github.com/sbstndalton/noevia/issues/229), [#230](https://github.com/sbstndalton/noevia/issues/230), [#232](https://github.com/sbstndalton/noevia/issues/232), [#238](https://github.com/sbstndalton/noevia/issues/238), [#239](https://github.com/sbstndalton/noevia/issues/239); [#231](https://github.com/sbstndalton/noevia/issues/231) partial) — deployed as `cowork-web:c7f7999` (full build FROM release source, `apps/web` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** merged, not yet deployed — stays `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env`/Compose backed up as `*.bak.before-c7f7999`.

`origin/main` was confirmed at `c7f7999` and every check-run on that commit (Docling extraction
contract, Docker images build, Node tests/typecheck/frontend build, Model manager test suite,
Diary test suite, offline-contract, Detect changed areas, CI required) was completed/success before
release. Only `apps/web` changed since the live `89142c0`. Source shipped via `git archive c7f7999`
to `releases/c7f7999`. Web required a full build (frontend changed); server/Dockerfile/package files
unchanged in scope but the build ran end to end, producing `index-BjjnjAwL.js` / `index-7jjrR2RA.css`.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero
restarts and reported healthy. Public `/` returned 200, `/api/profile` returned 401, and the served
`index-*.js/css` names matched the web image's `dist/assets` byte-for-byte by filename.
`diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept
identical container ids, `StartedAt` and zero restarts. Restart-alert baseline re-acked. No model
runs, real Diary data, new harness installation or broader exposure were part of this release.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-c7f7999 config/.env`, `ln -sfn releases/89142c0 current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release 89142c0 — 2026-09-24 (composer Chat/Cowork toggle, tool catalogue)

### Services

- **Web:** [#276](https://github.com/sbstndalton/noevia/pull/276) composer Chat/Cowork toggle and permitted tool catalogue (closes [#236](https://github.com/sbstndalton/noevia/issues/236), [#237](https://github.com/sbstndalton/noevia/issues/237)) — deployed as `cowork-web:89142c0` (full build FROM release source, `apps/web` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** merged, not yet deployed — stays `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env`/Compose backed up as `*.bak.before-89142c0`.

`origin/main` was confirmed at `89142c0` and every check-run on that commit (Docling extraction
contract, Docker images build, Node tests/typecheck/frontend build, Model manager test suite,
offline-contract, Detect changed areas) was completed/success before release. Only `apps/web`
changed since the live `9b532a8`. Source shipped via `git archive 89142c0` to `releases/89142c0`.
Web required a full build (frontend changed); server/Dockerfile/package files unchanged in scope
but the build ran end to end, producing `index-DKpCIBTO.js` / `index-DghX1G7f.css`.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero
restarts and reported healthy. Public `/` returned 200, `/api/profile` returned 401, and the served
`index-*.js/css` names matched the web image's `dist/assets` byte-for-byte by filename.
`diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept
identical container ids, `StartedAt` and zero restarts. Restart-alert baseline re-acked. No model
runs, real Diary data, new harness installation or broader exposure were part of this release.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-89142c0 config/.env`, `ln -sfn releases/9b532a8 current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release 9b532a8 — 2026-09-24 (model manager guided tuning, secrets rotation, Diary tombstone/quarantine, upload/RAG/MCP hardening, code-sandbox batch A)

### Services

- **Web:** [#240](https://github.com/sbstndalton/noevia/pull/240) model manager filters/phone routing/calibration guard/settings headings, [#241](https://github.com/sbstndalton/noevia/pull/241) secrets key rotation UI, [#242](https://github.com/sbstndalton/noevia/pull/242) (web side) Diary tombstone/quarantine/status polling, [#243](https://github.com/sbstndalton/noevia/pull/243) uploads/offsite/pdf-reduce caps + RAG version filter + source lock + job ids, [#244](https://github.com/sbstndalton/noevia/pull/244) untrusted-prompt framing/replay/MCP hardening, [#246](https://github.com/sbstndalton/noevia/pull/246) Q5 KV-cache floor + task-aware sampling presets, [#248](https://github.com/sbstndalton/noevia/pull/248) (web side) code-sandbox batch A hardening, [#251](https://github.com/sbstndalton/noevia/pull/251) guided estimate/tuning pre-flight/Quality and Recover — deployed as `cowork-web:9b532a8` (full build FROM release source, `apps/web/src` changed).
- **Diary:** [#242](https://github.com/sbstndalton/noevia/pull/242) tombstone, quarantine cascade, status polling, backup perf — deployed as `cowork-diary:9b532a8` (`diary-overlay.sh 9b532a8`, `agent/` only, FROM `cowork-diary:d264606`).
- **Model manager:** merged, not yet deployed — stays `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** [#248](https://github.com/sbstndalton/noevia/pull/248) batch A hardening (harness, egress, sandbox) — deployed as `cowork-code-sandbox:pi-0.87.0-9b532a8` (`pi-acp-bridge.cjs` + `supervisor.cjs` overlay, FROM `cowork-code-sandbox:pi-0.87.0-dda50c2`).
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env`/Compose backed up as `*.bak.before-9b532a8`.

Source shipped via `git archive 9b532a8` to `releases/9b532a8`. Web required a full build (frontend
changed across `apps/web/src`); server/Dockerfile/package files unchanged in scope but the build ran
end to end, producing `index-BJqPT_o9.js` / `index-BrNEIg3U.css`. Diary and code-sandbox diffs against
`d264606`/`pi-0.87.0-dda50c2` were confirmed limited to `services/diary/agent` and
`services/code-sandbox/{pi-acp-bridge.cjs,supervisor.cjs}` respectively (Dockerfiles/requirements
identical), so both are overlays with no dependency install.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web`, `diary-overlay.sh 9b532a8` for
Diary (appdata backup `ab_20260924_173346` verified, `gzip -t` passed), and `up.sh --profile code
--no-build --no-deps --wait` for `code-sandbox`. All three recreated with zero restarts and reported
healthy/running. Public `/` returned 200, `/api/profile` returned 401, and the served `index-*.js/css`
names matched the web image's `dist/assets` byte-for-byte by filename. `model-loader`, `laya`, `ocr`,
`docling`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero restarts.
Restart-alert baseline re-acked.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-9b532a8 config/.env`, `ln -sfn releases/d264606 current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
- Diary: `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=d264606/' config/.env` (or restore
  `config/.env.bak.before-diary-9b532a8`), then `up.sh --env-file … -- -d --no-build --no-deps --wait
  --wait-timeout 180 diary`.
- Code sandbox: `sed -i 's/^CODE_SANDBOX_VERSION=.*/CODE_SANDBOX_VERSION=pi-0.87.0-dda50c2/'
  config/.env` (or restore `config/.env.bak.before-code-sandbox-9b532a8`), then `up.sh --env-file …
  --profile code -- -d --no-build --no-deps --wait --wait-timeout 180 code-sandbox`.

## Release d264606 — 2026-09-24 (code-actions publish/network gating, fetchJson body cap, Diary corpus_store NameError and queued-edit races)

### Services

- **Web:** [#233](https://github.com/sbstndalton/noevia/pull/233), [#235](https://github.com/sbstndalton/noevia/pull/235) (web side) — deployed as `cowork-web:d264606` (server/ overlay FROM `cowork-web:b5941e4`).
- **Diary:** [#235](https://github.com/sbstndalton/noevia/pull/235) (`corpus_store.py`, `journal.py`) — deployed as `cowork-diary:d264606` (`diary-overlay.sh`, `agent/` only, FROM `cowork-diary:b5941e4`).
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-dda50c2`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** live Compose files unchanged (backed up as `*.bak.before-d264606`).

Source shipped via `git archive d264606` to `releases/d264606`. All of `apps/web` outside `server/` is identical to b5941e4
(only `code-actions.cjs`, `http.cjs` and their tests changed), so the web image is `FROM cowork-web:b5941e4` with `/app/server`
replaced (candidate `sha256:fa337d92…`). With no network, the in-image `code-actions.cjs`/`http.cjs` SHA-256 hashes match the
release, `node --check` passes and the two changed test files pass 30 of 30. Dist still serves `index-BsftJ7Co.js` /
`index-CV0N4hHI.css`. The Diary diff vs b5941e4 was `agent/corpus_store.py`, `agent/journal.py` and one test (requirements.txt
and Dockerfile identical). The overlay took appdata backup `ab_20260924_151049` (gzip verified), then recreated Diary as image
`cb092351…`; Diary health via web returned 200. In-container `journal.py` contains `unapplied_exchange_edit` and
`corpus_store.py` contains `errors: Optional`.

Cutover used guarded `up.sh … --no-build --no-deps --wait` for `web`, then the Diary overlay (its appdata backup restarted web
again). Web started at 19:11:03Z and Diary at 19:11:10Z. Both are healthy with zero restarts. All other cowork containers
(code-sandbox, model-loader, laya, ocr, docling, llama, embed, kiwix) kept identical ids and start times. Public `/` returned 200
on 3 of 3 requests, and `/api/profile` returned 401. Web logs had zero error markers over 60 s. No Diary data was read.
Restart-alert baseline re-acked.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-d264606 config/.env` (also reverts DIARY_VERSION), `ln -sfn releases/b5941e4 current`, then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
- Diary: `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=b5941e4/' config/.env` (or restore `config/.env.bak.before-diary-d264606`), then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 diary`.

## Release b5941e4 — 2026-09-24 (routing/menu fixes, stale loaded summary, chat-only prompt suite, Diary polling and journal replay order, admin-gated warm-up, backup-worker backoff)

### Services

- **Web:** [#207](https://github.com/sbstndalton/noevia/pull/207), [#208](https://github.com/sbstndalton/noevia/pull/208) (web side), [#209](https://github.com/sbstndalton/noevia/pull/209), [#213](https://github.com/sbstndalton/noevia/pull/213) — deployed as `cowork-web:b5941e4` (full `compose build web` from the release context; frontend changed).
- **Diary:** [#208](https://github.com/sbstndalton/noevia/pull/208) (journal replay order, `ORDER BY rowid`) — deployed as `cowork-diary:b5941e4` (`diary-overlay.sh`, `agent/` only, FROM `cowork-diary:11617a3`).
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-dda50c2`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** live Compose files unchanged (backed up as `*.bak.before-b5941e4`).

Source shipped via `git archive b5941e4` to `releases/b5941e4`. `apps/web/src` changed vs 11617a3 (lockfile and
Dockerfile identical), so web was built on DaServer (`cowork-web:b5941e4`, image `752c3966e0ca`). Candidate checks were run
with no network. `isChatGenerationModel` (chat-model-kind.cjs) and `MAX_BACKOFF_MS` (diary-backup-worker.cjs) are present.
Dist serves `index-BsftJ7Co.js` / `index-CV0N4hHI.css`. The `installedSummary` / `notifyModelsChanged` grep can't match
minified output because both are renamed identifiers. The bundle and SettingsShell chunk hashes changed from 11617a3.
The Diary diff vs 11617a3 was `agent/journal.py` plus one test (requirements.txt and Dockerfile identical). The overlay took
appdata backup `ab_20260924_144722` (gzip verified). It then recreated Diary as image `aedb9cef…`, and Diary health via web
returned 200. The in-container `/app/agent/journal.py` contains `ORDER BY rowid`.

Cutover used guarded `up.sh … --no-build --no-deps --wait` for `web`, then the Diary overlay. Web started at 18:47:36Z and
Diary at 18:47:43Z. Both are healthy with zero restarts. All other cowork containers (code-sandbox, model-loader, laya, ocr,
docling, llama, embed, kiwix) kept identical ids and start times. Public `/` returned 200 on 3 of 3 requests, and
`/api/profile` returned 401. Web logs had zero error markers over 60 s. No Diary data was read. Restart-alert baseline re-acked.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-b5941e4 config/.env` (also reverts DIARY_VERSION), `ln -sfn releases/11617a3 current`, then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
- Diary: `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=11617a3/' config/.env` (or restore `config/.env.bak.before-diary-b5941e4`), then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 diary`.

## Release 11617a3 — 2026-09-24 (round-13 fixes: harness approval bypasses, MCP discovery TTL, Diary storage-outage handling, UI fixes)

### Services

- **Web:** [#166](https://github.com/sbstndalton/noevia/pull/166), [#167](https://github.com/sbstndalton/noevia/pull/167), [#168](https://github.com/sbstndalton/noevia/pull/168) (web side), [#169](https://github.com/sbstndalton/noevia/pull/169) (web side), [#171](https://github.com/sbstndalton/noevia/pull/171), [#172](https://github.com/sbstndalton/noevia/pull/172), [#187](https://github.com/sbstndalton/noevia/pull/187), [#188](https://github.com/sbstndalton/noevia/pull/188), [#189](https://github.com/sbstndalton/noevia/pull/189) (web side) — deployed as `cowork-web:11617a3` (full `compose build web` from the release context; frontend changed).
- **Diary:** Diary parts of [#134](https://github.com/sbstndalton/noevia/pull/134), [#168](https://github.com/sbstndalton/noevia/pull/168), [#169](https://github.com/sbstndalton/noevia/pull/169), [#189](https://github.com/sbstndalton/noevia/pull/189) — deployed as `cowork-diary:11617a3` (`diary-overlay.sh`, `agent/` only, FROM `cowork-diary:5b6d9b6`).
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-dda50c2`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** live Compose files unchanged (backed up as `*.bak.before-11617a3`).

Source shipped via `git archive 11617a3` to `releases/11617a3`. `apps/web/src` changed vs dda50c2
(lockfile and Dockerfile identical), so web was built on DaServer with `docker compose build web`
(`cowork-web:11617a3`, image `23fd3187b3cb`). Candidate checks, run with no network: the in-image `code-harness.cjs` and
`mcp-wiring.cjs` SHA-256 hashes match the release; `pinnedParent` and `discoveryFailTtlMs` are present; dist serves
`index-CzWzWYqN.js` / `index-CV0N4hHI.css`. Diary diff vs 5b6d9b6 was `agent/` plus tests only (requirements.txt and
Dockerfile identical). The overlay took appdata backup `ab_20260924_140932` (gzip verified), which restarted web at
18:09:47Z (same container id). It then recreated Diary as image `96dc142c…`, and Diary health via web returned 200.

Cutover used guarded `up.sh … --no-build --no-deps --wait` for `web`, then the Diary overlay. Web and Diary are healthy
with zero restarts. All other cowork containers (code-sandbox, model-loader, laya, ocr, docling, llama, embed, kiwix)
kept identical ids and start times. Public `/` returned 200 on 3 of 3 requests, and `/api/profile` returned 401. The served assets exist in
the image, and web logs had no error markers over 60 s. The Diary import check passed; no Diary data was read. Restart-alert
baseline re-acked.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-11617a3 config/.env` (also reverts DIARY_VERSION), `ln -sfn releases/dda50c2 current`, then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
- Diary: `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=5b6d9b6/' config/.env` (or restore `config/.env.bak.before-diary-11617a3`), then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 diary`.

## Release dda50c2 — 2026-09-24 (harness containment, RAG/prompt budget, round-12 hardening, pi bridge timeouts)

### Services

- **Web:** [#132](https://github.com/sbstndalton/noevia/pull/132), [#133](https://github.com/sbstndalton/noevia/pull/133) (web side), [#134](https://github.com/sbstndalton/noevia/pull/134), [#135](https://github.com/sbstndalton/noevia/pull/135) — deployed as `cowork-web:dda50c2` (server/ overlay FROM `cowork-web:958022b`).
- **Diary:** no image change — stays `cowork-diary:5b6d9b6`; the #134 Diary `agent/` changes are merged, not yet deployed.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** [#133](https://github.com/sbstndalton/noevia/pull/133) — deployed as `cowork-code-sandbox:pi-0.87.0-dda50c2` (pi-acp-bridge.cjs overlay).
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** repo-side changes only; live Compose files unchanged (backed up as `*.bak.before-dda50c2`).

Source shipped via `git archive dda50c2` to `releases/dda50c2`. Web lockfiles and all of `apps/web`
outside `server/` are identical to 958022b, so the web image is `FROM cowork-web:958022b` with
`/app/server` replaced (node_modules kept) and the existing dist reused (`index-BaEAos9j.js`,
`index-CVYcHCIL.css`). Candidate `sha256:e6544d4d…`: server `.cjs` hashes match the release; the in-image
server tests pass 1144 of 1152. The 958022b image fails the same 8 tests the same way (repo files that
are not in the image). With no network, `/api/setup/status` returned 200. Sandbox `sha256:2ecb13d6…`:
the diff against 5b6d9b6 was only the bridge and its test; `node --check` passes; bridge tests 5/5;
the in-container bridge SHA-256 `5ce4f3db…` matches the release.

Cutover used guarded `up.sh … --no-build --no-deps --wait` for `web`, then `--profile code` for
`code-sandbox`. Both were recreated with zero restarts. Web is healthy and the sandbox is running. All other cowork containers
(diary, model-loader, laya, ocr, docling, llama, embed, kiwix) kept identical ids and start times.
Public `/` returned 200 on 3 of 3 requests, and `/api/profile` returned 401. The served assets exist in the image. Web logs had no error markers over 60 s.
Restart-alert baseline re-acked.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-dda50c2 config/.env` (also reverts the sandbox tag), `ln -sfn releases/958022b current`, then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
- Code sandbox: `sed -i 's/^CODE_SANDBOX_VERSION=.*/CODE_SANDBOX_VERSION=pi-0.87.0-5b6d9b6/' config/.env`, then `up.sh --env-file … --profile code -- -d --no-build --no-deps --wait --wait-timeout 180 code-sandbox`.

## Release 5b6d9b6 — 2026-09-24 (Diary hardening, model manager + code sandbox hardening, per-service tags; sidecars only)

### Services

- **Web:** no change — stays `cowork-web:958022b` (`current` and `COWORK_VERSION` untouched).
- **Diary:** [#77](https://github.com/sbstndalton/noevia/pull/77), [#84](https://github.com/sbstndalton/noevia/pull/84), [#87](https://github.com/sbstndalton/noevia/pull/87), [#93](https://github.com/sbstndalton/noevia/pull/93), [#94](https://github.com/sbstndalton/noevia/pull/94), [#99](https://github.com/sbstndalton/noevia/pull/99) — deployed as `cowork-diary:5b6d9b6` (agent/ overlay).
- **Model manager:** [#79](https://github.com/sbstndalton/noevia/pull/79) — deployed as `cowork-model-loader:5b6d9b6` (app/ overlay).
- **Code sandbox:** [#79](https://github.com/sbstndalton/noevia/pull/79) — deployed as `cowork-code-sandbox:pi-0.87.0-5b6d9b6` (supervisor.cjs overlay).
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** [#104](https://github.com/sbstndalton/noevia/pull/104), [#106](https://github.com/sbstndalton/noevia/pull/106) merged; live `.env` and Compose Manager files migrated to `DIARY_VERSION`/`OCR_VERSION`/`MODEL_MANAGER_VERSION`.

Source shipped via `git archive 5b6d9b6` to `releases/5b6d9b6`. Before building, diffs against the
running sources were confirmed limited to Diary `agent/` (+ tests, README), model manager `app/*.py`
(+ tests) and code sandbox `supervisor.cjs`; Dockerfiles and requirements identical, so every image
is an overlay `FROM` the running one with no pip/npm step.

1. Per-service tags: backed up `docker-compose.yml`, `docker-compose.override.yml` and `.env` as
   `*.bak.before-per-service-tags`; diary/ocr/model-loader image lines switched to the required
   variables, pinned to the running tags (5004b50/5004b50/a1ededd). `compose config` resolved every
   cowork image to its running tag and a dry-run `up` recreated nothing; no container changed.
2. Model manager `sha256:869beb3f…`: recreated `model-loader` only (guarded `up.sh`), healthy,
   `/api/v1/health` 200 from web; api.py in the container matches the release (shardBase guard).
3. Code sandbox `sha256:ba39f7fc…`: recreated `code-sandbox` only (`up.sh --env-file … --profile code --`),
   running with zero restarts, supervisor.cjs SHA-256 matches the release, TCP reachable from web.
4. Diary `sha256:ab519fdf…`: `diary-overlay.sh 5b6d9b6` took appdata backup
   `ab_20260924_130511` (verified; it stops/starts web and diary, so web kept its container id
   but has a new start time), recreated diary only, healthy, health via web 200.

All other cowork containers (laya, llama, embed, ocr, docling, kiwix) kept identical ids and start
times. Public `/` 200, `/api/profile` 401.

Rollback (from the Compose Manager project directory; old images untouched):
- Model manager: `sed -i 's/^MODEL_MANAGER_VERSION=.*/MODEL_MANAGER_VERSION=a1ededd/' config/.env`, then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 model-loader`.
- Code sandbox: `sed -i 's/^CODE_SANDBOX_VERSION=.*/CODE_SANDBOX_VERSION=pi-0.87.0-99be0a2/' config/.env`, then `up.sh --env-file … --profile code -- -d --no-build --no-deps --wait --wait-timeout 180 code-sandbox`.
- Diary: `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=5004b50/' config/.env` (or restore `config/.env.bak.before-diary-5b6d9b6`), then `up.sh … diary`.
- Per-service-tag migration: restore the three `*.bak.before-per-service-tags` files.

## Release 958022b — 2026-09-24 (job start controller leak, phone preview Settings, web-only)

### Services

- **Web:** [#102](https://github.com/sbstndalton/noevia/pull/102) — deployed as `cowork-web:958022b`.
- **Diary:** no change.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#102](https://github.com/sbstndalton/noevia/pull/102) starting a background job no
longer leaks a controller when the journal write fails; the phone preview on desktop collapses
Settings panes like a real phone.

CI green on `958022b`. Deployed via `git archive 958022b` (no local checkout modified; archive
SHA-256 matched after upload) to `/mnt/docker/appdata/cowork/releases/958022b`, built as
`cowork-web:958022b`
(`sha256:ee934d3dc820296cd3f567ed17686ada0a07aaad6c2897295d0a805ca362e9fd`). Config and the
live Compose Manager file were backed up as `*.bak.before-958022b`; `current`/`COWORK_VERSION`
were repointed at `958022b`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only, from the Compose Manager project directory. All 42 non-web
container IDs and start times were identical before and after.
`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:c3a03c7`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-BaEAos9j.js` and `index-CVYcHCIL.css` are present in the image's `dist/assets`;
no error/unreadable lines in the startup log.

Rollback: `config/.env.bak.before-958022b` and the Compose Manager
`docker-compose.yml.bak.before-958022b` restore `current` to `releases/c3a03c7`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release c3a03c7 — 2026-09-24 (account cleanup, job journals, research saves, code harness hardening, web-only)

### Services

- **Web:** [#98](https://github.com/sbstndalton/noevia/pull/98), [#99](https://github.com/sbstndalton/noevia/pull/99), [#100](https://github.com/sbstndalton/noevia/pull/100), [#101](https://github.com/sbstndalton/noevia/pull/101) — deployed as `cowork-web:c3a03c7`.
- **Diary:** [#99](https://github.com/sbstndalton/noevia/pull/99) (Diary part) — merged, not yet deployed.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#98](https://github.com/sbstndalton/noevia/pull/98) deleting a user removes their MCP
sign-ins and directory keys; disabled admin credentials are no longer used for discovery; WebDAV
hrefs decode HTML entities; `$` in key templates is handled literally;
[#99](https://github.com/sbstndalton/noevia/pull/99) one unreadable job journal no longer blocks other background
jobs; [#100](https://github.com/sbstndalton/noevia/pull/100) research reports save to the current project by id,
the phone preview honours `data-layout` in JS checks, and the approval card re-enables after a
decision; [#101](https://github.com/sbstndalton/noevia/pull/101) code harness config writes refuse symlinks,
approvals are answered by id, the engine key is never committed (tracked config is refused and
pinned files are removed before auto-commit), and grants are released once. Diary changes in #99
are merged but not deployed by this web-only release.

CI green on `c3a03c7`. Deployed via `git archive c3a03c7` (no local checkout modified; archive
SHA-256 matched after upload) to `/mnt/docker/appdata/cowork/releases/c3a03c7`, built as
`cowork-web:c3a03c7`
(`sha256:57bccee21803427c2c8ee3a28a0c187798f887d4652071def4a52fa94de0c275`). Config and the
live Compose Manager file were backed up as `*.bak.before-c3a03c7`; `current`/`COWORK_VERSION`
were repointed at `c3a03c7`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only, from the Compose Manager project directory. All 34 non-web
container IDs and start times were identical before and after.
`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:852ef76`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-DTEDzgUo.js` and `index-C7qt3UiI.css` are present in the image's `dist/assets`;
`cwdPinPaths` is a function in the running container; no error/unreadable lines in the startup log.

Rollback: `config/.env.bak.before-c3a03c7` and the Compose Manager
`docker-compose.yml.bak.before-c3a03c7` restore `current` to `releases/852ef76`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release 852ef76 — 2026-09-24 (S3 region, storage secret v2, replay history, web-only)

### Services

- **Web:** [#96](https://github.com/sbstndalton/noevia/pull/96), [#97](https://github.com/sbstndalton/noevia/pull/97) — deployed as `cowork-web:852ef76`.
- **Diary:** no change.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#96](https://github.com/sbstndalton/noevia/pull/96) S3 connections store and sign with a
region (new `storage_connections.region` column, default `us-east-1`, migrated at startup); storage
secrets are always encrypted and bound to the account (v2), and legacy v1 secrets are upgraded on
read; [#97](https://github.com/sbstndalton/noevia/pull/97) model replay merges adjacent same-role turns and never
starts with an assistant turn; WebDAV MOVE/COPY default `Overwrite` to `T` per RFC 4918.

CI green on `852ef76`. Deployed via `git archive 852ef76` (no local checkout modified; archive
SHA-256 matched after upload) to `/mnt/docker/appdata/cowork/releases/852ef76`, built as
`cowork-web:852ef76`
(`sha256:25a1b70c5f1dfea627f34bb06a6abbdea4e7512c0562ceb9ca6f48f576ac0c79`). Config and the
live Compose Manager file were backed up as `*.bak.before-852ef76`; `current`/`COWORK_VERSION`
were repointed at `852ef76`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only, from the Compose Manager project directory. All 42 non-web
container IDs and start times were identical before and after.
`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:0c2be32`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-SGaWTEhw.js` and `index-C7qt3UiI.css` are present in the image's `dist/assets`;
`normalizeReplayHistory` is a function in the running container; no error/migration lines in
the startup log.

Rollback: `config/.env.bak.before-852ef76` and the Compose Manager
`docker-compose.yml.bak.before-852ef76` restore `current` to `releases/0c2be32`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release 0c2be32 — 2026-09-24 (routing model, Diary edit proxy and offsite backup hardening, web-only)

### Services

- **Web:** [#90](https://github.com/sbstndalton/noevia/pull/90), [#91](https://github.com/sbstndalton/noevia/pull/91), [#92](https://github.com/sbstndalton/noevia/pull/92), [#95](https://github.com/sbstndalton/noevia/pull/95) — deployed as `cowork-web:0c2be32`.
- **Diary:** [#93](https://github.com/sbstndalton/noevia/pull/93), [#94](https://github.com/sbstndalton/noevia/pull/94) — merged, not yet deployed.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#90](https://github.com/sbstndalton/noevia/pull/90) Details/Configure hide tuning and calibration for the system
routing model, and the Settings routing summary wraps at narrow widths; [#91](https://github.com/sbstndalton/noevia/pull/91) the Diary
edit proxy forwards `base_hash` and relays 409 conflicts; [#92](https://github.com/sbstndalton/noevia/pull/92) fixes offsite S3 listing
with a "/" prefix and adds a Drive-copy busy-lock guard; [#95](https://github.com/sbstndalton/noevia/pull/95) the Drive mirror never
prunes a foreign backup store (store id, sibling folder, 25% guard, serialized runs), caps
storage reads/listings, and fixes SigV4 canonical path encoding. [#93](https://github.com/sbstndalton/noevia/pull/93) (Diary trash long
names) and [#94](https://github.com/sbstndalton/noevia/pull/94) (Diary tenant delete race, fixed 502 text) are merged but NOT deployed by
this web-only release.

CI green on `0c2be32`. Deployed via `git archive 0c2be32` (no local checkout modified; archive
SHA-256 matched after upload) to `/mnt/docker/appdata/cowork/releases/0c2be32`, built as
`cowork-web:0c2be32`
(`sha256:ecb14d6ef8aafcb22d72e6282eaaf672375c8690afae11691bafb8a0123ee257`). Config and the
live Compose Manager file were backed up as `*.bak.before-0c2be32`; `current`/`COWORK_VERSION`
were repointed at `0c2be32`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only, from the Compose Manager project directory. All 42 non-web
container IDs and start times were identical before and after.
`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:7e8ce3a`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-94Ntc5E5.js` and `index-C7qt3UiI.css` are present in the image's `dist/assets`;
`/app/server/offsite-s3.cjs` loads in the running container.

Rollback: `config/.env.bak.before-0c2be32` and the Compose Manager
`docker-compose.yml.bak.before-0c2be32` restore `current` to `releases/7e8ce3a`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release 7e8ce3a — 2026-09-24 (code-workspace and Drive hardening, web-only)

### Services

- **Web:** [#86](https://github.com/sbstndalton/noevia/pull/86), [#88](https://github.com/sbstndalton/noevia/pull/88) — deployed as `cowork-web:7e8ce3a`.
- **Diary:** [#87](https://github.com/sbstndalton/noevia/pull/87) — merged, not yet deployed.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#86](https://github.com/sbstndalton/noevia/pull/86) the code-workspace
release refuses harness-planted git hooks, filters and fsmonitor, and runs git with them
disabled; [#88](https://github.com/sbstndalton/noevia/pull/88) caps Drive reads (Range request
plus a streamed cap), makes autoconfig suggest only calibrator-verified context sizes, and adds
InstructionSkills guards. [#87](https://github.com/sbstndalton/noevia/pull/87) (Diary
index_update validation and quarantine) is merged but NOT deployed by this web-only release.

CI green on `7e8ce3a`. Deployed via `git archive 7e8ce3a` (no local checkout modified; archive
SHA-256 matched after upload) to `/mnt/docker/appdata/cowork/releases/7e8ce3a`, built as
`cowork-web:7e8ce3a`
(`sha256:e0400c5f93df8e60b598934c74080fb344f94736578a4a07ae5d50c870ca99e7`). Config and the
live Compose Manager file were backed up as `*.bak.before-7e8ce3a`; `current`/`COWORK_VERSION`
were repointed at `7e8ce3a`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only, from the Compose Manager project directory. All 42 non-web
container IDs and start times were identical before and after.
`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:7ce2213`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-B6Wdf04v.js` and `index-B1OLP7Ag.css` are present in the image's `dist/assets`;
`/app/server/code-workspace.cjs` loads in the running container.

Rollback: `config/.env.bak.before-7e8ce3a` and the Compose Manager
`docker-compose.yml.bak.before-7e8ce3a` restore `current` to `releases/7ce2213`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release 7ce2213 — 2026-09-24 (hardening batch, web-only)

### Services

- **Web:** [#76](https://github.com/sbstndalton/noevia/pull/76), [#80](https://github.com/sbstndalton/noevia/pull/80), [#81](https://github.com/sbstndalton/noevia/pull/81), [#82](https://github.com/sbstndalton/noevia/pull/82), [#83](https://github.com/sbstndalton/noevia/pull/83), [#85](https://github.com/sbstndalton/noevia/pull/85) — deployed as `cowork-web:7ce2213`.
- **Diary:** [#77](https://github.com/sbstndalton/noevia/pull/77), [#84](https://github.com/sbstndalton/noevia/pull/84) — merged, not yet deployed.
- **Model manager:** [#79](https://github.com/sbstndalton/noevia/pull/79) — merged, not yet deployed.
- **Code sandbox:** [#79](https://github.com/sbstndalton/noevia/pull/79) — merged, not yet deployed.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#76](https://github.com/sbstndalton/noevia/pull/76) server error
bodies no longer leak raw errors, JSON bodies are checked, chat ids are sanitized and
approvals are scoped; [#80](https://github.com/sbstndalton/noevia/pull/80) and
[#83](https://github.com/sbstndalton/noevia/pull/83) guard the system model (Laya) from
delete, calibration, preset apply and section delete/rename, and gate research maintenance;
[#81](https://github.com/sbstndalton/noevia/pull/81) hides system-model rename/delete in the
Configure tab, merges racing history loads and orders stats updates;
[#82](https://github.com/sbstndalton/noevia/pull/82) caps and aborts MCP responses and makes
the diary stream and tool arguments robust; [#85](https://github.com/sbstndalton/noevia/pull/85)
makes chat delete stop the reply and block saves, resets the project view on switch, and keeps
merged roles alternating. [#77](https://github.com/sbstndalton/noevia/pull/77),
[#79](https://github.com/sbstndalton/noevia/pull/79) and [#84](https://github.com/sbstndalton/noevia/pull/84)
(Diary service, model-manager, code-sandbox) are merged but NOT deployed by this web-only release.

CI green on `7ce2213`. Deployed via `git archive 7ce2213` (no local checkout modified) to
`/mnt/docker/appdata/cowork/releases/7ce2213`, built as `cowork-web:7ce2213`
(`sha256:e3605b2deabbd04561cfe1312c0b47e131540563f97a599f7b9153a1575b6c0a`). Config and the
live Compose Manager file were backed up as `*.bak.before-7ce2213`; `current`/`COWORK_VERSION`
were repointed at `7ce2213`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only (it must run from the Compose Manager project directory; the first
attempt from another cwd was blocked before any change). All 42 non-web container IDs and start
times were identical before and after.

`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:7b6942c`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-DoBtRaex.js` and `index-B1OLP7Ag.css` are present in the image's `dist/assets`;
`errorResponse` from #76 is exported in the running container.

Rollback: `config/.env.bak.before-7ce2213` and the Compose Manager
`docker-compose.yml.bak.before-7ce2213` restore `current` to `releases/7b6942c`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release 7b6942c — 2026-09-24 (chat save races)

### Services

- **Web:** [#75](https://github.com/sbstndalton/noevia/pull/75) — deployed as `cowork-web:7b6942c`.
- **Diary:** no change.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

[PR #75](https://github.com/sbstndalton/noevia/pull/75) fixes chat save races while replies
stream. The chat list no longer drops a chat when two sends overlap; a save conflict during
a streaming reply no longer replaces the transcript or loses the reply; and persisting was
moved out of the React state updater. Deployed web-only via `git archive 7b6942c` (no local
checkout modified) to `/mnt/docker/appdata/cowork/releases/7b6942c`, built as
`cowork-web:7b6942c` (`sha256:da15caf99d8e8d3b40bbf177ea9feaf40a6a297ce6bfd5e262592b3e17ad542a`).
Config and the live Compose Manager file were backed up as `*.bak.before-7b6942c`;
`current`/`COWORK_VERSION` were repointed at `7b6942c`. Cutover used the guarded preflight
`--no-build --no-deps --wait --wait-timeout 180 web` only; all 42 non-web container IDs and
start times were identical before and after.

`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:9ee7bb0`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-RdBcm5Rx.js` and `index-B1OLP7Ag.css` are present in the image's `dist/assets`.
Later PRs merged to main after 7b6942c are not part of this release.

Rollback: `config/.env.bak.before-7b6942c` and the Compose Manager
`docker-compose.yml.bak.before-7b6942c` restore `current` to `releases/9ee7bb0`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release 9ee7bb0 — 2026-09-23 (Laya excluded from auto-tuner)

[PR #74](https://github.com/sbstndalton/noevia/pull/74) blocks the auto-tuner from
selecting or deleting `laya_multilingual_f16`. Deployed web-only via `git archive
9ee7bb0` (no local checkout modified) to `/mnt/docker/appdata/cowork/releases/9ee7bb0`,
built as `cowork-web:9ee7bb0` (`sha256:b0c2f0ef69c671465864ad80ed4df9456fac647aacbf5dfd33802eceb2d98ced`).
Config and the live Compose Manager file were backed up as `*.bak.before-9ee7bb0`;
`current`/`COWORK_VERSION` were repointed at `9ee7bb0`. Cutover used the guarded
preflight `--no-build --no-deps --wait --wait-timeout 180 web` only; no other
service was rebuilt or restarted.

`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:6b59118`).
Read-only, without starting a tune, `require('/app/server/model-system.cjs')` inside
the running container confirmed `isSystemModel('laya_multilingual_f16')` returns
`true` (reason: "System routing model — not tuned"/"not deleted"), while an ordinary
model ID returns `false`. Locally the container answered its root path with the
expected unauthenticated 302 redirect and the built `dist/assets` matched the served
bundle name pattern from prior releases.

**Public HTTPS verification did not complete.** `https://noevia.daserver.work/` and
`/api/profile` both returned Cloudflare edge error 530 at cutover and on retries; the
`CloudflaredTunnel` container logs show persistent QUIC dial timeouts to Cloudflare's
edge starting around the same time, while `ping 1.1.1.1` from the host showed 0%
loss, indicating an outbound tunnel/edge problem rather than home WAN loss or a web
regression. `CloudflaredTunnel` was left untouched (out of scope for a web-only
release) and was not restarted. Laya (`cowork-laya:0.3.5-recovery-2ffd153`), Diary,
OCR, code-sandbox, model-loader, docling and the native llama engine kept identical
container IDs and `StartedAt` timestamps before and after cutover. Web was not
rolled back because the failure is isolated to the tunnel, reproducible without any
version dependency, and the container itself is verified healthy locally; the public
200/401 checks remain outstanding and must be reconfirmed once the tunnel recovers. Reconfirmed after the tunnel recovered without restarting it: `/` returned 200 and `/api/profile` returned 401 (3/3 tries), and the served `index-C1P7G4yr.js` and `index-B1OLP7Ag.css` are present in the `cowork-web:9ee7bb0` image.

Rollback (only needed if the web image itself is found to be at fault):
`config/.env.bak.before-9ee7bb0` and the Compose Manager
`docker-compose.yml.bak.before-9ee7bb0` restore `current` to `releases/6b59118`,
then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release 6b59118 — 2026-09-23 (Auto routing label in inference stats and saved replies)

[PR #69](https://github.com/sbstndalton/noevia/pull/69) shows the Auto routing decision
alongside inference stats and in saved replies. Deployed web-only, staged via
`git archive 6b59118` (no local checkout modified) to
`/mnt/docker/appdata/cowork/releases/6b59118`, built as `cowork-web:6b59118`
(`sha256:ddf73b888f317e70c2e894ecb1b856bca104704f3aebbc746252882b9ecffa22`). Config and
the live Compose Manager file were backed up as `*.bak.before-6b59118`; `current` and
`COWORK_VERSION` were repointed at `6b59118`. Cutover used the installed guarded preflight
`--no-build --no-deps --wait --wait-timeout 180 web`; no other service was rebuilt,
restarted or touched.

`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:6b1621c`).
`https://noevia.daserver.work/` returned 200 and `/api/profile` returned 401 unauthenticated.
Served `index.html` referenced `index-CU_LuO7r.js` and `index-B1OLP7Ag.css`, both present
byte-identically in the built image's `dist/assets`. Laya (`cowork-laya:0.3.5-recovery-2ffd153`),
Diary, OCR, code-sandbox, model-loader, docling and the native llama engine kept identical
container IDs and `StartedAt` timestamps before and after cutover; only synthetic checks were
used, no real tune or Diary access.

Rollback: restore `config/.env.bak.before-6b59118` and the Compose Manager
`docker-compose.yml.bak.before-6b59118`, repoint `current` at
`releases/6b1621c`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release 6b1621c — 2026-09-23 (auto-tune recovery and compact progress)

Auto-tune now waits until the router reports every model unloaded before saving the
next candidate profile. This prevents the immediate 409 that could follow a rejected
quality probe while the previous model was still unloading. A bounded timeout names
the blocking model and state; cancellation still restores the current phase. Failed
quality probes report the check and failure type without storing generated answers.
The Auto Tune panel puts status, progress and Resume above compact queued details.

[Issue #72](https://github.com/sbstndalton/noevia/issues/72) was fixed by
[PR #73](https://github.com/sbstndalton/noevia/pull/73), merged as `6b1621c`.
All 1,354 web tests, typecheck, build and design lint passed; the candidate web image
passed 32 isolated tuner/calibration tests. A web-only guarded overlay from `5004b50`
completed with the web container healthy. Public CSS and model-manager JavaScript
match the validated build; protected routes return 401 without authentication.
Brave review confirmed the deployed layout and recovery controls without resuming a
real tune. Diary, OCR, llama and the Laya recovery image retained their container
IDs and start times. Configuration and Compose backups named `.bak.before-6b1621c`
are retained for web-only rollback to `5004b50`; no full appdata backup was run
because it would restart unrelated services. Historical state cannot explain why
the initial f16 quality probe failed.

## Release 827932b — 2026-09-22 (three-material refinement)

Removed the redundant Glassmorphism mode from preferences, pre-paint initialization,
settings, CSS and reference samples; old saved values fall back to Soft. Soft is matte
with restrained depth and visible switch boundaries. Liquid Glass is limited to functional
controls, with readable content, restrained highlights, no label refraction or pointer tilt,
and reduced-preference handling. Material 3 uses paired color roles, tonal selection,
correct pressed/disabled states and native-checkbox switch contrast. Shared geometry stays
stable. General now correctly distinguishes synced theme/accent from browser-local preferences.

`ui/material-refinement` (`7663b40`, `827932b`) was pushed, then fast-forwarded into main
from `9cf92b3` after a fresh fetch. No remote changes conflicted; no force push or branch
deletion. The original `ui-polish-update` checkout is unchanged and clean.

Validation: 1,247 unit tests, typecheck, build and design lint pass. Fourteen distinct
synthetic browser suites pass, including Code, approvals and onboarding in all three
materials. The broad inventory covers 468 states; the final focused confirmation covers
198 states, with zero detected overflow, matte-mode blur leaks or page errors. Both themes,
375/768/1440 widths, smaller approval/drawer viewports, keyboard focus and accessibility
preferences are covered. All 12 rendered switch on/off/mode/theme pairs meet 3:1 contrast.
The Impeccable detector's five dimension-animation findings were fixed. See the full
[material audit and iteration log](material-audit-2026-09-22.md) for evidence and scope limits.
No real Diary corpus, live model inference or user data was used for testing.

Backup `ab_20260922_143433` completed successfully; web, Diary and extra-file archives
independently passed `gzip -t`. Local/remote SHA-256 matched for source
`0731f040149d450e122841bd69443f7bb6475a1f50389c16125b933cde0c7d01` and app
`9b7232a1d68dbf4b6fb211de415f91d77b795eae39d437b1bf802c3c739b269d` archives.
Guarded overlay `04780e6` → `827932b` passed mount/env/tenant-isolation preflights and
reported `RELEASE_827932b_COMPLETE` at 14:46 EDT. Web, Diary and OCR are healthy with zero
restarts. Native engine, embeddings, pi sandbox and Laya IDs/start times are unchanged.
Laya remains pre-existing unhealthy. Existing volume/swap-limit warnings are unchanged.

Public index serves `index-U2SHbFp3.js` / `index-Dtub7VGn.css`; both and `theme.js`, `lens.js`,
`glass-highlight.js` match the local build byte-for-byte. Unauthenticated profile/admin-users
requests return 401; web logs contain zero error markers since cutover. A Python HTTP client
received 403; ordinary curl returned 200 and verified every public asset without changing any
edge/security configuration.

Rollback: restore `config/.env.bak.before-827932b`, point `current` at `releases/04780e6`,
then run the guarded no-build startup for web/diary/ocr. Old images, branches and backups
are retained. The subsequent main commit records rollout evidence only; deployed application
source is `827932b`.

## Release 04780e6 — 2026-09-22 (development branches integrated)

Integrated `ui-polish-update` (`7014b69`) and local
`codex/harness-hardening-claude-pi` (`c729379`) from `origin/main` (`506f0f8`).
The tuning commit already existed as a patch-equivalent change; no duplicate feature
or stale alternative was applied. Only documentation conflicted. See
[integration evidence](integration-2026-09-22.md).

1,245 unit tests, typecheck, build, design lint and 15 synthetic browser/HTTP suites
pass. Real pi 0.87.0 and Claude ACP 0.79.0 pass local scripted-model approval checks,
including hostile Claude repository resources. The Linux pi candidate passes the same
allow/decline fixture with no network or production volumes. The web image passes 80
isolated harness/approval/tuning tests. No real Diary corpus or live inference was used.

Backup `ab_20260922_135257` completed successfully; web, Diary and extra-file archives
independently passed `gzip -t`. Source/app archive checksums matched before deployment.
Guarded overlay `5a88558` → `04780e6` passed all preflights and reported
`RELEASE_04780e6_COMPLETE`. Web, Diary and OCR are healthy, zero restarts. The pi
sandbox was rebuilt from its Dockerfile with pi 0.87.0 and lifecycle scripts disabled,
then activated as `cowork-code-sandbox:pi-0.87.0-99be0a2`; its deployed bridge SHA-256
matches source, version is 0.87.0, and the container runs with zero restarts.

The first candidate package accidentally included a dependency symlink; Docker refused
it before cutover. The corrected archive excludes dependencies/state. The initial sandbox
activation put the profile flag after the wrapper separator; Compose refused it, the env
was restored, and the corrected preflight invocation succeeded. Neither failed attempt
ran an unvalidated candidate.

Public index serves `index-B5Qudv_W.js` / `index-3Twk2Xqu.css`; JavaScript SHA-256 matches
the local build. Unauthenticated model-tuning access returns 401, and web logs contain
zero error markers since cutover. Native llama, embeddings and Laya IDs/start times
are unchanged. Laya's pre-existing unhealthy status remains outside this release.
The existing unmanaged-volume and kernel swap-limit warnings remain unchanged.

Rollback: restore `config/.env.bak.before-04780e6` (including the old pi tag), point
`current` at `releases/5a88558`, then use the guarded preflight no-build startup for
web/diary/ocr and `--profile code -- -d --no-build --no-deps code-sandbox` for the
sandbox. The old release, pi image and backups are retained. The subsequent record
commit is documentation only; deployed application source is `04780e6`.

## 2026-09-22 — Complete automatic model tuning (release `5a88558`)

Models → Your models now has **Tune untuned models** beside **Check for updates**. One
confirmed maintenance window runs a sequential queue of configured chat models without a
current tune. It measures f16/q8/q4 KV cache, long-context recall, three existing-MTP-head draft
settings, n-gram and batch sizes. Three deterministic quality probes screen each setting; the
fastest passing complete profile is rechecked and applied automatically. 60–70% draft acceptance
is guidance, not a cutoff. No model/head downloads; no production benchmarks were started.

Changed artifacts, presets/defaults or engine builds invalidate a tune. Cancellation, failures
and interrupted runs restore the active model's original settings when safe, without overwriting
external edits. Earlier successful queue entries remain tuned. The probes are smoke tests, not
general quality certification. 1,242 tests, typecheck/build/design lint and both affected browser
suites pass; six responsive/theme layouts inspected. The deployed image passes all 10 synthetic
full-tuning tests. Native engine, embeddings and pi sandbox remain unchanged.

## 2026-09-22 — Claude Code and pi pins hardened (source only)

Claude Code now receives the full noevia-owned permission/model configuration inline, exposes a
fixed core tool set, and loads no settings, context, hooks, skills/commands or MCP servers from the
checked-out repository. Its own sandbox can no
longer auto-approve Bash, and both automatic and manual self-update paths are off. pi starts with
only noevia's approval gate and a fixed tool set, never loads project resources or context, makes no startup
network checks, saves no session, and waits for the true whole-turn completion event. Its package
install can no longer run lifecycle scripts. Codex remains refused because it cannot meet the
per-command approval rule. Verified with fake ACP/pi processes; no CLI was installed, no model was
run, and this source change is not deployed.

## 2026-09-22 — Code mode now runs pi

The coding agent in Code mode is now **pi**, the minimal agent many forks start from. It runs in
the same locked-down sandbox. Because pi normally never asks before acting, noevia adds its own
gate: every edit and command shows up on your approval card first, with the exact command or
file. Tested live twice on the throwaway `scratch` repository: it fixed the bug and the tests
pass. OpenCode is still installed and one setting away.

## 2026-09-22 — Diary service updated

The Diary service now keeps the previous version in Trash when a WebDAV client overwrites a
file, and reports each file's last-modified time so sync apps like Obsidian can tell what
changed. Nothing else in the Diary changed, and no Diary data was touched. File sharing (WebDAV)
remains off until you turn it on.

## 2026-09-22 — A local graph for Diary notes

Open a note in the Diary editor and expand **Local graph** to see the notes it links to and the
notes that link back, as a small diagram and a list you can click. Links you have just typed show
straight away. Two-way links are drawn heavier, incoming links dashed. It only reads: nothing is
indexed or changed, and it says so when the backlink scan could not cover every file.

## 2026-09-22 — Claude Code and pi can be pinned; Codex refused (releases `59249d9`, `d59d1a0`, `2577e16`)

Nothing changes in Code mode today; it still runs OpenCode. noevia now knows how to lock down
more coding agents the way it locks OpenCode: every edit, command and web access asks you,
the agent's own "skip permissions" modes are off, it talks only to your local engine, and it does
not update itself or send telemetry. For pi, which has no permission prompts of its own, noevia
installs a gate that asks for every non-read action and blocks if it cannot ask. Installing any
of them in the sandbox is your call. Tested with the real Claude Code and pi against a scripted
fake model: approvals reach you, Decline blocks, and a repository's own settings can't skip the
question. Codex was tested the same way and is **refused**: its commands ran without asking.

## 2026-09-22 — Step supervision stops pausing ordinary chats (release `b055571`)

With Step supervision on, Laya sometimes stopped a harmless chat for review (for example after a
plain project list) and added needless "double-check" rounds. New wording, measured on synthetic
cases: 16/17 on a fresh set with no needless pauses or extra rounds, and every synthetic
dangerous case (hidden instructions, credential requests, destructive commands) still stops.

## 2026-09-22 — System-One decisions show up in the web log (release `e19119d`)

Each routing and supervision decision writes one line — chosen role or action, margin, time
and whether it fell back — and never the message. This is how the next tuning step gets real
evidence instead of synthetic cases.

## 2026-09-22 — System-One routing picks Smart and Code when it should (release `6c3cde0`)

Laya was routing most reasoning and code questions to the Fast model. Probing it with the exact
requests production sends, on synthetic messages, showed the abstract role descriptions were the
cause: 23 of 40 held-out decisions right. Concrete descriptions ("greetings, thanks, or a
one-line factual answer" / "explaining, comparing, planning…" / "anything involving programming
code…") score 36 of 40; the rest are near-ties. Step supervision was checked the same way (8/9)
and left alone. Fallbacks, manual model choice and approvals are unchanged.
[Evidence](research/system-one/19-routing-labels.md).

## 2026-09-22 — Request-local live inference readouts (source `80d116f`, deployed in `e7b59d6`)

The inference footer now follows the visible chat's own event stream instead of treating the
engine-wide `/api/stats` poll as reply telemetry. It shows the routed model and generating state
immediately, records server-observed first output as it arrives, and applies provider-reported
tokens, rate and MTP acceptance without waiting for the next poll. Tool-loop rounds are
cumulative and use a weighted provider rate. Missing measurements remain explicitly unavailable;
they are never guessed from chunks or text. Engine totals/hardware stay separately labelled, so
another chat or a stale poll cannot replace the visible reply's facts.

Verification: 39 focused telemetry/tool-loop tests and 1,111 socket-free tests pass; typecheck,
production build (195 modules), design lint and diff whitespace checks pass. The full suite could
not complete in this task sandbox: 34 listener-based tests were refused with `listen EPERM`, while
1,143 tests passed and no assertion failure was observed. A fully synthetic, port-free browser QA
was added, but Chromium launch and visual inspection were blocked by the task's browser sandbox.
No inference, benchmark, paid endpoint, personal source or Diary data was used. Production remains
on `3d2521d` until the pushed source is deployed and checked on DaServer.

## 2026-09-22 — Compact context inside tool continuations

The chat loop now rechecks and, when necessary, compacts its model-facing projection before
every continuation after tool execution. The saved transcript and cross-turn summary remain
unchanged. The current user turn, assistant tool calls and their matching results stay
byte-identical and atomic; invalid or oversized protected groups stop with a readable error
without deleting messages, fabricating results or replaying tools. Continuation summaries use
the existing provider-neutral compaction call and conservative context estimate, in bounded
rolling batches. The context meter and opt-in context log report the compacted continuation.

Verification: 1,196 web tests, typecheck, production build, design lint and diff whitespace
checks pass. Focused coverage forces the real handler over budget between tool rounds and
confirms the next request receives a summary plus the intact current tool group. No model
inference, paid endpoint, personal source or Diary data was used.

Deployed as `3d2521d` after verified backup `ab_20260922_020935`; release preflights,
application/Laya health, public HTTP and clean-log checks passed. Native inference, embedding
and Laya container identities/start times remained unchanged.

### 2026-09-21 — Material 3 shares component geometry

## 2026-09-22 — Configure and enable Laya routing in Experimental

Added shared decision-service setup with editable URL/deadline, installed-Laya shortcut,
health-only connection test and persistent admin Save. Routing now uses the configured
Laya service for Fast/Smart/Code instead of requiring the old option-logit endpoint.
Settings apply to subsequent routing and supervision decisions without restart.
1192 tests, typecheck, build and design lint pass; scoped light/dark responsive UI verified.
See [configuration and verification](research/system-one/18-decision-service-settings.md).

## 2026-09-21 — Laya endpoint for model-independent step supervision

Connected the experimental checkpoint seam to a private typed-decision service.
Laya uses a separate CPU-only, offline serving container; the selected answering
provider (including OpenRouter/OpenAI-compatible endpoints) remains unchanged.
Validated bounded responses, no redirects or shared answering credentials, and
existing fallback/approval limits. Pinned model/runtime and optional Compose profile.
One authorized synthetic Laya inference passed on DaServer; no benchmarks.
See [service scope and setup](../services/laya/README.md).

## 2026-09-21 — Experimental step supervision

Added a separate unavailable-by-default Experimental entry and a provider-neutral chat
checkpoint seam. Mocked decisions can continue, request a bounded verification round,
or pause for review. Failed decisions preserve existing behavior; durable escalation
uses the existing checkpoint store and blocks automatic restoration. No Jev/Laya calls,
model switching or replay. 1181 web tests, typecheck, build and design lint pass.
See [scope and verification](research/system-one/17-step-supervision.md).

Material 3 now inherits the shared dimensions, padding, font metrics and layout borders
instead of replacing them. Tonal colors, radii, shadows and inset outlines retain the
Material appearance. Removed the width-changing selected checkmark and matched segment
font weights; rounded selection fills stay within wrapped tracks. Sidebar spacing also
uses the common tokens. Regression test rejects Material-only geometry overrides.

Verification: 1171 unit tests, typecheck/build/design lint and diff whitespace checks pass.
Synthetic browser comparison: 43 settings/navigation boxes match exactly across Soft,
Liquid glass, Glassmorphism and Material 3 at 375 and 1440 CSS px, plus the normal desktop
viewport. Visually inspected the corrected selection fills. No model or personal-data tests.

### 2026-09-21 — Descriptions above settings controls at every width

Corrected the requested layout: shared settings descriptions occupy their own full-width
row above buttons/selectors even on wide desktops. Compact on/off switches retain their
inline label. Wrapped segmented choices remain visible. This supersedes the prior
width-dependent placement in 126637e.

### 2026-09-21 — Release 126637e deployed

User authorized automatic deployment. Live now includes the shared responsive-control fixes,
Experimental settings and prior bounded continuation source changes. Backup and preflight
passed; all checked services healthy, public HTTP 200. Live Material text/options visually
verified. System-One remains off/unconfigured, durable chat inactive, native engine unchanged.
See [deployment verification and rollback](deployment.md#release-126637e--2026-09-21-shared-responsive-controls-and-experimental-routing).

### 2026-09-21 — Shared settings and segmented-control wrapping (local, undeployed)

Fixed the shared flex-row cause of one-word-per-line descriptions and clipped controls.
Settings rows now wrap by their available content width, including narrow desktop panels;
text retains a readable minimum width and control/value groups stay within the card.
Segmented controls throughout the app wrap instead of hiding options in a horizontal
scroller. Their selection highlight now tracks both axes and the selected button height,
including Material 3. Coding composer action groups also wrap within their available width.

Verification: 1170 unit tests passed; typecheck, build, design lint and diff whitespace
checks passed. Synthetic browser checks reproduced the original narrow desktop General
settings and confirmed readable descriptions and all Material choices visible. Checked
Material/Density/Motion/Layout at 375, approximately 768 (767 due to browser zoom rounding),
and 1440 CSS pixels: no document or segment overflow. Verified second-row Material 3
selection/highlight alignment, light/dark styling, capability label/value rows and the
Experimental switch page. Desktop screenshots were inspected; viewport override screenshots
still suffer the in-app browser's tiled-capture issue. A complete every-view/two-theme sweep
and physical-device testing were not run. No live preferences or data changed; no deployment.

### 2026-09-21 — Experimental System-One routing switch (local, undeployed)

Settings → Experimental now exposes an administrator-only System-One routing switch,
using the existing persisted/audited feature registry. On selects the option-logit
comparison baseline for new Auto role decisions; off restores the existing classifier.
Failures and deadlines fall back to that classifier. Requires an explicitly configured
private decision endpoint; no model is loaded, downloaded or selected automatically.
1170 unit tests, typecheck, build and design lint passed. Synthetic browser checks covered
save/reload, keyboard rollback and mobile/desktop presentation. See
[implementation and verification](research/system-one/16-experimental-routing.md).
No deployment or real inference. Dedicated System-One model selection remains open.

### 2026-09-21 — Default model mode setting (release c53713b, deployed)

### 2026-09-21 — Broader continuation verification (local, undeployed)

Added separate-process SIGKILL tests for durable generation and ambiguous tool execution.
Verified 1164 web tests, 64 decision/experiment tests, four synthetic real-HTTP suites,
typecheck/build/design lint, and targeted browser tool/approval/responsive checks.
Read-only live checks found Diary disabled for the account and a Nextcloud viewer registration
console error; no file-preview failure reproduced. See [exact scope and results](verification-2026-09-21-continuation.md).
No production changes, model inference or personal data operations.

### 2026-09-21 — First durable-chat slice (local, disabled, undeployed)

Added an optional chat recorder using the existing tenant job journal, with fsynced hash chains,
canonical tool results separate from context projections, stable turn identity, approval history
and persisted retry limits. Mocked replacement generation preserves completed tool results;
ambiguous execution requires review and cannot replay. No production wiring or switching.
See [implementation scope and exact verification](research/system-one/15-durable-chat-slice.md).
Focused durability/regression tests: 45 passed. Final web suite: 1162 passed; typecheck, build
and design lint passed. No live provider, Diary, engine, downloads or deployment involved.

### 2026-09-21 — Adapter cutoff and conditional bounds (local, undeployed)

Applied the reviewed continuation patch at its exact d6e7081 base. Independent run budget
covers version/startup/requests; cleanup is bounded and recorded separately. Partial option
scores now carry normalized conditional bounds and reject malformed distributions.
Current-repository verification: focused tests 28/28; existing decision/experiment tests 36/36;
web unit suite 1138/1138; typecheck, build and design lint pass with installed dependencies.
Only synthetic Node workers ran. No inference, downloads, live checks or deployment.

Models → Routing has a new "Default model mode" panel with an Auto/Manual choice for new projects. It is stored per workspace in `preferences.json` and replaces the browser-local setup-wizard flag; the wizard now writes this setting. "Switch existing projects to <mode>" rewrites that user's projects only. `GET/PUT /api/routing-default` takes `{ routing, applyToExisting }`. At the user's request, all 205 Manual projects in the `sebastian` workspace were switched to Auto, making 224/224 Auto; the member workspace (Ernestpov, 1 project) was switched too, at the user's request. 1,117/1,117 unit tests; `qa/models-settings` extended and green.

### 2026-09-21 — Auto routing is the default (release f9dc5df, deployed)

At the user's request, new projects are created with Auto (Fast/Smart) routing unless Manual is asked for. This replaces the step-12 Manual default. The setup wizard's Auto box starts ticked, and unticking it stores `manual`. Existing projects keep their setting. Auto with no Fast/Smart roles configured now uses the project's model instead of refusing the message. Also in this release: the multi-hop rerun on the fixed corpus. Rerank 12→6 got 3/4 against 2/4 for the baseline, and 24→3 got 1/4, which supports keeping 6. 1,116/1,116 unit tests; typecheck clean.

### 2026-09-21 — RAG rerank in chat (release 67f336e, deployed)

Project retrieval now takes a cosine pool (`RAG_RERANK_POOL`, default 12, max 24) and lets Qwen3-Reranker-0.6B pick the chunks kept (`RAG_RERANK_KEEP`, default 6) through the decision layer (`decisions.rank()`, `llama-rerank` backend). A down, malformed or slow reranker (`RAG_RERANK_DEADLINE_MS`, default 3000) falls back to the cosine top-6 used before, so chat never waits past the deadline. The whole feature is behind `NOEVIA_FEATURE_RAG_RERANK` + `RERANK_BASE_URL`. The engine's model manager keeps `RERANK_MODEL` loaded beside the chat model, the way it keeps the embedding model. Placement (the user's choice): the reranker is the router's second resident, `reranking = true` / `pooling = rank` in `models.ini`. Embeddings stay on the CPU `embed` container. DaServer GPU timing, warm: 12 chunks ~1.95 s, 24 ~3.9 s (CPU was ~21 s). The prototype scored 12→6 at 89%, 24→6 at 86% and 24→3 at 91%; keep stays at 6 because at 3 one exact-number demotion loses the answer. 1,115/1,115 unit tests.

### 2026-09-21 — Curated plugin starters (release 067ac1d, deployed)

`server/plugin-starters.json` is noevia's starter list: five first-party hosted MCP servers (Exa, Notion, Linear, Hugging Face, Cloudflare docs) and six Anthropic skills, each with a one-line reason. `GET /api/plugins/directory?starters=1` resolves them against the live registry and skills repository (cached an hour), keeps their order and drops any that vanished. The Plugins page shows them as "Recommended by noevia" above each directory until you search. Verified from DaServer: 5 servers, 6 skills. 1,103/1,103 unit tests; `qa/shared-sidebar` extended and green.

### 2026-09-21 — Ordinary WebDAV clients can write (release 42540fb, web only)

rclone, Finder, Explorer and Obsidian sync send no `If-Match`, so every DAV write was refused (428). Per the user's decision, DELETE and MOVE without `If-Match` use the version read at request time (both reversible); an untagged `Overwrite: T` reads the destination's version (the replaced file goes to Trash); a PUT over an existing file first keeps its bytes in Trash through the companion's new `preserve` op — restorable beside the file as `<name> (replaced <UTC time>).md` — then writes against the version just read. Protected files still require `If-Match`. New `qa/dav-interop.cjs` runs rclone against the real web server and the real companion on a throwaway tenant: 18/18. Web released; the Diary image is not rebuilt (the live Diary stays untouched), and DAV sharing remains off live (`COWORK_DAV_PORT=0`).

### 2026-09-21 — Shared context across a project's Chat and Code modes (release dbfbd92, deployed)

`shared-context.cjs`: `project.sharedContext = { chat, code }`, both off by default, validated on the project config route. Sharing into Code prepends the project's goal, instructions, memories and up to eight recent chat titles to the agent's prompt (not to the task label); sharing into Chat adds up to six recent Code tasks (prompt, status, branch, error) to the system prompt. Both blocks are capped at 6,000 characters and framed as reference data. Edit project shows the toggles only when Chat and Code are both on. 1,101/1,101 unit tests; `qa/project-modes` extended and green at 375/1440 light/dark.

### 2026-09-21 — Code mode can reach granted domains (release 9611580, deployed)

The egress proxy (`code-egress.cjs`, D15) now runs inside web on `CODE_EGRESS_PORT` (8040), reached by the sandbox as `egress` on the internal code network. A Code task approved for network or installs, with named domains, gets a per-task token that allows only those domains on 80/443 and is revoked when the task ends; unset, the capabilities stay unavailable. A granted task now keeps the engine host in `NO_PROXY` — empty, its model calls would have gone through the proxy and been refused as a private address. Live compose: web joins `code` with alias `egress` and gets `CODE_EGRESS_PORT`/`CODE_EGRESS_HOST` (`.bak.before-egress` backups of the override and `.env`).

### 2026-09-21 — index.cjs is wiring (branch `wip/index-split`, release 2ce73df, deployed)

Everything `handleRequestScoped` still carried inline moved into its own module with injected
dependencies and a `routes/` file: the project, source and upload routes (`projects.cjs`), the
provider registry (`providers.cjs`), the models routes (`models.cjs`), the Diary routes and the
connector endpoint (`diary.cjs`), then sign-in/profile/admin, the storage connection, tool
approvals, the chat lists and transcripts, reasoning settings, health, and the HTTP helpers
(`http.cjs`). The member-origin policy shared by providers, storage and the Diary corpus is now
`createEndpointApproved` in `ssrf.cjs`. Each move is verbatim behind one sentinel and mounted in
its original order, so every status code, message, the session and CSRF gate and the three
approval actions answer as before; `index.cjs` is 2,787 → 752 lines and holds only config,
construction, the router and server start. 68 new tests, none booting the server;
`documents.test.cjs` now calls the modules instead of slicing `index.cjs` as text. The Claude
Diary plugin README's revocation section points at Settings → Diary & storage → Connected apps
instead of a deleted script.


### 2026-09-21 — index.cjs in pieces, and a measurement instead of a port (release a4e0178, deployed)

The server's toolboxes and built-in tools, its MCP wiring and its chat loop each moved out of
`index.cjs` into a module with injected dependencies (`toolboxes.cjs`, `mcp-wiring.cjs`,
`chat.cjs`) and a `routes/` file, with tests that never boot the server; the tests that used
to slice `index.cjs` as text now call the modules. Behaviour is unchanged: the approval gate,
the per-user MCP credentials and the project a tool call acts for all travel exactly as
before. `index.cjs` is 4,241 → 2,787 lines.

Removed because nothing called them: the Hugging Face model search and the variants listing
(server routes, front-end wrappers and their types), six helpers in `index.cjs`, a finished
Docling handoff document. Every spec is now linked from the docs index, and the Claude Diary
plugin README no longer points at a script that was deleted.

Measured, with synthetic data: Node spends about 10 µs of CPU per streamed token; the engine
spends 25–90 ms. Nothing is worth porting. The one slow Node path — fitting a long tool
result to the model's budget re-rendered every surviving record on every step — is now
linear: a 500-record listing reduces in 0.5 ms instead of 53, byte-identical. Study and
numbers: `docs/research-language-consolidation.md`; rerun with
`apps/web/scripts/profile-hot-paths.cjs`.


### 2026-09-21 — The Code tab, full height and honest about the network (2d7ba8f)

The chat composer no longer sits under the Code tab, which left the task form half the height
with an unrelated send button below it. And because this server runs no egress proxy, "Reach the
network" and "Install dependencies" are shown unavailable with the reason — and the server no
longer grants them — instead of being accepted and then quietly never happening.


### 2026-09-21 — "Thought for 12s" (bbae129)

A reasoning reply now says how long the model thought — from its first thought to the first word
of the answer, or to the tool it decided to use — measured as it streamed and kept with the chat.
Older chats, and ones streamed on another device, fall back to the length of the thinking.


### 2026-09-21 — A quieter chat footer (5ae8d7f)

The context meter no longer takes a row above the composer to say "Calculated when you send":
a short chat that has not been measured shows nothing, a measured one shows a single quiet line
aligned with the composer, and a long unmeasured chat still offers compaction. It is read when
a chat opens and when a reply finishes, instead of every three seconds for every open chat.
"Thought for 312 words" now reads "Thought · 312 words".


### 2026-09-21 — Templates for new Diary files (a1ededd)

A `Templates` folder at the Diary's root — Obsidian's convention — is offered when a new file is
still empty. `{{title}}`, `{{date}}` and `{{time}}` are filled in (with optional formats, as in
Obsidian); anything else in braces stays as written. Nothing is saved until you save.


### 2026-09-21 — Unlinked mentions (780b8c7)

"Find links to this file" also lists the notes that name it in prose without linking it — whole
words, case-insensitive, never inside code or properties. They are shown, not rewritten: turning
a mention into a link is an edit to someone's note, and edits here are explicit.


### 2026-09-21 — Auto-tune says what it is doing, as it does it (f66ecd2)

A run is 5–15 minutes of a progress bar that can sit still for a minute while the engine
loads, and a still screen reads as nothing happening. Auto-tune now keeps a timed, line-by-line
account: each test and the exact settings it writes, "still loading · 25s" while the engine
loads, every workload's speed and draft acceptance, why a candidate was rejected, what it chose
and why, and whether the original settings were put back after a cancel. It follows the newest
line while running, and folds away once the run is done. The panel now refreshes every second.


### 2026-09-21 — A note's properties, and the tags a vault really uses (5b0e531)

A leading YAML block is shown as the properties it is rather than as three dashes and a list of
keys pretending to be prose; a line the reader cannot parse is shown as written rather than
dropped. The tag filter now also reads the `tags:` property, which is where a diary written in
Obsidian keeps its tags — excluding it meant the filter quietly missed most of them.


### 2026-09-21 — Documents in folders could not be read (c237480)

The Docling sidecar refuses a name that could be a path, and noevia's names are paths, so every
document inside a folder failed with "Document extraction unavailable (HTTP 400)" while a file
at the root worked. noevia now sends the file name. A 400 is also named for what it is — noevia
sending the document wrongly — and stays retryable, so the documents it broke read again on the
next sync rather than keeping a cached failure. Rollback 71f1ab0.


### 2026-09-21 — Typing [[ offers the files you could mean (71f1ab0)

The Markdown editor suggests the files in the folder as soon as you type `[[`, inserts the
shortest name that is unambiguous and closes the brackets for you. Arrow keys choose, Enter or
click inserts, Escape leaves what you typed alone. It stays a textarea throughout — the
suggestions are an offer beside it, not a form control.


### 2026-09-21 — The Docling sidecar is deployed

Document extraction now uses the sidecar that was verified in September and then sat unused:
reading order, table structure, and the Office, OpenDocument, HTML and image formats that were
previously stored whole and unread. CPU-only, so it never contends with the engine for VRAM.


### 2026-09-21 — Obsidian-style [[links]] in the Diary (f72c2a6)

A vault written in Obsidian is full of `[[wiki links]]`, and noevia rendered every one as
literal text and found none of them when asked what links to a file. They now render as links,
open the file, and count as backlinks alongside relative Markdown links. Aliases, heading and
block anchors and the `![[embed]]` form are all recognised; a link to a file that is not there
is shown as the writer wrote it rather than as a button that opens nothing. Nothing is
rewritten: the vault stays exactly as its owner left it.


### 2026-09-21 — Connect an app to the Diary in Settings (6eb1698)

Connected apps is a section of Settings → Diary & storage: name it, copy the credential once,
revoke it in one click. It replaces `diary-connector-admin.cjs`, a script an administrator had
to run on the server. Also removed: two components nothing rendered, and the CSS of two
interfaces that no longer exist (the old Code sidebar and the old Diary landing).


### 2026-09-21 — Code mode runs, and is on (f57dd21)

noevia writes the coding harness's own configuration file — every action class asking, one model
endpoint, no self-update — and refuses a harness whose configuration it cannot pin. A repository
owned by the harness user is used instead of being reported as "Not a git repository". The
sandbox is deployed on an internal network whose only other member is the engine, and a real
task fixed the scratch fixture end to end. Rollback 39b0970.


### 2026-09-21 — Usage: peak hour, favourite model, tool calls (b126eb6)

The usage file gained two counters: replies by hour of the local clock, and one count per tool
call recorded where the call runs. Usage shows a peak hour on a readable clock, the busiest
model and a per-tool list. Older files read as empty rather than needing a migration, and an
account with nothing recorded says so. Rollback 05cc153.


### 2026-09-21 — The project screen (05cc153)

Header actions, context chips above the composer, an Outputs row for the documents noevia made
in the project, labelled recent chats, and a context panel with Context and a Scheduled row
marked not yet available. Covered by `qa/project-screen.cjs` at 1440 light and 390 dark.
Rollback 5379771.


### 2026-09-21 — Nextcloud is a connector of its own (5379771)

Plugins → Connected lists Nextcloud beside Google Drive. It reuses the connection set under
Settings → Diary & storage, says plainly when that connection is missing, not configured on
this server, or at an address outside `MCP_NEXTCLOUD_ORIGINS`, lists the toolboxes it offers,
and carries the same per-tool permissions as Drive — writes can never be “Always allow”.
Rollback 76865e1.


### 2026-09-21 — Routing split; Projects tab (76865e1)

Routing keeps the Auto roles; thinking effort is its own panel; per-project routing is its own
tab. Rollback a73a72d.


### 2026-09-20 — Models page: one tab bar (a73a72d)

Routing, Hardware, Benchmarks and Prompts are tabs instead of sections stacked under the model
list. Rollback d99c066.


### 2026-09-20 — README, icon set, last Cowork prose (d99c066)

The logo's two squares now read as depth in light mode; adds a favicon, Apple touch icon,
maskable icons and a web manifest (none existed). README describes what noevia does today.
Rollback 06f5aa4.


### 2026-09-20 — Add an MCP server by URL (06f5aa4)

Admins can add a server that is not in the registry, with an optional sign-in header (shared
or per account) or OAuth. Same checks as a directory server. Rollback 8b458e9.


### 2026-09-20 — Routing panel spacing and width (8b458e9)

The four Auto role pickers sit two to a row; Default thinking effort is separated from the
save button; disclosure rows and panels share one spacing scale. Rollback b8d78a9.


### 2026-09-20 — The UI and MCP branch is merged into main (b8d78a9)

An overnight deploy of main had replaced the 2026-09-19 UI and MCP work, which was only on
`claude/blissful-brown-v86y3o`. Merged (two conflicts: appended tool-routing tests and
release notes, both kept) and deployed together with Docling and tool-result compaction.
823 server tests, 74 QA suites. Rollback aad6216.


### 2026-09-19 — Models page: faster, cards side by side, one toolbar (06f9402)

The list shows at once while file details load; the folder scan is cached server-side.
Cards up to three per row; tabs, search and filters on one line. Rollback d459867.


### 2026-09-19 — Diary from Code; model and tools panel reworked (d459867)

Diary opens from Code mode. The model panel spreads model and tools side by side on wide
screens, with a segmented Auto/Manual switch, one-line model rows, compact tools and a budget
meter, on an opaque surface. Rollback da5dfa9.


### 2026-09-19 — Per-account API keys for directory MCP servers (da5dfa9)

Admins choose 'Each person uses their own key' or 'Everyone uses this key'; each account adds
its own key in Plugins → Connected and only then gets the server's tools. Rollback 3f3ff1e.


### 2026-09-19 — Hand-registered apps for MCP sign-in (3f3ff1e)

Sign-in services without self-registration: the admin registers an app with the shown return
address and enters its client ID (and secret). Stored encrypted; replacing it signs everyone
out. Rollback c173952.


### 2026-09-19 — Per-account OAuth sign-in for directory MCP servers (c173952)

Servers that ask for OAuth are added through a sign-in tab; each account signs in for itself
from Plugins → Connected and only then is offered the server's tools. PKCE, resource
indicator, refresh; tokens encrypted per account. Rollback e4fc0d3.


### 2026-09-19 — Sign-in keys for directory MCP servers (e4fc0d3)

Hosted servers that need a key can be added: checked before saving, stored encrypted, never
returned, sent only to that server in its declared headers; changeable; admins only. Rollback
6330ea8.


### 2026-09-19 — Skills auto-load; skills and MCP servers from the directory; long model names (6330ea8)

A message matching one enabled skill gets its reviewed instructions. Plugins → Skills adds a
published SKILL.md to a project (arrives needing review). Admins can add hosted MCP servers
from the registry: own toolbox, no credentials, every tool asks, removable. Model names keep
their start and quantization ending; the model list filters. Nine QA suites updated; all 74
pass. Rollback a163543.


### 2026-09-19 — Settings no longer reopens on a quick reload (a163543)

Closing Settings forgets it as the reload target at once. qa/mtp and qa/google-drive pass again.
Rollback 957e972.


### 2026-09-19 — Model picker Tune button back to 44px (957e972)

A later generic button rule had shrunk it to 30px. Rollback ba95afa.


### 2026-09-19 — Engine holds the embedding model beside the chat model (ba95afa)

llama `--models-max 2` (live override edited, backup kept); before a chat model is used, other
chat models are unloaded and the embedding model stays. Tool routing (already on via
NOEVIA_FEATURE_TOOL_ROUTER=true) no longer evicts the chat model. Rollback 41cb2aa.


### 2026-09-19 — Tool routing: "Using:" line and ask-for-more (41cb2aa)

When routing narrows a message's toolboxes the reply says which, and the model can ask once for
the rest of the project's tools. Routing stays off: the live engine holds one model
(`--models-max 1`), so the embedding model would evict the chat model on every message.
Rollback 363171c.


### 2026-09-19 — Re-fit after zoom (363171c)

The page re-stretches after zooming in and back out on iOS. Rollback c71a30d.


### 2026-09-19 — Tall screens: full layout from 520px, pages grow, greeting centred (c71a30d)

A zoomed-out phone keeps the sidebar from 520px wide; short pages grow up to 125% on phones and
tablets; the empty chat greeting sits mid-height. Rollback 70631b0.


### 2026-09-19 — Shrink-to-fit for slightly-too-tall pages and menus (70631b0)

Pages and menus that overflow by a little are scaled just enough to fit (never below 82%);
long lists keep their size and scroll. Rollback f87b157.


### 2026-09-19 — One sidebar for Chat and Code; Plugins page (f87b157)

Code mode reuses the chat sidebar (current look, switch in the header, aligned rail, shared
collapse). Closing Settings keeps you in Code. New chat floats over the list; the collapsed
rail names items on hover; Chat/Code eases in. Google Drive moved from Settings to Plugins,
which also browses the MCP registry and Anthropic's skills. Rollback 027bd00.


### 2026-09-18 — iOS keyboard fix; web image flattened (027bd00)

The keyboard no longer pushes the page up on iOS. The web image had hit Docker's 127-layer
limit; overlay-release.sh now flattens it automatically past 100 layers. Rollback d995cd9.


### 2026-09-18 — Composer focus, iOS keyboard, phone Settings (d995cd9)

No square focus ring in the composer; the app follows the iOS keyboard; legacy narrow phone
Settings rules removed. Rollback 7326ac0.


### 2026-09-18 — Visual pass (7326ac0)

Legibility sweep across sizes, materials and themes with real device user agents; fixed the
phone composer row, phone Settings width, sidebar row alignment. Rollback 4c151be.


### 2026-09-18 — Sidebar header and phone drawer like Claude's (4c151be)

Small Chat/Code switch beside the logo; full-width phone drawer with search on top; the
drawer closes when you switch mode. Rollback 5cd033b.


### 2026-09-18 — Diary in the bottom bar, sliding Chat/Code, project colours (5cd033b)

Diary beside Search; liquid-glass Chat/Code thumb; phone Code drawer works; project colours
everywhere. Rollback 5a0e026.


### 2026-09-18 — Icon centring scoped; row options beside the title (5a0e026)

Only icon-only buttons centre their icon; sidebar row options no longer cover the title.
Rollback 350050e.


### 2026-09-18 — Composer like Claude's, SVG icons (350050e)

Centred SVG + with a files-and-tools menu (no duplicate model entry), Thinking as a menu of
levels, Code keeps a closed sidebar, every icon an SVG and centred. Rollback 91a89ba.


### 2026-09-18 — Account menu and Search like Claude (91a89ba)

Light/dark in the account menu, Search beside the account, account menu unclipped from
the rail, clean rail Chat/Code, no blank page entering Code. Rollback 94909d3.


### 2026-09-18 — Collapsed sidebar like ChatGPT's (94909d3)

Icon-only rail with the avatar at the bottom, remembered per device, expands from its
empty space. Rollback 4152d15.


### 2026-09-18 — Settings and sidebar organised like ChatGPT (4152d15)

Sidebar order Pinned, Projects, Recent chats. Settings is one flat list: General, …,
Security and login, Account; renamed pages, same content. Rollback 95eacd6.


### 2026-09-18 — Sidebar as one scrolling plane (4ea3282, 95eacd6)

Like ChatGPT: one scrolling rail, Diary and Plugins with the top destinations, flat
Projects/Pinned/Recent lists, only the account pinned, every chat listed. Rollback 4ea3282.


### 2026-09-18 — Material 3 and phone fixes (265c650, 6930549)

The Material material is now Material 3 component by component; touch fields are 16px
everywhere; narrow Appearance controls fit; Projects counts active projects; sidebar lists
never collapse to their heading. Two guarded overlays after verified backups; five
services healthy. Rollback 265c650.


### 2026-09-18 — Phone review fixes (3d20de0, a2a1c8e, e777259)

Three guarded web-only overlays over d11cfac, each after a verified appdata backup.
The phone drawer is whole from any view, Diary/Plugins are never under the footer,
row menus are no longer clipped, theme previews and the selected ring are correct,
Settings rows align, the strip no longer reports a false outage at start, and desktop
list headings stay in view. Five services healthy after each. Rollback a2a1c8e.


### 2026-09-18 — UI overhaul release 3 and phone-review fixes

Deployed d11cfac over ab2720a as a web-only overlay (no dependency changes). 861 web tests,
typecheck, design lint and a fresh build passed first; appdata backup ab_20260918_112354.
Five services healthy, zero restarts, native engine untouched. Live browser QA was partial
(write-approval card, phone width, themes and accents still owed). No real Diary corpus used.
Rollback ab2720a with .env.bak.before-d11cfac; see deployment.md.


## 2026-09-14 — Qualified direct native inference in production

### 2026-09-14 — Markdown date/tag filters

Deployed 48432fe: bounded stored-file search supports inclusive filename dates and
whole hashtags, alone or combined with text. 426 web tests, 343 Linux image tests,
CI and synthetic six-size/two-theme editor checks passed. Production health and
ordinary-chat smoke test passed; no real Diary corpus used.


### 2026-09-14 — native model UI and mobile approvals

Deployed 02495a7: embedding/reranking excluded from chat selection, accurate native
MTP guidance, 44-pixel approval targets. Full arguments and three decisions verified
in six viewports/both themes. 424 web tests, 343 exact-image server tests and CI
passed. Production synthetic chat and all four service health checks passed.


Switched the existing 2570a02 app release to pinned native llama.cpp with guarded
GPU and isolated app/client workload tests. Preserved existing model IDs, shared
provider settings and rollback backups; retained Lemonade stopped for recovery.
Verified live phone chat, 32k context and actual MTP counters; archived synthetic
verification chat. Added repeatable native and populated mobile QA. No real Diary
corpus testing, migration or reindex. See deployment.md for exact rollback.

# Changelog

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


Newest first. Merged from `QA-2026-09-08.md` and `review-fixes.md`.

Dependency audits report known advisories; they are not a guarantee that software
is free of vulnerabilities. Keep dependencies, the host, and the inference services
updated.

---

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

## Chat context budgeting and compaction — 2026-09-10

Added ordinary/project-chat context meter above the composer with an expandable
breakdown of messages/summary, instructions/memory/sources, tools, generation
reserve, safety buffer and free space. Counts are conservative UTF-8 estimates,
not exact tokenizer or account totals; unknown limits use a labelled 8k fallback.
Lemonade uses the loaded model's configured ctx_size, not its architecture maximum.
The first prepared request establishes the meter; later visible output updates
its estimate. Existing chats can use Compact chat before sending another turn.

Manual and automatic compaction summarize older exchanges with the selected
provider, preserve two recent exchanges verbatim, and keep the full visible/saved
transcript. Summaries are private per-user/per-chat files and exact-prefix hashes
invalidate them after edits. Failed/unusable/truncated summaries retain previous
context; oversized sources/recent messages fail clearly rather than being dropped.
Compaction is lossy and may omit details. Diary's separate journal is unchanged.

Requests reserve up to 4,096 generation tokens and 15% estimation margin; automatic
compaction triggers when input exceeds the remainder (about 72% for 32k). High
effort cannot expand or discard this budget. Tool continuations are rechecked;
context errors inside SSE are surfaced, and heartbeat frames cover silent waits.
No automatic retry of tools or writes. Configured capacity is not a guarantee of
available shared-backend memory, and non-Lemonade model limits remain a fallback.

338 tests, typecheck/build, and synthetic browser QA pass: manual/automatic
compaction, transcript retention, cache reuse, failure handling, streamed errors,
375/768/1440 widths and both palettes. Deployed `ae39000`; all three services
healthy, public assets match, 290 Linux server and 13 worker tests passed. No private
financial data, Diary prompts, model reloads or live corpus changes used in QA.

## 2026-09-10 — shared Diary server connector and Nextcloud push repair

Deployed `12a1646`: dedicated revocable Diary credentials and live version-checked
Markdown tools. Stale saves conflict rather than overwriting newer files. Private
Claude plugin prepared; import and a real Claude round trip remain outstanding.
The plugin identifies itself as `noevia-diary/1.0` because production rejects the
default Python client identifier. Synthetic tests pass; no corpus edits performed.
Nextcloud push now uses its internal Apache callback; six self-tests pass before
and after restart. Rerun the repair after AIO recreates the push container.

## 2026-09-10 — oversized PDFs and native local-Qwen thinking

Deployed `ddbe852` (including `2408c32`). PDFs up to 60 MB receive asynchronous
native-text extraction and image compression before the 25 MB storage limit is
applied. Validated compressed PDFs and labelled text-only fallbacks use distinct
filenames; originals remain on the user's computer. Invalid, encrypted and
unrecoverable inputs fail without replacing existing sources. Local Qwen Low/High
now uses the actual thinking-template switch rather than a hint. Default remains
provider default. The exact installed 9B GGUF lacks MTP weights; support in the
original architecture does not make this file MTP-capable.

329 web tests, typecheck/build, synthetic browser checks, 281 Linux server and
13 real worker tests passed. Health/public assets verified. Shared Diary editing
is designed around version-checked server access; the Claude adapter is not yet
configured. Nextcloud's push self-test found a reverse-proxy trust failure, while
Mac upload-queue health remains unverified. See `spec-diary-shared-editing.md`.
No real Diary writes, corpus reconciliation or model changes were performed.

## 2026-09-10 — MTP controls, acceptance and fixed inference footer

Deployed `cac1778`, including `df8a486` (New chat launch) and `8eb7b99` (native
MTP Yes/No load controls and permanent inference footer). Chat and Diary show
actual acceptance: cumulative backend counters when available, otherwise the
current user's last response timings, labelled accordingly. Installed llama.cpp
b9632 uses the latter and updates at completion. Unsupported models explain why
MTP cannot be enabled; existing GPU/cache/context settings survive changes.

325 web tests, 178 Diary tests (3 skipped), typecheck/build, synthetic browser
checks, 277 isolated Linux server tests and eight worker tests pass. The Diary
wheel-scroll regression timed out during concurrent browser runs and passed on
its isolated rerun. All three services run `cac1778` with zero restarts/OOM;
Diary healthy, web/OCR 200, public assets match. No production model loads or
real Diary corpus tests. Multi-GPU benchmarking and compatible external draft
models remain experiments. Broader roadmap testing pause continues.

## 2026-09-10 — live Diary progress and long-request connection

Deployed `3ef0501`. Diary now streams real provider thinking/answer output while
retrieval and capture stages report their progress with an elapsed timer. Optional
tool traces stay on their turn. Immediate response headers and keep-alives prevent
silent long-running exchanges from waiting for capture before responding. Proxy
HTML is sanitized, interrupted saves are explicitly unconfirmed, and there is no
automatic resend. Switching app views keeps the mounted exchange; full page reload
recovery remains open. 319 web tests, typecheck/build, 177 Diary tests (3 skips),
synthetic browser regressions, 271 Linux server and eight worker tests passed.
All services healthy; public build assets match. Broader roadmap remains paused.

## 2026-09-10 — Diary reading and reasoning feedback

Deployed `ecaaa73`: saved summaries are a separate disclosure during the active
conversation; the day composer stays outside scrolling content. Diary and normal
chat stop following output when the reader scrolls up. Provider reasoning reaches
the Diary thinking disclosure separately from journal text and follow-up history.
Diary reasoning arrives at completion, only when the provider supplies it; live
Diary streaming and durable full conversation history remain open.
315 web tests, typecheck/build, 172 Diary tests (3 skips), synthetic browser checks,
267 candidate Linux server tests and eight worker tests passed. All three services
run the release, public assets match, zero restarts/OOM. Broader roadmap paused.

## 2026-09-10 — skill metadata names the file to load

The existing skill index now supplies exact filenames, escapes metadata as JSON,
and bounds catalogue size. Tool permissions and source loading remain unchanged.
314 web tests, typecheck/build and 171 Diary tests (3 skipped) pass, including a
real-handler prompt assertion. Full instruction-skill lifecycle remains planned.
Deployed `79cd24f` after 267 Linux server and eight worker tests. Wizard and
limited default-off DAV shipped in `9e2bfbb`.

## 2026-09-10 — explicit Diary and storage choices during setup

Fresh setup asks Diary/chat before account creation. Storage offers server-held
or existing external service choices; skipping and failed saves preserve the
configuration. The picker waits for saved settings before editing or saving.
Admin preferences include the existing thinking default. 310 web tests,
typecheck/build, 171 Diary tests (3 skipped) and expanded synthetic browser checks
pass. Existing completed users remain completed. Rollout pending.

## 2026-09-10 — optional bounded Diary file sharing

Added a separate, default-off listener and per-user sharing controls. Supported
Markdown reads/property lists/conditional writes use the existing tenant file API.
App-password scope and configured transport are enforced. No port is published by
default. Full DAV/file-manager compatibility remains open. 310 web / 171 diary
(3 skipped), typecheck/build and synthetic real-app browser checks pass. Rollout
pending; production sharing will remain off.

## 2026-09-10 — revocable device app passwords

Per-user name/scope/date metadata, shown-once random secrets, Argon2id hashes and
individual revocation are available in Profile & security. Credentials do not
permit account login or chat. Sharing remains unavailable; no new listener opens.
304 web / 171 diary tests (3 skipped), typecheck/build and synthetic real-app
browser checks pass. 257 Linux server and eight worker tests passed; deployed `2525de5`.

## 2026-09-10 — DOCX main-body text and tables

Unified uploads and connected-folder refresh retain originals and extract bounded
DOCX body/table text in the private worker, with explicit partial-coverage labels.
Malformed replacements clear stale text and remain downloadable; no dependencies
or corpus changes. 301 web / 171 diary tests (3 skipped), typecheck/build, six
local worker tests and synthetic real-worker browser QA pass. 254 candidate Linux server and eight worker tests passed; deployed `e18f1de`. See the roadmap audit for parser limits.

## 2026-09-10 — engine throughput omits unstable short samples

The display labels the engine rate as reported and omits invalid or sub-second
count/rate samples instead of displaying timer-dominated spikes. Valid longer
samples remain untouched; missing values stay unavailable. 297 web / 171 diary
tests (3 skipped), typecheck/build, live read-only sample and manual UI check pass.
This is sample filtering, not a repaired upstream benchmark. Deployed `3b1e256`.

## 2026-09-10 — reasoning-only output is no longer presented as an answer

The final-answer channel now reports that no final answer was returned instead of
copying internal narration. Per-round tracking covers tool continuations, retaining
tool results and separate reasoning. No extra inference/tool retries. 295 web /
171 diary tests (3 skipped), typecheck/build and synthetic real-server browser
verification pass. Model output quality remains a separate limitation. Deployed `34df7c2`.

## 2026-09-10 — thinking effort reports what the provider receives

Added admin defaults, project/free-chat overrides and optional Diary extras effort
controls beside model selection. Documented GPT-5.4 on OpenAI receives a parameter;
other pairs get labelled hints. High hints request an explicit 8,192-token budget,
with field-rejection fallback. Default leaves the request unchanged. The companion
and approval gate remain unchanged. 292 web / 171 diary tests (3 skipped),
typecheck/build, synthetic real-server/browser checks and local inference pass.
Uncapped budgets and wider provider verification remain out of scope for this v1.
Deployed `6570c51`.

## 2026-09-10 — Diary components are easier to maintain

Landing, calendar and context sidebar are extracted from dense inline JSX.
Existing navigation, storage and composer behavior remains; Up honors busy like
other file navigation. 281 web / 171 diary tests (3 skipped), typecheck/build,
both synthetic browser suites and manual calendar review pass. Deployed `7a34a0a`.

## 2026-09-10 — Diary landing reflects its actual contents

Empty diaries show a first-entry composer without a fictitious month. Populated
diaries show memory files, recent entry dates and tenant Raw Sources Markdown,
with month navigation below. Loading/errors do not masquerade as empty diaries.
Operator-wide import paths remain administrator-only. 281 web / 171 diary tests
(3 skipped), typecheck/build, synthetic browser and manual layout checks pass.
Deployed `8edacf7`.

## 2026-09-10 — first-entry folders survive interrupted writes

New corpora receive Entries, AI Memory and Raw Sources seed READMEs with their
first logged exchange. Create-only writes use the existing durable journal and
ETag recovery, preserving existing files and avoiding duplicate entries on retry.
Existing/imported entry corpora are not migrated. AI Memory files join direct
context reads without copying legacy memory. 171 diary tests (3 skipped), 281 web
tests, typecheck/build and synthetic manual verification pass. Deployed `b34c33f`.

## 2026-09-10 — older entries remain available without semantic matches

The companion now falls back to bounded direct tenant file reads when semantic
retrieval is missing, empty or fails. It reads two explicit past ISO dates plus
three preceding days by default, within shared context limits. References state
the limited scope; successful semantic matches avoid extra reads. Existing daily
and monthly layouts remain the single source of truth. No write path changed.
166 diary tests (3 skipped), 281 web tests, typecheck/build pass. Deployed `23ba691`.

## 2026-09-10 — landing Diary messages follow the selected day

Landing messages previously stayed in a hidden home conversation. Send now opens
the destination day first, preserving its existing history, local/streamed replies,
retry state and optional-tool approval scope. Past-day selection and timestamps
stay unchanged; cancellation never starts capture. 281 web tests, typecheck/build,
157 diary tests (3 skipped), synthetic browser regressions and manual review pass.
Deployed as `5b1ef12`.


## 2026-09-10 — resumable member onboarding and explicit Diary choices

Invitations inherited a completed-onboarding default, skipping setup entirely.
New invitees now start incomplete, and members get Diary/preferences/passkeys
without administrator setup or global model controls. Saved Diary choices hydrate
the wizard immediately; updates persist with visible failures and retained focus.
Back and sign-out/resume clarify navigation; the dead-end models step is removed.
Completion preserves existing consent and defaults missing rows off. The separate
legacy feature backfill no longer re-enables missing rows on each restart.

Verification: 278 web tests, typecheck/build, 157 diary tests (3 skipped, two
existing warnings), synthetic real-server browser regression and manual review.
Application **`baf38aa`** is deployed to all three services, replacing `66af1ad`.
All 234 server tests passed in an isolated production-host image; 42 scoped live
assertions passed, including synthetic invitation/resume/completion/role boundaries
and cleanup. Public UI served the final bundle without resetting the existing user
into onboarding. Five synthetic accounts were removed; no real diary prompts or
corpus changes. `.bak.before-baf38aa` config/Compose/override and the previous
release remain for rollback. Tailscale was restored to stopped.


## 2026-09-10 — shared composers and opt-in Diary context

Project landing pages and Diary lacked the composer controls, and free chats could
not retain their own attachments/tool selection. All functional chat composers now
share the + menu. Diary extras are opt-in for the current session and off on reload;
its normal retrieval/capture remains active. Preparation uses the existing MCP
approvals and tool loop, then supplies bounded reference to the diary companion.
Attachments stay outside the diary corpus. See the audit for test evidence and
behavioral boundaries.


## 2026-09-10 — composer files and tool controls

Tools and uploads were buried outside the conversation. A + control now opens
a compact menu above the chat composer: Files and photos, Tools grouped into
Built-in/Connectors, and Model and routing. Project tool selections use the
existing permission-checked configuration route; all three write approvals remain.
Uploads retain the existing file limits, organized Nextcloud storage, and progress.
No skills or plugin execution features are implied by this menu.


## 2026-09-10 — unified uploads and visible processing

Application release `48027ef` replaces `e3b29bb` in production. One Sources upload
control now accepts non-archive originals up to 25 MB, including DOCX. Connected
storage receives Documents/Images/Text/Other subfolders; the UI uses the same
groups. Opaque formats remain stored-only, with authenticated original downloads
and explicit model-context disclosure. Images retain a bounded local cache for
inference; the 8 MB image-input budget is separate from the storage limit.

Earlier local image uploads are copied to connected storage on refresh. Transfer
percentage and per-file elapsed time are distinct from saving/extraction stages;
image chat exposes preparation status before model processing. The obsolete 1 MB
background request cap and 40-file refresh cap were corrected. The project quota
remains 60 total sources, with regression coverage for a 41-file refresh.

Verification: 256 web tests, typecheck/build, and 155 diary tests passed (3 skipped,
two existing dependency warnings). Local browser checks covered mixed uploads and
mobile source rows. Authenticated production checks uploaded synthetic PNG, PDF,
and DOCX files through one chooser, confirmed Documents/Images storage paths,
OCR-ready PDF metadata, original links, timing details, and successful refresh.
Image preparation feedback appeared at 0.2 seconds in the synthetic chat check;
the model correctly identified the shapes, colors, and ZEBRA-73 heading in 21.9
seconds. The synthetic chat and project were archived after verification.
The diary corpus and private financial files were not used for testing.

Deployment used the existing Tailscale configuration because the LAN route was
unavailable. All three service images use `48027ef`; prior release and
`.env.bak.before-48027ef` / Compose backups are retained for rollback. Tailscale
was restored to its previous stopped state after deployment and verification.


## 2026-09-10 — bounded reliability, OCR and image rollout

Production now runs `e3b29bb` (previous `cd717b0` retained). This includes the
agent deployment contract, duplicate tool-call protection, page-aware PDF source
retention/status, binary source reads, isolated local OCR, and image handling fixes.
All changes were pushed to main after 247 web tests, typecheck/build, 155 diary
tests (3 skipped), and three real OCR container tests passed.

Lemonade 10.8.0's Qwen 9B registration now loads its matching mmproj. Synthetic
inference recovered an invoice, dated/signed amounts, and total; authenticated
production chat identified a blue circle, orange triangle, and ZEBRA-73 from a
separate image, then correctly cited the scanned second PDF page and its values.
A synthetic mixed PDF uploaded through Nextcloud and showed OCR-ready status and
an Original PDF link. No real diary prompts or financial-document tests were used.

The live Compose Manager file now includes the internal OCR network and service;
web can reach OCR health, diary is healthy, and all three images use `e3b29bb`.
Compose/env backups carry `.bak.before-e3b29bb`; the Lemonade registration backup
is `user_models.json.bak.noevia-vision-20260910`. OCR preserves original/native
text, labels its output, and enforces documented resource limits. Existing PDFs
need refresh/re-upload. OCR accuracy, complex tables, and handwriting still need
human checking; interrupted polling after a server restart requires retry.


## 2026-09-08 — development continuation and QA

Based on a clean `0f8a9c1` checkout. The older UI master prompt was treated as
design context; much of its implementation was already present.

### Environment and build

- Fresh startup creates the state directory before writing its encryption key.
- **Dev, build and type-check scripts now invoke Node directly**, fixing the
  long-standing "`npm run typecheck` is broken" workaround. Vite uses the runner
  config loader, avoiding temporary writes inside the external dependency symlink.

### Projects and sources

- New project folders include the project ID, preventing same-name projects from
  sharing a folder. Existing paths preserved.
- Uploading to an older project creates its missing storage folder on demand.
  Without remote storage, text/PDF uploads remain usable as local sources. S3 uses
  a prefix instead of an unsupported directory operation.
- Image/document request caps account for base64 expansion while keeping
  decoded-byte limits — a 7 MB image no longer fails the advertised 8 MB limit.
- Failed source reads preserve the previous source text. Successful empty listings
  and explicit detachment still remove old sources.
- A refresh preserves uploads and folder changes made while it was awaiting
  storage. Opening a project refreshes attached folders, throttled to once a minute
  for the same folder selection.
- Invalid project settings no longer partly mutate the live project.
- Debounced edits merge different changed fields instead of dropping all but the
  last patch. The edit dialog awaits saving and retains input on failure.
- Model/routing/toolbox save errors are displayed rather than silently ignored or
  becoming unhandled rejections.

### Vision

- Probes are scoped to endpoint, credentials and model, with expiring results.
  Missing projectors and availability failures now have **distinct, actionable
  explanations** shown in chat — previously a 500 ("maybe missing mmproj") was
  conflated with a 400 ("model cannot do this"), which is what led to
  "Qwen3.5-9B is blind" being asserted wrongly.
- Image-description cache keys include the user, provider endpoint and full
  question. Provider authorization runs before image requests; vision requests
  refuse redirects and respond to chat cancellation.

### Tools and approvals

- Repeated tool calls across inference rounds retain distinct chip identities.
- Pending approvals keep their full arguments and all three decision buttons.

### UI and accessibility

- Mobile chat breadcrumbs truncate long names without hiding Settings or the
  inspector. Project headings reserve inspector space. Tool results use a compact
  layout; approval arguments remain fully visible and wrap.
- Mobile Settings uses a category selector so forms get full width. Provider fields
  have accessible labels. The diary navigation-expand control is restored on phones.
- Project/model dialogs use native modality, Escape dismissal and focus restoration.
  Keyboard activation of a card's child controls no longer opens the project.
  Filter/archive empty states are explicit.
- Creation uses shared text-file validation rather than reading arbitrary selected
  binaries as text. Project initials use theme text contrast; the initial browser
  theme colour matches the dark canvas.
- `MarkdownPreview`: parenthesized links and tables now render.

### Verification

Web **161 passed** (11 new regressions); diary **145 passed, 3 skipped** (no diary
implementation changes); typecheck, build and `git diff --check` all passed.

Browser checks used an isolated authenticated instance at localhost:8022 with
disposable state and a local inference simulator — no production diary messages,
files or tool writes were created. Phone (375), tablet (768) and desktop (1440)
layouts in both themes, plus chat overflow at 320/640/641/1024 with no clipping or
horizontal overflow. Exercised onboarding, project creation, model selection,
failed-chat retry, two successive clock-tool rounds, Markdown tables/code/
parenthesized links, settings, diary home/calendar/error states, coding preview and
keyboard modal/card controls.

Docker was unavailable on the Mac; container builds and Compose validation were not
run locally. A live RAG/embedding smoke test remains necessary.

### Deployment note

Read-only SSH confirmed DaServer still ran `0f8a9c1` with a healthy diary
container. The patch introduced no required environment variables. Publishing and
deployment were subsequently approved; rollout is recorded in the DaServer
changelog. Existing projects that already share a folder are **not** automatically
split or moved.

---

## Earlier — diary conversation and reliability update

Diary questions now receive thoughtful replies directly in the diary conversation.
**The separate Insights screen, reflection endpoints and activity badge were
removed.** The logger still preserves the user's own words separately from
assistant commentary.

Clearer diary and chat composers, consistent focus states, better text contrast,
calmer cards, mobile layout adjustments, reduced-motion support. Setup completion is
acknowledged by the server before exiting, and unfinished onboarding resumes after
sign-in.

### Reliability and security

- Streaming errors use SSE after headers are sent. Split SSE lines are retained; all
  provider fetch paths refuse redirects and respect cancellation signals.
- Retry identifies the exact failed final message and preserves earlier history.
- Provider deletion updates the correct private/shared collection.
- Diary edits report pending writes honestly. Durable invalidation prevents stale
  retrieval after a crash, and pending operations replay in order.
- S3 storage enforces conditional writes; a disposable capability probe rejects
  unsupported servers before writing diary data. Bucket listings paginate.
- Members can connect only to operator-approved origins, avoiding DNS-rebinding
  exposure from member-controlled endpoints. Existing shared providers remain
  usable — see `SECURITY.md` for `MEMBER_OUTBOUND_ORIGINS`.
- External import folders require administrator access. Requests, import reads,
  session histories and pending Nextcloud login flows are bounded.
- Tenant UUID validation is strict; legacy migration applies only to the designated
  owner. Cache eviction no longer closes active requests' resources.
- Browser security headers protect against framing and MIME sniffing. Node runtime
  builds use the lockfile without falling back to an unlocked install.
- Auxiliary inference uses the documented endpoint/key fallback.
- The Python installer was upgraded past a known advisory.

### Verification

Node suite covers provider deletion, first-round model failures, split SSE, redirect
refusal, request limits and approved-origin checks. Diary tests cover failed-edit
acknowledgment, crash recovery, stale-retrieval exclusion, empty-document cleanup
and refusal of nonconforming S3 stores. The UI was exercised with an isolated local
fixture using synthetic responses.

---

## 2026-09-09 — deployed `f6832bf`

Three commits shipped to DaServer, replacing `8a78172`:

- `d8a6f2c` journal poison pill — one malformed entry no longer blocks every
  subsequent diary write.
- `def7c18` state directory permissions — parents of a nested state path took the
  umask rather than `0o700`.
- `f6832bf` docs consolidated from ten files to nine; the old
  `noevia-design-system.md` palette was stale and would have reintroduced the
  fire-engine red the UI overhaul removed.

Verified before push: 162 node, 147 python + 3 skipped, typecheck clean, on `main`
rather than on the feature branch. Verified after deploy: both containers on
`:f6832bf`, diary healthy, the poison-pill fix present *inside the running
container*, `localhost:8021` and `https://cowork.daserver.work` both 200, no
errors or tracebacks in either container log since restart.

**Not yet verified against real data** — these need an authenticated browser
session and were not done: a real diary write (the poison-pill fix is in exactly
that path), a Nextcloud upload, and one MCP write approval.

Rollback: `releases/8a78172` is on disk; repoint `current` and `COWORK_VERSION`,
then rebuild. Env backup at `config/.env.bak.20260909203405`.

### Incident during this deploy

The working tree's entire `docs/` directory disappeared mid-session — all nine
files at once, after they were committed and pushed. This is the same Nextcloud
eviction that previously ate `dist/assets` and `node_modules`. Nothing was lost
(`git checkout -- docs/` restored it, and `origin/main` was never affected), but
it is a reminder that this checkout lives on a sync client that removes files
underneath you. Commit early; do not treat the working tree as durable storage.

## 2026-09-09 — aux model 404, found while verifying the deploy

`LLM_AUX_MODEL` was the literal string `default` on the live deployment, because
`DIARY_AUX_MODEL` was never set and every compose file fell back to that
placeholder. No backend serves a model by that name, so **every** summariser,
skip-classifier and index-maintenance call had been 404ing — for at least five
days before it was noticed.

It hid because the pipeline degrades gracefully: `summarizer failed (...);
logging verbatim assistant reply`. Entries kept being written correctly and only
lost their `— Topic` headers. September 5–9 have 0 topics across 75 time headers.

Fixed in three places, because a fix in only one of them leaves the trap armed
for the next deployment:

- **Live `.env`**: `DIARY_AUX_MODEL=gemma-4-E2B-it-GGUF-UD-Q4_K_XL`. Verified the
  aux model now returns 200 on the exact call that was failing.
- **compose.yaml, deploy/examples/unraid-compose-manager.yml, and the live
  compose-manager copy**: `${DIARY_AUX_MODEL:-${DIARY_CHAT_MODEL:-default}}`.
  This mirrors what line 36/37 already did for `llm.aux.base_url` and
  `api_key` — the aux *model* was simply never given the same fallback.
  All three interpolation cases verified against real `docker compose config`.
- **services/diary/agent/config.py**: `_resolve_aux_model()` treats an empty or
  placeholder aux model as "reuse the chat model" and logs a warning naming
  `DIARY_AUX_MODEL`. This catches every deployment path, not just compose. Four
  tests, including that an explicit aux model is never overridden and that a
  wholly unconfigured pair is left alone rather than guessed at.

Historic entries were **not** backfilled. `/api/relog` looks like the tool for it
and is not: it re-logs an exchange from the *current in-memory session* at
`now=datetime.now()`, with an empty `sub_header`. Pointed at old entries it would
append duplicates stamped today rather than repair anything.

Tests: 151 python (+4), 162 node.

Synthetic source refresh also passed through the browser's background polling
path. The QA project and chat were archived (recoverable); their invented fixtures
remain available for review. The temporary OCR test container and host fixtures
were removed. Production remains on the tested application release `e3b29bb`.

Composer release `3320fc3` is deployed, replacing `48027ef`. All three service
images use the new tag; `.bak.before-3320fc3` config/Compose backups and the prior
release are retained. Diary health passed and web-to-OCR health returned 200.
The authenticated production browser verified a composer upload to Nextcloud and
enabled Nextcloud Files using the new menu. Qwen on the real Lemonade endpoint
then made exactly one `nc_webdav_list_directory` MCP call against the synthetic
project's Documents folder. The successful result named the synthetic DOCX; the
exchange took 23.7 seconds. This was a live integration test, not a locally
configured MCP endpoint. The QA chat/project were archived, local QA server and
tabs closed, viewport reset, and Tailscale restored to stopped. No real diary or
financial corpus was used.


Shared-composer rollout: application `12ba04f` replaces `3320fc3`. All three
production images use the new tag. `.bak.before-12ba04f` environment/Compose
backups and the previous release are retained; no environment/schema additions
were needed. Diary health passed and web-to-OCR health returned 200. The live
authenticated browser confirmed the new Diary + menu and extras OFF by default.
No production diary prompts were sent, nor were extras enabled against the real
corpus. Execution/approval tests used isolated synthetic inference, MCP, and diary
fixtures; the earlier real MCP integration test remains recorded above. Temporary
QA servers/tabs were closed, viewport reset, and Tailscale returned to stopped.

Live reliability audit rollout: `4ec8269` is now deployed to all three services,
following `cfc3a05` and `12ba04f`. Fixed repeat legacy migration into new admin
accounts, stale image input after oversized replacement, and administrator
deletion blocked by issued invitation/recovery tokens. Deletion also preserves
the last active admin when other admins are disabled. All three fixes passed
live rechecks; 266 web tests, typecheck/build, 157 diary tests (3 skipped), and
222 server tests inside the built image passed. Real Nextcloud approvals, OCR,
vector retrieval and isolated diary capture were exercised. Synthetic accounts,
corpora and the QA Nextcloud folder were removed. No real diary prompts/corpus
changes. Backups `.bak.before-cfc3a05` and `.bak.before-4ec8269` and previous
releases retained. [Coverage and remaining concerns](roadmap.md).

Composer model placement: `dc325d5` deployed to all services, replacing `4ec8269`.
Removed the chat-header model selector and placed it beside Send inside the text
composer, keeping the existing picker/routing behavior. Long labels truncate on
mobile. 266 web tests, typecheck/build and 157 diary tests (3 skipped) passed;
synthetic browser layout/switch/send checks and the live picker check passed.
Thinking-effort options are a future follow-up. `.bak.before-dc325d5` backups and
the prior release are retained; no environment/Compose changes were needed.

Shared composer controls: `66af1ad` deployed, replacing `dc325d5`. Project landing
and Diary home/day composers now share the model-button component and placement
used in free/project chats. Diary shows its fixed companion until extras are
enabled; the enabled picker configures optional context only. Thinking options
remain planned. Tests: 266 web, typecheck/build, 157 diary (3 skipped). Synthetic
mobile/desktop and light/dark checks, scoped picker checks, live project/Diary
checks and service health passed. No real diary prompts or corpus edits.

## Model manager: settings-native styling, layout mode, working search — 2026-09-17

Settings → Models & routing now draws on the same surfaces, radii, type scale and control
sizes as the rest of the settings pane; see design-system.md. No class names or tab
structure changed.

Hugging Face search no longer asks the hub for `full=true`. That parameter existed only to
fill in a per-repo GGUF file count, and it made the hub serialize every sibling file of
every hit — against the client's 20s timeout an ordinary browse of the top 30 GGUF repos
could time out and surface as "Network error" with an empty list. The count is now shown
only when the hub volunteers it. A named search that the `gguf` tag filter answers with
nothing is retried once without the filter and narrowed to repos that look like GGUF, so a
repo the hub has not tagged is still findable; browse mode (no query) is not retried, since
an untagged top-30 is not a GGUF browse. Failures are reported with the reason — a 401/403
points at the saved token, a 429 explains that a token raises the rate limit — instead of a
bare status code, and owner avatars, which noevia's Download tab never renders, can no
longer fail the search. Changing Sort by re-runs the search, and the empty state
distinguishes "nothing matched your search" from "the browse list came back empty".

New: a Layout control (Automatic / Phone / Desktop) backed by `public/layout-mode.js` and
user-agent detection. It sits in Settings → Appearance.

Verified locally: `npm run typecheck` and `npm run build` clean; web tests unchanged from
this checkout's baseline (274 pass, 45 pre-existing environment failures, identical before
and after); model-manager Python tests 19 passed, including 8 new ones covering the search
query, both fallbacks and the error messages. The hub itself was not reachable from the
development environment, so the search changes are verified against a mocked hub only.

## Merged main (PR #1) into the model-tuning branch — 2026-09-17

Four files conflicted, all of them touched by both PR #1 and Discover. Decisions:

- **`noevia.css`** — PR #1's surfaces win: `--bg-surface` on `--border-subtle`,
  `--radius-panel` for panels, 14px for rows, tiles, results and tables,
  `--radius-control` for fields, and the shared glass block with its reduced-transparency
  fallback. Its pixel sizes are re-expressed as this branch's type-scale roles, which is
  the same value in every rule the two sides both set, and the 550 weights it carried over
  are normalised to 600 — both are `lint:design` rules rather than a look. Each side's
  appended block is kept whole; PR #1's shared material goes last, as its comment assumes.
- **`api.py`** — Discover's endpoint wins, with one correction. It caught
  `httpx.HTTPStatusError`/`httpx.HTTPError`, which `search_models` no longer raises; taken
  verbatim, every rate-limited or unreachable hub would have become an unhandled 500
  instead of a readable error, and silently, because the types simply stop lining up. It
  now catches `hf.HfSearchError`, and the avatar lookup is guarded again. Both are pinned
  by new tests in `test_api.py`; the first fails against the unmerged endpoint.
- **`DownloadTab.tsx`** — Discover wins outright. Its header search box, sort control and
  filters supersede PR #1's local ones, and its `[sort]` effect already re-runs the search,
  so that fix is retired. Carried across: the query is trimmed, a new search collapses an
  expanded repository (the sort and filter paths did this, pressing Enter did not), a
  malformed body can no longer crash the list, the caption reads the term the results were
  actually fetched for rather than the 400ms-behind search box, and a hub error offers a
  retry.
- **`SettingsShell.tsx`** — this branch's settings restructure wins; the `general` section
  PR #1 mounted the layout control in no longer exists. `LayoutModeControl` is now
  `LayoutModeChoice`, a Layout row in `AppearanceSettings` next to chat font and density.

`hf.py` never conflicted — this branch does not touch it, so PR #1's search fix applies to
Discover unchanged. Dropping `full=true` costs Discover nothing either: it already fetches
repo trees itself, because the hub's search response carries no file sizes.

Verified: typecheck, build and `lint:design` clean; web tests 473 pass / 57 fail, identical
to this branch's head before the merge (the failures are this environment's missing native
dependencies); model-manager pytest 48 passed, up from 38 + PR #1's 8, plus the 2 new ones
above.
# 2026-09-22 (cloud material state correction; deployed as `72ae258`)

Corrected wrapped Material 3 segmented boundaries and role-paired hover/pressed
states for the mode switch, menus, outlined and destructive buttons. Liquid primary
actions retain legible primary colors during interaction, including in dialogs.
No geometry or application behavior changed. The cloud browser binary was unavailable;
rendered review remains pending. See [audit continuation](material-audit-2026-09-22.md).

The test runner now isolates state and restricts outbound sockets to disposable
fixture ports. The SSRF and egress disconnect tests no longer target arbitrary
host-local ports. All 1,247 guarded tests pass, along with typecheck, build and
design lint; the cloud browser blocks the local fixture, so visual QA is pending.

Local recovery: both cloud commits were recovered through their exact combined diff.
All 1,247 guarded tests and required static checks pass locally; the 468-state
synthetic view sweep, accessibility preferences, Code mode and mobile approvals pass.
Fixed two remaining nested/collapsed hover/press cascade conflicts and added a
rendered interaction regression. See the audit and deployment record for final status.

Release `72ae258` is live after verified backup `ab_20260922_201853` and guarded
overlay from `827932b`. All application services healthy, zero restarts; public assets
match the local build, protected endpoints return 401, no web error markers. Model
services and pi sandbox unchanged. Full rollback evidence is in docs/deployment.md.
