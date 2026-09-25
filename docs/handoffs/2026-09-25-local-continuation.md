# Handoff: continue the 2026-09-25 run locally (Mac, with ssh to DaServer)

Paste into the local Claude Code session on the Mac:

> Read `docs/handoffs/2026-09-25-local-continuation.md` on branch `claude/exciting-babbage-7x0g5n` of sbstndalton/noevia and work through it in order. Read `docs/handoffs/2026-09-25-cloud-run-ledger.md` first for what was already done; do not redo anything recorded there.

## State when the cloud session stopped
- `origin/main` = see the ledger's last MERGE entry (66794f7 or later; PRs for #262/#263 may have merged after, see below).
- Live per docs/changelog.md: web 2037ffd, diary 9b532a8, model-loader 5b6d9b6, code-sandbox pi-0.87.0-9b532a8, ocr 5004b50, docling 2026-09-21. **Nothing from main after 2037ffd is deployed.**
- The cloud session could not ssh, deploy, or delete remote branches (egress proxy 403).

## 1. Deploy, in this order (docs/deployment.md is the runbook; deploy-noevia skill applies)
1. **Web-only release from main** (carries #322, #325 docling header fix, #320 docs, #319 web side with the flag at its default, #321 web side inert until the key is set). Before: confirm `UI_AUTH_TOKEN` is set explicitly in the live `.env` if `LEGACY_AUTH_COMPAT=true` (#322 removed its fallback to `DIARY_AUTH_TOKEN`). After: `/api/ready` returns 200; `docker logs cowork-web-1 | grep egress` shows `egress.listening` on the code-network address; i18n screens render in the account locale.
2. **M2 (#321):** generate `DIARY_TENANT_KEY` (32+ random bytes, hex), add it to BOTH the diary and web env in all three Compose copies (`deploy/preflight/web-env-keys.txt` lists it). Release the diary sidecar image from main (`cowork-diary:<sha>`; this image also carries #326's month-file protection fix, so run `qa/dav-clients.cjs` locally first), verify a diary read and write, then release web again. Never roll the diary image back while web holds the key. Direct sidecar clients using `DIARY_LEGACY_USER_ID` stop working once the key is set.
3. **M3 (#319):** release a model-loader image from main (has `PUT /api/v1/models-ini`), then set `MODELS_INI_WRITER=model-loader`, recreate web, verify a preset save and a calibration run; `models.ini.noevia-backup-<rev>` is the rollback file. Follow-up PR: web's `/llamacpp-config` mount to `:ro`.
4. **Embed overlay (#320):** confirm every `[live: verify]` field in `compose.embed.yaml` against the box (image digest, healthcheck, depends_on, network incl. `lemonade_default`), then reconcile the three compose copies per the new docs/deployment.md section; `--no-deps --wait embed web` only.
5. Changelog entry per release; rollback line per release.

## 2. Branch cleanup
`git push origin --delete claude/qa-c claude/i18n-b claude/arch-267 claude/i18n-a claude/i18n-d claude/i18n-c claude/models-owner claude/embed-overlay claude/diary-tenant claude/web-hardening claude/skill-eval-harness` `claude/dav-clients` `claude/docling-verify` (both merged). Never delete ChatGPT's branches.

## 3. Approved runs (per-run approvals already given by the owner; smoke test first each time)
- **#261** approved: `docs/handoffs/2026-09-25-run-plan-261.md`. Confirm the live `DATA_DIR` mount first. Output: counts and classes only, no prompt content; comment on #261, link from roadmap.
- **#264** approved with **Gemma 12B Q4 QAT** (not Ornith): `docs/handoffs/2026-09-25-run-plan-264.md`. Pause Nextcloud Assistant and any other inference for the window; run detached outside backup/mover windows; smoke test fixture Q1 variant A alone; feature flag stays off.
- **#265**: harness merged (#323, `experiments/system-one/skills-mcp/live.cjs`, README has the commands). The live run still needs a separate approval from the owner (model, window) and must not overlap #264.

## 4. Verifications only the host can do
- **#262**: follow `docs/handoffs/2026-09-25-verify-262-docling.md` (merged in #325, on main) on the next authorised project open; record any failure as a separate bug with contents excluded.
- **#263**: the emulation rows are done (#326, docs/dav.md run 3, 45 checks); the device rows (Finder, Windows Explorer/WinSCP, iOS Files) remain, per the exact steps in run 3; disposable files only; live DAV sharing stays off.
- Spec Appendix A of docs/spec-service-boundaries.md: read-only checks that confirm the map's `[live: verify]` assumptions.
- QA scripts that failed only in the sandbox on unmodified main (Chrome channel): models-settings, mtp, mcp-status, native-model-picker, storage-accessibility, passkey-rename, onboarding. Run them locally; file issues if any fails for real.

## 5. Still open, untouched
#255 tracker; #272, #273, #275 architecture (design only); #268-#271 narrowed, awaiting work per their Decision sections.

## Rules that still apply
Deploy from main only; web-only via the guarded up.sh from the Compose folder; never touch laya/llama/embed/ocr/docling/kiwix/model-loader/diary/code-sandbox in a web release; never print .env values; synthetic fixtures only; never send prompts to the real Diary; per-run approval for any model/eval/live-data run; every bug found becomes an issue.
