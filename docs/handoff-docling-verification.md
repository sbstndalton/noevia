# Handoff: verify, fix and deploy the Docling extraction backend

For an agent running **on the Mac** — the only machine that can reach all three of
Docker + the internet, `daserver` over SSH, and the live instance in a browser.

The work on `claude/ai-repos-token-optimization-xasjfx` was written in a sandboxed
cloud environment whose egress proxy blocks HuggingFace and cannot reach the Unraid
host. So the Docling sidecar **has never run**, and none of the three commits have been
checked against real data. `docs/agent-brief.md` is explicit that automated tests are
not sufficient evidence here — it records tests twice passing obviously broken code.

Scope agreed with the owner: **verify, fix and deploy**, including the live-instance
checks with a real write.

Read `AGENTS.md` and `docs/agent-brief.md` first; its "What NOT to do" and
"Verification expectations" sections bind this work. Never send prompts to the diary.

## What is on the branch

| Commit | What it is | Verified? |
|---|---|---|
| `b459208` | Six defect fixes: `internalCallProject` tenant-isolation reentrancy, non-UTF-8 text silently zeroed, MCP session leak, SSE request/response confusion, missing embedder timeout, context-ladder drift | Tests only |
| `3826578` | `rag.test.cjs` — 26 tests, mutation-checked | Tests only |
| `5ba71c5` | Opt-in Docling backend: `services/docling/`, `apps/web/server/docling.cjs`, `compose.docling.yaml` | **Docling itself never executed** |

## Order of work — stop at the first failure and record it

### 0. Probe before doing anything expensive

Never trust a doc for what is live, including this one:

```sh
ssh root@100.70.173.74 "readlink -f /mnt/docker/appdata/cowork/current; \
  docker ps --format '{{.Names}}\t{{.Image}}' | grep cowork"
```

Tailscale is `100.70.173.74`; `10.69.0.130` only resolves on the home LAN.

Then the question that decides the whole deploy shape — **can the box reach
HuggingFace?** `services/docling/Dockerfile` downloads ~1.6 GB of models at build time,
and `docs/deployment.md` builds on the box:

```sh
ssh root@100.70.173.74 "curl -sS -o /dev/null -w '%{http_code}\n' \
  https://huggingface.co/api/models/ds4sd/docling-models"
```

If that is not 200, do **not** start the build. Fall back to: build on the Mac,
`docker save | gzip`, `scp`, `docker load` on the box, and change the `docling`
service from `build:` to a pinned `image:`.

Expect the build to take far longer than the usual ~10 min in any case — CPU torch
plus the models over the Tailscale relay.

### 1. Selftest on the Mac first — cheapest place to find this is wrong

`services/docling/extract.py` was written against Docling's documented API and never
executed. `_convert` and `_pages_from` are the two functions likely to need fixing;
everything else is unit-tested with Docling stubbed.

```sh
docker compose -f compose.yaml -f compose.docling.yaml build docling
docker compose -f compose.yaml -f compose.docling.yaml run --rm \
  --entrypoint python docling selftest.py /path/to/sample.pdf
```

Run it against at least: a **multi-column PDF**, a **scanned PDF**, and an **.xlsx**.
Look at the output with your own eyes — reading order and pipe tables — rather than
inferring them from an exit code.

Record real **pages/sec** and **peak RSS**. The "~3.1 s/page" in
`services/docling/README.md` is Docling's own benchmark machine, not this hardware, and
`DOCLING_MEM_LIMIT` in `compose.docling.yaml` is a guess that should be replaced with a
measurement. A limit set too low shows up as the container being killed mid-conversion,
which looks like a retryable worker failure.

### 2. Fix and push

Fix what the selftest exposes. Add a test for anything found. Then the full suite:

```sh
make test          # 916 web + 313 diary + 9 docling + 8 tools
cd apps/web && npm run typecheck && npm run build && npm run lint:design
cd ../.. && make compose-check
docker compose -f compose.yaml -f compose.docling.yaml config --quiet
```

Push to `claude/ai-repos-token-optimization-xasjfx`. Do not open a PR.

### 3. Live-instance checks — before deploying anything

These verify the commits already pushed and are independent of Docling. The public URL
is **`https://cowork.daserver.work`** — the hostname kept its old name after the
rebrand, deliberately. `LEGACY_AUTH_COMPAT=false`, so there is no bearer-token path:
this needs a real authenticated browser session.

- A real chat with a Nextcloud toolbox enabled: one chip per tool **call**, named, with
  a result.
- A real **write** call: the approval card appears with full arguments and all three
  buttons; declining returns a readable message; "Allow for this chat" suppresses the
  next prompt in that chat but **not** in another. Write to a scratch note or folder and
  delete it afterwards.
- The MCP session `DELETE` added in `b459208`, against the real Nextcloud MCP server:
  confirm it is accepted, or that a 405 is handled without surfacing an error.
- Upload a Latin-1 `.txt` and confirm it now reads with the windows-1252 caveat rather
  than arriving empty.

The scripts in `apps/web/qa/` are **not** for this. They stand up a disposable server on
`localhost:31237` and their header says *"Never points at production."* Run them locally
as regression only.

### 4. Deploy — only if 1–3 pass

Follow `docs/deployment.md` exactly. Two traps specific to this change:

**`compose.docling.yaml` does not fit production.** It is a `docker compose -f a -f b`
overlay, which is right for a dev box and wrong for the Unraid Compose Manager plugin —
that drives project "Cowork" from a single `docker-compose.yml` plus one override for
the `lemonade_default` external network, and will not read a second `-f`. The `docling`
service and `DOCLING_BASE_URL` have to be hand-added.

**Three copies of the compose config exist and do not auto-sync.** A new env var must go
in all three:

1. repo `compose.yaml`
2. `deploy/examples/unraid-compose-manager.yml`
3. `/boot/config/plugins/compose.manager/projects/Cowork/docker-compose.yml` ← the live one

Back the live one up first:
`cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)`

Then the standard flow: `git archive` tarball → extract under `releases/<sha>/` → back
up `config/.env` → build → **verify the candidate before flipping the `current`
symlink** → `sed` `COWORK_VERSION` → bring up via
`/mnt/docker/appdata/cowork/tools/preflight/up.sh`, **not** the Compose Manager GUI,
which bypasses the preflight.

Rollback: repoint `current` and `COWORK_VERSION` at the previous SHA and re-run up with
`--no-build --wait`.

### 5. Record it

Append a dated section to `docs/deployment.md` in the style of the existing entries,
with the measured pages/sec, peak RSS and the memory limit actually used. Replace the
"not verified" caveat in `services/docling/README.md` with what was observed. Commit and
push — write findings into the repo rather than only replying, because the return
channel to the originating session is not guaranteed.

## What is deliberately not in scope

- **Charts.** Chart extraction loads `granite-vision-3.3-2b-chart2csv`, a 2B vision
  model — a different order of cost from the ~1.6 GB layout/table pair, and it would
  contend with llama.cpp for VRAM. Enabling it means revisiting `_build_converter` in
  `extract.py`, the memory limit, and where the job queues.
- **EasyOCR.** Docling's default OCR engine measures ~13 s/page on CPU. Tesseract is
  used instead and is already in the image.
- **The MCP SDK split** (`docs/agent-brief.md` audit verdict 2) — a separate piece of
  work, not started.

## Known gap left open

`apps/web/src/sources.ts` still lists `DOCUMENT_EXTENSIONS = ['.pdf']`. It feeds only a
rejection message in the text picker — the document upload path has no extension filter,
so the server decides and the feature is reachable — but the wording will be wrong for
Office files once Docling is on. Wants a server-driven list.
