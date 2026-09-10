# Paste-ready next-task prompt

You are working on noevia, a self-hosted workspace for project-aware chat and
private, durable diary capture. Continue the roadmap with one bounded batch:
**onboarding correctness, Workstreams 3.5 and 3.6**. Do the work, not just a plan.

Repository: https://github.com/sbstndalton/noevia
Work from main. Inspect status and recent history first; preserve unrelated edits.
At this handoff the last application deployed was `66af1ad`; `efd1c3c` records
its verification. Later documentation commits reconcile the roadmap. Verify
current history rather than checking out these older commits.

Read first, in order:
1. AGENTS.md and docs/agent-brief.md, including its later follow-ups.
2. docs/roadmap-audit.md — current summary/table/priorities supersede historical
   stage reports saying completed work was only local.
3. docs/roadmap.md — Workstream 3, with 4c as the subsequent priority.
4. docs/live-audit-2026-09-10.md — actual coverage, exclusions and remaining issues.
5. docs/deployment.md — actual live Unraid procedure. DEPLOY.md and
   cowork.setup.json are generic fresh-install instructions, not the live runbook.

Already implemented and deployed; preserve these:
- Agent deployment entry points and exchange-scoped duplicate-tool-call protection.
- PDF originals/native pages, private Poppler/Tesseract OCR, async processing
  status, image projector support, unified uploads with progress and categorized
  Nextcloud folders. Non-archive originals up to 25 MB; images above the 8 MB
  model-input limit and unsupported formats such as DOCX remain stored-only.
- Shared + menus and model controls in the composer across project landing,
  project/free chats, and Diary home/day. Do not restore the top-bar model picker.
- Diary's required retrieval/capture companion remains active. Optional attachments
  and MCP tools are OFF by default and reset OFF on reload. Their settings/files
  persist separately; extras cannot replace the raw diary message or write path.
  The extras model selector changes preparation only, not the companion model.
- Live-audit fixes prevent legacy data being copied into new administrators,
  obsolete image assets surviving replacement, and issued tokens blocking account
  deletion. Preserve tenant isolation and last-active-administrator protection.

Implement this batch:
- Reproduce invite onboarding: auth.cjs acceptInvite currently omits onboarded,
  whose database default is 1; AuthGate opens resumed setup only when false.
  New invited users need a resumable, member-safe onboarding path. Do not merely
  route members through administrator-only setup or global model management.
- Preserve explicitly enabled AND disabled diary choices across invitation,
  setup, reload/resume, and completion. Existing onboarded users must not be
  reset into the wizard by a migration.
- Inspect markOnboarded: its conflict branch currently preserves diary choice;
  its missing-row insert uses diary_enabled=0. This is an audit/test gap, not
  proven overwriting of existing users. Define missing-row semantics and test
  them before changing behavior.
- Keep setup truthful and navigable, with clear skip/resume behavior. Remove or
  clarify dead-end model guidance where required by this flow. Do not expand this
  into a storage rewrite or full onboarding redesign.
- Add meaningful regression coverage for fresh admin setup, invited members,
  diary yes/no, missing feature rows, reload/resume, completion, role boundaries,
  and account isolation. Use synthetic fixtures and mocked tools.

Constraints:
- Never send test prompts to the real diary or modify its corpus. Synthetic
  isolated tenants/fixtures only, including any live integration checks.
- Preserve all three write approvals: Decline, Allow once, Allow for this chat.
  No global bypass. Preserve cancellation, tool-result pairing, and scope.
- Cowork-prefixed identifiers are intentional. Do not rename them.
- No new runtime dependencies/frameworks; no diary write-path changes.
- UI/sidebar is accepted. Keep existing shared composer behavior and previews.
- Do not implement the entire roadmap. Diary navigation (4c) is the next batch;
  scaffolding/zero state, thinking controls, DOCX readers, storage and skills need
  their own scope. Thinking options belong beside the composer model selector
  eventually, but must reflect verified model capabilities, not cosmetic toggles.

Verify:
    cd apps/web && npm test && npm run typecheck && npm run build
    cd services/diary && .venv/bin/python -m pytest tests/ -q

Last verified baseline: 266 web tests; 157 diary tests passing, 3 skipped,
with two existing dependency warnings. Run fresh checks after code changes.
Dependencies/build output use external symlinks to avoid Nextcloud eviction;
read the brief before replacing them. Manually test affected onboarding flows,
member/admin boundaries, reload/resume, keyboard access, responsive widths and
both themes. Passing automated tests alone is insufficient.

The user authorized Git push and production rollout after successful verification.
Follow the live runbook, build candidates before switching the live release,
retain rollback configuration/releases, and perform scoped health/UI checks.
Do not deploy failed checks or touch real diary data. Restore temporary network
state and remove only synthetic test artifacts you created. Never print secrets.
Actual Lemonade and MCP integration testing is authorized when relevant, using
synthetic content; it does not require exercising every available tool.

Update roadmap/audit and deployment records to match what actually shipped.
Use the repository's root-cause-and-motivation commit style. Report changes,
fresh verification, deployed revision (or concrete blocker), remaining concerns,
and the next bounded batch, then stop.

Known unresolved limits from the live audit: color recognition errors, slow
inference/tool round trips, implausible throughput telemetry, and reasoning-only
fallback narration reaching final answers. DOCX is not yet readable. The prior
live audit was broad, not exhaustive; do not claim these issues are resolved by
onboarding work or that every model/provider/MCP tool has been tested.
