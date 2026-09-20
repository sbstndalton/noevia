# Vendored skills

`impeccable/` — the frontend design skill, vendored separately.

`doubt-driven-development/`, `debugging-and-error-recovery/`,
`source-driven-development/` — from
[addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) at `c004a74`,
MIT (Copyright (c) 2025 Addy Osmani). Each carries an unmodified body with one
added header note; the upstream licence text applies.

Three of the pack's 25 were taken, not all of them. The rest either duplicate
what `AGENTS.md` and `docs/agent-brief.md` already say (planning, spec
writing, shipping), collide with `impeccable` and `npm run lint:design`
(frontend), or restate a slash command this repo already has (code review,
security review). These three cover ground nothing here covered:

- **doubt-driven-development** — adversarial fresh-context review. This is the
  direct answer to the line in `docs/agent-brief.md`: "Automated tests have
  twice passed code that was obviously broken in one real interaction."
- **debugging-and-error-recovery** — systematic root-cause triage.
- **source-driven-development** — verify against official docs rather than
  memory, which matters against a moving llama.cpp and OpenAI-compatible APIs.
