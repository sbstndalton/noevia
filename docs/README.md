# noevia docs

Consolidated 2026-09-09 from `docs/` plus two master prompts that lived outside
the repo. Ten files became nine; the redundancies are listed at the bottom so
nothing looks silently lost. The originals of the seven tracked files remain in
git history; the two master prompts were never tracked and exist only as the
content folded in below.

| File | What it is | Read it when |
| --- | --- | --- |
| [agent-brief.md](agent-brief.md) | Orientation, build/test, architecture reference, and the hard "do not do this" rules | **Start here** on any fresh session |
| [deployment.md](deployment.md) | The live daserver runbook — tarball ship, three compose copies, Tailscale | Shipping a commit to production |
| [design-system.md](design-system.md) | Polymetal palette, contrast contract, theme plumbing | Touching colour, tokens, or CSS |
| [ui-overhaul.md](ui-overhaul.md) | The five-phase UI plan, with what shipped marked | Continuing UI work |
| [diary.md](diary.md) | Diary requirements and as-built behaviour, including storage/sync | Touching the diary |
| [spec-diary-smb.md](spec-diary-smb.md) | Server-local Diary and Mac SMB migration plan, concurrency gaps and acceptance checks | Planning Diary storage migration |
| [roadmap.md](roadmap.md) | Planned work: setup wizard, thinking modes, diary zero-state, tool scaling | Planning what's next |
| [changelog.md](changelog.md) | What was fixed and how it was verified, newest first | Checking whether something is already done |
| [backlog.md](backlog.md) | Every open item from every source, deduplicated and ranked | Picking up loose ends |

Repo-root docs are unchanged and remain authoritative for their subjects:
`README.md` (quick start), `DEPLOY.md` + `cowork.setup.json` (generic
agent-executable deploy), `SECURITY.md` (trust model).

## What was merged into what

| Source | Fate |
| --- | --- |
| `MASTER-PROMPT-noevia-continuation-2026-09-08.md` | Split: orientation/architecture → `agent-brief.md`; runbook → `deployment.md`; open work → `backlog.md` |
| `MASTER-PROMPT-noevia-ui-implementation-2026-09-08.md` | Split: palette → `design-system.md`; phases → `ui-overhaul.md`; rules → `agent-brief.md`; backlog → `backlog.md` |
| `noevia-design-system.md` | **Superseded** — its palette was stale (see the conflict note in `design-system.md`) |
| `ui-shell-preview.md` | Folded into `agent-brief.md` (placeholder surfaces) and `ui-overhaul.md` |
| `diary-master-prompt.md` | Folded into `diary.md` as "Requirements" |
| `diary-workspace.md` | Folded into `diary.md` as "As built" |
| `spec-reasoning-effort.md` | Folded into `roadmap.md` as the thinking-modes appendix |
| `roadmap-2026-09.md` | Became `roadmap.md` |
| `QA-2026-09-08.md`, `review-fixes.md` | Merged into `changelog.md` |

### Redundancies collapsed

- **Build/test instructions** appeared in both master prompts with **conflicting
  advice** — both warned `npm run typecheck` was broken. It was fixed in the
  2026-09-08 QA pass (`package.json` now invokes Node directly). One corrected
  copy now lives in `agent-brief.md`.
- **"What NOT to do"** was near-duplicated across both master prompts. One list.
- **The `cowork`-identifiers rule** appeared in four files. One statement.
- **Diary landing/calendar/storage/sync** was described three times — as
  requirements, as as-built, and again in a fix summary. One file, two sections.
- **Test counts** were quoted as 134, 150, and 161 in different files. All were
  true when written; only the current number is now stated, once.
