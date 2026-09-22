# Session kickoff prompt

Paste the block below into a new agent session, working in the project folder
"AI frontend thing". It is deliberately short: `docs/master-prompt.md` is the real brief, and
this only points at it, fixes the starting state and sets the working rules for the session.

Keep it in sync when the live release or the current phase changes.

---

```text
You're continuing work on noevia, the self-hosted workspace in `noevia-application/` inside the
project folder "AI frontend thing" (GitHub `sbstndalton/noevia`). This kickoff is for the user's
intended Opus 5 successor; do not claim that model identity if it is not actually available. Read
`docs/master-prompt.md` fully and follow it: the read-first list, "Working with the user", the
non-negotiables, testing, deploying and decisions D1–D27. Also read `docs/roadmap.md`,
`docs/deployment.md`, `docs/changelog.md`, `docs/research/system-one/README.md`, and
`docs/research/system-one/18-decision-service-settings.md`.

Starting state: branch `main`; source `80d116f` is pushed to `origin/main` but is not deployed.
Production remains release `3d2521d` on DaServer (2026-09-22). Confirm repository, origin and box
before assuming — `current`, `COWORK_VERSION` in the host `.env`, `docker ps`, and the site. Where
the docs and the code or the box disagree, believe the code and the box, and fix the doc.

First run the deterministic, synthetic `apps/web/qa/live-stats.cjs` against a fresh build and
visually inspect light/dark at 375/768/1440 CSS px. Then deploy `80d116f` with the guarded overlay
runbook and verify the live footer. It now separates per-chat SSE telemetry from engine polling,
shows generating and first-output state immediately, and applies exact provider-reported usage,
rate and MTP across tool-loop rounds. The prior task passed 39 focused and 1,111 socket-free tests,
typecheck/build/design lint; its browser sandbox could not launch Chromium, so no visual pass is
claimed. Production backup `ab_20260922_020935` is the current verified backup; rollback remains
`54d7cf2` plus `.env.bak.before-3d2521d`.

After that, test → adjust → deploy → verify System-One routing and step supervision using a small,
bounded set of synthetic, non-personal Fast/Smart/Code cases and the existing local answering
model. Inspect actual Laya decisions and change only what evidence supports. Laya is already
installed and configured at `http://laya:8040` with a 1500 ms deadline; do not reinstall or
download it. Preserve fallbacks, manual model choices, approval gates and execution budgets.
This is not authority for benchmarks, paid APIs/search, Diary or personal sources, training,
model downloads, rented compute, engine changes or heavy workloads.

Commit, push and deploy each finished change (verified backup first, `overlay-release.sh`),
with `npm test`, `npm run typecheck`, `npm run build`, `npm run lint:design` and the affected QA
suites; for UI changes, look at screenshots at 375/768/1440 in light and dark.

Never send prompts to the real Diary or modify its corpus; synthetic fixtures only; never point
QA at production. On the server: detach long jobs with `setsid`, never use unbracketed
`pkill -f` patterns over SSH, and leave no sessions attached.

Ask when an answer changes what you build; otherwise choose sensibly, say so, and keep going.
When you stop, update `docs/roadmap.md` (Where things stand, Done, Next, Needs the user) and
clean up every server, port and temp file you started.
```
