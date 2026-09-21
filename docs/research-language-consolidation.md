# Language consolidation: what runs where, where the time goes, and whether to port

Written 2026-09-21 on branch `wip/fable-cleanup`, from measurements taken with synthetic data
only (a temporary data directory, a fake OpenAI-compatible provider, a generated tool
catalogue and generated documents). No real Diary, corpus, model or network was involved.
The measurement script is `apps/web/scripts/profile-hot-paths.cjs`; rerun it to refresh the
numbers.

The question this answers: the app is written in three languages plus a native engine. Is any
of the Node code worth porting to Rust, C++ or Python for a gain the user would notice?

## 1. Inventory

| Where | Language | Lines (tracked, no tests) | What it does |
|---|---|---:|---|
| `apps/web/server` (127 modules) | Node.js CommonJS | 17,300 | the web server: auth, projects, chat loop, toolboxes, MCP, documents, DAV, backups |
| `apps/web/src` | TypeScript + React | 4,500 ts + 11,200 tsx | the browser app |
| `apps/web/qa` | Node (Playwright) | 6,400 | browser QA suites, not shipped |
| `services/diary` | Python (FastAPI) | 10,700 | Diary Companion: context assembly, the `/v1` proxy, Markdown journal writes |
| `services/model-manager` | Python (FastAPI) | 12,500 | Model Loader (vendored fork): GGUF catalogue, downloads, the engine's process control |
| `services/docling` | Python | 700 | the document extraction sidecar around IBM Docling |
| `services/ocr` | Python | 350 | PDF page rendering and OCR (Tesseract), DOCX text |
| `services/code-sandbox` | Node | 200 | the Code-mode sandbox supervisor |
| engine (`compose.llamacpp.yaml`) | C++ (llama.cpp, Vulkan), pinned image | — | inference; **untouched by design** |
| `tools/repo-index` | Node | 270 | dev-only MCP server for agents working on the repo |

Three runtime languages, one of them (Python) entirely at the edges: every Python service is
a wrapper around a library that is itself Python (Docling, Tesseract bindings, the Model
Loader's Hugging Face client) or a fork we did not write. Node owns everything on the request
path between the browser and the engine.

Tests: 1,024 Node tests (`npm test`) run without booting the server or touching the network;
the Python services carry their own `test_*.py`.

## 2. Where the time goes on a chat turn

The prior expectation, recorded in the roadmap, was that latency is dominated by llama.cpp,
Docling and I/O rather than by Node. The numbers below confirm it, by three to four orders of
magnitude.

### 2.1 The engine (from the measured settings, `research-known-good-settings.md`)

| Stage | Rate on the Arc A380 | Cost per token |
|---|---|---|
| prefill (reading the prompt) | 294–559 tok/s depending on model | 1.8–3.4 ms |
| decode (writing the reply) | 11–40 tok/s depending on model and MTP | 25–90 ms |

A 900-token prompt with a 24-tool catalogue costs the engine roughly 2–3 s before the first
word; a 300-token reply costs it 8–25 s.

### 2.2 Node, per chat request (`profile-hot-paths.cjs`, Node 26 on an Apple M2)

Everything in this table is the whole path through `handleRequest`: authentication, the
project lookup, system-prompt assembly, context preparation, the upstream call, SSE parsing
and re-emission to the browser.

| Request | Wall | CPU | CPU per token |
|---|---:|---:|---:|
| `POST /api/chat`, 1,000-token reply, upstream answers instantly | 6.9 ms | 12.3 ms | **12 µs** |
| same, with a 200-message history that triggers compaction | 5.0 ms | 8.9 ms | 9 µs |
| `POST /api/chat`, 100 tokens paced at 14 tok/s (the 9B model's decode rate) | 7,300 ms | 41 ms | 410 µs, of which the fake pacer is most |
| `GET /api/workspace` (session lookup in SQLite + JSON) | 0.16 ms | 0.20 ms | — |

So Node's share of a paced reply is **0.6 % of wall time** (41 ms of CPU across 7.3 s), and
on the target box (a slower CPU than the M2) it would be a small multiple of that, still
under 2 %. Per token, Node costs ~10 µs of CPU against the engine's 25–90 ms: roughly
**1 : 5,000**.

### 2.3 The pure hot paths, per call

| Hot path | Per call | When it runs |
|---|---:|---|
| SSE line reassembly + JSON parse (the stream loop body) | 0.6 µs / token | every token |
| `estimateToolTokens` over a 160-tool catalogue | 69 µs | per turn |
| `resolveTools`, 160 candidates against cap and budget | 93 µs | per turn (twice with routing) |
| `chat-context.measure`, 200 messages + 24 tools | 255 µs | per round |
| `mcp.convertTool` × 160 | 225 µs | per discovery (10-minute TTL) |
| `isWriteTool` × 160 (rebuilds the read-only set each call) | 1.4 ms per 160 = 9 µs each | per tool call |
| `rag.chunkText`, 406 KB / 40 pages | 3.1 ms | per document ingest |
| `reduceToolResult`, 173 KB / 500-record listing | **53 ms → 0.5 ms** (see §3) | per tool result |

Nothing else on the request path reaches a millisecond.

### 2.4 The other sidecars

- **Docling** (from `deployment.md`, measured on DaServer 2026-09-20): 1.9 s/page for native
  text, 3.4 s/page with OCR, 10.9 s/page for table-heavy pages. TableFormer is the cost, not
  Python. Node's part of an ingest — `chunkText` at 3 ms per 400 KB and one embedding call per
  chunk — is invisible next to it.
- **Embeddings** run on the CPU `embed` server (llama.cpp again); Node only batches the texts.
- **I/O**: project files and sources go through WebDAV to Nextcloud; each read is a network
  round trip of tens of milliseconds, again far above anything Node does with the bytes.

## 3. What was actually slow, and what was done about it

One thing was measurably slow inside Node, and it was an algorithm, not a language.
`reduceToolResult` — which turns a big JSON tool result into a header row plus records so a
listing fits the model's budget — fitted the listing to the cap by re-rendering every
surviving record on every step. A 500-record listing (a real Nextcloud shape) took 53 ms of
the reply's own time, per tool call. It now renders once and drops lines: **0.5 ms**, output
byte-identical on 168 synthetic listings against the previous module, with a regression test
pinning both the shape and the bound. That is a 100× gain from twenty lines of JavaScript;
a port to Rust of the quadratic version would have made it perhaps 10× faster and left the
algorithm wrong.

`isWriteTool` rebuilding the read-only set on every call (9 µs) is the next largest, and it
is not worth touching: a chat turn calls it a few dozen times at most.

## 4. Recommendation

**Do not port anything.** No Node path on the request path costs enough for a user to notice
a rewrite, in any language:

- A reply's latency is the engine's decode time, then its prefill time, then network round
  trips to Nextcloud and the sidecars. Node is ~0.6 % of a paced reply and would still be
  under ~2 % on the slower production CPU. Even a port that made Node's share **zero** would
  save the user under 50 ms on a 7-second reply.
- Document ingest is Docling's TableFormer and OCR; those are already native code behind a
  Python wrapper, and the wrapper's overhead is not the cost.
- The one measurable inefficiency was algorithmic and has been fixed in place, with parity
  tests. That is the pattern to keep: measure first, fix the algorithm, stay in the language
  the surrounding code and tests are in.

What *would* justify native code, and does not exist today:

- a CPU-bound transformation over large data on the request path (a tokenizer, a local
  reranker, image decoding) — today those live in the engine and the sidecars where they
  belong;
- a measured, user-visible number: "this step costs N ms of Node CPU per request and the
  user waits for it". The profiler is in `apps/web/scripts`; run it before any such claim.

On consolidating the *three* languages: the Python is all at the edges around Python
libraries and a vendored fork. Rewriting Diary Companion or the Model Loader in Node would
remove a language from the repo but not a millisecond from a request, and would give up
the libraries (Docling, Tesseract, the Hugging Face client) that are the reason those
services are Python. Not recommended either.

The useful consolidation is structural, and it is what this branch did instead: one Node
server split into modules with injected dependencies (`toolboxes.cjs`, `mcp-wiring.cjs`,
`chat.cjs`, each with a `routes/` file and tests that do not boot the server), so the code
that *is* on the request path is readable and measurable. `index.cjs` went from 4,241 to
2,787 lines in the process.

## 5. How to rerun

```sh
cd apps/web && node scripts/profile-hot-paths.cjs        # table
cd apps/web && node scripts/profile-hot-paths.cjs --json # machine-readable
```

The script boots the real `handleRequest` against a temporary data directory, completes
first-run setup with a synthetic administrator, and replaces `globalThis.fetch` with a fake
provider for the duration of the chat measurements. It deletes the data directory when done.
Numbers are per machine; the comparison to the engine holds on any of them.
