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
