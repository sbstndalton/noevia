# Handoff — 2026-10-05: full repo sweep (bugs + old/deprecated/broken code)

Paste this as the first message of the next session. It is complete on purpose: running agents
ignore steering added later, so everything the sweep needs is in this brief.

---

You are taking over noevia (`sbstndalton/noevia`; local checkout `noevia-application/` inside a
Nextcloud-synced folder). Your task: **a full repository sweep**. Find and fix real bugs, and remove
old, deprecated, dead or broken code. Ship each fix through review → merge → deploy.

## Read first
1. `CLAUDE.md` → `AGENTS.md` → `docs/agent-brief.md`.
2. `docs/roadmap.md`, especially "Where things stand — 2026-10-05".
3. `docs/changelog.md` (latest releases and their rollback recipes) and `docs/deployment.md`.
4. Open issues: `gh issue list -R sbstndalton/noevia --state open`.

## Current state
- **Live:** web `cowork-web:29732472` on DaServer (`ssh daserver`, 10.69.0.130),
  https://noevia.daserver.work.
- **Flags:** `chatFraming` is ON. Everything else from the last sprint is OFF: `framingReasoner`,
  `brainContext`, `provenancePolicy`, `routingModes`, and the per-user mirror and traces.
  **Never flip flags.** That is the owner's call.
- **Recent code you may touch carefully** (all in `apps/web/server/` unless noted):
  - `chat-framing.cjs`, `chat-frame-steering.cjs`, `task-packet.cjs`, `framing-reasoner.cjs`
  - `chat-vault-mirror.cjs`, `chat-brain.cjs`, `provenance-policy.cjs`, `routing-modes.cjs`
  - `storage-client.cjs` `checkLogin`
  - `experiments/framing-eval/` (repo root)

  These have specs (`docs/spec-task-packet.md`, `docs/spec-chat-brain.md`) and byte-identity
  tests for flag-off. Keep them passing.
- **Untouchable without the owner:** ChatGPT's branches (`codex/*`) and the issues it files. It is a
  co-worker that may push to main, so re-fetch main before every merge.

## Sweep scope
Work area by area; one PR per coherent area.

**Code areas:**
- **web server:** `apps/web/server`
- **web client:** `apps/web/src`
- **Diary:** `services/diary`
- **model-manager:** `services/model-manager`
- **deploy tooling:** `deploy/`, `tools/`
- **experiments:** `experiments/`

**What to look for:**
- **Bugs:** correctness, races, tenant isolation (every read and write must be scoped to the
  caller's workspace), injection boundaries, destructive paths, unbounded growth, errors thrown
  into request paths, and regex backtracking.
- **Dead or deprecated code:** unused exports and modules, superseded paths whose replacement
  has shipped, stale feature flags that are permanently on or off, obsolete experiments, and docs
  describing removed behaviour.
  - **Prove** a thing is dead before you delete it: grep every caller, check the tests, check
    `index.cjs` wiring, check the client `src`, check deploy scripts.
  - When unsure, file an issue instead of deleting.
- **Broken code:** tests skipped for no current reason, scripts that no longer run, and dangling
  references.
- **Do NOT rename `cowork*` identifiers.** That is intentional.

## Required process (owner's standing rules)
1. **File an issue first.** Every finding becomes a labelled GitHub issue before you fix it
   (`bug`, `cleanup`, `security`, `chat-framing`, …). The fixing PR closes it.
2. **Model roles:**
   - **Fable** orchestrates and does the final review.
   - **Opus** handles complex or security code.
   - **Sonnet** does ordinary fixes, merges and deploys.
   - **Haiku** does clerical work.
3. **Use worktrees outside Nextcloud.** Work in `~/.noevia-worktrees/<name>`, never inside the
   synced folder: Nextcloud deletes refs and files. Use
   `NODE_PATH=/Users/sebastiandalton/.noevia-deps/node_modules` if needed. `better-sqlite3` is
   missing locally, so DB-backed tests run only in CI.
4. **Check for phantom deletions.** Run `git status` before every commit.
5. **Tests:**
   - Use `node:test` and pytest. CI is authoritative; do not run the full `npm test` locally.
   - UI changes need a Playwright QA script in `apps/web/qa/` that fails before the change and
     passes after. Run it with Brave via `QA_CHROME_PATH` and `PLAYWRIGHT_MODULE` from the npx
     cache, because Chrome isn't installed.
6. **Review:**
   - Fable reviews every diff before merge. The `noevia-reviewer` agent has **no Bash**, so
     capture `gh pr diff` into an untracked `review-input/` folder for it and delete the folder
     afterwards.
   - Fold medium findings into the PR before merging; file low ones as issues.
7. **Merge:** squash-merge with `--match-head-commit` on the head CI verified, then delete the
   branch.
8. **Deploy:**
   - **Web:** web-only. Overlay `dist/` and `server/` from `git archive` onto the current
     `cowork-web:<sha>`. Back up `.env`, update `COWORK_VERSION` and the `current` symlink, then
     run the guarded `tools/preflight/up.sh --env-file <abs> -- -d --no-build --no-deps --wait web`.
     Snapshot all containers before and after; only web may change. Add a changelog entry with a
     rollback recipe.
     - Never use `overlay-release.sh` for a web-only release.
     - Never print `.env` values; refer to key names only.
   - **Diary and sidecars:** follow the per-service overlay flows in `docs/deployment.md` (Diary
     ships from the running image, `agent/` only). Model-manager fixes also ship a model-loader
     image.
9. **Live-test** after each deploy with an Opus live-tester:
   - Use the owner's signed-in Brave via Claude in Chrome.
   - Use only test items the tester creates itself; never touch the owner's data.
   - Never delete anything permanently. Archive test items instead.
10. **No model runs** (local or DaServer) without per-run approval. A safety classifier blocks
    them anyway.
11. **Context:** at about 150k tokens, save state to the memory ledger, then compact.
12. **Branches:** delete merged work branches. Only `main`, plus ChatGPT's branches, should
    remain.

## Known loose ends worth checking in the sweep
- `docs/project-ideas.md` is untracked in the local checkout. It is the owner's file; leave it.
- The sensitivity option label in `routing-modes.cjs` is 137 chars, over the 120-char label
  limit, so it gets slightly truncated. This is a low-priority nit.
- The keyword pre-rule in `routing-modes.cjs` will false-positive on code like `token = …`.
  That fails toward "ask", but it is worth tuning.
- In hybrid routing, tool results are checked only by pre-rules, not by Laya. This is
  documented and deliberate until #780 lands.
- `checkLogin` 403 → unverified. A refresh 401/403 → "login rejected". This is consistent but
  worth one live check once the owner fixes #767.
- Old experiments in `experiments/` (acp-spike, persona-kv, …): check whether each is still
  referenced, and propose deleting the dead ones through issues.
- Stale docs: `docs/roadmap.md` "Next — in order" still lists items from 2026-09. Verify each
  against `main` and prune what is done.

## Finish
At the end, give a summary covering:
- the issues filed and closed
- the PRs merged and the releases deployed
- the code removed (files and lines)
- anything left for the owner

Update `docs/roadmap.md` "Where things stand", and save the memory ledger.
