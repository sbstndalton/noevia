# Continuation checkpoint — 2026-09-10, user disconnecting

User resumed on the home network. LAN SSH to 10.69.0.130 works; Tailscale SSH
timed out. Full roadmap work is active again.
User chose **reusable instructions using existing approved tools** for skills;
produce that scoped proposal, not executable packages or a new framework.

## Git and production

- main includes tested/pushed DOCX `e18f1de`, app passwords `2525de5`, and limited
  DAV `b45390a`. Production is **2525de5** (all three services); DAV is not cut over.
- `b45390a` candidate images built successfully on root@100.70.173.74 with **263
  serial isolated Linux server tests and eight worker tests passing**. Build log
  `/tmp/noevia-build-b45390a.log` has CANDIDATE_BUILD_AND_TESTS_PASSED. The prepared
  `/tmp/noevia-switch-b45390a.sh` expects current=2525de5 and has rollback. It has
  NOT been executed. Do not assume otherwise; verify current before resuming.
- No DAV port/configuration or production device credentials enabled. Default
  COWORK_DAV_PORT=0. Existing live Compose Manager files are separate from repo
  examples; use docs/deployment.md. No real diary prompts or corpus tests used.
- All older release directories and .bak.before-* config backups retained.

## Saved wizard work in this checkpoint commit

SetupWizard adds Welcome → explicit Diary/chat choice before administrator account
creation, preserving the chosen value in completeSetup. Account fields survive
Change choice. Existing authenticated resume/member flow stays unchanged. Added
StorageChoice with two explicit options (server-held vs existing external service),
no preselection, skip preserves storage, switching does not migrate files. Hosted
save offers the bounded sharing panel; external uses StoragePicker onlineOnly.
Administrator preferences include existing immediately saved thinking default;
members never see global control. Theme/auto/timezone behavior remains unchanged.

Verification after these changes: **310 web tests**, typecheck and build pass.
Updated real-server onboarding browser script passes fresh Diary on/off, invited
member/admin, failed saves, toggle/reload, Back, sign-out/resume, completion, role
isolation, and 375/768/1440 light/dark with keyboard. It currently exercises storage
SKIP; add focused hosted/external choice/save/failure/preservation checks before
calling the new storage flow fully verified or deploying this checkpoint. The
Diary suite last passed immediately before wizard edits (171 passed, 3 skipped,
two existing warnings); rerun it with final batch. Screenshots are in
/tmp/noevia-wizard-screens. No wizard production image built yet.

## Recent implemented limits

DOCX main-body/table extraction is partial and labelled, preserves original bytes,
private Python worker, no dependencies. Unsupported/malformed replacements clear
stale readable/indexed text. See roadmap audit for limits; all eight real worker
checks passed in image.

App passwords: shown-once 256-bit random secrets, Argon2id hashes, tenant metadata,
LAN/public immutable scope, 20-active cap, mint throttle, transactional rechecks,
individual revoke, no account/chat authentication. AppPasswords.tsx is in Profile.

DAV b45390a: optional separate listener in web, own app-password Basic auth,
exact authority and HTTPS proxy-secret boundary; per-user off/lan/public settings,
local server-held Diary only. OPTIONS/HEAD/GET/PROPFIND and conditional PUT relay
through existing tenant companion API. No direct volume access. **Limited profile,
not full DAV or file-manager compatibility**: no MKCOL/DELETE/MOVE/COPY/LOCK etc,
no advertised DAV class header. See docs/dav.md and spec-storage-appliance.md.
Synthetic real HTTP and actual app/listener browser QA passed; production stays off.

## Resume priorities

1. Verify checkpoint git/push and production current. Finish focused wizard QA,
   docs/changelog and deploy as a tested bounded batch. A later candidate can
   include b45390a; do not cut over both unnecessarily. Update switch baseline.
2. Storage: full DAV namespace/client compatibility and managed fresh-install
   volume defaults/Unraid /boot guard remain open. Preserve existing explicit bind
   paths; no silent migration to empty volumes. Match docs/spec-storage-appliance.
3. Wizard Insights badge is only unused auth schema/methods today: no working UI
   indicator discovered. Do not expose a setting that does nothing. Other remaining
   wizard/model-manager/display-name details require focused review.
4. Skills proposal: instructions using approved tools, user-selected scope. Existing
   skillsIndexFor/parseSkillFrontmatter in index.cjs already index project files;
   read_project_file loads bodies. Index currently omits actual filename when name
   differs; broad knowledge injection also includes file text. Reconcile rather
   than build a parallel system. Planning deliverable first per roadmap Workstream9.
5. Workstream5 research: deferred tool disclosure and planner/executor need scoped
   evidence/specs; offline Wikipedia needs a selected available service. Thinking
   v1 high=8192 explicit hint budget, not uncapped or guaranteed bigger than unknown
   defaults. Model accuracy/performance limitations remain open.

## Local setup and QA

Repo is noevia-application inside the AI frontend thing project. npm scripts under
apps/web. node_modules symlink to ~/.noevia-deps; dist symlink /tmp/noevia-qa-dist.
Keep both. PLAYWRIGHT_MODULE=/Users/sebastiandalton/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright
Scripts: qa/onboarding.cjs, qa/diary-navigation.cjs, qa/diary-landing.cjs,
qa/reasoning.cjs, qa/docx.cjs, qa/app-passwords.cjs, qa/dav.cjs.
All actual-server scripts create disposable state and clean themselves up.
Older synthetic fixture servers may remain on localhost31240 and31244; inspect
exact listener PIDs before stopping, never broad pkill. CUA tabs 5/6 use31240,
7/8 use31244; public read-only tab4 uses cowork.daserver.work. Tailscale was started
for rollouts after initially stopped; restore initial stopped state at end if safe.

Read AGENTS.md and docs/agent-brief.md before continuing. Preserve cowork-prefixed
compatibility identifiers, accepted UI/shared composers, Diary extras OFF on
reload, companion pipeline and all three tool-write approval actions. Test and
push each implemented roadmap item; production rollout previously authorized.
No subagents unless explicitly requested. No real diary/corpus testing.


Resume verification: storage hosted/external loading, skip preservation, failure
and hosted-save browser checks now pass. StoragePicker initial-load race fixed.
310 web tests, typecheck/build and 171 Diary tests (3 skipped) pass. This supersedes
the earlier focused-QA gap. Next candidate includes wizard and b45390a together,
with production baseline still 2525de5. See latest audit for rollout status.


Latest resume state: production is now 9e2bfbb across all services, healthy on LAN
SSH 10.69.0.130, sharing disabled. Skills proposal and tool research plan are pushed.
Current next batch fixes exact filenames/bounds in existing skill metadata; see
latest audit for its test/rollout record. Earlier production baseline notes above
are historical. Temporary fixture servers from the previous session were stopped.
