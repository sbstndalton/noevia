# Handoff: <what needs doing>

For an agent running **on <machine>** — the machine that can reach <what this session
cannot: the host over SSH, the live instance in a browser, the public internet>.

<One paragraph: what was built, in what environment, and precisely why it could not be
verified there. Be specific about the blocker — "the egress proxy blocks X" beats "I
couldn't test it".>

Read `AGENTS.md` and `docs/agent-brief.md` first; the "What NOT to do" and "Verification
expectations" sections bind this work. Never send prompts to the diary.

Scope agreed with the owner: <verify only | verify and fix | verify, fix and deploy>.

## What is on the branch

| Commit | What it is | Verified? |
|---|---|---|
| `<sha>` | <one line> | <Tests only / Not at all / what was checked> |

## Order of work — stop at the first failure and record it

### 0. Probe before doing anything expensive

<The cheap checks that decide the shape of everything after: reachability, whether a
dependency is available from where it will actually run, what is currently live. Include
the exact commands. Say what to do if each one fails.>

### 1. <The cheapest place to discover the work is wrong>

<Put the highest-uncertainty step first and somewhere cheap. If something was written
against an API that was never executed, say which functions are most likely wrong so the
agent knows where to look instead of reading everything.>

### 2. Fix and push

<The full local suite, with the expected counts so a silent drop is visible.>

Push to `<branch>`. <Whether to open a PR — default no.>

### 3. Verify against real data

<The live checks. Name the real hostname. Note anything that makes verification
non-obvious — auth modes, what to clean up afterwards.>

### 4. Deploy — only if the above passes

<Point at `.claude/skills/deploy-noevia/references/runbook-traps.md` rather than
restating it. Call out anything specific to THIS change: a new env var needing all three
compose copies, an overlay that has to be hand-merged, a longer build.>

### 5. Record it

Append a dated section to `docs/deployment.md` in the style of the existing entries, with
what was measured. Replace any "not verified" caveats in the code or docs with what was
actually observed. Commit and push — **write findings into the repo rather than only
replying**, because the return channel to the originating session is not guaranteed.

## What is deliberately not in scope

<Things a capable agent would otherwise reasonably do. Say why, so it does not look like
an oversight and get "helpfully" fixed.>

## Known gaps left open

<Anything knowingly unfinished, so it is not rediscovered as a bug.>
