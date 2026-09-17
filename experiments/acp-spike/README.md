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
TOOL=bash ASK=1 node spike.mjs allow                                         # a shell command instead of a write
```

## Results

| Agent config | Client answer | Permission asked? | Write went through client `fs`? | File written |
|---|---|---|---|---|
| default | reject_once | **no** | no (agent's own process) | **yes** |
| default, workspace path via a symlink (`/var` → `/private/var`) | reject_once | yes, kind `other`, titled with the directory (outside-cwd check) | no | no |
| default, same symlink path | allow_once | yes (same) | no | yes |
| `permission: { edit: ask, bash: ask, webfetch: ask }` | reject_once | yes, kind `edit`, titled with the file | no | **no** |
| same | allow_once | yes, kind `edit` | **yes** (`fs/write_text_file`) | yes |

Shell command (`bash`, `echo ran > hello.txt`), client advertising `terminal: true` as well:

| Agent config | Client answer | Permission asked? | Ran through client `terminal/*`? | Side effect |
|---|---|---|---|---|
| default | reject_once or allow_once | **no** | no | **happened** |
| `bash: ask` | reject_once | yes, kind `execute`, titled with the command | no | did not happen |
| `bash: ask` | allow_once | yes, kind `execute` | **no** (agent's own process) | happened |

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
- Shell commands are different: `ask` gives a real yes/no, but an approved command runs in the
  agent's own process even when the client offers `terminal/*`. noevia can decide whether a command
  runs, but not what it touches once allowed. For commands the sandbox is the only containment:
  worktree-only writes, no credentials, proxied egress.
- Not tested: MCP tools inside the agent, Qwen Code, and the Claude and Codex adapters.

## Server spike — DaServer, real local models, sandboxed (2026-09-17, D14)

`server-spike.mjs` + `server-run.sh`. OpenCode 1.18.31 over ACP inside the `cowork-web` image with:
read-only root, `--cap-drop ALL`, `no-new-privileges`, non-root (1000), 3 GiB / 512 pids, tmpfs
`/tmp` and `$HOME`, the task worktree `/work` as the only writable mount, and an `--internal` Docker
network whose only other member is the engine (alias `sandbox-llama`). The adapter pins
`permission: { edit: ask, bash: ask, webfetch: ask }`; the client allows edits only inside `/work`,
allows commands (the sandbox contains them) and refuses the rest. Task: a synthetic `median()` with
two bugs (lexicographic, in-place sort; wrong even-length median) and a test that must stay unchanged.
The harness runs the test itself afterwards.

| Model | Solved (test passes, test.js unchanged) | Wall | Tool calls | Permissions (all allowed) | Writes via client `fs/write_text_file` |
|---|---|---|---|---|---|
| Qwen3.5-4B-Q5_K_M (ctx 24 576) | **yes** | 165 s | 11 | 3 edit, 5 execute | 3 |
| Ornith-1.5-9B-Q5_K_M (ctx 16 384) | **yes** | 265 s | 10 | 2 edit, 5 execute | 2 |

Sandbox probes from inside the container (both runs identical): write `/etc` and `/app` → `EROFS`;
Docker socket absent; no token/key/secret variables; `huggingface.co`, `model-loader`, `web` and
`diary` → name resolution fails; the engine → 200. Every approved command ran in the agent's own
process (the client's `terminal/*` was never used), as in the local spike: for commands the sandbox
is the boundary. Nothing was left on the server (network, container and spike folder removed).

**Result:** the CodeHarness shape works end to end on this hardware: pinned `ask` permissions map to
noevia's approval card, edits go through noevia's file API, and the container holds against file,
socket, secret and network escapes. Next (spec §3): per-task git worktree ownership, an egress proxy
for tasks that need packages, job events relayed to the web app, and the Code mode UI.
