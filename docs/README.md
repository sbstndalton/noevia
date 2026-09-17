# noevia docs

Consolidated 2026-09-09 from `docs/` plus two master prompts that lived outside
the repo. Ten files became nine; the redundancies are listed at the bottom so
nothing looks silently lost. The originals of the seven tracked files remain in
git history; the two master prompts were never tracked and exist only as the
content folded in below.

| File | What it is | Read it when |
| --- | --- | --- |
| [agent-brief.md](agent-brief.md) | Orientation, build/test, architecture, the hard "do not" rules | **Start here** on any fresh session |
| [roadmap.md](roadmap.md) | The one plan: status, open work, order, testing rules | Deciding what to do next |
| [master-prompt.md](master-prompt.md) | The one executable brief matching the roadmap | Handing work to an agent |
| [deployment.md](deployment.md) | Live DaServer runbook; `deploy/examples/overlay-release.sh` | Shipping to production |
| [changelog.md](changelog.md) | What was fixed and how it was verified | Checking whether something is done |
| [design-system.md](design-system.md), [spec-ui-direction.md](spec-ui-direction.md), [ui-reference-review.md](ui-reference-review.md) | Palette, contrast, visual direction, references | Touching UI |
| [diary.md](diary.md), [dav.md](dav.md), `spec-diary-*.md`, [spec-storage-appliance.md](spec-storage-appliance.md) | Diary and storage | Touching the Diary or storage |
| [spec-context-projection.md](spec-context-projection.md), [spec-agent-execution.md](spec-agent-execution.md), [spec-deep-research.md](spec-deep-research.md) | Context layers/compaction/reduction; qualification, Prompt Architect, CodeHarness, durable work, execution nodes, browser; deep research | Context, agent-execution or deep research work |
| other `spec-*.md` | Design specs (reasoning effort, tool routing, models, documents, MTP, skills, backend) | Working in that area |

On 2026-09-16 the roadmap audit, backlog, continuation checkpoint, Codex handoffs, live
and settings audits, UI-overhaul plan, Freebuff report and all master prompts were merged
into `roadmap.md` and `master-prompt.md`; originals are in git history.

Repo-root docs are unchanged and remain authoritative for their subjects:
`README.md` (quick start), `DEPLOY.md` + `cowork.setup.json` (generic
agent-executable deploy), `SECURITY.md` (trust model).

## What was merged into what

| Source | Fate |
| --- | --- |
| `MASTER-PROMPT-noevia-continuation-2026-09-08.md` | Split: orientation/architecture → `agent-brief.md`; runbook → `deployment.md`; open work → `roadmap.md` |
| `MASTER-PROMPT-noevia-ui-implementation-2026-09-08.md` | Split: palette → `design-system.md`; phases → `roadmap.md`; rules → `agent-brief.md`; backlog → `roadmap.md` |
| `noevia-design-system.md` | **Superseded** — its palette was stale (see the conflict note in `design-system.md`) |
| `ui-shell-preview.md` | Folded into `agent-brief.md` (placeholder surfaces) and `roadmap.md` |
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
