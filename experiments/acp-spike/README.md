# ACP spike: does a coding agent ask before writing? — 2026-09-17

One question for the CodeHarness contract (`docs/spec-agent-execution.md` §3): through ACP, can
noevia's approval gate stop an agent's file writes, or does the agent write on its own?

`spike.mjs` starts a fake OpenAI-compatible model that scripts one `write` tool call. It runs
OpenCode 1.18.31 as an ACP agent (`opencode acp`) in a throwaway workspace with a throwaway HOME,
and connects with `@agentclientprotocol/sdk` 1.4.0. The client advertises `fs.readTextFile` and
`fs.writeTextFile`, logs every `tool_call` and permission request, and answers permissions with
`allow_once` or `reject_once`. Nothing leaves the machine; no real model or account is used.

```bash
cd "$(mktemp -d)" && npm init -y && npm i opencode-ai@1.18.31 @agentclientprotocol/sdk@1.4.0
cp /path/to/experiments/acp-spike/spike.mjs . && node spike.mjs reject      # or: allow
ASK=1 node spike.mjs reject                                                  # agent permission config = ask
```

## Results

| Agent config | Client answer | Permission asked? | Write went through client `fs`? | File written |
|---|---|---|---|---|
| default | reject_once | **no** | no (agent's own process) | **yes** |
| default, workspace path via a symlink (`/var` → `/private/var`) | reject_once | yes, kind `other`, titled with the directory (outside-cwd check) | no | no |
| default, same symlink path | allow_once | yes (same) | no | yes |
| `permission: { edit: ask, bash: ask, webfetch: ask }` | reject_once | yes, kind `edit`, titled with the file | no | **no** |
| same | allow_once | yes, kind `edit` | **yes** (`fs/write_text_file`) | yes |

Offered permission options were `allow_once`, `allow_always` and `reject_once`; `reject_always`
was not offered. Tool calls were reported as kind `edit` with statuses `pending`, `in_progress`,
then `completed` or `failed`.

## What this means

- ACP carries a real gate, but only if the harness is configured to ask. With OpenCode's defaults
  an in-workspace write happens silently, and the client only learns about it afterwards.
- With `ask`, a rejected write never happens, and an approved write is carried out through the
  client's `writeTextFile`. noevia can enforce path containment, keep an audit and snapshot there,
  even after approval.
- So the CodeHarness adapter owns the agent's config. For OpenCode it writes
  `permission: { edit: ask, bash: ask, webfetch: ask }` into the task workspace and refuses to
  start a harness whose effective config it cannot pin. The OS sandbox (worktree-only writes, no
  credentials, proxied egress) stays underneath, because a different agent or a changed default
  would put back the first row of the table.
- Not tested: `bash` through the client `terminal/*` capability, MCP tools inside the agent, Qwen
  Code or adapters for Claude and Codex.
