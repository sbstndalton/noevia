# Sources

Every outside repository, product and document this project has leaned on, and what it was used
for — including what was read and rejected. Gathered 2026-09-20 from the docs, specs, research
notes, the code, and the session transcripts (which is where anything we only looked at in
conversation lives).

Three kinds of entry, kept apart on purpose:

- **Runs here** — code or a service that is part of the deployment.
- **Vendored** — copied into this repo (so it has to be licence-compatible and re-checked on update).
- **Read, not used** — a reference, a measurement someone else published, or an idea taken from a
  design; nothing of theirs ships.

## Engine, models and serving

| Source | Kind | Used for |
| --- | --- | --- |
| [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) | Runs here | The inference engine. Its server README, `common/arg.cpp`, `common/fit.cpp` and `tools/server/*.cpp` (pinned at build `b10920`) are the reference for every flag noevia sets, the model router's behaviour and the `--fit` work. Issue [#19818](https://github.com/ggml-org/llama.cpp/issues/19818) and discussion [#18839](https://github.com/ggml-org/llama.cpp/discussions/18839) back the context and MTP notes |
| [llama.cpp GGUF constants](https://github.com/ggml-org/llama.cpp/blob/master/gguf-py/gguf/constants.py) | Read | Reading GGUF headers for model details (`gguf-meta.cjs`) |
| [lemonade-sdk/lemonade](https://github.com/lemonade-sdk/lemonade) | Read | The previous backend. Its `runtime_config.cpp`, `llamacpp_server.cpp` and `auto_tune.h` (v10.8.0) informed the auto-tune and preset work after the move to direct llama.cpp; [docs](https://lemonade-server.ai/docs/guide/configuration/) |
| [scratchhax/model-loader](https://github.com/scratchhax/model-loader) | Runs here | The model-manager sidecar (`cowork-model-loader-1`), and the parity audit target for noevia's own model pages |
| [unslothai/unsloth](https://github.com/unslothai/unsloth) | Read | Quantisation guidance: [dynamic v2](https://unsloth.ai/blog/dynamic-v2), [dynamic 3.0 GGUFs](https://unsloth.ai/docs/basics/dynamic-3.0-ggufs), [Qwen3.5 GGUF benchmarks](https://unsloth.ai/docs/models/qwen3.5/gguf-benchmarks) |
| [Hugging Face GGUF docs](https://huggingface.co/docs/hub/gguf) and the Hub API | Runs here | Model search, downloads and cache layout in Discover |
| [vLLM](https://docs.vllm.ai/en/latest/getting_started/installation/gpu/) ([GGUF](https://docs.vllm.ai/en/v0.20.1/features/quantization/gguf/)), [ROCm inference](https://rocm.docs.amd.com/projects/ai-ecosystem/en/latest/inference/vllm.html), [llm-tracker AMD GPUs](https://llm-tracker.info/howto/AMD-GPUs) | Read | Backend-portability research; no migration ([spec](spec-backend-portability.md)) |

## Protocols and agent interfaces

| Source | Kind | Used for |
| --- | --- | --- |
| [Model Context Protocol](https://modelcontextprotocol.io) | Runs here | The tool protocol noevia speaks (`server/mcp.cjs`: streamable HTTP, `initialize`/`tools/list`/`tools/call`), its authorization spec (protected-resource metadata, PKCE, resource indicators) and the [public registry](https://registry.modelcontextprotocol.io) browsed in Plugins |
| [Agent Client Protocol](https://agentclientprotocol.com/overview/introduction) | Runs here | Code mode's harness transport ([agents](https://agentclientprotocol.com/get-started/agents.md), [tool calls](https://agentclientprotocol.com/protocol/v1/tool-calls.md), [streamable HTTP RFD](https://agentclientprotocol.com/rfds/streamable-http-websocket-transport.md)) |
| [OpenCode](https://opencode.ai) | Read | The ACP agent Code mode is built against; the live run is still pending |
| [cbcoutinho/nextcloud-mcp-server](https://github.com/cbcoutinho/nextcloud-mcp-server) | Runs here | The Nextcloud MCP server behind the Notes, Files, Calendar, Tasks, Talk and Mail toolboxes; its quirks (SSE-wrapped JSON-RPC, session header) shaped the client |
| [microsoft/playwright-mcp](https://github.com/microsoft/playwright-mcp) and [Playwright MCP security notes](https://qaskills.sh/blog/playwright-mcp-security-best-practices-2026) | Read | Browser-capability research; not adopted |
| [Anthropic Agent Skills](https://agentskills.io) and [Claude Code skills docs](https://code.claude.com/docs/en/skills) | Read | The `SKILL.md` format noevia's instruction skills follow |
| [anthropics/skills](https://github.com/anthropics/skills) | Read | The skills catalogue Plugins browses and installs from (one `SKILL.md` per skill, fetched on request) |

## Design references

| Source | Kind | Used for |
| --- | --- | --- |
| [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines) ([materials](https://developer.apple.com/design/human-interface-guidelines/materials)) | Read | Touch targets, legibility, materials and motion throughout the UI overhaul |
| [Material 3](https://m3.material.io) | Read | The colour-role system behind the tokens, and the Material mode in Settings → Appearance |
| [emilkowalski/skills](https://github.com/emilkowalski/skills) (MIT) | Read | Installed at user level; `apple-design`, `emil-design-eng`, `animate`, `mobile-native` guide motion and polish work |
| [pbakaus/impeccable](https://github.com/pbakaus/impeccable) | Read | Deterministic design-rule check (D4), run against `apps/web/src` |
| [justinwetch/HIGAgentSkills](https://github.com/justinwetch/HIGAgentSkills), [aka-kika/akakika-skills](https://github.com/aka-kika/akakika-skills), [Appllama/appllama-skills](https://github.com/Appllama/appllama-skills), [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | Read | Patterns and checklists consulted during the UI passes |
| [Ramps Studio](https://www.ramps.studio/), [zoxilsi/studio](https://github.com/zoxilsi/studio) ([site](https://studio.zoxilsi.cc/)), [AetherCSS](https://aethercss.lovable.app), [nikdelvin/liquid-glass](https://github.com/nikdelvin/liquid-glass), [CSS liquid glass roundup](https://freefrontend.com/css-liquid-glass/) | Read | Visual character: ramps, glass and the four materials. None of their code ships; `public/glass.js` is noevia's own |
| `ui mockups/inspiration/` (in this repo) | Read | The merged screenshots and descriptions the overhaul's architecture came from |

## Documents, files and storage

| Source | Kind | Used for |
| --- | --- | --- |
| [Docling](https://github.com/docling-project/docling) and [ds4sd/docling-models](https://huggingface.co/api/models/ds4sd/docling-models) | Runs here (opt-in) | The layout/table extraction sidecar (`services/docling`, `server/docling.cjs`), layout + TableFormer only |
| [OCRmyPDF](https://ocrmypdf.readthedocs.io/en/stable/cookbook.html) ([advanced](https://ocrmypdf.readthedocs.io/en/stable/advanced.html)) and [Tesseract](https://tesseract-ocr.github.io/tessdoc/ImproveQuality.html) | Runs here | The OCR sidecar and its quality settings |
| [unpdf](https://github.com/unjs/unpdf) | Vendored (dependency) | Text extraction from PDFs in the web server |
| [Nextcloud](https://docs.nextcloud.com/server/latest/admin_manual/configuration_files/external_storage_configuration_gui.html) ([reverse proxy](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/reverse_proxy_configuration.html), [macOS VFS](https://docs.nextcloud.com/server/stable/user_manual/en/desktop/macosvfs.html)), [nextcloud/notify_push](https://github.com/nextcloud/notify_push) | Runs here | Diary storage over WebDAV, the AIO deployment beside noevia, and live-update research |
| [RFC 4918 (WebDAV)](https://www.rfc-editor.org/info/rfc4918/) | Read | The DAV contract for rename, delete, copy and locks ([docs/dav.md](dav.md)) |
| [Samba SMB2 leases](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html#SMB2LEASES), [SQLite over a network](https://www.sqlite.org/useovernet.html) | Read | The SMB pilot and why the Diary index stays local ([spec](spec-diary-smb.md)) |
| [rclone](https://rclone.org) | Retired | Host-side mirror of the encrypted backup store, replaced by noevia's own Google Drive upload |
| [Google Drive API](https://developers.google.com/drive/api/guides/about-sdk) (device flow, `drive.file`) | Runs here | Off-site backups and the Drive connector |
| [Kiwix](https://kiwix.org) / `kiwix-serve` with `wikipedia_en_all_nopic` | Runs here | The offline Wikipedia toolbox (D9) |
| [Moodiary](https://docs.moodiary.net/guide/) | Read | Diary product reference |
| [File System Access API](https://developer.chrome.com/docs/capabilities/web-apis/file-system-access) | Read | Considered for the Diary workspace; not adopted |

## Libraries in the app

| Source | Kind | Used for |
| --- | --- | --- |
| [React](https://react.dev) + [Vite](https://github.com/vitejs/vite) + TypeScript | Vendored (dependency) | The web client and its build |
| [SimpleWebAuthn](https://simplewebauthn.dev) (browser and server) | Vendored (dependency) | Passkeys |
| [@node-rs/argon2](https://github.com/napi-rs/node-rs) | Vendored (dependency) | Password hashing |
| [better-sqlite3](https://github.com/WiseLibs/better-sqlite3) + [sqlite-vec](https://github.com/asg017/sqlite-vec) | Vendored (dependency) | The auth/settings database and vector search for project files |
| [Lucide](https://lucide.dev) | Vendored (SVG paths) | Every icon in the app; paths are copied into `src/components/icons/`, no CDN |
| [Playwright](https://playwright.dev) | Read (dev only) | The QA suites; the runtime is not installed in the repo |

## Networking and the box

| Source | Kind | Used for |
| --- | --- | --- |
| [Tailscale](https://tailscale.com) | Runs here | Remote access to DaServer |
| [Headscale](https://headscale.net) and [NetBird](https://netbird.io) | Read | Remote-access alternatives; [research](research-remote-access.md) says don't migrate |
| [Unraid](https://docs.unraid.net) Compose Manager and the appdata backup plugin | Runs here | How noevia is deployed and backed up |
| [canirun.ai](https://github.com/midudev/canirun.ai) ([models](https://github.com/midudev/canirun.ai/blob/main/packages/models/src/index.ts), [compatibility](https://github.com/midudev/canirun.ai/blob/main/packages/compatibility/src/index.ts)) | Read | Fit estimates: how someone else judges whether a model runs on given hardware |

## Web search and offline reference

| Source | Kind | Used for |
| --- | --- | --- |
| [Tavily](https://docs.tavily.com/) (`mcp.tavily.com`) | Runs here | The web-search and web-crawl toolboxes, and the search step in deep research |
| [Kiwix ZIM downloads](https://download.kiwix.org/zim/wikipedia/) | Runs here | `wikipedia_en_all_nopic_2026-06` behind the offline Wikipedia toolbox |

## Looked at, not adopted

Gathered from the session transcripts, so the record includes what was read and rejected. None
of this ships; each line says what it was weighed for.

**Other ways to serve models** — [ollama/ollama](https://github.com/ollama/ollama),
[vllm-project/vllm](https://github.com/vllm-project/vllm),
[LostRuins/koboldcpp](https://github.com/LostRuins/koboldcpp),
[mostlygeek/llama-swap](https://github.com/mostlygeek/llama-swap),
[danveloper/flash-moe](https://github.com/danveloper/flash-moe),
[RaymondHuang210129/llama.cpp-adaptive-kv-streaming](https://github.com/RaymondHuang210129/llama.cpp-adaptive-kv-streaming),
[ROCm/ROCm](https://github.com/ROCm/ROCm), and the Lemonade forks. Weighed while deciding to run
llama.cpp directly and how to schedule one GPU; [vLLM vs Ollama](https://tech-insider.org/vllm-vs-ollama-2026/)
and the local-inference write-ups on dev.to
([Gemma 4 on a Ryzen mini PC](https://dev.to/hrodrig/21-toks-gemma-4-on-a-ryzen-mini-pc-llamacpp-vulkan-and-the-messy-truth-about-local-chat-m82),
[Lemonade v10.3](https://dev.to/arshtechpro/lemonade-v103-run-local-llms-image-gen-and-speech-on-your-own-gpu-for-free-29ob),
[Windows vs Linux VRAM limits](https://dev.to/lanternproton/windows-vs-linux-for-local-ai-my-radeon-890m-has-96gb-of-ram-but-windows-only-lets-me-use-35gb-39ln))
came from the same reading.

**Hardware comparisons** — [NotebookCheck GPU pages](https://www.notebookcheck.net/Radeon-780M-vs-Radeon-890M_11564_12524.247598.0.html)
for the iGPU generations, and r/LocalLLM, r/IntelArc and r/AI_Agents threads on VRAM, vision
models and [how many tools a model can be given](https://www.reddit.com/r/AI_Agents/comments/1lwxh4r/what_is_the_maximum_number_of_tools_that_can_be/) —
that last one informed the tool-routing work.

**Agent harnesses and protocols** — [zed-industries/claude-agent-acp](https://github.com/zed-industries/claude-agent-acp),
[agentclientprotocol/codex-acp](https://github.com/agentclientprotocol/codex-acp),
[svkozak/pi-acp](https://github.com/svkozak/pi-acp),
[deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness),
[mufasadb/ai-lego-bricks](https://github.com/mufasadb/ai-lego-bricks),
[omnigent-ai/omnigent](https://github.com/omnigent-ai/omnigent). Read while choosing ACP and
OpenCode for Code mode.

**Browser and computer use** — [browser-use/browser-use](https://github.com/browser-use/browser-use),
[trycua/cua](https://github.com/trycua/cua),
[Angeluis001/playwright-mcp](https://github.com/Angeluis001/playwright-mcp) and the
[qaskills.sh Playwright MCP guides](https://qaskills.sh/blog/playwright-mcp-security-best-practices-2026).
Recorded as a later capability, not built.

**Skills and agent writing** — [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills),
[anthropics/claude-code](https://github.com/anthropics/claude-code),
[Red Hat: MCP servers vs skills](https://www.redhat.com/en/topics/ai/what-is-model-context-protocol-mcp)
([article](https://developers.redhat.com/articles/2026/01/08/building-effective-ai-agents-mcp),
[OpenCode piece](https://developers.redhat.com/articles/2026/04/22/opencode-model-neutral-ai-coding-assistant-openshift-dev-spaces)),
[agentskills.io best practices](https://agentskills.io/skill-creation/best-practices). Shaped
skill auto-loading and the split between skills and MCP servers.

**Nextcloud and identity** — [nextcloud/all-in-one](https://github.com/nextcloud/all-in-one),
[Rello/nextcloud-dynamic-mcp-server](https://github.com/Rello/nextcloud-dynamic-mcp-server),
and the Jellyfin SSO projects
([9p4](https://github.com/9p4/jellyfin-plugin-sso),
[registration portal](https://github.com/DevJernejTDO/Jellyfin-Registration-Portal),
[SSO UI](https://github.com/gergogyulai/jellyfin-sso-ui)) — single sign-on across the box, not
pursued.

**Front-end odds and ends** — [vercel/satori](https://github.com/vercel/satori),
[snapdom](https://github.com/zumerlab/snapdom), [resvg-js](https://github.com/yisibl/resvg-js)
(server-side rendering of images, not needed);
[Impeccable's own gallery](https://impeccable.style) for the design-rule work;
[this StackOverflow thread](https://stackoverflow.com/questions/38619762/how-to-prevent-ios-keyboard-from-pushing-the-view-off-screen-with-css-or-js)
for the iOS keyboard fix, which did ship.

**Products whose interfaces were studied** — ChatGPT and Claude's own apps (sidebar behaviour,
settings structure, the collapsed rail, the model and thinking menus), opened in the browser
during the UI passes at the user's request. Patterns only.

**Also seen** — [CodebuffAI/freebuff](https://github.com/CodebuffAI/freebuff) and its forks (the
report that prompted an audit), [leonickson1/Swiftlet](https://github.com/leonickson1/Swiftlet)
and [trycua/cua](https://github.com/trycua/cua) (noted as ideas to explore),
[siddsachar/row-bot](https://github.com/siddsachar/row-bot), [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd).

## Where the longer write-ups live

[research-findings-2026-09-17.md](research-findings-2026-09-17.md) ·
[research-known-good-settings.md](research-known-good-settings.md) ·
[research-master-container.md](research-master-container.md) ·
[research-references.md](research-references.md) ·
[research-remote-access.md](research-remote-access.md) ·
[spec-backend-portability.md](spec-backend-portability.md) ·
[spec-agent-execution.md](spec-agent-execution.md) ·
[dav.md](dav.md)

Adding a source: put it in the table it belongs to, say plainly what it was used for, and mark
whether anything of it ships. A link with no purpose beside it is not a source, it is a bookmark.
