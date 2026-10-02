# Chat brain, schema 1

A chat brain is a small, structured note about one chat: what it was about, what was decided, what
was established, what is still open and who or what came up. It is a framework interface, versioned
like the [task packet](spec-task-packet.md). Any model that emits this JSON can fill the reasoner
role, including a future in-house model. The code is in `apps/web/server/chat-brain.cjs` (issue
#742).

## Shape

```json
{
  "brain_schema": 1,
  "summary": "Planning a synthetic garden shed. The user settled on timber and a spring build.",
  "decisions": ["Use untreated timber", "Build in spring"],
  "facts": ["The plot is 3 by 4 metres"],
  "open_questions": ["Is a permit needed?"],
  "entities": ["Garden shed", "Synthetic Hardware Store"]
}
```

| Field | Type | Bounds |
| --- | --- | --- |
| `brain_schema` | integer | exactly `1` |
| `summary` | string | 1 to 600 characters after trimming |
| `decisions` | array of strings | at most 12 items, each 1 to 300 characters, one line |
| `facts` | array of strings | at most 16 items, each 1 to 300 characters, one line |
| `open_questions` | array of strings | at most 12 items, each 1 to 300 characters, one line |
| `entities` | array of strings | at most 24 items, each 1 to 80 characters, one line |
| whole brain | | at most 12 KiB serialized (UTF-8) |

All six keys are required; an empty list is `[]`.

## Validation

The task packet's rules, unchanged in spirit:

- Strict, all or nothing, no repair. An unknown key, a wrong type, an empty string, a line break in
  a list item or any exceeded bound rejects the brain; the previous brain (or none) stays.
- Control characters other than tab and newline, bidi overrides, zero-width characters and the BOM
  are rejected.
- An unknown `brain_schema` number is rejected. A richer brain gets a new number; validators accept
  only the numbers they know, and a note written with an older number stays readable as it is.
- The model output is accepted as a bare JSON object or that object inside one ```` ```json ````
  fence. Rejection reasons are a JSON path and a rule, never brain text, so they are safe to log.
- Engines with constrained output get `BRAIN_JSON_SCHEMA` through the same request path as the task
  packet (`createEngineCompletion`); the validator always runs.

## Generation

- Behind the `framingReasoner` flag (which needs `chatFraming`) AND the user's own "Mirror chats to
  Diary" opt-in. Off by default.
- Runs when a chat goes idle: every change to a chat (the same requests that nudge the mirror)
  restarts a per-chat timer of three minutes. Builds run one at a time across all users, never on
  the request path. A brain that already matches the chat's `updatedAt` is not rebuilt.
- The reasoner model is the `framingReasonerModel` admin setting, on the local default engine.
  Empty means skip. The budget gate is #740's `admitReasoner`: the reasoner runs only when it is
  the model already loaded, or it is on the keep-alongside list and the model manager says it fits.
  It never swaps the answer model out.
- The transcript (the conversation export's Markdown, reasoning left out, start and end kept when
  long) is untrusted and reaches the reasoner inside `frameUntrusted('chat transcript', ...)`.
- Fallbacks, each leaving the previous brain in place: flag off, empty chat, no model, budget,
  deadline (30 s), engine error, invalid JSON, schema failure. Deadline, error, budget and invalid
  output are retried once after 15 minutes.
- Storage: one JSON file per chat in the user's own workspace directory,
  `chat-brains/<sha256(chat id)>.json`, holding `{ chatId, sourceUpdatedAt, builtAt, brain }`
  (at most 32 KiB). A record whose chat id does not match or whose brain fails validation reads as
  none. A tombstoned chat loses its brain.

## In the vault note

When a chat has a brain, its mirrored note (`chat-vault-mirror.cjs`) gets `brain_schema: 1` in the
frontmatter and these sections right after it, followed by a rule and the transcript as before:

```markdown
---
noevia_id: "c-shed"
...
brain_schema: 1
---
## Summary

Planning a synthetic garden shed. The user settled on timber and a spring build.

## Decisions

- Use untreated timber
- Build in spring

## Facts

- The plot is 3 by 4 metres

## Open questions

- Is a permit needed?

## Entities

- Garden shed
- Synthetic Hardware Store

---

# Garden shed
...
```

The five sections are always present and in this order; an empty one reads `_None._`. Angle
brackets and ampersands are escaped and whitespace is collapsed, so model text cannot open HTML,
a heading or a frontmatter fence. Without a brain the note is exactly as before (`brain_schema: 0`).

## Retrieval

Behind the `brainContext` flag (off by default; also needs `chatFraming`). For a chat with a
stored, confirmed frame whose `links[]` name other chats, the system prompt gets those chats'
summaries:

- at most 3 brains, in link order; only chats in the signed-in user's own lists, read from the
  user's own workspace;
- each summary in its own `frameUntrusted('chat brain', <title>, ...)` block, under one plain line
  that says they are background;
- the whole block at most `brainContextChars` characters (admin setting in
  `/api/admin/framing-settings`, default 2000, 0 to 200000; 0 turns it into a no-op). Summaries are
  clipped to fit; a brain that cannot get at least a few words in is left out.

With the flag off, no confirmed frame, no links or no stored brains, the model request is byte for
byte what it was before.

## Upgrading

Everything that depends on hardware is a setting: the reasoner model, the keep-alongside list and
budget (model manager), and `brainContextChars`. A larger machine raises them; nothing names a model
or a memory size. A richer brain is `brain_schema: 2` with its own validator; schema 1 notes stay
valid.
