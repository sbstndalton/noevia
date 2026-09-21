# Session kickoff prompt

Paste the block below into a new agent session, working in the project folder
"AI frontend thing". It is deliberately short: `docs/master-prompt.md` is the real brief, and
this only points at it, fixes the starting state and sets the working rules for the session.

Keep it in sync when the live release or the current phase changes.

---

```text
You're continuing work on noevia, the self-hosted workspace in `noevia-application/` inside the
project folder "AI frontend thing" (GitHub `sbstndalton/noevia`). Read `docs/master-prompt.md`
fully and follow it: the read-first list, "Working with the user", the non-negotiables, testing,
deploying, and the decisions D1–D27. Then take `docs/roadmap.md` → "Next — in order" from the top.

Starting state: branch `main`; release `2d7ba8f` is live on DaServer (2026-09-21), nine
containers including `code-sandbox` and `docling`. Confirm it yourself before assuming —
`current`, `COWORK_VERSION` in the host `.env`, `docker ps`, and the site. Where the docs and
the code or the box disagree, believe the code and the box, and fix the doc.

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
