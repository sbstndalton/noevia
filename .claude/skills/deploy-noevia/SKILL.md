---
name: deploy-noevia
description: Deploy noevia to DaServer, verify a change against the live instance, or check what is actually running there. Use this skill whenever the user asks to deploy, ship, release, roll out, roll back, or push something live; whenever they ask whether a change is live or what version DaServer is on; and whenever work needs verifying against real data — real Nextcloud folders, MCP tool calls, the write-approval card, vision, or source refresh. Use it even when the request sounds small ("can you just push this?", "is it live yet?", "did that fix work on the server?"). Most sessions run in a sandbox that cannot reach the host at all, so the first job is finding that out rather than assuming; this skill handles both the reachable case and the handoff when it is not.
---

# Deploying and verifying noevia

Two things make this harder than `docker compose up`, and both cost real time when
rediscovered:

1. **Most sessions cannot reach the host.** Cloud Claude Code sessions (iOS, web, the
   `anthropic_cloud` environment) sit behind an egress proxy with no route to DaServer
   and no SSH key. The work still has to happen — it just has to happen somewhere else.
2. **Production does not look like `DEPLOY.md`.** The repo root's `DEPLOY.md` describes
   a generic fresh install. Following it here updates nothing. The live runbook is
   `docs/deployment.md`, and it has traps that are easy to walk into.

## Step 1 — Find out what you can actually reach

Do this before planning anything. It decides everything downstream, and it costs
seconds.

```sh
# Can this session reach the host at all?
timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 root@100.70.173.74 'echo reachable' 2>&1 | tail -1
```

Tailscale is `100.70.173.74`. The `daserver` alias and `10.69.0.130` only resolve on the
home LAN — off-site, Tailscale reports that peers advertise routes but `--accept-routes`
is false, which is why the LAN address stays dead. One SSH failure is not proof the host
is down; the route from sandboxed environments has been transiently flaky. Retry once
before concluding.

If SSH works, go to **Step 3**. If it does not, go to **Step 2**.

## Step 2 — Hand off to a machine that can

Do not try to work around the network. Do not ask the user to paste command output back
and forth for a multi-step deploy — that is how a 20-minute job becomes an hour and how
steps get silently skipped.

**Is another agent already reachable?**

Call `ListAgents`. Sessions on the user's Mac appear as `bridge` sessions once Claude
Code is running there with Remote Control connected. If one is listed, `SendMessage` it
and point it at the handoff document you are about to write.

If nothing is listed, say so plainly and tell the user what to start — do not spawn a
cloud session as a substitute. A new cloud session lands in the *same* environment as
this one, with the same proxy and the same missing route. It cannot help.

**Write the handoff into the repo, not just into a message.**

Use `assets/handoff-template.md`. Fill it in, save as `docs/handoff-<topic>.md`, commit
and push to the working branch. Two reasons this beats a chat message: it survives the
session, and the return channel is not guaranteed — a cloud session cannot message back,
and whether a bridge session can is unconfirmed. So the brief must also tell the
receiving agent to **write its findings into the repo and push**, rather than reply.

Then tell the user exactly what to type on the other machine, e.g.:

> Read `docs/handoff-<topic>.md` on branch `<branch>` and work through it in order.

**Be honest about what is now unverified.** Until that agent reports back, describe the
work as untested. A green test suite is not the evidence this repo asks for — see
`docs/agent-brief.md`, which records automated tests twice passing obviously broken
code.

## Step 3 — Check what is actually live

Never trust a doc for this, including `docs/deployment.md` and including anything you
wrote earlier in the session. `changelog.md` has been wrong within a day of being
written.

```sh
ssh root@100.70.173.74 "readlink -f /mnt/docker/appdata/cowork/current; \
  docker ps --format '{{.Names}}\t{{.Image}}' | grep cowork"
```

`COWORK_VERSION` lives in the host `.env`, not in a container env var. Where the docs and
the box disagree, believe the box and fix the doc.

## Step 4 — Deploy

Read `references/runbook-traps.md` before touching anything. It covers the five things
that bite: the tarball deploy (there are no git credentials on the server), the three
unsynced copies of the compose config, the preflight wrapper, verifying the candidate
*before* flipping the symlink, and rollback.

The short version, with the full sequence in that reference:

1. `git archive` a tarball, `scp` it, extract under `releases/<sha>/`
2. Back up `config/.env`
3. Build — allow ~10 min over the Tailscale relay, much longer if the image pulls models
4. **Verify the candidate before flipping `current`**
5. Repoint the symlink, `sed` `COWORK_VERSION`
6. Bring up through `/mnt/docker/appdata/cowork/tools/preflight/up.sh` — never the
   Compose Manager GUI, which bypasses the preflight

## Step 5 — Verify against real data

This is the step the repo actually cares about, and it cannot be done from a test suite.

The public URL is **`https://cowork.daserver.work`**. The hostname kept its old name
after the rebrand, deliberately — `noevia.daserver.work` does not exist, and assuming it
does wastes a debugging cycle.

`LEGACY_AUTH_COMPAT=false` on live, so there is no bearer-token path. Verification needs
a real authenticated browser session.

Check the things that only break against real data:

- A real chat with a Nextcloud toolbox: one chip per tool **call**, named, with a result.
- A real **write**: the approval card appears with full arguments and all three buttons;
  declining returns a readable message; "Allow for this chat" suppresses the next prompt
  in that chat but **not** in another. Write to a scratch location and clean up after.
- Nextcloud uploads and deletions, source refresh, vision — each has broken here before
  in ways tests did not catch.

For UI work, `docs/agent-brief.md` asks for more: toggle the theme in every view
confirming no reload and no flash before React mounts; 375 / 768 / 1440 in both themes;
no horizontal overflow; visible focus rings on both canvases.

**The `apps/web/qa/` scripts are not for this.** All 73 drive a disposable server they
start themselves on `localhost`/`127.0.0.1`, and `onboarding.cjs` states the policy
outright: *"Never points at production."* Names like `diary-live.cjs` and
`drive-tools-live.cjs` mean live *services and credentials*, not the live host. They are
local regression — running them proves nothing about the box.

## Step 6 — Record it

Append a dated section to `docs/deployment.md` in the style of the existing entries: what
was deployed, what was verified, what was measured, what is still open. The file is a log
of what actually happened, not a plan — future sessions read it to avoid repeating work,
and an entry that overstates what was checked is worse than none.

## Standing constraints

From `AGENTS.md` and `docs/agent-brief.md`. These apply to any change that reaches the
box:

- Do not rename `cowork`-prefixed identifiers — env vars, images, cookies, storage keys,
  the state dir. They are a compatibility contract with the live deployment.
- Do not remove or simplify the tool-approval card, and never add a global "never ask".
- Do not put a secret in an `MCP_SERVERS` URL; those are logged verbatim at startup.
  Tokens go in their own env var via `bearer:NAME`.
- **Do not send prompts to the diary.** It is the user's real private journal.
