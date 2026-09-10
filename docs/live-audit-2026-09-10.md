# Live reliability audit — 2026-09-10

Started against running release `12ba04f`, using HTTP requests from inside the
production web container, actual Lemonade/MCP servers, real Nextcloud storage,
and the authenticated public browser. Three temporary synthetic accounts separated
administrator, local diary, and connected-storage tests. No test prompt was sent
to the real diary and no real corpus was edited.

## Defects fixed

- **Legacy migration could repeat for a new administrator.** Root legacy files
  remain on disk for recovery. `claimLegacy` previously checked only whether the
  requesting administrator had a workspace, so another administrator could copy
  the original account's data/credentials and acquire a diary migration marker.
  A durable `legacy-owner.json` now restricts migration to one owner, recovering
  that identity from existing migration markers on upgrades. Synthetic regression
  tests cover a second administrator and original-owner removal. Production still
  had retained root files and one migration marker; reproduction used synthetic
  files, avoiding a copy of personal data into a test account.
- **Replacing an image could leave old model input active.** A live upload of a
  replacement above the 8 MB vision limit correctly became stored-only, but the
  previous image asset remained attached to chat. Replacement now removes that
  stale asset before installing new vision input. Regression coverage verifies
  resizing below the limit restores vision and pruning removes superseded bytes.
- **Administrator deletion failed after issuing invitations.** Live cleanup
  returned a foreign-key error because invitation/recovery rows referenced their
  creator. Deletion now revokes those tokens and deletes the user atomically,
  retaining audit history. A related regression prevents deleting the last active
  administrator merely because another disabled administrator exists.

## Exercised against production

| Area | Evidence |
| --- | --- |
| Authentication | Invite signup/replay rejection, password login/failure, secure cookies, origin/CSRF enforcement, onboarding, disable/enable, recovery/replay rejection, session invalidation, logout |
| Tenant boundaries | Project/config/history/original/source-job separation; another account cannot decide a pending approval; disabled Diary inaccessible; internal context records hidden |
| Sources | TXT, PNG, mixed native/scanned PDF, opaque DOCX and binary originals; four groups; byte-for-byte downloads; asynchronous jobs; empty/archive/traversal/>25 MB rejection; PDF page reads |
| Storage | Actual Nextcloud TXT and PNG originals read back at exact synthetic paths; category-folder refresh; local uploads retained after refresh |
| Inference/retrieval | Actual Qwen 9B vision, PDF read tool and paired SSE result; seven native vector chunks indexed and a fact beyond the direct-injection threshold retrieved; disconnect without server failure |
| MCP | 165 tools discovered across Nextcloud/Tavily; actual Nextcloud listing and writes; Decline, Allow once, Allow for this chat; next-chat approval required again; invalid decisions rejected |
| Diary | Synthetic online capture durable and invisible to another tenant; local exchange returns changed files for selected date, leaving online corpus untouched; versioned memory edits and stale-version/traversal rejection; extras off rejected; opt-in preparation calls clock tool |
| Browser | Free-chat grouped composer, Diary default-off extras/always-on capture, Projects navigation, settings/service status, theme switching, mobile/tablet/desktop layouts, Code/Scheduled preview labels |
| Runtime | All three containers running without OOM/restarts; diary/OCR ports not published; inference/diary/native retrieval healthy; disk 43% used |

## Observations and limits

- Mixed PDF extraction/OCR completed in about **1 second** inside the server.
  Image storage was immediate; image inference took **14.8 seconds**. PDF tool
  reading took **12.1 seconds**; Nextcloud model/tool round trips **25–31 seconds**;
  synthetic Diary capture **72.5 seconds**. These are individual observations,
  not load benchmarks. Network upload time is excluded from server measurements.
- Vision recognized the blue circle and triangle but called the orange triangle
  yellow. The strict color assertion failed: model accuracy remains imperfect.
  OCR totals should still be checked against originals.
- The live engine panel displayed an implausible 1,000,000 tokens/second sample
  from upstream statistics; per-exchange generation measured about 13–14.
  Treat that panel's instantaneous upstream metric cautiously.
- Some Qwen tool continuations exposed verbose internal narration through the
  existing reasoning-only answer fallback. Output quality needs follow-up.
- This is broad sampled coverage, **not exhaustive certification**. Hardware
  passkeys, S3, every provider/model/MCP tool, model downloads/removals, destructive
  sharing/calendar operations, outages, sustained concurrency, and browser login
  in a separate cookie profile were not exercised. Public browser checks reused
  the owner's session without test messages; mutation tests used synthetic
  accounts through authenticated HTTP.
- DOCX remains stored-only. Coding execution, schedules, and plugins remain
  labeled previews; this audit does not implement those roadmap features.

## Regression verification

266 web tests passed; typecheck and production build passed. Diary: 157 passed,
3 skipped (2 existing warnings). Rollout and cleanup evidence follows after final
verification.
