# Session kickoff prompt

Paste the block below into a new agent session, working in the project folder
"AI frontend thing". It is deliberately short: `docs/master-prompt.md` is the real brief, and
this only points at it, fixes the starting state and sets the working rules for the session.

Keep it in sync when the live release or the current phase changes.

---

```text
You're continuing work on noevia, the self-hosted workspace in `noevia-application/` inside the
project folder "AI frontend thing" (GitHub `sbstndalton/noevia`). Read `docs/master-prompt.md`
fully and follow it, including the read-first list, the non-negotiables, the testing rules, the
decisions D1–D20 and the steps under "Current phase", in order.

Starting state: branch `main`; release `ca5d2f6` is live on DaServer (deployed 2026-09-17 night,
PR #1 and PR #2 merged). Confirm that yourself before assuming it — check `current`,
`COWORK_VERSION`, `docker ps` and the public bundle hash. Where the docs and the code or the box
disagree, believe the code and the box, and fix the doc.

Work through the current-phase steps in order. Commit and push after each, with `npm test`,
`npm run typecheck`, `npm run build`, `npm run lint:design` and the affected QA suites; for UI
changes, screenshots at 375/768/1440 in light and dark, read before moving on.

Never send prompts to the real Diary or modify its corpus: use a per-run copy of `diary-test/`
and synthetic accounts only. Never point QA at production.

On the server: don't raise `--models-max`, don't run heavy benchmarks during a backup or mover
window, detach long jobs with `setsid` (a plain `nohup … &` over SSH dies with the session), never
use unbracketed `pkill -f`/`pgrep -f` patterns (they match your own SSH command), and don't leave
SSH sessions attached. Remember one model slot is shared with the Nextcloud Assistant, so a
concurrent request evicts the model under test.

Don't stop to ask questions: collect them and put them in a final summary. Anything that is mine —
deploying, spending, host settings (GTT cap, syslog mirror), model downloads, live Compose or preset
edits, the SMB share — goes in that summary rather than being done.

When you're done, update `docs/roadmap.md` (status and the bug log) and `docs/master-prompt.md`
("Current phase"), and clean up every server, port and temp dir you started.
```
