# Noevia run ledger, 2026-09-25 (cloud session; append to Claude handoff 2026-09-24/OVERNIGHT-RUN.md on the Mac)

Environment: cloud container, no ssh to DaServer, no gh CLI (GitHub MCP used), Mac ledger folder absent.
Start state: origin/main a19ff5d, 0 open PRs, open issues 255, 261-265, 267-273, 275 (all deferred earlier). Live web 5a47942 per brief (not re-verified here).

## Triage
- New issues since a19ff5d: none. #283 closed by #284.
- 261/262/264/265: model/eval/live-data runs, need per-run approval: deferred (comments exist).
- 263: needs user devices: deferred. 267-273, 275: architecture/plan: deferred (no doc-only plan PRs).
- Bugs filed this run (Haiku): #285 untranslated screens after #281; #286 first-load bundle 533 kB.

## Work in flight
- claude/i18n-a (Sonnet): account menu, Projects, Diary i18n. Closes #285.
- claude/i18n-b (Opus): Settings catalogue chunk + remaining Settings screens. Closes #286.
- claude/qa-c (Sonnet): live Chromium browser-service QA (#280 follow-up), dark-mode #282 banner shots.

## MERGE: PR #287 qa: live browser-service Chromium run + dark-mode #282 banner check
- Head aafc599 -> squash d1a6719 on main. CI 7/7 green. qa-only (no src/server change), no deploy needed for it.
- Review findings (Fable): async check() never asserted, no-op overflow check, missing header selector; fixed in aafc599. 375 px "clipped" banner = scroll region (max-height 40vh, overflow auto), verified by a new check; not a bug.
- Live browser-service run: 22/22 through real routes/service/jobs + real Chromium; gaps: real egress proxy (direct:true), 5/10-min timeouts (fake-clock unit coverage).
- LEFTOVER: remote branch claude/qa-c not deleted, the session's egress proxy returns 403 on branch deletes. Mac: `git push origin --delete claude/qa-c`.

## MERGE: PR #288 i18n: Settings catalogue chunk + remaining Settings screens (Closes #286, part of #285)
- Head d161f41 -> squash a6663cc on main. CI 7/7 green. #286 CLOSED.
- First-load index 532.84 kB -> 469.71 kB (no warning); Settings strings now segments src/i18n/settings/<locale>.ts; Customise (PluginsView) now lazy.
- 364 keys x 8 locales: Models summary, Connectors, Data, Memory, Usage, Security, Users, Providers. Opus reviewer: no blockers; Fable findings fixed (Connectors heading de/nl, sidebar badge/placeholder clipping CSS, loaders guard, fr group label).
- Gaps: ModelsSettings (model manager chunk), Diary & storage, Service status, rest of Customise still English. qa passkey-rename/onboarding/models-settings/mcp-status fail identically on main in this sandbox (Chrome channel), unverified on Mac.
- NEEDS DEPLOY (web, src changed): a6663cc. LEFTOVER: remote branch claude/i18n-b delete (403 here).

## User decisions (this run)
- No-doc-PR rule lifted for #267. Opus writing docs/spec-service-boundaries.md (map + contracts + recommendations for #268-#271 + DaServer verification appendix), Closes #267, branch claude/arch-267.
- "Merge #289 when ready" (i18n-a restructured onto #288 segments).

## Issues filed from the #267 map (Haiku, code-verified by Opus reviewer)
- #291 Diary trusts X-Cowork-User-ID with shared/empty token (bug, security; medium-high, internal network only)
- #292 decrypted remote storage credential in X-Cowork-Storage (security)
- #294 UI_AUTH_TOKEN falls back to DIARY_AUTH_TOKEN (security; admin bearer if LEGACY_AUTH_COMPAT=true)
- #295 models.ini two writers (bug)
- #296 code egress proxy binds 0.0.0.0 (security, low)
- #297 no unauthenticated readiness endpoint (enhancement)
- #298 embed service only in live override (bug)
- #293 remaining English screens (final i18n batch, bug)
## PR #290 (docs: spec-service-boundaries, Closes #267): reviewed (11 corrections applied, head dcb724d), merger dispatched.

## MERGE: PR #290 docs: versioned service boundaries and migration contracts (Closes #267)
- Head dcb724d -> squash 1217498 on main. CI 7/7 green. Docs-only (spec + two link lines): no deploy needed.
- Verdicts: web process is the core (in-process: orchestration, approvals, auth, secrets, MCP wiring, storage client); existing sidecars stay; browser executor must be sandboxed before enabling; Diary contract weakest (M2 tenant assertion); models.ini needs one owner (M3, gated on System-One).
- Recommendations: #268 narrow (API contract + /api/ready), #269 narrow then defer, #270 defer, #271 adopt comparison but M2 first.
- LEFTOVER: remote branch claude/arch-267 delete (403 here). Appendix A: read-only DaServer checks for the user to run.

## MERGE: PR #289 i18n: account menu, Projects, Diary (Closes #285)
- Head 94d0d54 -> squash 779634f on main. CI 7/7 green. #285 CLOSED.
- 'projects' and 'diary' catalogue segments; eager ProjectView/EditProjectModal/ProjectIdentity/DiaryModal keys stay in base; first-load index 482.93 kB, no warning. DiaryStorageStatus translated.
- Review rounds: German du register (was Sie), search-summary count regression, proper plural pairs, first-load-key source-scan test (caught diary.modal.closeDialog in wrong segment).
- NEEDS DEPLOY (web, src changed): 779634f (supersedes a6663cc). LEFTOVER: remote branch claude/i18n-a delete (403 here).

## MERGE: PR #299 i18n: Customise segment, chat footer, Thinking control, view loading, project Inspector (Closes #293)
- Head 18acff1 -> squash be18b92 on main. CI 7/7 green. #293 CLOSED.
- 'customise' segment; admin MCP key/OAuth forms translated; StatsBar/ReasoningControl/lazy-views/Inspector base keys; first-load 487.96 kB. Dead non-global select branch in ReasoningControl removed (verified unreachable).
- NEEDS DEPLOY (web): be18b92. LEFTOVER: remote branch claude/i18n-d delete (403 here).
- PR #300 (models segment, Part of #293) still open: engineer merging main + review fixes.

## MERGE: PR #300 i18n: model manager segment, Diary & storage, Service status (Part of #293)
- Head 67935dc -> squash 8454694 on main. CI 7/7 green. 'models' segment (821 keys x 8), StoragePicker/DiarySharing/ModelPopup base keys, locale number formatting, delete-cleanup error key.
- First-load 493.56 kB (6.4 kB headroom). NEEDS DEPLOY (web): 8454694 = latest main.

## RUN COMPLETE (cloud session)
Merged: d1a6719 (#287), a6663cc (#288), 1217498 (#290), 779634f (#289), be18b92 (#299), 8454694 (#300).
Closed: #285 #286 #267 #293. Filed open: #291 #292 #294 #295 #296 #297 #298. Deferred unchanged: #255 #261-#265 #268-#273 #275.
Mac to do: deploy web-only from 8454694 per docs/deployment.md; delete remote branches claude/qa-c claude/i18n-b claude/arch-267 claude/i18n-a claude/i18n-d claude/i18n-c; append this file to Claude handoff 2026-09-24/OVERNIGHT-RUN.md.
Rollback of last live release (5a47942 -> 9a8f29e) unchanged from brief.

## Second phase (user decisions 2026-09-25)
- Live per changelog: web 2037ffd (Mac deployed 8454694 -> ... -> 2037ffd). main 25a2419 docs-only on top. Nothing undeployed.
- User: code ALL seven boundary findings (#291 #292 #294 #295 #296 #297 #298); accept spec recommendations for #268-#271 (Haiku edits issues); plan eval runs #261 #264 #265 for approval; user deletes claude/* branches on the Mac.
- Branches: claude/diary-tenant (Opus, #291 #292), claude/web-hardening (Sonnet, #294 #296 #297), claude/models-owner (Opus, #295), claude/embed-overlay (Sonnet, #298).

## Run approvals (user, 2026-09-25)
- #261: APPROVED as planned (run from the Mac per docs/handoffs/2026-09-25-run-plan-261.md; confirm live DATA_DIR first).
- #264: APPROVED with model Gemma 12B Q4 QAT (not Ornith 9B); Nextcloud Assistant paused; smoke test Q1/A first; flag stays off.
- #265: build the live-model harness first (Opus PR, branch claude/skill-eval-harness); run approval later, after #264 for the model slot.
- Issues #268-#271 narrowed/retitled by Haiku per accepted spec recommendations.
## PRs open for review: #319 models-owner (#295), #320 embed-overlay (#298), #321 diary-tenant (#291 #292), #322 web-hardening (#294 #296 #297). Container restarted once; worktrees survived.

## MERGE: PR #320 Compose: embed service overlay (Closes #298)
- Head 63f4e3e -> squash f5a4392 on main. CI 8/8 green. Review fixes: image disclosed as the same server-vulkan digest as llama [live: verify], curl healthcheck, depends_on service_started, strict structural test, CI filters cover compose.*.yaml.
- DEPLOY NOTE (Mac): reconcile the three live compose copies per docs/deployment.md new section; confirm every [live: verify] field against the box; apply with --no-deps --wait embed web only; no sidecar restarts during a web release.

## MERGE: PR #319 Models: model-loader single writer of models.ini (M3) (Closes #295)
- Head fef2f61 -> squash d738f8e on main. CI 8/8 green (model-manager suite 76 passed). Sidecar WRITE_LOCK, immutable models.ini.noevia-backup-<rev>, dir fsync, PUT /api/v1/models-ini CAS endpoint; web MODELS_INI_WRITER flag default `web` (no behaviour change until flipped).
- DEPLOY NOTE (Mac): (1) build+release a model-loader image from >= d738f8e (has the endpoint); (2) set MODELS_INI_WRITER=model-loader in .env and recreate web; verify a preset save + calibration; (3) follow-up PR flips web's /llamacpp-config mount to :ro. Rollback: flag back to web.

## MERGE: PR #321 Diary: per-request tenant assertion + scoped storage credentials (M2) (Closes #291 #292)
- Head 5387344 -> squash e2be0b5 on main. CI 8/8 green (diary pytest 411). v2 HMAC assertion (tenant, ts, nonce, method, encoded path, sha256(query), sha256(JSON body) or body=stream), nonce cache with 503 on exhaustion, open mode needs DIARY_ALLOW_OPEN=1, header-less legacy fallback refused when key set, storage secret sent only on 428/backup with secretRef.
- DEPLOY NOTE (Mac), ORDER MATTERS: (1) add DIARY_TENANT_KEY (random 32+ bytes) to the Compose Manager env for BOTH diary and web (deploy/preflight/web-env-keys.txt now lists it); (2) release the diary sidecar image from >= e2be0b5 with the key set (sidecar accepts unsigned requests until web sends them); (3) web-only release from main with the key set; (4) verify a diary read/write and the 428 retry in logs. Never roll the diary image back while web has the key. Direct legacy clients using DIARY_LEGACY_USER_ID stop working once the key is set.

## MERGE: PR #322 Web: independent auth tokens, narrower egress bind, /api/ready (Closes #294 #296 #297)
- Head 8832ee0 -> squash 7c2593c on main. CI 8/8 green. UI_AUTH_TOKEN no longer falls back to DIARY_AUTH_TOKEN (auth-tokens.cjs, independent warnings); CODE_EGRESS_BIND defaults to web's `egress` alias on the code network or loopback (logged: egress.listening / bind_fallback_loopback / bind_failed); GET /api/ready unauthenticated {ready,version}.
- DEPLOY NOTE (Mac): web-only. Before release confirm UI_AUTH_TOKEN is set explicitly in the live .env if LEGACY_AUTH_COMPAT is true (it no longer inherits DIARY_AUTH_TOKEN). After release: `docker logs cowork-web-1 | grep egress` shows egress.listening on the code-network address; curl /api/ready returns 200.

## MERGE: PR #323 Skill selection: live-model evaluation harness, no run (Part of #265)
- Head 5f4ae0d -> squash 66794f7 on main. CI 8/8 green. experiments/system-one/skills-mcp/live.cjs + fixtures + tests; explicit endpoint only; no Skill script execution; run needs separate approval (after #264 for the model slot).

## PHASE TWO COMPLETE. main = 66794f7. Live = 2037ffd (per changelog). Nothing deployed from this session.
Merged this phase: f5a4392 (#320), d738f8e (#319), e2be0b5 (#321), 7c2593c (#322), 66794f7 (#323). Closed: #291 #292 #294 #295 #296 #297 #298.
Mac deploy sequence: (1) web-only release from main (carries #322, #320 docs, #319 web side with flag default web, #321 web side inert until DIARY_TENANT_KEY set); (2) M2: add DIARY_TENANT_KEY to diary+web env, release diary sidecar image, verify, then web release again with key; (3) M3: release model-loader image, flip MODELS_INI_WRITER=model-loader, verify preset save; (4) reconcile the three compose copies for the embed overlay ([live: verify] fields).
Remote branches to delete on the Mac: claude/qa-c i18n-b arch-267 i18n-a i18n-d i18n-c models-owner embed-overlay diary-tenant web-hardening skill-eval-harness.
Run approvals: #261 approved; #264 approved with Gemma 12B Q4 QAT; #265 harness merged, live run approval pending.
