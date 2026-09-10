# Roadmap audit — 2026-09-10

Original audit (committed as `f0dd19e`) inspected `d726a63` on main, plus a
read-only production timezone check. That documentation-only audit made no
implementation changes or deployments; its baseline was 194 web tests and
155 diary tests (3 skipped).

Reliability batch follow-up, 2026-09-10: Workstreams 1 and 5a are now complete
locally. The updated statuses below reflect the implementation, not production.
No production access, diary prompts, or corpus changes were made. Verification:
`npm test` — 208 passing (14 new); `npm run typecheck` and `npm run build` —
passing; diary `.venv/bin/python -m pytest tests/ -q` — 155 passing, 3 skipped.
The diary suite emitted two dependency deprecation warnings. No runtime
dependencies, UI changes, or diary write-path changes were introduced.

## Status and evidence

| Item | Status | Evidence / remaining work |
| --- | --- | --- |
| UI/sidebar | Accepted, complete for now | Deployed `cd717b0`; see `ui-reference-review.md`. Do not reopen the visual redesign. |
| 1: agent deploy contract | Complete locally | Root `AGENTS.md`/`CLAUDE.md` link the brief and distinguish generic `DEPLOY.md`/`cowork.setup.json` from the existing live Unraid runbook. Wizard wording matches the implemented account checkbox and models guidance. No deployment. |
| 2 / 5b: thinking modes | Not implemented | No reasoning-effort schema, override, badge, or verified-provider fallback in web code. `index.cjs` has `enable_thinking` suppression for a helper call, not the planned user-facing feature. Main streaming and non-streaming fallback bodies must both be considered. |
| 3: wizard restructure | Partial | `SetupWizard.tsx` still uses account → provider → diary → models → prefs → passkey. Diary opt-in is an account checkbox; models remains deployment guidance. Timezone confirmation and display-name collection already exist. |
| 3.5: invite onboarding | Confirmed gap | `auth.cjs:acceptInvite` omits `onboarded`; the database default is 1. `AuthGate.tsx` shows the wizard only when it is false. Existing invitation tests check diary choice/isolation, not onboarding. Resume mode exists, but a member-safe invited flow still needs verification. |
| 3.6: markOnboarded | Audit/test gap, not proven data loss | Its conflict branch preserves diary choice; the insert branch uses 0. Do not claim an existing user's enabled diary is overwritten without reproducing it. Establish missing-row semantics and regression coverage first. |
| 4a: diary scaffolding | Not implemented as specified | No first-entry scaffold for Entries, AI Memory, and Raw Sources in diary agent code. Existing storage lazily creates paths. |
| 4b: diary zero state | Not implemented as specified | `DiaryView.tsx` still has the shared landing; month discovery adds the current month even when there are no entries. No dedicated first-entry composer / three-panel populated split. |
| 4c: landing-to-day navigation | Confirmed gap | `DiaryView.tsx:submit` computes entryDay but stores the conversation under existing scope and does not set month/day before streaming. Browser-local and server-backed paths both need tests. |
| 4d: diary visual/refactor work | Partial / defer cosmetics | Broad visual updates shipped, but the specified component split and new panel behavior have not. UI is now accepted; implement necessary behavior without restarting cosmetic work. |
| 5a: duplicate tool-call guard | Complete locally | `tool-exchange.cjs` is instantiated inside `handleChat`; canonical arguments, exchange-only result reuse, read invalidation on attempted writes, and handler-level mocked streaming/fallback regression coverage. See Workstream 5a for denial/failure/validation semantics. |
| 5: deferred tool disclosure; 5c: planner/executor | Research only | Static toolbox cap/budget resolution and message-level Fast/Smart routing remain. No dynamic find_tools or phase-based planner/executor implementation found. |
| 5d: offline Wikipedia | Not implemented; optional | No Wikipedia toolbox found. Requires a selected available service; it is not a prerequisite for OCR, skills, or correctness fixes. |
| 5e: harness framing | Partial | Already explained in `docs/agent-brief.md`; root agent entry points now link the brief. |
| 6a: timezone | Complete, including production | Both Compose definitions, `.env.example`, wizard timezone helper, and timezone regression tests exist. Live read-only check: TZ=America/New_York, EDT -0400. The old statement that the live copy remains unapplied is stale. |
| 6b: direct diary context | Partial; original claim too broad | `agent/context.py` directly reads the current day, standing sections, and memory files. Older entries still use retrieval; a bounded older-entry fallback is the remaining design question. The browser-local path also supplies local reference material. |
| 6c / 6d: memory ownership/privacy | Architectural constraints | Disk-backed diary memory already feeds context. Keep the single-store and no-cross-profile diary-content boundaries; these are not standalone missing UI features. |
| 7a: Unraid state default | Original example hazard addressed | `deploy/examples/unraid-compose-manager.yml` requires COWORK_STATE_DIR explicitly. Generic `compose.yaml` and the manifest still use ./state. No named-volume default or explicit /boot-path rejection exists; those are separate remaining decisions. |
| 7b / 7c: local storage UX | Partial | Storage clients and browser-local folder access exist, but they do not expose server-held files to other devices. The two-choice appliance setup flow is absent. |
| 7d / 7e / 7h / 7i: served storage | Not implemented | No noevia WebDAV server or noevia-issued app-password lifecycle found. Outbound PROPFIND/MKCOL and saved Nextcloud credentials are client functions, not these features. No managed corpus volume default / Off-LAN-Public sharing wizard. |
| 7f / 7g: endpoint and proxy notes | Design/reference material | These describe requirements and prior experiments, not shipped endpoint features. The roadmap repeats 7g/7h sections; reconcile before implementing storage. |
| 8: PDFs/OCR/images | Existing foundation, investigation next | PDF text extraction and image capability/routing exist. Scanned PDFs explicitly fail without OCR. No OCR implementation added. |
| 9: skills | Planning only | No selected skills format, execution model, or lifecycle. Coordinate with existing instructions/toolboxes rather than adding a parallel framework. |

## Corrected priority order

1. **Small reliability batch: complete locally.** Workstream 1 entry-point/runbook
   links and Workstream 5a duplicate-call protection are implemented. The existing
   approval gate remains; no deployment or diary corpus changes were made.
2. **Onboarding correctness:** Workstream 3.5 and regression coverage for 3.6.
   Invited users should get a member-safe setup path; preserve diary choice.
   Then remove the dead-end models guidance step and improve diary opt-in order.
   Do not make this depend on building a WebDAV server.
3. **Diary navigation:** Workstream 4c, using mocked/synthetic exchanges only.
   Preserve the server write path and browser timestamps. Scaffolding/zero state
   (4a/4b) is a separate follow-up; reconcile its data model before changing it.
4. **PDF/OCR/image audit and spec:** Workstream 8 is the user's next feature focus
   after the small correctness fixes, not behind every historical research item.
5. **Thinking modes:** Workstream 2 / 5b remains a real unimplemented feature.
   Define a bounded output budget, capability verification, and fallback behavior
   before implementing; do not equate a prompt hint with actual model support.
6. **Storage architecture:** Workstream 7 needs a scoped spec, with app passwords
   before exposing DAV. Existing working storage need not be replaced to do OCR.
7. **Skills and tool research:** Workstream 9 and the relevant parts of 5. Defer
   optional Wikipedia and planner/executor experiments until there is a concrete need.

These priorities distinguish correctness work from feature research rather than
blindly retaining the old numerical sequence. The next coding task starts with
item 2 (onboarding correctness), not the entire remaining roadmap.

## Design cautions discovered during the audit

- Do not expose the admin-only external-source mount listing to members merely
  because Workstream 4 proposes it. Tenant ownership and filtering must be defined
  first; the current endpoints explicitly restrict server import folders.
- The old insights-badge proposal must be reconciled with the removal of diary
  insights from the product; do not resurrect it just to satisfy old checklist text.
- Scaffold names must be reconciled with the memory paths actually read today.
- A duplicate-call guard must normalize JSON object key order, preserve array
  order, avoid re-executing writes or re-requesting approval for the same call,
  and preserve tool-result/SSE pairing. Decide/document how denied or failed calls
  behave. Cache scope must be one exchange, never another turn or tenant.
