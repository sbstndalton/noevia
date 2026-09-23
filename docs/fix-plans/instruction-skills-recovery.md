# Instruction skill conflict recovery plan

Issue: [#53](https://github.com/sbstndalton/noevia/issues/53)

Status: implemented in this branch; final-head verification and independent review are tracked through the cleanup routing work item.

When an instruction file changes after Sources loaded, the enable PUT correctly returns 409, but the component retains its old body/hash. Fetch the current instruction-skill list after this specific conflict and display its latest content, status, and hash beside a clear message that the version changed. Keep the newly fetched version disabled until the user inspects it and explicitly clicks **Enable this version** again. Do not retry the PUT automatically or weaken the server hash check.

Implementation: `InstructionSkills` uses the existing GET endpoint after a 409, updates its list and `onFiles`, and explains that the current version is shown for review. A failed recovery GET leaves the stale Enable button disabled and provides a Reload current version action. Request ordering prevents older list responses from replacing a newer conflict recovery; lifecycle checks prevent late callbacks after a project switch or unmount. A prop-triggered reload clears a stale busy state. Other PUT errors stay visible and retryable. Backend selection, external skill installation, and prompt/tool loading are unchanged.

Acceptance: the first click with a stale hash yields 409 and no saved enable action; the open panel then shows the new body and review status. A second, explicit click sends the new hash and enables only that reviewed version. `qa/instruction-skills-conflict.cjs` exercises a second synthetic browser client, ordinary PUT error, recovery GET failure/retry, same-project prop refresh, an old GET snapshot resolving after recovery, and navigation during a delayed recovery. Each sequence runs at 375 and 1440 pixels in both light and dark themes.

Final-head verification: run `npm test`, `npm run typecheck`, `npm run build`, and `npm run lint:design` from `apps/web`, plus both the focused synthetic Playwright regression and existing real-HTTP skills approval QA. Use external shared dependencies and an isolated build directory. No private Diary files, live model, production instance, or external skill download.
