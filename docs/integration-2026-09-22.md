# Development branch integration — 2026-09-22

Base: `origin/main` at `506f0f8`. The original `ui-polish-update` checkout was clean
and remains untouched; integration uses a separate worktree and
`integration/noevia-20260922`.

## Branch accounting

- `ui-polish-update` / `origin/ui-polish-update` at `7014b69`: merged, including
  settings hierarchy/navigation and project-library keyboard/card improvements.
- Local `codex/harness-hardening-claude-pi` at `c729379`: merged. Its remote at
  `4a4a8a0` is an ancestor, not an alternative to merge separately.
- `a866a39` is patch-equivalent to main's `c03ecd2`; Git retained the already-shipped
  tuning implementation and `5a88558` spacing fix without duplication.
- No other local or origin development branches existed after fetching. No branches
  were deleted or force-pushed, and no uncommitted work required moving.

Only roadmap/changelog prose conflicted. Main's current release evidence was kept,
and the harness-hardening record was added. No application conflict required a
product decision. The combined diff contains the two UI commits and harness
hardening; dependency manifests and tuning implementation are unchanged.

## Validation

- `npm test`: 1,245 passed, zero failed/skipped. Initial isolated-worktree run lacked
  server dependencies; linking the existing dependencies corrected the environment.
- `npm run typecheck`, `npm run build`, `npm run lint:design`, `git diff --check`: pass.
- Synthetic Chrome suites: settings-navigation, general-settings, projects-library,
  projects-empty, models-settings, models-autotune, appearance-system,
  mobile-approvals, tool-calls, code-mode, onboarding, mobile-surfaces,
  mcp-internal-http, tool-scope-http and diary-navigation: pass.
- Settings/projects reviewed at phone/desktop sizes, with automated 375/768/1440
  light/dark coverage, search, keyboard focus and overflow assertions. Appearance
  persistence and device theme changes pass. Approval cards retain complete
  arguments and Allow once / Decline / Allow for this chat, including mobile sizing.
- Internal MCP synthetic HTTP checks prove two-tenant isolation, spoofed identity
  rejection, and refusal/replay protection for unapproved writes.
- Real pi 0.87.0 and Claude ACP 0.79.0 against local scripted model fixtures: pass.
  Allow once writes only the disposable proof file; Decline does not. Claude's
  hostile repository hooks, skills and MCP server cannot bypass the gate.
- Impeccable detector: one pre-existing, documented false positive on the theme
  thumbnail's sidebar border; no new design defect identified in the scoped review.

No real Diary corpus or production inference was used. Physical-device testing
and authenticated personal-data workflows are outside this synthetic validation.
Deployed as `04780e6`, with sandbox `pi-0.87.0-99be0a2`. The Linux sandbox
also passed the real pi fixture without network or production mounts, and the final
web image passed 80 targeted tests. See [deployment evidence](deployment.md).
