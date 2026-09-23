# Instruction skill conflict recovery plan

Issue: [#53](https://github.com/sbstndalton/noevia/issues/53)

Status: plan only. No application fix is in this commit.

When an instruction file changes after Sources loaded, the enable PUT correctly returns 409, but the component retains its old body/hash. Fetch the current instruction-skill list after this specific conflict and display its latest content, status, and hash beside a clear message that the version changed. Keep the newly fetched version disabled until the user inspects it and explicitly clicks **Enable this version** again. Do not retry the PUT automatically or weaken the server hash check.

Implementation scope: `apps/web/src/components/InstructionSkills.tsx` and a focused synthetic browser/API QA script under `apps/web/qa/`. Reuse the existing GET endpoint. Update `onFiles` with the refreshed file names. Keep other PUT and GET errors visible; if conflict refresh fails, say that the current version could not be loaded. Ignore late conflict-refresh results after the component switches projects or unmounts. Do not change project lifecycle, backend selection semantics, external skill installation, or prompt/tool loading.

Acceptance: the first click with a stale hash yields 409 and no saved enable action; the open panel then shows the new body and review status. A second, explicit click sends the new hash and enables only that reviewed version. The synthetic QA must include a second client changing the same project file after the first list, assert the refreshed content and disabled server state, then assert the explicit retry succeeds. It should also confirm that an ordinary non-409 failure remains visible without an automatic retry.

Verification at the implementation head: run `npm test`, `npm run typecheck`, `npm run build`, and `npm run lint:design` from `apps/web`, plus the focused synthetic Playwright browser regression. Use external shared dependencies and an isolated build directory. No private Diary files, live model, production instance, or external skill download.
