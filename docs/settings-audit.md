# Settings audit — 2026-09-13 continuation

Inspected SettingsShell, SettingsView, API client, shared controls and actual
server routes at handoff `47c04fb`. This audit distinguishes implemented behavior
from this increment's verification. The local preview is synthetic, never a
production integration test.

| Category | Implemented behavior and persistence | Gaps / next increment |
| --- | --- | --- |
| General | Five palettes, separate light/dark choices, authenticated profile persistence, immediate browser cache, loading/saving/error/retry feedback. | Local preview uses synthetic process memory; real SQLite persistence and account isolation verified in tests. Production deployment pending. |
| Profile & security | Name PATCH and Diary preference PUT use authenticated account storage. Passkeys and sessions use real auth routes; app passwords are server-held hashes with shown-once secrets. Added retryable profile loading, validated responses, pending action states, draft preservation, save success and failures. Failed passkey DELETE now checks HTTP status. | Actual passkey ceremony/session revocation and app-password lifecycle were not exercised this increment. App-password initial loading/retry can be improved. Name in shell refreshes on app reload. |
| Diary & storage | Account-level enablement, saved storage connection, connection test, optional DAV sharing. Failed enable/disable now retains previous value and explains retry; changing preference does not delete corpus files. | StoragePicker still lacks action serialization and a direct load retry. Sharing load retry/success feedback needs refinement. Browser-local recovery remains default-off and separate. Never change storage merely for a visual test. |
| Your connections | Existing provider test/create/delete routes; server saves user/shared connections, masks keys and independently checks authorization. Added loading, valid empty state, retryable errors, response validation and removal busy state. | End-to-end provider connection/removal needs isolated real-server browser QA; no real provider contacted here. Review member presentation of shared-provider option. |
| Usage & activity | Server aggregates reported tokens; rates persist in settings, administrator aggregate route is protected. Empty and malformed usage have distinct states. | Full candidate pricing/aggregate browser QA remains a release gate; synthetic preview shows zero usage and no editable rates. |
| Planned features | Disabled previews only. Labels now distinguish account-wide instructions/memory and a future skill/connector catalogue from existing project instructions/skills and connections. | No new global instructions, notifications, export/retention, plugin execution or coding engine was invented. |
| Users | Admin routes implement invitation/recovery, enable/disable and confirmed deletion; load retry and role checks exist. | Mutation busy/error states and clipboard failure recovery remain unfinished. No accounts/invitations/recovery links changed in this increment. |
| Models & routing | Real model manager and project selectors; global reasoning default persists via admin-only PUT. | Reasoning-load failure currently hides the control; needs visible retry. Model list needs explicit empty/loading distinction. No production model setting changed. |
| Service status | Real health and MCP catalogue status; manual reload and unavailable/degraded explanations exist. | Synthetic availability labels do not verify live services. Broader live candidate QA pending. |

## Increment 1 — implemented locally

The accepted Study 03 material is now in the real application's final stylesheet,
with its decorative tokens in tokens.css and bounded reflection in public/glass.js.
Settings navigation/header, selection, forms and controls now share the optical
edges. Chat/project/Diary composers, project cards, context rails, coding preview,
menus and modal/setup surfaces inherit the same material without moving layout.
Reading surfaces stay opaque. Sidebar ancestors remain unfiltered; existing
reduced motion/transparency, high-contrast and no-blur fallbacks remain.

Sources browser review found that the old fixture returned `{}` for instruction
skills. It now returns an explicit empty list; the real component rejects a missing
list before committing state, preventing a render crash on malformed responses.

The settings fixture explicitly implements name/Diary preference updates in process
memory, delayed loads, valid empty lists and one-shot failures through `/__qa`.
It rejects unsupported settings mutations with 501. It is not durable persistence:
restarting the preview resets synthetic values. No stored secret is used.

## Verification record

- 376 web tests, typecheck and build passed before final visual refinements; final
  rerun recorded in roadmap-audit.md.
- Real authenticated request-handler test checks profile name and Diary preference
  round-trips through actual server storage, plus an unauthenticated PATCH refusal.
  Existing auth/provider tests also pass. Only disposable local test state used.
- Browser: name save pending/success, reload persistence in fixture, failed PATCH
  retaining the entered draft, and successful retry.
- All nine Settings categories visited at measured 375/768/1440 widths, light/dark;
  no dialog overflow or panel alerts in the normal fixture. General additionally
  switches all three palettes at each width/mode. These are DOM/layout checks;
  representative screenshots were reviewed separately, not 54 screenshot reviews.
- Sources, Projects and Diary were visually inspected at desktop width. Additional
  navigation/menu/focus checks are recorded with final roadmap verification.

## Deployment boundary

This increment is not deployed. Production remains last verified at `8fa1112`;
existing independent candidate `8bc4339` is unchanged. Finish its isolated browser
QA and recheck live state before any release; use docs/deployment.md and the
mandatory preflight wrapper. The broader roadmap remains open: SMB client/cutover,
off-site destination/budget, managed-path rename/delete policy and client bridge
workflow retain their existing decisions and safety constraints.

## Models follow-up — 2026-09-14 (local)

Switch/Manage now distinguish model loading, empty lists and retryable failure;
model responses are validated before use. The model window adds Guidance with
reported-capability filtering, an explicit memory plan and read-only inference
hardware information. Download variants share the plan. This does not complete
reasoning-setting load retry, runtime model qualification or automatic routing.
See spec-model-guidance.md and the latest roadmap verification record. No deployment.
