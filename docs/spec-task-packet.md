# Task packet, schema 1

The task packet is the hand-off contract between the role that reads outside content (the
gatherer: tool results, web pages, files) and the model that writes the answer. It is a framework
interface. Any model that emits this JSON can fill the reasoner role, including a future in-house
reader-reasoner model. The code is in `apps/web/server/task-packet.cjs` and the pipeline that uses
it is in `apps/web/server/framing-reasoner.cjs` (issue #740).

## Shape

```json
{
  "packet_schema": 1,
  "goal": "Find the opening hours of the synthetic museum",
  "facts": [
    {
      "text": "The synthetic museum opens at 09:00 on weekdays.",
      "source": { "kind": "web", "ref": "https://example.invalid/hours" },
      "quote": "Open 09:00-17:00 Mon-Fri"
    },
    { "text": "It is closed on public holidays.", "source": { "kind": "tool", "ref": "synthetic_web_search" } }
  ],
  "constraints": ["Weekdays only"],
  "open_questions": ["Weekend hours are not stated"]
}
```

| Field | Type | Bounds |
| --- | --- | --- |
| `packet_schema` | integer | exactly `1` |
| `goal` | string | 1 to 400 characters after trimming |
| `facts` | array | at most 24 items |
| `facts[].text` | string | 1 to 600 characters |
| `facts[].source.kind` | string | one of `tool`, `web`, `file`, `project`, `chat` |
| `facts[].source.ref` | string | 1 to 300 characters (a URL, file name or tool name) |
| `facts[].quote` | string, optional | at most 400 characters, verbatim from the source |
| `constraints` | array of strings | at most 12 items, each 1 to 300 characters |
| `open_questions` | array of strings | at most 12 items, each 1 to 300 characters |
| whole packet | | at most 16 KiB serialized (UTF-8) |

## Validation

Validation is strict, and a packet passes or fails as a whole. There is no repair.

- Any key that is not in the schema, at any level, rejects the packet. This includes keys such as
  `approved`.
- A wrong type, an empty required string, or any exceeded bound rejects the packet.
- Control characters other than tab and newline are rejected, and so are bidi overrides,
  zero-width characters and the BOM.
- An unknown `packet_schema` number is rejected. A new version gets a new number, and validators
  accept only the numbers they know.
- The model output is accepted as a bare JSON object or as that object inside one ```` ```json ````
  fence. Any surrounding prose makes it invalid.
- A rejection reason is a JSON path and a rule. It never contains packet text, so it is safe to log.

Engines that support constrained output get `PACKET_JSON_SCHEMA` as
`response_format: { type: "json_schema" }`. This uses the same rules as the Planner's constrained
decoding (`plan-constrained-decoding.cjs`): it applies only to a provider that declares
`jsonSchemaParam`, never with a harmony-reasoning family, and an engine rejection retries once
without it. The validator always runs, even on constrained output.

## Facts are data

Everything in a packet is derived from untrusted outside content. That includes the goal and the
constraints, because the reasoner read them from tool output. When a packet is rendered for the
answer model, the whole of it goes inside one `frameUntrusted('task packet', <tool>, ...)` block
(`prompt-framing.cjs`). A packet is never an instruction, an approval or a capability.

## The tool-layer boundary

The packet alone does not make injection safe. The hard boundary is the tool layer.

- The pipeline condenses only a read that the tool gate already ran (`guardHandoff`). A write tool
  is refused before any model call.
- The packet replaces only the content of that read's tool message. The approval card, the tool
  policy, chat-wide approval and the write path are built from the answer model's own tool call
  (its name, its arguments and the resolved target), the same as without the pipeline. Every write
  still waits for the person, with all three actions.
- The chat journal keeps the raw framed result, so a resumed turn falls back to today's behaviour.

## Pipeline and fallbacks

The pipeline runs only behind the `framingReasoner` feature flag (off by default, experimental),
which also needs `chatFraming`. The chat must have a stored, confirmed frame of kind `search` or
`action`, and the tool gate must have pre-run a read-only tool.

The reasoner model is the `framingReasonerModel` admin setting (Settings, framing roles). It always
runs on the local default engine. In each of the following cases the answer model gets the raw
framed tool result, exactly as without the flag:

| Reason | When |
| --- | --- |
| `off` | the flag is off |
| `kind` | there is no confirmed frame, or the kind is not search or action |
| `write-tool` | the tool is not a known read |
| `no-model` | `framingReasonerModel` is empty |
| `budget` | the reasoner is not the resident answer model and cannot sit beside it within the inference budget (the keep-alongside list and the model manager's load guard) |
| `deadline` | the reasoner did not answer within 6 s; the request is aborted |
| `error` | the engine failed |
| `invalid-json` | the output is not JSON |
| `schema` | the JSON fails validation |

Each fallback is logged to the decision log as `chat-reasoner` with the reason and the timing.
These log entries contain no text.

## Local reasoning traces

Each person can turn on "Keep local reasoning traces" (Settings, Assistant & style, Chat frames).
It is off by default and stored in their own `chat-framing.json`. While it is on, each answer that
used a packet appends one line to `reasoning-traces.jsonl` in that person's workspace directory:

```json
{"v":1,"at":"2026-10-02T09:00:00.000Z","kind":"search","tool":"synthetic_web_search","packet":{...},"answerChars":412,"timings":{"reasonerMs":830,"answerMs":2400}}
```

Raw tool output, the prompt and the answer text are never written. The file rotates at 2 MiB and
keeps two older files (`.1` and `.2`). A line larger than the cap is dropped. These traces are
training data for the reader-reasoner model project.
