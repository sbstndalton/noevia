# Software change history

These historical notes describe software changes and their recorded qualification limits.
Per-installation service inventories, real accounts, paths, backup receipts, and recovery
configuration are retained in a verified local archive excluded from version control.
The notes do not establish the current state of any running installation. Public history
prior to this cleanup can still contain the earlier text.

## Unreleased

OCR is native only (#1071). The OCR image runs `noevia-ocr` directly; the Python OCR server, its DOCX and PDF-reduction modules and the entrypoint that chose between them are deleted from noevia-services (the merged copy at services `bbed9b8` stays the test oracle). `compose.yaml` and the Unraid manager example pin `NOEVIA_OCR_IMPL: rust` instead of reading it from `.env`, because an image built before the retirement still defaults to Python; `.env.example` no longer lists the key. A leftover `NOEVIA_OCR_IMPL` or `DOCX_TEXT_IMPL` in an older `.env` is ignored; once the image carries a noevia-rs with the retirement, the server prints one warning per leftover key at startup. An installation that never selected `rust` moves from the Python OCR server to the native one with its next OCR image.

Chat-context routes (GET and POST `/api/chats/{id}/context`) are permanently Rust-owned (#1071, #1264). The web supervisor now requires the `rust-project-writes` front feature, no longer reads or forwards `NOEVIA_RUST_PROJECT_WRITES` (set to any value it only logs the retired-switch warning), and the release assembler refuses a noevia-rs that still gates chat context on that switch or a core whose `OWNED_ROUTES` omits either context method.

The release assembler (#2091, #2096) reads `routes.toml` as TOML rather than matching one spelling: an indented, tab-separated, single-quoted or trailing-comment `switch` is found, a comment that merely names a switch is not, and a route carrying any other switch is refused (deployment switches are retired, so none is expected). The idle-jobs test falls back to `shasum -a 256`. An unset `NOEVIA_FRONT` now defaults to `rust` in the web supervisor instead of the refused value `node` (#2094), and the release pins for web, core, services and rs moved to the permanent chat-context heads.

## Release web 1e632e54 - 2026-11-12 (web client only; noevia-web#122, #123, #124, #125; #2136, #2326, #2397, #2399, #2400, #2401, #2456, #2457, #2458, #2459, #2460, #2461)

Pins: web 1e632e54 (was 90d470d7), core cb2dea2d, rs d8874d7c, services 61d44d27 (all three unchanged). The previous release was 2406d67a. Only the web image is replaced.

What changed for you:
- Twelve interface fixes (noevia-web#122, #125). Models page: refusals with a known code read in the interface language (#2136), the tab strip fits at 375 px or scrolls with an edge fade and moves with the arrow, Home and End keys (#2459, #2460), and the reranker switch shows the effective state (#2397). The inference banner keeps its closing period with the Settings link (#2326). The chat/code switch no longer spills through the open sidebar header (#2461).
- Sidebar search refuses a query over 200 characters with a message and notes truncated results (#2399). The Settings detail panel draws no frame when focus moves in without a key press (#2401). Searching settings opens the single remaining section, or the first one if the open section is filtered out (#2458). The retention setting reads "Not loaded" instead of "Never" while it has not loaded (#2400).
- The Diary page says so when Diary is off for the account, or when it cannot be reached, instead of a blank area (#2456). "Set up later" on the passkey step is remembered for 30 days per browser (#2457).
- The Spaces and Coworkers area (noevia-web#123, #124) is in the client but stays hidden: the pinned server does not have its routes yet, so no entry appears and `/spaces` and `/coworkers` read as not found. It switches on with the release that carries those routes.

## Release (pending SHA) - 2026-11-12 (Coworkers and Spaces, phase 1; #2446, #2474, #2475, #2476)

Pins: web 51ceda61 (#126, #127), core 6c23568d (#355, #356, #357), rs 3c4a7e92 (#443-#448), services 61d44d27 (unchanged). `NOEVIA_SERVICES_RS_REF` and `NOEVIA_SERVICES_RS_SHA256` keep the sidecar images at rs d8874d7c: only the web image is replaced. The egress proxy Dockerfile follows the new rs pin but its running container is not rebuilt.

What changed for you:
- Coworkers and Spaces appear in the app: create Spaces with pages (autosave, conflict handling, search), and coworkers you grant Spaces to, whose proposed pages you review before saving (#2446, phase 1).
- Removing a source now asks first (#2475), the source hover card stays inside the window (#2476), and the sign-in wizard resumes where it stopped (#2474, partly; the rest is #2478).
- Not in phase 1: the event route, the coworker computer, connections and schedules.
- Rolling back to the previous image hides the area again and leaves the new files untouched. A coworker created in between leaves its hidden project in the old image's project list; delete the coworker before rolling back.

## Release 2406d67acad3e9261e8e12b471c10fe10107340f - 2026-11-11 (native owners: maintenance lease, code egress, workers; #2416, #2424, #2423, #2419, #2418, #2417, #2426, #2409, #2367, #2369, #2421, #2420, #2425, #2360, #2359, #2365)

Pins: web 90d470d7 (unchanged), core cb2dea2d, rs d8874d7c, services 61d44d27. The previous release was 758f2eb.

What changed for you: nothing you will see day to day. More of the server now runs in the native front:
- The Rust front is the single model-maintenance lease authority (#2420). Node keeps only the chat-admission latch.
- The code-egress issuer moved to the front. It adopts the previously published key, rotates it once immediately, and keeps the published shape (#2421).
- The embedding worker, the media/figure/document backfill and the emergency budget watch run in the native worker (#2365, #2416, #2367).
- These moved to the front as well: the change-journal and vault mirror, startup project migration, MCP discovery and status, the inference-machine registry, reranker settings, auto-roles writes and residual method/path fallbacks (#2418, #2417, #2423, #2424, #2426, #2409, #2419). The Diary tools overlay moved too (#2359, #2360).
- Chat journal activity and the framing-suggestion edge are answered natively (#2369).
- Release assembly shares the Rust capability checks that verify the shipped binary (#2425).

Qualification: the in-image tests passed 2207/2207. The synthetic qualification passed on attempt 2 of 3. Every failure along the way was a harness fault, not a product fault. Attempt 1 failed because the synthetic member id was not UUID-shaped. The earlier runs and two unofficial dry runs found three more:
- the loader stub had no benchmark progress route, so the new boot barrier of the sweep guard never lifted;
- a capability check raced the code client's reconnect after an egress restart;
- an issuer grant raced the front's control-ready after a web restart.

The rollback rehearsal passed on synthetic state. Known gap, filed as #2439: if the model loader is unreachable or does not answer ok at web start, chat and maintenance holds stay paused with no log line until it answers ok.

## Release 9375ce98e35abb1cef148c75835ad62b65de2448 - 2026-10-19 (native-service completion; #1318, #1071, #2027)

Core 1896db0 makes role-context, streamed JSON validation, presets, and relevant tool decisions unconditionally Rust-owned, and adds the bounded Rust workspace-claim helper called by Node while the authenticated account transaction is held (#2027). Services 2545ebc retires Diary's tenant selector while keeping its restart guard and nonce cache.

What changed for you: nothing you will see day to day.
These are bug fixes:
- Model deletion and model-file parsing keep the embedding hold and the admission permit until they finish, bounded by the route deadline (#1997, #1998).
- A benchmark waits for the chat engine to come back after its restart (#1940).
- The host's remote health probes name services by role and can use an optional key file (#1980).
Nothing on this server uses them: no `NOEVIA_REMOTE_*` key is set.

Candidates (`candidates.out`, `candidates-ml.out`):
- clean rust web: ready;
- leftover keys: ready, with retired-key warnings only;
- in-image tests: 173/173;
- isolated model-loader: 14 native features advertised, and updates and detail digests equal between the native parent and the Python child.

## Release 26160903 — 2026-10-17 10:29Z (web + model manager; #1318 draft heads + backends (dark), #1970, #1972, #1978, #1983, #1984, #1985, #1986, #1987, #1989, #1990, #1993, #1994, #1995, #1996)

What changed for you: in Models, you can now dismiss a finished auto-tune from the Recover card.
This is the web half of #1978 (web#91); a8121f10 shipped only the core half (core#182).
The rest is safety and memory work:
- Model deletion: a reserved model folder is released when a client drops or times out (#1983), and mixed-mode deletes are fixed (#1984, #1994).
- Hub lookups: the draft-heads read now uses at most ~100 MiB per lookup instead of 1-2 GiB (#1985, #1995), and the update check's listing is bounded (#1996, security).
- The GPU probe only execs into active backend containers (#1986).
- Native draft heads and backends (#1318) ship dark: `MODEL_MANAGER_DRAFT_HEADS_IMPL` and `MODEL_MANAGER_BACKENDS_IMPL` are `python`.
- The model-loader now runs with `TZ=UTC` (#1989).

Candidates (`candidates.out`, `candidates-ml.out`):
- clean rust web: ready;
- leftover keys: ready, with retired-key warnings only;
- in-image tests: 156/156;
- isolated model-loader: 14 native features advertised, the new switches `python` with confirmations 0, and updates and detail digests equal between the native parent and the Python child.

What changed for you: in Models, a saved idle-unload setting now shows a notice (#1976), and a failed auto-tune shows its failing phase with an admin Clear (#1977, #1978).
Model deletion is safer: the Python delete no longer falls back to a same-named model in another folder (#1964, a data-loss fix), and it refuses while a download is queued or running into that model's folder (#1966).
Native model deletion (#1318 slice 11) ships dark: `MODEL_MANAGER_MODEL_DELETE_IMPL=python`.

## Release f1ad65f4 — 2026-10-17 03:56Z (web + model manager; #1318 slices 9–10, #1957, #1953, #1962)

What changed for you: nothing visible. The model manager now has native code for the benchmark runner (#1318 slice 9) and the download job table (#1318 slice 10). Both stay off: `MODEL_MANAGER_BENCHMARK_RUNNER_IMPL` and `MODEL_MANAGER_DOWNLOADS_IMPL` are `python`, as are all other `MODEL_MANAGER_*_IMPL`. A leftover `MODEL_FILES_IMPL` is now only a "retired and ignored" notice (#1957). The web image adds the #1953 import/replace review fixes and the #1962 contract test.

## Release 6adf2033 — 2026-10-17 00:56Z (web + model manager; #1949, #1950, #1264, #1071, #1937, #1939, #1942, #1318)

Sign-in, the project routes and the project store are now always the native front's: `NOEVIA_RUST_AUTH`, `NOEVIA_RUST_PROJECTS` and `NOEVIA_RUST_PROJECT_STORE` are retired, and leftover values only warn.
The model manager's native parent is permanent.
Every #1318 switch stays `python`.

**Owner:** these retired keys are still in `.env` and only warn or do nothing: `NOEVIA_RUST_{AUTH,PROJECTS,PROJECT_STORE,USAGE,SAMPLING_SETTINGS,REASONING_SETTINGS,ROUTING_MODE,ROUTING_DEFAULT,STATS,CHATGPT_STATUS,STORAGE_READS,STORAGE_BROWSE,EXPORT}`, `MODEL_MANAGER_IMPL` and `MODEL_FILES_IMPL`.

## Release 8207bb96 and the project store flip — 2026-10-16 20:25Z / 20:39Z (web + model manager; #1264, #1934, #1922, #1906, #1908, #1902, #1318)

What changed for you: nothing visible.
Saves to the project list and the free-chat list now go through the native front's internal project store instead of Node writing the files under a `flock` (#1264).
Every other new switch ships off.

## Switch flips on 7ac94a2f — 2026-10-16 08:52Z–09:17Z (web: 4 on; model manager: 1 rolled back; #1071, #1368, #1373, #1315, #1318)

What changed for you: nothing visible.
The ChatGPT connection status, connected-storage metadata, the connected-storage list and text read, and the conversation export are now answered by the native front.

Every gate: jobs idle, llama idle 0, no autotune process (last job state `failed`, not running).

| Export | Node serves (switch 0) | Native serves (switch 1) |
| --- | --- | --- |
| 300 chats × 30 messages, ZIP 26,837,251 bytes (identical size) | Node 141 → 180 MiB (+39); cgroup peak 159 → 312 MiB | front 53 → 76 MiB (+23); cgroup peak 154 → 255 MiB |
| 700 chats × 30 messages, ZIP 62,620,451 bytes (identical size) | Node 135 → 270 MiB (+135); cgroup peak 180 → 462 MiB | front 53 → 114 MiB (+61); cgroup peak 179 → 378 MiB |
| 1000 chats × 30 messages (over the 64 MB cap) | 413 JSON | 413 JSON, front peak +66 MiB |

Native peak is lower than Node's in every case and far from the 8 GiB MemAvailable floor.

## Release 7ac94a2f — 2026-10-16 08:28Z (web + model manager; #1863, #1880, #1901, #1751, #1264 slice 1 dark)

What changed for you: chat models now unload after 30 minutes idle (was 15), and an administrator can change that in Settings → Models → Performance (#1863). A chat role's model can be measured (auto-tuned) on its own Inference machine from Settings (#1880). Automatic routing sends short simple asks (count, list, a joke, a short poem or story) to Fast without a decision call, and Kev's route labels name simple short tasks as Fast (#1901, core#168). A decision call that hits a reset or refused connection is retried once within the deadline (#1751). Native project chat-context routes are shipped behind the new default-off `NOEVIA_RUST_PROJECT_WRITES` switch, which is off (#1264 slice 1).

## Release 3b23d181 — 2026-10-16 03:54Z (web only; #1894, #1895, #1896)

What changed for you: the Models page's local-engine health check now asks the model manager's `/api/v1/health` (#1894). When a model change is still finishing, a chat waits up to 3 s for it and then gets a retryable "still finishing" answer instead of an error; the client retries once (#1896). The composer pill is fixed (#1895).

## Release 88adc3a1 — 2026-10-16 02:54Z (web + model manager; #1886, #1891, #1889, #1318)

What changed for you: when a large PDF's storage read fails during a refresh, the source reopens from the copy noevia already stored, and every sync logs one `[sources] sync` count line (#1891). Opening a project no longer saves its settings when nothing changed (#1886). The model manager can serve model detail natively (#1318, #1889), but that is switched off.

## Release 092bc8e0 — 2026-10-16 01:21Z (web only; core#158, #1885)

**Post-checks.** Healthy, restarts 0, PID 1 `docker-init`; `/api/ready` `092bc8e0` on loopback and public; signed-out `/api/projects` and `/api/models/reranker` 401 on both; served dist equals image dist (145 files; `index.html`, `manifest.webmanifest`, `version.json` and 16 hashed asset names differ from `eb5a4523` although web is unchanged); allow-listed switches identical apart from `COWORK_VERSION`; embedding service 200 and `embed:8080/health` 200; Kev decision 0.33 s; decision config unchanged; project counts unchanged; preflight 0 missing keys. Only `cowork-web-1` changed id.

**Watch (20 min, read-only).** Web and OCR healthy, 0 restarts, 0 OOM, 0 web error/warn lines, OCR memory 27 MiB. The one record carrying the #1885 error (9 of 9 pages `ocr-needed`) was not processed: no `[documents]` or `[large-document-lock]` lines and no OCR `/extract` requests. The reopen happens on the next source sync/refresh.

## Release eb5a4523 — 2026-10-16 00:19Z (whole stack: web + OCR + Docling; #1854, #1867, #1868, #1869, #1876, #1878, #1879, #1881, #1882, #1853)

What changed for you: very long documents keep becoming searchable after the first sync: a background pass, 90 s after start and then every 5 minutes, embeds the rest of each long document within an hourly budget, and pauses whenever a chat or Diary turn runs (#1868, #1869, #1881). Large PDFs reach the OCR and Docling sidecars in page ranges of up to 96 MiB, stay within the sync's OCR budget, and pages left incomplete are retried at 400 dpi (#1867, #1882). Inference machines show per-machine measurements (#1854). The code relay is hardened (#1876), the Code pipeline and sandbox follow the Code role to its machine (#1853), and logs and the source count are fixed (#1878, #1879).

## Release 9b238027 — 2026-10-15 21:48Z (web + model manager; #1861, #1862, #1863, #1864, #1865, #1866, #1871, #1872, #1318)

What changed for you: Kev's health is checked at `/v1/models`, and a saved ChatGPT model the account no longer offers is flagged (#1861, #1862). Automatic routing pre-loads the shared Fast/Smart model while it decides, and cancels a wrong guess (#1863). Large PDFs are read in page ranges, up to 96 MiB per read, one large read at a time. Degraded pages are retried with OCR, at most 40 OCR pages per sync (#1864, #1865, #1871). The large-document lock has an acquire timeout (#1872). Citations show page numbers (#1866). Sources show where a PDF stopped and each page's OCR retry outcome. The model manager can serve model updates natively (#1318), but that is switched off.

## Release 88827187 — 2026-10-15 19:00Z (web only; Inference machines for every part, health probes with reasons; #1840, #1841, #1844, #1847, #1849, #1850, #1851, #1855, #1856, #1845, #1857, #1858, #1843)

What changed for you: OCR, Docling, sensitivity checks, chat roles, Manual, the router and Deep Research can each be assigned to an Inference machine, with tool limits per machine (#1841, #1844, #1847, #1840, #1851, #1849, #1850, #1855). Each chat turn checks that the assigned machine actually serves the model (#1851). Machine health shows a reason, and Kev answering 401 counts as up but needing sign-in (#1856). Routing shows a refresh note (#1857), and indexing shows a toast (#1858).

## Release a5d9cbf2 — 2026-10-15 16:31Z (whole stack: web + model manager + Diary overlay; #1576, #1638, #1315, #1368, #1373, #1318, #1826)

What changed for you: there is one chat surface now. Every project takes chats, and Task is a per-send choice in the composer (#1576, #1839). Settings gains an Inference machines page that lists machines and which part of noevia each one serves (#1638). The page also fixes refresh issues (#1814, #1828, #1829), shows the model in the inspector, and adds a Creative note. The native Rust routes for export (#1315), storage reads and browse (#1368) and ChatGPT status (#1373) ship in the image but stay switched off. The model manager can serve its settings natively (#1318), also switched off.

## Release da2e18b9 — 2026-10-15 11:28Z (whole stack: web + model manager + Diary overlay; #1806, #1665, #1666, #1667, #982, #1783)

What changed for you: a project's source text now lives in its own files instead of inside projects.json, so projects can hold up to 1000 sources, 200 documents and 12 images (#1806). A source whose text has gone missing says so in Sources (#1815). The Models page gains the reranker switch and choice, a decision model choice and a Creative role (#1665, #1666, #1667). The model manager no longer prunes operator `.bak` files next to `models.ini` (#1783). The Diary image now carries the Rust workspace ZIP gate (#982), still switched off.

Web (to 3b978351). The old image reads source text only inline, so put it back first, with web (and so the Rust front) stopped:

## Release 3b978351 — 2026-10-15 08:21Z (web; folder import; #1805, #1806)

What changed for you: a project's Sources can take a whole folder. "Add folder" and dropping a folder onto Sources import every file in it, subfolders included, and an attached storage folder is now read recursively, so files in its subfolders become sources too (#1805). Limits are unchanged: 60 sources, 60 documents and 12 images per project, and at most 100 MB per folder import.

Web (to fee7d681):

## Release fee7d681 — 2026-10-15 06:25Z (web; gte reranker on 06:28Z; #1761, #1765, #1795, #1796, #1784, #1785, #1788, #1665)

What changed for you: project knowledge search now reorders its passages with the gte reranker before the model reads them (#1665), so the most relevant passage is more often first. A model that is unloaded after idling now reads "Sleeping" instead of looking broken, and a model that is set up but not loaded reads "Configured". The Models page can reset the decision model and shows Decision and Sensitivity rows. A chat gets a title after any completed reply, not only the first, with at most 3 tries. Fast turns on the local engine run without thinking. The "Stopped" note shows only for stopped or clean replies, and the app adopts the generated title against the first message.

Reranker off (keeps the release):

Web (to b84758dc):

b84758dc's core has no TEI backend, so turn the reranker off first.

## Release b84758dc — 2026-10-15 04:51Z (web; #1784–#1793, #1797)

What changed for you: a stopped answer is now marked "Stopped" instead of looking complete (#1784), and the last answer line no longer sits under "Jump to latest" while streaming (#1789). Chat titles follow the conversation instead of staying on the first greeting, and the app adopts the new title (#1785). The first reply of a new chat stops showing as streaming when it is done, without waiting up to 8 s for the title (#1797). A request that never mentions storage no longer triggers an unrelated Drive search (#1786). The High effort hint no longer leaks scratch reasoning into the reply (#1787), and Fast lowers only the default effort, so a greeting no longer spends seconds thinking (#1788). An attached image no longer hangs at "Reading image sources": describing it skips thinking and gives up after 120 s (#1790). A harmless image is no longer flagged as a password or key (#1791). Images count toward the context and are handled by compaction (#1792), and answers from a project knowledge file show their source chips again (#1793).

Web (to c453e9ec):

## Release c453e9ec — 2026-10-15 02:42Z (web; #1776, #1778, #1777; #1731 preset)

What changed for you: opening projects and documents no longer creates search indexes as a side effect (#1776). When a new chat's framing settles on the kind of chat early, it now stops waiting on a hung embedding, and a failed project or tag lookup keeps the kind it already found (#1778). The web container now runs under Docker's init, so it stops cleanly on restart (#1777). The chat model list no longer carries a preset for a model file that does not exist (#1731).

Web (to 2f583a82, without init):

## Release 2f583a82 — 2026-10-15 01:33Z / 01:35Z (web; embed `--models-max 3`; #1770, #1771, #1772, #1775)

What changed for you: PDFs that were added before multimodal RAG was turned on now get their figures read once (#1770). The image backfill no longer creates empty indexes for chat-context projects (#1771). An image pass no longer pushes a text embedding model out of the embeddings router (#1772). A new chat's framing now asks what kind of chat it is first (#1775).

Web (to 4a7f9d0b):

embed (to `--models-max 2`):

## Diary overlay 9d308b22 — 2026-10-15 00:56Z (Diary only; #1768, #1759, #1766 complete)

What changed for you: the Diary's search index is complete again. The 12 long Diary sections that could not be embedded are now embedded with EmbeddingGemma 2 (53 of 53).

## Release 4a7f9d0b and multimodal RAG on — 2026-10-15 00:17Z / 00:20Z / 00:21Z / 00:22Z (web + multimodal enable: model-loader, embed, web; #1762, #1726)

What changed for you: a question about a project can now find its pictures, not just its text. Every image in a project gets one image vector from EmbeddingGemma 2. Retrieved images go to a chat model that can see them, and a model that can't see them gets the image's text or a cached caption. Diary images are never embedded (#1736). Separately, noevia now warns when an embedding address is public (#1762).

Multimodal off, in this order:

The override lines can stay, since they default to `0`. With the flag off, stored image vectors are ignored and kept.

Never copy a `.env.bak.*` file back wholesale.

## Diary overlay d3474b3c and Kev cutover (limited) — 2026-10-15 00:01Z / 00:04Z / 00:12Z (Diary + new cowork-kev + web env; #1759, #1766, #1639)

What changed for you: the Diary now splits a chunk that the embedding server refuses as too long, instead of leaving it without a vector (#1759, #1766).
The 12 long Diary chunks still need one re-index pass before the next embedding model covers all 53.
Route, tool gate, step supervision, chat framing and the load advisor are now decided by the decision model.
Sensitivity stays on the sensitivity model.

### Diary overlay

- 36 base layers identical, plus 2 new layers;
- `/app/agent` equals the services tree (33 files);
- the tenant-assertion binary is byte-identical, and its self-test prints `ok`;
- the imports load.

### Kev cutover (docs/kev-cutover.md)

Preconditions all held. Laya baseline (counts only, 2026-09-22T15:16Z to 2026-10-14T10:28Z, 1185 entries):

- supervise S 92, escalations E 10, weak-escalate W 1, benign pauses B 0 (none marked yet);
- route N 304 / 40 failures; tool gate N 388 / 20; supervise 18 failures; sensitivity N 136 / 101.

After the re-save, the synthetic post-checks (first line `shared kev-0.8b kev sensitivity laya laya`):

| Purpose | Answer | Model | Time |
| --- | --- | --- | --- |
| route | smart | kev-0.8b | 480 ms |
| tool gate | none | kev-0.8b | 463 ms |
| chat framing | idea | kev-0.8b | 431 ms |
| load advisor | unknown | kev-0.8b | 339 ms |
| step supervision | verify | kev-0.8b | 597 ms |
| sensitivity | not_sensitive | convaiinnovations/laya | 600 ms |

Kev, Laya and web are healthy with 0 restarts and `OOMKilled=false`. `cowork_laya` is internal, and the web log has 0 "names no known decision model" lines. Kev memory: process VmHWM 4.41 GiB, and the cgroup peak reached its 5 GiB cap (page cache included, as in the eval). Only `cowork-web-1` changed id, and `cowork-kev` is new.

## Release a6de6203 — 2026-10-14 19:33Z / 19:40Z / 19:50Z (web + model manager + chat-engine restart; #1747 idle unload live)

The next message wakes it in about 12–15 seconds, and noevia keeps treating a sleeping model as available.
Vision descriptions now use only the default provider, a missing sensitivity key logs a startup warning, and service addresses (embedding, rerank, System One) follow one on-this-network rule, checked when they connect.

## EmbeddingGemma 2 switch: preparation — 2026-10-14 17:59Z (embed memory limit live; model not switched yet)

What changed for you: nothing visible.
Search still uses the current embedding model.
The embedding service can now hold the current and the next embedding model together, which the owner-approved switch (#1636) needs.
The switch itself is not done yet.

Then send one synthetic embedding to `http://embed:8080/v1/embeddings` from web to load nomic at once (the model manager's watcher also re-warms it within about 30 s).

## Release d37a16e5 — 2026-10-14 16:45Z / 17:37Z / 17:42Z (whole stack: web + model manager + document extraction)

What changed for you: decision prompts now use the wording tuned for the decision model, follow the configured decision model, and keep the Code route label (#1639, #1739, #1740).
Multimodal RAG (#1726) is shipped in web, the model manager and document extraction but stays off (`NOEVIA_MULTIMODAL_RAG` is not set).
Document extraction can now return a document's figures and mark OCR-read pages, but only when it is asked to.

## llama.cpp image b11610 on embed and the chat engine — 2026-10-14 14:22Z / 14:32Z (live)

What changed for you: nothing visible.
Both llama.cpp containers now run build 11610 instead of 10920 (owner: "approve the llama.cpp update, I can't imagine it would break anything in any other capacity honestly").
The switch needs its own owner approval.

## Release a03fbc63 — 2026-10-14 14:09Z (web + model manager)

What changed for you: the New chat button works again (#1716). After the embedding container restarts, the model manager now loads the embedding model again by itself (#1717), so search does not wait for a first request.

## Diary switch TENANT_ASSERTION_IMPL=rust — 2026-10-14 13:52Z (Diary only)

What changed for you: nothing visible.
The Diary now checks every web request's tenant signature twice, once in Python and once in the Rust `tenant-assertion` leaf.

## Decision service cutover 0.3.5-noevia5 — 2026-10-14 15:01Z (decision service only)

What changed for you: nothing visible.
The decision service now runs the image with the late-answer guards (#1074) and the native front (#1326).

Then check: image `cowork-laya:0.3.5-noevia4`, healthy, restarts 0, a synthetic `/v1/decisions` returns `selected` in the options.

## Document extraction native mode on — 2026-10-14 13:42Z (`NOEVIA_DOCLING_IMPL=rust`)

What changed for you: nothing visible.
Document extraction now goes through the native `noevia-docling` server (#1322), with the same results: the synthetic PDF reads correctly and Markdown still gets the 415 "unsupported" answer.

## Document extraction cutover 785643f4 — 2026-10-14 13:30Z (native mode off)

What changed for you: Markdown files no longer go to Docling. They now get a clear "unsupported" answer (415) instead of the misleading "processing limits" error (#1711). PDF and other document extraction works as before. Native Docling stays off: `NOEVIA_DOCLING_IMPL` is not set, so the service runs `python server.py` (#1322, owner switch).

Note that rolling back brings back the #1711 `.md` 422.

## Release 785643f4 — 2026-10-14 13:04-13:20Z (web; model manager Rust front; settings-driven embedding live; Docling candidate built)

What changed for you:
- Cloud chats only see history from turns that went to that route (#1703).
- Summaries name only tools that exist (#1704).
- Performance → Memory budget shows estimates again, as do Will it fit?, the load-budget guard and calibration starting settings (#1708).
- A fetch where every URL failed shows a red ✕ (#1707).
- Projects shows a loading skeleton and an error with Retry (#1709).

Behind the scenes:
- The model manager runs its Rust front (owner-approved, #1689).
- The embedding service is now driven by Settings (#1668). It still serves the same model, nomic-embed-text-v1, so retrieval did not change and nothing was re-indexed.
- No model was switched, turned off, loaded beyond nomic, or deleted.
- No chat, tune or benchmark was run.

## Docling cutover attempt fbb960dd — 2026-10-14 10:45Z (rolled back; no live change)

What changed for you: nothing.
Document extraction stays on `cowork-docling:f6885a55`.
The same check also fails on the existing image, so this is filed as #1711.

## Release fbb960dd — 2026-10-14 (tool-call follow-ups, Models page prune, embedding warm-up; web + model manager)

What changed for you: an Auto (Fast) follow-up turn keeps its web search tools again (#1692), and a Code route turn that only produced reasoning now gets a final-answer round (#1693).
Tool calls that returned an error, including plain-text `ERROR:` results, no longer show a green check (#1694, #1699).
Deleting a model now reloads the engine's preset list, and the Models page removes leftover presets for files that are gone when an admin opens it (#1695).
It refuses to remove anything if the folder scan is empty or more than half would go (#1698).
The model manager has the rs#104 embedding warm-up fixes (#1682, #1685, #1696); it still runs the python front, so the #1668 embedding service stays inactive.
No chat, model load, switch, delete, prune, tune or benchmark was run to test this.

## Release 20b07d3f — 2026-10-14 (chat, UI and backend batches, embedding guards; web + model manager + Diary overlay)

What changed for you: the chat batch (core#100) retries a turn that came back with reasoning only or that promised a tool call without making one (#1477, #1552, #1587, #1592, #1604). Engine rows in Settings no longer stay on "Checking", and raw restart errors are now translated (#1545). The Features page has plain text for the Preview and Offline Wikipedia rows (#1580). The Models page now refuses to switch to an embedding model that the embeddings server doesn't serve (core#97). Code for the settings-driven embedding service (#1668) is included but **not active** (see Model manager below). Embeddings still run on `nomic-embed-text-v1`, unchanged. The Diary companion now has the #1636 per-model vector slots, with nomic as the active slot, so nothing was re-indexed. No chat, Diary message, model load, switch, delete, tune or benchmark was run to test this.

## Release d119c502 — 2026-10-14 (Models page overhaul, upload fixes)

What changed for you: the Models page was rebuilt around what each model is assigned to (#1660-#1663): deleting a model now also removes its preset, so it no longer lingers as "File missing" (#1661), and the new assignments overview shows which model serves each role (#1662). Uploads got follow-up fixes, and files orphaned by a failed upload are cleaned up (#1653, #1664). Members no longer see environment variable names (#1656). The statistics route got small fixes (#1654). All Rust switches stay on, as before. No chat, Diary message, model load, delete, tune or benchmark was run to test this.

## Release 2461e63b — 2026-10-14 (core main released, #1647 hold lifted; Rust stats and routing-default built in)

What changed for you: the hybrid sensitivity check now reads the decision service's confidence correctly (#1640), and hybrid routing can only reach a cloud model through a sensitivity model that passed qualification (#1647).
No model is qualified yet, so **hybrid stays local** until one is.
Uploading a file with a name that is already taken no longer silently replaces the project source (#1454), and renaming a project moves its storage folder (#1458).
Date answers get the ISO week right (#1603).
Signing in as another user in a different tab no longer leaves this tab showing the old account's state (#1643).
The metrics and routing popovers no longer overlap (#1649).
The embedding settings gained profiles (#1636); the default stays `nomic-v1`, nothing was re-indexed and `embed-next` was not started.
The Rust front now includes the routing-default and engine statistics routes (`rust-routing-default`, `rust-stats`), but their switches stay off.
No chat, Diary message, model load, tune or benchmark was run to test this.

## Release 1aed463c — 2026-10-13 (UI batch, Diary out of the page, 404 shell)

What changed for you: the Diary is no longer kept hidden in the page behind the other views, so its text cannot leak into a chat tab (#1635).
The Nextcloud connector tile and the empty-state icons now carry the two-tone accent, and the row you are on is fully accented (#1623 follow-ups).
Opening a page that does not exist now shows the app with a "not found" instead of a bare error (#1620).
The Rust projects store now skips malformed file entries the way the Node server does (#1621); it is only used once `NOEVIA_RUST_PROJECTS` is turned on, which it is not.
No chat, Diary message, model load, tune or benchmark was run to test this.

**Held.** noevia-core main (`f10e5a9`, core#85 #1640 and later) is not in this release: release hold #1647.

## Release d907438b — 2026-10-13 (two-tone icons, visual fixes, Automatic tools)

What changed for you: decorative icons now have a two-tone accent in the theme colour, while icons you can click stay one colour (#1623).
Project names on cards no longer break through the middle of a hyphenated name (#1542), and Restore on an archived project restores it instead of opening it (#1626).
In Automatic tools mode, a message that needs the web or your Nextcloud now gets Web search and Nextcloud offered to the model, so it can look things up instead of saying it cannot browse (#1550).
No chat, Diary message, model load, tune or benchmark was run to test this.

## Release ab1445b0 — 2026-10-13 (2026-10-12 integration; web, Diary and model manager; MODEL_AUTOCONFIG=rust)

Sidebar search finds chats by what was said in them, and the sidebar has keyboard navigation; storage failures and Retry are worded more clearly; focus rings and phone-width layouts were fixed in several places; the Usage page, Code Plugins/Customise and the Diary overview load and lay out better.
The public site now sends HSTS (six months, no `includeSubDomains`) and a Permissions-Policy that turns off camera, microphone, location, payment and the other device features the app never uses (#1480).
The Models page's size recommendation is now double-checked by the Rust port (`MODEL_AUTOCONFIG=rust`, #1137); every recommendation it gave was the same before and after.
No chat, Diary message, model load, tune or benchmark was run to test this.

## Release 4746fb83 — 2026-10-12 (Diary companion answers again, #1422 #1065; web and Diary)

What changed for you: the Diary companion answers again.
It had been set to a model name the local server does not serve, so every reply failed; it now uses a model the local server does serve (when the configured name is not one of them it falls back to a served chat model, and the Diary health reply says which).
The banner that used to stay stuck now offers Show it, Put back and Dismiss, and the old stuck exchanges from 2026-10-12 and 2026-09-18 can be dismissed.
Nothing about your saved Diary entries changed, and no chat or Diary message was sent to test this.

## Release d7b6081d — 2026-10-12 (files attached to a free chat are shown with your message, #1441)

What changed for you: files you attach to a chat are now presented to the model as attached to your message, so it stops saying nothing was attached. A message sent right after attaching waits up to 30 seconds for the file to be read instead of going out without it. The privacy check still reads attached files.

## Release 96691012 — 2026-10-12 (no "This looks sensitive" card when the privacy check cannot answer, #1421)

What changed for you: in Hybrid, when the privacy check cannot give an answer, the turn stays local and no "This looks sensitive" card appears. The Local badge tooltip says why it stayed local, so there is nothing to approve or dismiss.

## Release 8d0b2e0a — 2026-10-12 (Nextcloud browser sign-in, #1427 #1432 #1433)

## Release fdd5b48a — 2026-10-12 (M4 free-chats slice available, off by default)

## Release fca7489a — 2026-10-12 (M4 chat-list slice available, off by default; missing-model popup)

## Release dd15bf6f — 2026-10-12 (mobile layout repair #1314, reviewed Core and native sidecar pins)

## Release cf521caa — 2026-10-11 (M6 native auth ownership guard pinned)

## Release b44dae9a — 2026-10-10 (native sampling settings wired, default off; M6 with merged runtime pins, #1304)

## Release 4e9ca4c2 — 2026-10-10 (default-off native usage preflight key and isolated image qualification, #1291)

## Release 9e9bdc0f — 2026-10-10 (S3 native OCR acceptance)

## Release 21057c0c — 2026-10-10 (M4 slice 1: Rust project images available, off by default)

## Release 80852237 — 2026-10-10 (M3: Rust sign-in available, off by default)

## Flag enabled 2026-10-09 — `BROWSER_POLICY_IMPL`, `TOOL_GATE_IMPL` and `TOOLBOXES_PERMITTED_IMPL` = `wasm` (config only web stays be3043cd)

## Flag enabled 2026-10-09 — `CODE_ACTIONS_IMPL=wasm` and `PROVIDER_EGRESS_IMPL=wasm` (config only web stays 22e5c113)

## Release be3043cd — 2026-10-09 (TOOL_GATE_IMPL and TOOLBOXES_PERMITTED_IMPL, dark; #1223 and #1224 fixed in the live JS; web and core)

## Release 3d06ea7d — 2026-10-09 (BROWSER_POLICY_IMPL, dark; #1218 and #1219 fixed in the live JS; web and core)

## Release 22e5c113 — 2026-10-09 (#1212 code-actions linear and limited in the Rust port; #1211 NFD names; web and core)

## Release a6b287da — 2026-10-09 (PROVIDER_EGRESS_IMPL, dark; #1208 and #1209 fixed in the live JS; web and core)

## Flag enabled 2026-10-09 — `CODE_ACTIONS_IMPL=wasm` and `PROJECT_FILE_NAMES_IMPL=wasm` (config only web stays 240eea5f)

## Release 240eea5f — 2026-10-09 (CODE_ACTIONS_IMPL + PROJECT_FILE_NAMES_IMPL, dark; #1201 find -exec fix live; web and core)

## Release 1c5172fb — 2026-10-09 (retire nine always-Rust switches; web and core, #1071 batch 3)

## Release 1e4e3b82 — 2026-10-09 (Retry forwarding log, Diary reset warnings, Diary retry QA; web and Diary)

## Flag enabled 2026-10-09 — `GGUF_META_IMPL=wasm` (config only web stays 3eab05e3)

## Release 3eab05e3 — 2026-10-09 (KaTeX math, Diary reset logging, per-layer GGUF arrays; web, model manager and Diary)

## Release f790069a — 2026-10-09 (hybrid-model autoconfig: recurrent state and attention layers, Discover estimate reason; web and model manager)

## Release ac500b45 — 2026-10-09 (retire five always-Rust security switches; web and core, #1071 batch 2)

## Release 5c92fb14 — 2026-10-09 (live-tester UI fixes, Diary files throttle pass-through, Laya autoconfig answer, estimate diagnostics; web and model manager)

## Release e58351d4 — 2026-10-09 (model manager: autoconfig spec, files, present and baseline behind MODEL_AUTOCONFIG, dark; deterministic current_diff order; model-manager only)

## Release 0815292 — 2026-10-09 (retire six always-Rust switches; web and core, #1071 batch 1)

## Release c72ee95 — 2026-10-09 (Diary storage 429/401/5xx handling; Diary only)

## Flags enabled 2026-10-09 — nine more `*_IMPL` switches (config only web stays d28ce1c)

## Release d28ce1c — 2026-10-09 (live-tester fixes #1154-#1160; web and core)

### Behaviour change

`PUT /api/model-manager/sections/:name` with an invalid size (`code: invalid_size`) now answers HTTP 400; it was 409, which the client showed as "settings file changed". The budget refusal stays 409.

## Release fc6ecbbf — 2026-10-09 (Diary overlay with the Rust tenant-assertion binary, TENANT_ASSERTION_IMPL off; Diary only)

## Release e2b6d7cd — 2026-10-09 (model manager: autoconfig input prep and values behind MODEL_AUTOCONFIG, dark; model-manager only)

## Release a917cf7f — 2026-10-09 (model manager: autoconfig size core behind MODEL_AUTOCONFIG, dark; model-manager only)

## Release 2237e0d6 — 2026-10-08 (llamacpp-autoconfig in Rust, LLAMACPP_AUTOCONFIG_IMPL dark; size-knob validation; core#37; web and core)

### Behaviour change (independent of the switch, [#1132](https://github.com/sbstndalton/noevia/issues/1132))

A preset whose `ctx-size` (or `c`), `ubatch-size` or `batch-size` is set but is not a whole number (Infinity, -1, a decimal such as 4096.5, and 0 for `ubatch-size` or `batch-size`) is now refused at save and at load (`code: invalid_size`). `ctx-size` 0 still means the model's native context, and a leading `+` is accepted. A non-finite footprint never passes the load gate. Autotune KV ceilings are planned with the JS footprint (#1133), and the `estimateInputs` comparison also requires equal `moe`, `chat`, `nativeCtx` and current ctx/kv (#1134).

## Release 7c2842a5 — 2026-10-08 (task lifecycle in Rust, TASK_LIFECYCLE_IMPL dark; core#36; web and core)

## Release e921406d — 2026-10-08 (completeness report in Rust, COMPLETENESS_REPORT_IMPL dark; core#35; web and core)

## Release 15538388 — 2026-10-08 (role-context projections in Rust, ROLE_CONTEXT_IMPL dark; core#34; web and core)

## Release 3ace1bf5 — 2026-10-08 (code-net-guard decisions in Rust, CODE_NET_GUARD_IMPL dark; core#33; web and core)

## Release 0020d687 — 2026-10-08 (mcp-servers and decision checks in Rust, MCP_SERVERS_IMPL and DECISION_IMPL dark; core#32; web and core)

## Flags enabled 2026-10-08 — S3_SIGN_IMPL, PROMPT_FRAMING_IMPL, SSRF_IMPL (config only web stays 82d0da73)

## Release 82d0da73 — 2026-10-08 (stream-guard validator in Rust, STREAM_GUARD_IMPL dark; core#29; web and core)

## Release c4ade220 — 2026-10-08 (SSRF decisions in Rust, SSRF_IMPL dark; core#28; web and core)

## Release 20930e20 — 2026-10-08 (S3 SigV4 signing in Rust, S3_SIGN_IMPL dark; core#27; web and core)

## Release 866f3db6 — 2026-10-08 (low/high context profiles, Long tune profile; core#24 web#15; #1079; web and core)

## Release 3e1e36df — 2026-10-08 (prompt-framing Rust slice dark, Laya served-elsewhere hardening, card size fallback; core#25 core#26 web#16; web and core)

## Release 673768f5 — 2026-10-08 (Models page size/shape from the loader, Laya "Runs in its own service"; #1084, part of #1083; web and core)

## Rust toggles, batch A — 2026-10-08 (config only, no release; #1071 groundwork)

Owner standing order 2026-10-08: enable the Rust switches proven in `rust-toggle-verification.md`, remove the old code later.

**Evidence.** Before: autotune and calibration jobs `passed`, no coding task, sandboxes idle, no model-loader download. Web: healthy, 0 restarts; the startup line `dav-parse.wasm verified for DAV_PARSE_IMPL, S3_PARSE_IMPL, UPLOAD_SNIFF_IMPL, MCP_FRAME_IMPL, ...`; no FATAL; `/api/ready` 200 locally and on noevia.example.com; each flag reads `wasm` in the container. MCP discovery on real servers under `MCP_FRAME_IMPL=wasm`: noevia 10 and Nextcloud 181 tools; Tavily logged one `fetch failed` at startup (outbound-only, as on a previous first start) while a direct list from the container gave 5 tools under both `wasm` and `js`, so the full set is 196. Model-loader: healthy, 0 restarts, `GGUF_PARSER=rust`, `/api/v1/health`, `/models` and `/sections` 200, no `gguf-meta failed` or error lines, `gguf-meta` returns a summary for a real model header, `models.ini` sha256 identical before and after. No model was run, loaded or tuned. A real storage listing, upload and a tool call need a signed-in session and were not exercised (differential-only so far; `S3_PARSE_IMPL` has no S3 backend to observe).

## Release 8273a712 — 2026-10-08 (route fallback cause, Laya keeps its worker and stays warm #1070; core, web, Laya)

## Release 9035443e — 2026-10-08 (autotune waits for outside clients, coding tasks hold the inference gate #1062 #1067 #1068 #1069; core)

## Release 2b5c122f — 2026-10-07 (autotune KV policy #1057-#1061; web and core)

## Flags enabled — 2026-10-07 (owner approved; configuration only, no image change)

**What each flag does.** `AUTOTUNE_PLAN_IMPL=wasm`: the Rust planner orders autotune runs. `LAYA_LOAD_ADVISOR=on`: Laya advises on a guessed load failure only on a tie. `PRESET_RELOAD_IMPL=wasm`: a models.ini reload can go ahead while models are loaded. `MODEL_FILES_IMPL=rust`: Hugging Face tree listings go through `model-files tree` and fail closed (502) on bad input. None of these runs until the matching action (autotune, load failure, reload, repository listing) happens; nothing was triggered.

## Release f33a1b68 — 2026-10-07 (Library tab apply note #1036; web)

## Release 247d4c1a — 2026-10-07 (autotune engine-failure text replaced by fixed sentences #1049; web)

## Release 94599ba8 — 2026-10-07 (Laya load advisor #1004, dark; #1046 #1047 #1048; web)

## Release f48b9666 — 2026-10-07 (models.ini reload while models are loaded #1012, sleeping counts as loaded; web)

## Release 21c6cb3d — 2026-10-07 (core sandbox bridge toolCallFor #1000, web test-hang fix #1033, QA scripts #1030; web, code sandbox)

## Release 228e2ae4 — 2026-10-07 (core autotune planner #1003 + models.ini backup retention #1021, web, model manager, OCR)

## Release f505f1bb — 2026-10-07 (web: Back history on /models, single Tools and auto-tune entries, #1024 #1025)

## Release e2209540 — 2026-10-07 (web: models/routing and picker redesign, #1006 #1007 #1008 #1009 #1013)

## Release b34055c6 — 2026-10-07 (web: chat-template capability check, `CHAT_TEMPLATE_CAPS_IMPL`, #1002; real provider error reasons)

**Gemma 4 template check (no model loaded, no chat sent).** `/props?model=gemma-4-12b-it-qat-q4_0&autoload=false` answers 400 "model is not loaded" while the model is unloaded (the router has no template to return without loading it), so the template was read from the GGUF header instead: 18,681 bytes present, wasm `templateCaps` gives `known: true`, `tools: true`, `toolCalls: true`, `sendTools: true`. Chat will send tools to it.

## Release 8a8a7e83 — 2026-10-07 (web, plus code-verify recreate: MCP response framing in Rust/WASM behind dark `MCP_FRAME_IMPL`, #980; exact upload classify under `UPLOAD_SNIFF_IMPL=wasm`, #989)

**Build note.** The first server build hung for about 30 minutes in the image's client test step (`profile-features-request-dedup.test.cjs` idle at 0.3% CPU, Vite SSR); it was killed, nothing was tagged, and the identical rebuild passed in the normal time. The hung attempt's log is kept as `build-8a8a7e83.attempt1-hung.log`; treat it as a flake to watch.

## Release b29d0e0b — 2026-10-07 (web and code sandbox: the sandbox bridge's Rust/WASM path behind dark `SANDBOX_BRIDGE_IMPL`, #999)

## Release 9c3d67a3 — 2026-10-07 (web only: SECURITY, stored secrets with a GCM tag under 16 bytes are refused, #995; secret envelope in `dav-parse.wasm` behind dark `SECRET_ENVELOPE_IMPL`, #979)

## Release 8a8060d0 — 2026-10-07 (web only: a refused storage path is a 400, not a listing of the storage root, #984)

## Release 8f9ce34a — 2026-10-07 (web and OCR: upload checks in `dav-parse.wasm` behind dark `UPLOAD_SNIFF_IMPL`, Rust `docx-text` in the OCR image behind dark `DOCX_TEXT_IMPL`)

## Release 51871f21 — 2026-10-07 (web only: S3 listing parser and storage path rules behind dark switches, NUL refused in storage paths)

## Release ebe6344d — 2026-10-07 (web only: WebDAV listing hardening, `<bdi>` isolation of storage file names)

## Release 4be51449 — 2026-10-07 (web only: WebDAV listing parser moved to `server/dav-listing.cjs`, dark `DAV_PARSE_IMPL` switch, `dav-parse.wasm` built into the web image)

## Release Model manager 08c65957 — 2026-10-07 (model manager only: Rust `model-files` CLI behind `MODEL_FILES_IMPL`, default python)

## Release 3a48d1e6 — 2026-10-07 (web only: first release after the repo split; Glass menus, phone-preview settings, click after closing Settings)

## Release Laya f42f65f1 — 2026-10-07 (Laya only: concurrent serving, default still one model copy)

## Release 7baecb40 — 2026-10-07 (web only: UI redo, self-hosted fonts, dark Rust egress grant contract)

PRs: #953, #954, #955. Issues: #951, #956.

**Order and results.**

## Release a1dfd69f — 2026-10-06 (web only: model-download token and queue errors surfaced, Diary backup date uses the app locale)

PRs: #949. Issues: #948.

**Order and results.**

## Release e2f9d59b — 2026-10-06 (web only: benchmarks rating-clear error, saved-prompt delete confirmation, project delete flow)

PRs: #944, #945. Issues: #943, #942.

**Order and results.**

## Release eee0dc93 — 2026-10-06 (web only: ChatGPT sign-in failed retry marks only the failed sign-in)

PRs: #935. Issues: #934.

**Order and results.**

## Release e9efa32e — 2026-10-06 (web only: capped response reads, sign-in limits and credential epoch, SSRF and egress hardening)

PRs: #924 #929 #931. Issues: #920 #927 #928 #930 #932 #933.

**Order and results.**

## Release cf662822 — 2026-10-06 (web only: capped storage/provider reads and the project-bound chat grant)

PRs: #911 #915 #916 (web half) #921. Issues: #902 #903 #905 #917 #918.

**Order and results.**

## Release 227903da — 2026-10-06 (sidecars only: model-manager and OCR)

PRs: #907 #908 #912 #916. Issues: #901 #904 #909 #914.

**Order and results.**

**Verify.** Model-loader: healthy, `RestartCount` 0, `/api/v1/health` 200 `{"ok":true}`, web's `GET /api/v1/backends` calls return 200 in its log, `/usr/local/bin/gguf-meta` present (sha256 `aa262b77...`), `parser_choice()` is `python`. OCR: healthy, `RestartCount` 0, `/health` 200 and web reaches `http://ocr:8030/health` with 200; `/app/pdf_reduce.py` sha256 `2d07bffb...`. The 60-line log tails of both are clean. `sidecar-restart-alert.sh --ack` was run and `--dry-run` afterwards reported nothing. Diffing a full container snapshot (name, image, status, `StartedAt`, restart count, id) before and after: only `cowork-model-loader-1` and `cowork-ocr-1` changed. Web, Diary, Docling, Code sandbox, code-verify, llama, embed, Laya, Kiwix, DAV relay, the tunnel and every non-noevia container kept id and `StartedAt`.

## Release 8cbced50 — 2026-10-06 (web only: round-3 server fixes and the `contracts/` move)

PRs: #898 #899. Issues: #891 #892 #893 #894 #895 #897.

**Order and results.**

## Release 8e96d876 — 2026-10-05 (repo sweep release 4, final: web and model-manager; Diary not deployed)

PRs: #888 #889. Issues: #841 #843 #845 #876 #884 #885 #886 #887 (#885 is closed on GitHub, but its fix does not run until the Diary overlay is re-run).

**Order and results.**

## Release f6885a55 — 2026-10-05 (repo sweep release 3: web, Diary, model-manager, Code sandbox and Docling)

**Order and results.**

## Release 023ddcb5 — 2026-10-05 (web low follow-ups, Diary and model-manager UI removal)

## Release c6702509 — 2026-10-05 (web sweep batch, Diary overlay, model-loader image)

## Release 29732472 — 2026-10-05 (web: routing modes, flag off)

## Release 3e7bbed8 — 2026-10-04 (web: consistent project chat counts, storage redirect label)

## Release 1eb8bbad — 2026-10-04 (web: storage warning wording, project card count)

## Release b653843c — 2026-10-04 (web: storage login check)

## Release 6f59ba82 — 2026-10-04 (web: tool-layer provenance policy, flag off)

## Release 17b477dd — 2026-10-04 (web: vault mirror orphan note, skipped list-save ids)

## Release 25cabfb4 — 2026-10-04 (web: chat lists, suggest rate limit, vault mirror fixes)

## Release b31d0075 — 2026-10-02 (web: each chat as a small brain note, flags off)

## Release 58b4bffb — 2026-10-02 (web: per-user chat mirror into the Diary vault, inert)

## Release 23841302 — 2026-10-02 (web: chat framing phase 5 organise, flag off)

## Release e5cd0443 — 2026-10-02 (web: chat framing phase 4, flag off)

## Release fe6fb292 — 2026-10-02 (web: chat framing phase 3, flag off)

## Release 90390780 — 2026-10-02 (web: chat framing phase 2 confirm UI, flag off)

## Release 7635054 — 2026-10-02 (web: chat framing phase 1, flag off)

## Release 6d7ae96 — 2026-10-01 (web: Security hint hidden when the account can't connect)

- **Verify:** web healthy, `RestartCount` 0, `dist/version.json` is `6d7ae96`. The 11 other cowork containers kept ID, StartedAt and restart count (before/after lists in `state/nonweb.{before,after}-6d7ae96.txt`, identical). `https://noevia.example.com/` returned 200 and `/api/profile` 401. The served `index-l3TWrmjh.js` and `index-Dd9SpLmJ.css` exist in the container's `dist/assets`, and the JS contains "only works when your Diary is turned on". Web still listens on 127.0.0.1:8021 and 127.0.0.1:8031. No model run, tune or Diary access.

## Release 448531e — 2026-10-01 (web: Connect a device)

## Release c526350 — 2026-10-01 (code-sandbox image for code-verify, restart-alert tool)

- **Verify:** `code-verify` came up healthy and its startup log has no `EACCES` line. A probe from web (`reachability-probe`, valid nonce) got `not_configured` with the nonce echoed, and the container restarted. Two earlier malformed probes (wrong request shape) were refused and also restarted it, so `RestartCount` went 0 → 4 over four probes (two malformed, two valid, the last one after `--ack`).
- **Restart alert:** after `--ack` and the last probe, a `--dry-run` and a real run were both silent.
- **Snapshot:** 46 containers before and after; the only difference is code-verify (`671bdab4c6c7` → `c54a91c132bd`, new image). All others keep ID, StartedAt and restart count, including the `sg716-*` evaluation containers and `cowork-llama-1`. No model run, tune or Diary access.

## Release 3c7e527 — 2026-10-01 (web, model-loader, code-sandbox, new code-verify)

Before/after snapshot of all containers (43 → 44): the only differences are model-loader `d7dda8e7ef3f` → `6a5ac490465a`, code-sandbox `563d1201582b` → `bd58b3d5e66f`, web `8a45208a9b65` → `b7826605665c`, and the new code-verify `671bdab4c6c7`. Llama, embed, diary, docling, laya, ocr, kiwix and every non-noevia container keep the same ID, StartedAt and restart count. There was no model run or tune and no Diary access.

Known follow-ups:
- Every verification restarts `code-verify` by design, so the sidecar restart alert will report each one.
- At each start the verifier logs `could not read /verify/run to sweep it: EACCES`. The server lacks DAC_OVERRIDE and `/verify/run` is 1003's 0700 tmpfs; it is fresh on every restart, so this is harmless.

## Diary overlay 9debec6 — 2026-10-01 (Diary embeds through the `embed` sidecar, #720)

**Parity (#720).** The single-string check of release 9debec6 gave cosine 0.99887, below its 0.999 threshold. The owner delegated the decision, and the broader sample was run with the multi-string `tools/embed-parity-check.cjs` ([#721](https://github.com/sbstndalton/noevia/pull/721)). Before running it, the router had no model loaded. The sample was 40 synthetic documents and 10 synthetic queries, no user data. Results for the router's `nomic-embed-text-v1` (Vulkan) against the `embed` sidecar (CPU, same GGUF, `--pooling mean`): min cosine 0.99863, median 0.99909, mean 0.99913, max 0.99962. Mean overlap@5 was 0.96: 8 of the 10 queries had identical top 5, and the other 2 differed by one document. The rule (min ≥ 0.997, overlap@5 ≥ 0.9) passes, so the vectors are the same model up to float noise and the existing Diary index stays valid without re-embedding. `nomic-embed-text-v1` was unloaded through the router afterwards.

## Release 9debec6 — 2026-10-01 (Docling native-text fallback, one model within a 16 GiB inference budget, web)

## Release web c70d1a9 — 2026-09-30 (auto-tune relative quality gate, Tune panel fixes)

## Release 53da4ce — 2026-09-30 (web + Laya: configurable decision deadline)

Web decision deadline: stored `decision:configuration` changed from 1500 to 2000 ms (URL unchanged) through `createDecisionSettings().save` against the app's own settings store. The running process caches the value at startup, so web was restarted once afterwards and reads back 2000. Zero supervise records since the restart at the time of writing.

## Release web 2c1aee7 — 2026-09-30 (Create-project dialog files stored in connected storage)

Checks: web healthy, zero restarts; zero error markers in web logs; `/llamacpp-config` RW=false; public root 200, `/api/profile` 401; the served `index-D3jigXrH.js` and `index-CHiiGa9G.css` are byte-identical to the image `dist`. Before/after snapshot of all 34 running containers (id, StartedAt, restart count): the only difference is the recreated web container (started 2026-09-30T10:18:19Z). Snapshots kept as `snap-before-2c1aee7.txt` / `snap-after-2c1aee7.txt`; older `.snap-*-92dfd2a` and `snap/*b4bed07*` files removed.

---

## Release web 92dfd2a — 2026-09-30 (Auto-tune link in Advanced mode, System-One gate fits Laya limits, reload mid-reply keeps the turn)

---

## Release web b4bed07 — 2026-09-30 (provider capabilities are data, roles renamed Planner/Executor/Laya/Auditor, plannerReview flag)

---

## Release web b6fda27 — 2026-09-29 (model-loader is the models.ini writer, read-only preset mount, declined-write note, auto-tune arithmetic replies, Diary retry records)

---

## Release web 4dc8ccf — 2026-09-29 (storage edit messages, no retry of conditional writes, phone chat header, unit wording, write-safety cards)

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `4dc8ccf`; all 82 files served publicly are byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply; the device-code route returns 404).

---

## Release web ffdcd9b — 2026-09-29 (project tools edit uploads in place, phone-preview stacking, Code header inset, French wording, byte plural)

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `ffdcd9b`; all 82 files served publicly are byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply; the device-code route returns 404).

---

## Release web 6e7eeba — 2026-09-29 (project files by bare name, phone-preview drawer, English size sentences, Auto label, timer start)

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `6e7eeba`; all 82 served asset files byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply).

---

## Release web 5e904b7 — 2026-09-29 (remaining English and de/fr wording, composer toolset names, Stopped placeholder, French byte units, Diary phone preview)

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `5e904b7`; all 82 served asset files byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply).

---

## Release web 3007ae5 — 2026-09-29 (toolbox and chat chrome translations, offsite-backup qa, hardware answer, phone theme cards)

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `3007ae5`; all 82 served asset files byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply).

---

## Release web a8a953a — 2026-09-29 (Code landing, admin Settings and Diary calendar localised, round-7 leftovers)

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `a8a953a`; all 82 served asset files byte-identical to the image `dist`; web logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set for them, defaults apply).

---

## Release web + model-loader 381760c — 2026-09-29 (round 6 fixes, stopped-backend uptime, field ids)

Checks: web and model-loader healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `381760c`; all 82 served asset files byte-identical to the image `dist`; web and model-loader logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off (no `NOEVIA_FEATURE_*` override set, defaults apply). Model-loader `/api/v1/health` 200; `/api/v1/backends` reports `uptime_s` 10256 and 14832 for the two running backends and `null` for the exited `llama-vulkan-test`; the `/api/v1/sections` schema carries `id` on all 98 fields (read from inside the web container with the token header). This closes [#603](https://github.com/sbstndalton/noevia/issues/603).

---

## Release web + model-loader 435ba54 — 2026-09-29 (locale gaps, backend uptime_s, tierId)

Checks: web and model-loader healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/api/auth/device/code` 404, `/version.json` `435ba54`; 53 served asset files (including `index-*.js`/`index-f8aq2N0j.css`, `theme.js`, `lens.js`, `glass-highlight.js`) byte-identical to the image `dist`; web and model-loader logs clean. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off. Model-loader `/api/v1/health` 200, `/api/v1/backends` includes `uptime_s` for every backend, and the `/api/v1/sections` schema carries `tierId` on all 10 tiers (read from inside the web container with the token header). Follow-up: [#603](https://github.com/sbstndalton/noevia/issues/603) (exited backends report an uptime).

---

## Release web ef6a83f — 2026-09-29 (unreadable sources excluded, Sources typography, lazy project folders)

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/version.json` `ef6a83f`; served `index-BK7x-LxY.js`, `index-f8aq2N0j.css`, `theme.js`, `lens.js` and `glass-highlight.js` byte-identical to the image `dist`; web logs clean. `/api/auth/device/code` returns 404. `astraReview`, `constrainedPlanDecoding` and `nativeClientAuth` are off.

---

## Release web a70f5a0 — 2026-09-29 (locale-aware model numbers; native-client device sign-in, flag off)

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/version.json` `a70f5a0`; served `index-BnZjcwNG.js`, `index-DSXrbO3N.css`, `theme.js`, `lens.js` and `glass-highlight.js` byte-identical to the image `dist`; web logs clean and the three `device_*` tables (plus indexes) exist. `/api/auth/device/code` returns 404 (flag off). `astraReview` and `constrainedPlanDecoding` off, `nativeClientAuth` and `browserExecutor` unavailable.

---

## Release web + model-loader b8755fb — 2026-09-28 (md uploads, model-switch race, embed loaded model, delete guard; preflight wrapper refreshed)

Checks: web and model-loader healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/version.json` `b8755fb`, served `index-B10eD_gz.js`, `index-NW1foXSN.css`, `theme.js`, `lens.js` and `glass-highlight.js` byte-identical to the image `dist`; web and model-loader logs clean. `astraReview` and `constrainedPlanDecoding` false, `browserExecutor` false and unavailable (no Playwright in the image); `nativeClientAuth` is not in the feature registry. Model-loader `/api/v1/health` 200; `/api/v1/backends` lists `cowork-embed-1` running with loaded model `nomic-embed-text-v1` (#580) and llama running `gemma-4-E2B_q4_0-it`. Delete guard, read-only check (nothing deleted): `model_holders` on the `nomic-embed-text-v1` entry returns `cowork-embed-1 (its command runs nomic-embed-text-v1/nomic-embed-text-v1.Q8_0.gguf)` plus `cowork-web-1 (EMBEDDING_MODEL is set to nomic-embed-text-v1)`.

---

## Release web + model-loader 682a45e — 2026-09-28 (embed status, Browser-mode flag, model-loader rope fixes round 2 fixes; embed on the models network)

Checks: web healthy, zero restarts; public root 200 three times, `/api/profile` 401, `/version.json` `682a45e`, served `index-ChIYCx9M.js` and `index-CmIqOpBa.css` byte-identical to the image `dist`; web and model-loader logs clean (MCP discovery only). `astraReview`, `constrainedPlanDecoding` and `browserExecutor` all report false. Model-loader healthy, zero restarts; `/api/v1/health` 200; `/api/v1/sections` and `/api/v1/backends` return 200 from inside the web container using the `X-Model-Loader-Token` header (token never printed); backends lists `cowork-embed-1` as running, no "connection refused". Embed recreated on both `cowork_default` and `cowork_models`, healthy, zero restarts (its old restart count was 4463); `POST http://embed:8080/v1/embeddings` from web returns a vector and model-loader reaches `embed:8080/health` (200).

---

## Release web 349a450 — 2026-09-28 (sampling recommendations, Skills revocation, Astra review behind a flag)

Includes the optional llama.cpp constrained-decoding module for the plan artifact (#517, flag reports unavailable), the web to model-loader `/api/v1` contract doc and tests (#269), per-model sampling recommendations and the auto-tune Sampling phase with i18n (#308), in-flight Skills revocation and web pinning (#272), and the Astra review step in Code mode (#519, `NOEVIA_FEATURE_ASTRA_REVIEW`, default off). The persona-swap experiments harness (#518) is not part of the image. No feature flag was set or changed.

## Release web ad71baf — 2026-09-28 (provider edit in place and hosted context size)

Providers can be edited in place, and a hosted provider can state its context size (whole tokens, 2048 to 2,000,000). Closes #535 and #536. Server and frontend only.

## Release web 0f5d9f2 — 2026-09-28 (NVIDIA Build provider preset)

Adds an NVIDIA Build (free trial) provider preset. Egress rules classify a provider as external by its URL, so `https://integrate.api.nvidia.com/v1` is treated as an external provider while local endpoints stay internal. Server and frontend only.

## Release web ab70db5 — 2026-09-28 (portable Skills contract and sampling provenance)

Projects expose portable Skill manifests and an exact-version content read while retaining the existing Sources review UI contract. Tenant ownership, reviewed/enabled state, stale-version rejection and core tool approvals remain enforced. Source sampling recommendations now come from a bounded, commit-pinned `generation_config.json` fetch and carry provenance and artifact scope. They are reported metadata only, without a new UI, automatic application or model qualification. #272 and #308 remain open for their later client/invocation and sampling-quality work.

## Release web b272746 — 2026-09-28 (calendar logo and tuner answer handling)

Exact source `b272746d00217f88025809ebcaadae8c6b331310` passed 2,517 combined tests with no failures or skips, typecheck, build and design lint. Logo synthetic browser coverage passed 507 assertions across 1440/768/390 widths, light/dark, all three themes, admin/member, persistence and preview cleanup. Both PRs passed CI and root exact-SHA reviews. Source archive SHA-256 matched locally and remotely: `fb435cbc500dd0e1dbbf906a3fdb3d5c9717805d23cd76eac272ade9f3979c52`.

Web is healthy with zero restarts, started at `2026-09-28T02:11:30.068581928Z`. Public root returns 200, unauthenticated profile 401, version `b272746`; `index-DrBXtR_7.js` and `index--htmrLTo.css` return 200 and exist in the image. Available memory remained about 9.3 GiB. Every non-web container retained its ID and image. Start times and restart counts also stayed unchanged except the existing embedding crash loop: its count advanced from 3,183 to 3,184 while the same container reported its missing Nomic GGUF (#336). Embedding recovery was not attempted.

## Release web c90046e — 2026-09-28 (server memory recovery and sidebar corrections)

Web-mediated native model admission now serializes eviction/loading, verifies successful eviction, and refuses a conflicting load. This does not impose a host-wide memory limit on other router clients. The release also versions the core browser API contract, reduces static Brotli warmup cost, fixes Chat/Code selection shape and hidden-drawer indicator geometry, and keeps sidebar rows above the account footer without opaque heading bands.

## Release web 7a3f736 — 2026-09-27 (theme consistency, navigation search, backup memory)

Root reviewed exact heads before push and again before matching-head squash merge; all PR CI gates passed. Combined main passed 2,497 tests, typecheck, an explicit temporary-output build and design lint, plus destination-search browser QA. Theme regressions passed 613 shape/material checks and 452 authentication/setup checks, with baseline failures reproduced, plus 216 reading states. Root inspected all theme/reading/authentication contact sheets and focal captures at 1440/768/390 in light/dark. These are synthetic Chrome fixtures; native WebKit, physical devices and actual credentials/inference are outside that coverage.

## Release web e51c5b1 — 2026-09-27 (tool policy after approval)

Chat now rechecks the account's current tool policy immediately before dispatch. If a tool was changed to Block while its approval card was pending, submitting that old approval refuses the call and records a denial. The original issue still required the owner to approve the displayed arguments; this fixes stale policy enforcement, not an unauthenticated or silent write bypass.

Root reviewed the exact head before push and again before matching-head squash merge; all eight CI checks passed. Combined main passed 2,494 tests with zero failures or skips. Branch typecheck, explicit build to a unique /tmp output, and design lint passed. Synthetic tests exercise the real approval gate and owner decision route with fake provider/Drive execution, covering blocked reads/writes and unchanged ask behavior.

## Release web c01f303 — 2026-09-27 (bounded passkey challenges)

Passkey challenge issuance now prunes expired rows transactionally and limits active challenges to 4,096. Capacity rejects new requests without invalidating existing ceremonies, with uniform public responses for known and unknown usernames. Registration and sign-in resume when challenges expire or are consumed. This bounds challenge records; it does not claim general HTTP/CPU denial-of-service protection or immediate SQLite file compaction.

Root reviewed the exact implementation before push and again before matching-head squash merge; all eight CI checks passed. Local focused auth tests, typecheck, build and design lint passed. Full local tests passed 2,491/2,491 on rerun; the first run had one unrelated chat-drafts LRU assertion failure that also passed in isolation. Synthetic real-route/SQLite tests cover concurrent issuance, cleanup, capacity errors and preservation of existing tokens.

## Release web 69a40a7 — 2026-09-27 (account deletion persistence)

All PR heads were independently reviewed before push and again before matching-head squash merge; CI passed. Combined web source passed 2,489 tests with zero failures or skips; the final main delta after that run changes only the undeployed Diary service. Branch typecheck, build and design lint passed. The separately merged sidecar fixes passed their applicable CI, but this release does not activate them.

## Release web f8a83f0 — 2026-09-27 (model states, provider validation, source deletion)

Model loader checks and installed-model panels now distinguish initial loading from unavailable or empty results. Removing a provider clears its associated model selection in the current workspace, and explicit unknown provider IDs are rejected while the legacy alias remains supported. Shared-provider references in other workspaces remain a separate lifecycle gap. Account deletion now revokes captured workspaces and fences project/source persistence, detached source journals, and RAG work before and after asynchronous boundaries. The separate chat-context persistence path remains tracked in #478; this release makes no universal account-erasure claim.

Each exact PR head was independently reviewed before push and again before squash merge with a matching-head guard. All applicable CI passed. Combined main passed all 2,484 Node tests with zero skips after linking the worktree to existing server dependencies; no package installation was needed. Typecheck, builds and design lint passed on the implementation branches. Synthetic Playwright checks fail on their bases and pass the UI fixes at 1440/768/390 in light/dark, covering pending and settled responses; root inspected the screenshot matrices. Deletion regressions pause extraction, storage and synthetic embedding across revocation and preserve active/other-tenant behavior.

## Release web e2f1e0a — 2026-09-27 (project validation and UI navigation)

Root independently reviewed each exact local commit before push and again before squash merge with matching-head guards. All applicable CI checks passed. The combined project/chat regression suite passed 67 tests. Both UI Playwright scripts fail on the original base and pass on the reviewed branch at 1440/768/390 in light/dark; the focus-away-and-back regression also fails on the intermediate implementation. Root inspected the screenshot matrices. Local typecheck/build/design lint passed; full local npm test did not complete due baseline-matching missing server dependencies and a RAG stall, so no full local pass is claimed.

## Release web d8f510d — 2026-09-27 (duplicate request fixes, #462)

Diary directory listings and Archived workspace reads now share requests. Chat context refreshes on chat changes and reply completion, avoiding the extra read caused by initial history hydration. Mutation, background-source completion and session invalidation preserve fresh reads. The request cache retains at most 128 keys and shares slow in-flight requests.

The reviewed PR head was `f16905dab654591f61fc00059b4014edf54c28cf`, squash-merged with a matching-head guard to `d8f510de4c2f646c83f5cadf4d7a42a17d264170`. Required CI is green, including Node tests/typecheck/build and Docker images; 754 frontend tests pass locally. Synthetic browser QA fails on main d0f9750 (two initial requests per endpoint) and passes on the fix (one, then one more after a mutation). The 1440/768/390 light/dark matrix was inspected before the final cache-only follow-up; final-head 1440-light request-count QA and cache regressions pass. Full local suites stalled at the same server RAG test after about 22 minutes with baseline missing-dependency failures; no full local pass is claimed.

## Release web b61a914 — 2026-09-27 (merge #451, deploy #449 #460 #461 #451)

## Release web b84b3b8 — 2026-09-26 (merge #445, deploy #445)

PR #445 (`fix/442-443-vision-role-size-units`) was draft with CI green (8/8, including "CI
required") at head `210c451a766200f8756d6e1b4938bdf556d5807a`, which already included `main` after
#444 (`origin/main` was still at `6d7f8e7`, the Batch 14 changelog commit, when this release
began — no re-merge was needed). Diff limited to `apps/web` (server routes + frontend), no
`services/`, so this was a web-only release; no other sidecar was touched. Marked ready and
squash-merged (`--match-head-commit 210c451a766200f8756d6e1b4938bdf556d5807a`) to `b84b3b8`;
`main`'s tree hash was confirmed identical to the PR head's tree hash post-merge
(`cad4f0554a4858032fbd309fbcf2b640418936dd`). Remote branch `fix/442-443-vision-role-size-units`
and its local worktree (`/tmp/noevia-fix-442`, registered under
`~/.noevia-deps/noevia-base/.git/worktrees`) deleted/removed after merge.

## Release web 97bf1eb — 2026-09-26 (merge #444, deploy #444)

## Release web 69712fb — 2026-09-26 (merge #441, deploy #441)

PR #441 was draft with CI green (7/7) at head `8894080`, based on `origin/main` at `8b07148`
(already current, so no main-merge or worktree rebase was needed). Marked ready and squash-merged
(`--match-head-commit 88940809a164df61652d0ee00ea7c260def7644e`) to `69712fb`. Remote branch
`fix/434-437-composer` and its local worktree/clone (`/tmp/noevia-fix-434`) deleted after merge.

## Release web 11911da — 2026-09-26 (merge #438, deploy #438)

PR #438 was draft with CI green (7/7) at head `8521c95`, based on `origin/main` at `25fa6a6`
(already current, so no main-merge or worktree rebase was needed). Marked ready and
squash-merged (`--match-head-commit 8521c959520d6e6abfcdb7afdf0c44b167de2916`) to `11911da`.
Remote branch `fix/387-431-stream-scroll-md-lists` and its local worktree/branch (under
`noevia-fix-387`) deleted after merge.

## Release web 63d1187 — 2026-09-26 (merge #432 #433, deploy #432 #433)

Both PRs were draft with CI green (7/7 each) against `origin/main` at `e8123c9`; `gh pr diff --name-only`
confirmed disjoint files (#432: `Sidebar.tsx` + its qa script/test; #433: `ChatView.tsx`, `LibraryTab.tsx`,
CSS, four qa scripts) and neither touched `services/`, so this was a web-only release. Marked ready and
squash-merged #432 first (`--match-head-commit 122ad7e`) to `c35266f`, which auto-closed #362 and left
#355 open as intended. #433's worktree (`/tmp/noevia-fix-428`) then merged `origin/main` (`c35266f`) with
no conflicts (disjoint files), pushed the new head `af10341`, waited for CI green again, then squash-merged
(`--match-head-commit af10341`) to `63d1187`. Remote/local branches for both and worktrees
`/tmp/noevia-fix-355b` and `/tmp/noevia-fix-428` deleted after merge.

## Release web 778f855 — 2026-09-26 (merge #427, deploy #427: header/container parity #413 #414 #415)

PR #427 (head `215d400`) was draft with CI green (7/7) against `origin/main` at `6db20fc`. No
`services/` changes, so this was a web-only release. Marked ready, squash-merged (`--match-head-commit
215d400`) to `778f855`; `origin/main` was still at `6db20fc` at merge time so GitHub applied the
PR's own 27-file diff cleanly (`mergeStateStatus: CLEAN`) with no unrelated main advancement to
reconcile. Worktree `/tmp/noevia-fix-413` and both copies of `fix/413-415-headers-containers`
deleted after merge.

## Release web 39bf823 — 2026-09-26 (a11y focus/labels #418–#421 #345 #362; settings nav/summary/dedup #374 #422 #423)

PR #424 (head `3d88930`) and PR #425 (head `46d0f01`) were both draft with CI green against
`origin/main` at `2c53d24`. #424 was already up to date with `2c53d24` (no local merge needed);
`apps/web`: `npm test` 2296/2296, `typecheck`, `build`, `lint:design` all clean; CI green (7/7);
`qa/sidebar-focus-undo.cjs`, `qa/model-popup-focus.cjs`, `qa/appearance-family-labels.cjs`,
`qa/model-card-labels.cjs` and `qa/tool-catalogue-escape-focus.cjs` each **PASS** against the
built `dist` with `PLAYWRIGHT_MODULE`. Marked ready, squash-merged to `06f1c45`; `git diff`
against `origin/main` empty (tree invariance). Worktree and both copies of
`fix/418-421-345-a11y` deleted.

#425 was then merged against the new `origin/main` (`06f1c45`, i.e. #424) — `ort` auto-merge, no
conflicts across the anticipated overlap in `Sidebar.tsx`, `ModelPopup.tsx`, `GeneralSettings.tsx`,
`ToolCatalogue.tsx` and CSS, keeping both PRs' changes — to `48dde0e`. `npm test` 2303/2303,
`typecheck`, `build`, `lint:design` all clean; CI green (7/7) on the merged branch;
`qa/settings-nav-edge-and-summary-wrap.cjs` and `qa/profile-features-dedup.cjs` each **PASS**
against the built `dist`. Marked ready, squash-merged to `39bf823` (final `main` SHA); `git diff`
against `origin/main` empty. Worktree and both copies of `fix/374-422-423-small` deleted.

## Release web 584bdba — 2026-09-26 (spacing rhythm: #417)

PR #417 (head `627f216`) was draft with CI green against an earlier `origin/main`. Main had since
advanced to `6c7fafb` (#412, #416 plus their changelogs); merged `origin/main` into the branch in a
worktree (`ort` auto-merge, no conflicts — including `Sidebar.tsx`, which kept both #416's row-actions
focus fix and this PR's phone touch-target/spacing rules) to `95463ac`. From `apps/web`: `npm test`
2295/2295, `typecheck`, `build`, `lint:design` all clean; CI green (7/7 checks); `qa/spacing-rhythm.cjs`
(180 screenshots, flush=0 clipped=0 small=0 zoom=0 overflow=0 nav-error=0 probe-error=0 — 9 unrelated
`pageerror`s only in the Editorial family, pre-existing and not part of this script's flush/overflow
gate), `qa/sidebar-focus-undo.cjs` (4/4) and `qa/settings-focus-deep-links.cjs` (all scenarios) each
**PASS** against the built `dist` with `PLAYWRIGHT_MODULE`. Marked ready, squash-merged to `584bdba`
(final `main` SHA); `git diff` against `origin/main` is empty, confirming tree invariance. The worktree
and both local+remote copies of `fix/spacing-apple-rhythm` were deleted after merge.

## Release web 3cf7233 — 2026-09-26 (two reviewed fixes: #412, #416)

Both PRs were draft with CI green against `origin/main` at `2c7488d` at the start of this release.
#412 (`c70ce3d`) merged `origin/main` cleanly (`ort` auto-merge, no conflicts) to `0639102`; `npm test`
2291/2291, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `4b38263`. #416
(`faa6b1c`) then merged `origin/main` (the merge had been started against `2c7488d`, before #412 landed)
cleanly — `ort` auto-merge, no conflicts, only `docs/changelog.md` — to `39ee9a6`; `npm test` 2289/2289,
`typecheck`, `build`, `lint:design` clean; `qa/sidebar-focus-undo.cjs` (4/4) and `qa/url-history.cjs`
(11/11, including the `/c`, `/c/`, `/p`, `/p/` SPA-shell fallback) both **PASS** against the built `dist`
with `PLAYWRIGHT_MODULE`; CI green (including `offline-contract`); squash-merged to `3cf7233` (final
`main` SHA — this squash lands cleanly on top of #412's already-merged `plugin-directory.cjs` change,
which is why `git diff` against `origin/main` shows exactly that file). All worktrees and their
local+remote branches were deleted after merge. The pre-existing spacing branch (`fix/spacing-apple-rhythm`)
was left untouched, as scoped.

## Release web 0a8cc31 — 2026-09-26 (three reviewed fixes: #407, #411, #408)

All three PRs were draft with CI green against `origin/main` at `2c0d59c` at the start of this release.
#407 (`511f8a7`) merged `origin/main` cleanly (`ort` auto-merge, no conflicts) to `0b59fdd`; `npm test`
2262/2262, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `aead398`. #411
(`db447ce`) then merged `origin/main` (now carrying #407): clean `ort` auto-merge, no conflicts, to
`e563658`; `npm test` 2273/2273, `typecheck`, `build`, `lint:design` clean; CI green (including
`offline-contract`); squash-merged to `637f003`. #408 (`2472e3e`) then merged `origin/main` (now carrying
#411's `chat.cjs`/`ModelsSettings` changes): the anticipated conflicts in `ModelsSettings.tsx`,
`App.tsx` and `Sidebar.tsx` did not materialize — `ort` auto-merged cleanly, both sides kept, to
`bb4a63c`; `npm test` 2289/2289, `typecheck`, `build`, `lint:design` clean, and
`qa/settings-focus-deep-links.cjs` (run against the built `dist` with `PLAYWRIGHT_MODULE`) **PASS**; CI
green; squash-merged to `0a8cc31` (final `main` SHA). `git diff --quiet <head> origin/main` confirmed
tree-identical after each squash. All three worktrees and their local+remote branches were deleted
after merge. The pre-existing spacing branch and #410 were left untouched, as scoped.

## Release web 592c4d3 — 2026-09-26 (three reviewed fixes: #400, #395, #402)

All three PRs were draft with CI green against `origin/main` at `ff0d4ea` at the start of this release.
#400 (`74bb630`) merged `origin/main` cleanly (`ort` auto-merge, no conflicts) to `e67370e`; `npm test`
2221/2221, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `edcf18d`. #395 (`9cab4ca`)
then merged `origin/main` (now carrying #400): the expected `ChatView.tsx` conflict materialized as a
two-line import-order conflict against #394's already-merged `edit-focus.ts` import — resolved by keeping
both import lines (`chat-drafts.ts` and `edit-focus.ts`), no logic conflict, to `10d6f8a`; `npm test`
2240/2240, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `fff2a02`. #402 (`c284a4d`)
then merged `origin/main` (now carrying #395's `chat-drafts.ts`): clean `ort` auto-merge, no conflicts, to
`e37d7d8`; `npm test` 2262/2262, `typecheck`, `build`, `lint:design` clean; CI green (including
`offline-contract`); squash-merged to `592c4d3` (final `main` SHA). `git diff --quiet <head> origin/main`
confirmed tree-identical after each squash. All three worktrees and their local+remote branches were
deleted after merge. The pre-existing spacing branch and the #399 QA PR were left untouched, as scoped.

---

## Release web f70e969 — 2026-09-26 (two reviewed fixes: #394, #391)

Both PRs were draft with CI green and `MERGEABLE` against `origin/main` at `d805cfd` at the start of this
release. #394 (`fa0f63f`) already had `d805cfd` as an ancestor, so `git merge origin/main` was a no-op and no
new merge commit was needed; squash-merged directly to `532b049` (`npm test` 2208/2208, `typecheck`, `build`,
`lint:design` clean; GitHub Actions CI green). #391 (`5a00528`) then merged `origin/main` (now at `532b049`,
carrying #394) — the expected `App.tsx`/`ChatView`-adjacent conflict did not materialize; the `ort` merge
strategy auto-merged `ChatView.tsx`, `DiaryModal.tsx`, `useChatScroll.ts`, i18n and the new `edit-focus.ts`/
`markdown-image.ts` files cleanly, keeping both PRs' changes intact, producing `704d569`. `npm test`
(2221/2221), `typecheck`, `build`, `lint:design` all clean on the merged worktree; GitHub Actions CI green
on the pushed head. `qa/url-history.cjs` ran against the built dist with a real Chromium
(`PLAYWRIGHT_MODULE` pointed at the codex-runtime `playwright` package, synthetic `page.route` API mocks,
no inference/storage/Diary/network) — all 10 scenarios passed, including the sign-in-returns-to-deep-link
case. Squash-merged #391 → `f70e969` (final `main` SHA). `git diff --quiet <head> origin/main` confirmed
tree-identical after each squash. Both worktrees and their local+remote branches were deleted after merge.

---

## Release web 5430d25 — 2026-09-26 (two reviewed fixes: #384, #365/#356)

Both PRs were draft with CI green and `MERGEABLE` at the start of this release (`origin/main` unmoved at
`16ba52d` since the orchestrator's review). #386 (`f599869`) already had `16ba52d` as an ancestor, so no
merge commit was needed; #385 (`1bc6756`) merged `origin/main` cleanly (auto-merge, no conflicts) to pick
up #386's `ModelPopup.tsx`/`routes/projects.cjs` changes, producing `e9c5c53`. `npm test`
(2162→2181 passing), `npm run typecheck` and `npm run build`/`lint:design` were green on both worktrees;
GitHub Actions CI was green on both heads and re-verified after #385's merge commit was pushed. Squash-merged
in order: #386→`443396d`, #385→`5430d25` (final `main` SHA). `git diff --quiet <head> origin/main` confirmed
tree-identical after each squash. Both worktrees and their local+remote branches were deleted after merge.

---

## Release web + model-loader 1c87ab0 — 2026-09-26 (five reviewed a11y/UX fixes: #345 #346 #352–#363 #366–#368, and deploying #347/#348)

All five PRs merged one at a time into `main` from base `31973d5`, each re-merged with the moving
`origin/main` tip and re-verified before squash-merge: #351→`74436e1`, #370→`b13250f` (conflict in
`ToolCatalogue.tsx` — kept #351's no-dialog-role/keepFocusOnMouseDown behaviour together with #370's
inline `placeCatalogue()` layout style), #369→`0b0b88e` (ChatView.tsx auto-merged both edit-action and
reply-telemetry/label changes cleanly), #364→`98641b0`, #382→`1c87ab0` (final `main` SHA; auto-merged
cleanly). Node/TS/build/lint:design green on every merge (2105→2155 tests passing as files were added);
`npm run typecheck` and `npm run lint:design` clean on every merge. GitHub Actions CI green on every
head before merge and again on every re-merged commit before squash.

---

## Release web 7a72713 — 2026-09-26 (five reviewed fixes: #339–#343)

---

## Release model-loader f6444b4 — 2026-09-25 (M3: model-loader is the single writer of models.ini)

---

## Release diary f6444b4 — 2026-09-25 (M2: Diary tenant assertion + month-file protection)

Verification after step 4: `cowork-diary-1` healthy, `RestartCount=0`; an unsigned tenant request from the
web container (`GET /api/diary/status` with only the bearer + `X-Cowork-User-ID`) returned **401** and diary
logged "tenant assertion rejected: missing or malformed assertion"; `/api/health` via web 200; every other
`cowork-*` container and Cloudflared kept identical container IDs; public `/` 200, `/api/profile` 401.
Not verified here (needs an authenticated browser session, `LEGACY_AUTH_COMPAT=false`): a real Diary tab
read/write through the signed path, covered by the unit suites (diary pytest 415, web
`diary-tenant-assertion.test.cjs`). Direct sidecar clients using `DIARY_LEGACY_USER_ID` stop working now that
the key is set.

---

## Release f6444b4 — 2026-09-25 (web-only: fix boot crash from 0d602d6 retry)

---

## Release 2037ffd — 2026-09-25 (web-only: theme families + cursor-pull hover)

## Release 58b340c — 2026-09-25 (favicon/app-shell cache-busting, stamp-test fix)

Preflight: `gh pr list --repo sbstndalton/noevia --state open` showed only #315 (theme families work, not part of this release) — nothing was merged. `origin/main` was confirmed at `58b340c` (full: `58b340c1553fd42ec40a14bc9c1a6728b7f7a370`) with no trailing non-docs commits ahead of it for `apps/`, `compose.yaml`, `.github/` (`git diff --stat` empty against the prior release SHA `20a24c2`... verified against 58b340c as tip). CI on `58b340c1553fd42ec40a14bc9c1a6728b7f7a370` (workflow `CI`, run 36112669958) completed success, including "Docker images build" (2m19s) and "Node tests, typecheck, frontend build" (1m24s), plus Diary test suite, Docling extraction contract and Model manager test suite.

## Release 20a24c2 — 2026-09-25 (new leaf logo)

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `20a24c2` (full: `20a24c28b34865480aa83e7075c122f9abdcc3ff`) with no trailing non-docs commits, and `git diff --stat 20a24c2 origin/main -- apps/` was empty. CI on that SHA (workflow `CI`) completed success, including "Docker images build" and "Node tests, typecheck, frontend build".

## Release 2ab7c99 — 2026-09-25 (Settings back/close loop fix, new chats default to Auto)

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `2ab7c99` (full: `2ab7c991d81e4b52d8bc724bdbbb5e434e2f2e6c`) with no trailing docs-only commits, and `git diff --stat 2ab7c99 origin/main -- apps/` was empty. CI on that SHA ("Fix Settings back/close loop through Models & routing; new chats default to Auto (#307)", workflow `CI`, plus "Offline skills MCP contract") completed success, including "Docker images build" and the "Node tests, typecheck, frontend build" job.

## Release 4e19d28 — 2026-09-25 (model delete now unloads, clears auto-router roles)

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `4e19d28` (full: `4e19d2850f49a6671f472a0b2d24ea02aebddff4`) with no trailing docs-only commits, and `git diff --stat 4e19d28 origin/main -- apps/` was empty. CI on that SHA (workflow `CI`, plus "Offline skills MCP contract") completed success, including "Docker images build" and the "Node tests, typecheck, frontend build" job.

## Release cfdb5b3 — 2026-09-25 (Laya tool gate, experimental, off by default)

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `cfdb5b3` (full: `cfdb5b30c483cfe39596cd80ccd8e7b43bd2231f`) with no trailing docs-only commits, and `git diff --stat cfdb5b3 origin/main -- apps/` was empty. CI on that SHA ("Tool gate: make small models use tools when the prompt needs them (experimental, off) (#301)", workflow `CI`, plus "Offline skills MCP contract") completed success, including "Docker images build" and the Node tests/typecheck/frontend-build job.

## Release 8454694 — 2026-09-25 (i18n catalogues, QA scripts, docs)

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `8454694` (full: `84546946e4b3460e95e1f608ab5d75c77b117549`). CI on that SHA (`i18n: model manager segment, Diary & storage and Service status (#300)`, workflow `CI`) completed success.

## Release 5a47942 — 2026-09-24 (Projects/Cowork task status, connector permissions, usage drilldown, Customise UI; MCP custom-server preview)

No open PRs against `sbstndalton/noevia` were merged for this release (a PR touching #283 was open but explicitly out of scope). `origin/main` was confirmed at `5a47942` followed only by docs-only changelog commits (`037cc23`, `b247bfa`), and `git diff --stat 5a47942 origin/main -- apps/` was empty. CI on `5a47942` (Detect changed areas, Docker images build, Diary test suite, Model manager test suite, Docling extraction contract, Node tests/typecheck/frontend build, CI required) was all green before release.

## Release 9a8f29e — 2026-09-24 (i18n interface translations)

## Release e35ab29 — 2026-09-24 (browser executor wired into managed jobs)

## Release c09ee38 — 2026-09-24 (model evidence import)

## Release d5cf1ea — 2026-09-24 (theme families, visual and motion system batch J)

## Release c7f7999 — 2026-09-24 (settings reorganisation, notifications, memory, response style, keyboard, archived chats, Customise, home recents)

## Release 89142c0 — 2026-09-24 (composer Chat/Cowork toggle, tool catalogue)

## Release 9b532a8 — 2026-09-24 (model manager guided tuning, secrets rotation, Diary tombstone/quarantine, upload/RAG/MCP hardening, code-sandbox batch A)

## Release d264606 — 2026-09-24 (code-actions publish/network gating, fetchJson body cap, Diary corpus_store NameError and queued-edit races)

## Release b5941e4 — 2026-09-24 (routing/menu fixes, stale loaded summary, chat-only prompt suite, Diary polling and journal replay order, admin-gated warm-up, backup-worker backoff)

## Release 11617a3 — 2026-09-24 (round-13 fixes: harness approval bypasses, MCP discovery TTL, Diary storage-outage handling, UI fixes)

## Release dda50c2 — 2026-09-24 (harness containment, RAG/prompt budget, round-12 hardening, pi bridge timeouts)

## Release 5b6d9b6 — 2026-09-24 (Diary hardening, model manager + code sandbox hardening, per-service tags; sidecars only)

All other cowork containers (laya, llama, embed, ocr, docling, kiwix) kept identical ids and start
times. Public `/` 200, `/api/profile` 401.

## Release 958022b — 2026-09-24 (job start controller leak, phone preview Settings)

## Release c3a03c7 — 2026-09-24 (account cleanup, job journals, research saves, code harness hardening)

## Release 852ef76 — 2026-09-24 (S3 region, storage secret v2, replay history)

## Release 0c2be32 — 2026-09-24 (routing model, Diary edit proxy and offsite backup hardening)

## Release 7e8ce3a — 2026-09-24 (code-workspace and Drive hardening)

## Release 7ce2213 — 2026-09-24 (hardening batch)

`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:7b6942c`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-DoBtRaex.js` and `index-B1OLP7Ag.css` are present in the image's `dist/assets`;
`errorResponse` from #76 is exported in the running container.

## Release 7b6942c — 2026-09-24 (chat save races)

`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:9ee7bb0`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-RdBcm5Rx.js` and `index-B1OLP7Ag.css` are present in the image's `dist/assets`.
Later PRs merged to main after 7b6942c are not part of this release.

## Release 9ee7bb0 — 2026-09-23 (Laya excluded from auto-tuner)

`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:6b59118`).
Read-only, without starting a tune, `require('/app/server/model-system.cjs')` inside
the running container confirmed `isSystemModel('laya_multilingual_f16')` returns
`true` (reason: "System routing model — not tuned"/"not deleted"), while an ordinary
model ID returns `false`. Locally the container answered its root path with the
expected unauthenticated 302 redirect and the built `dist/assets` matched the served
bundle name pattern from prior releases.

## Release 6b59118 — 2026-09-23 (Auto routing label in inference stats and saved replies)

## Release 6b1621c — 2026-09-23 (auto-tune recovery and compact progress)

Auto-tune now waits until the router reports every model unloaded before saving the
next candidate profile. This prevents the immediate 409 that could follow a rejected
quality probe while the previous model was still unloading. A bounded timeout names
the blocking model and state; cancellation still restores the current phase. Failed
quality probes report the check and failure type without storing generated answers.
The Auto Tune panel puts status, progress and Resume above compact queued details.

## Release 827932b — 2026-09-22 (three-material refinement)

Removed the redundant Glassmorphism mode from preferences, pre-paint initialization,
settings, CSS and reference samples; old saved values fall back to Soft. Soft is matte
with restrained depth and visible switch boundaries. Liquid Glass is limited to functional
controls, with readable content, restrained highlights, no label refraction or pointer tilt,
and reduced-preference handling. Material 3 uses paired color roles, tonal selection,
correct pressed/disabled states and native-checkbox switch contrast. Shared geometry stays
stable. General now correctly distinguishes synced theme/accent from browser-local preferences.

`ui/material-refinement` (`7663b40`, `827932b`) was pushed, then fast-forwarded into main
from `9cf92b3` after a fresh fetch. No remote changes conflicted; no force push or branch
deletion. The original `ui-polish-update` checkout is unchanged and clean.

## Release 04780e6 — 2026-09-22 (development branches integrated)

Integrated `ui-polish-update` (`7014b69`) and local
`codex/harness-hardening-claude-pi` (`c729379`) from `origin/main` (`506f0f8`).
The tuning commit already existed as a patch-equivalent change; no duplicate feature
or stale alternative was applied. Only documentation conflicted. See
[integration evidence](integration-2026-09-22.md).

## 2026-09-22 — Complete automatic model tuning (release `5a88558`)

## 2026-09-22 — Claude Code and pi pins hardened (source only)

## 2026-09-22 — Code mode now runs pi

## 2026-09-22 — Diary service updated

The Diary service now keeps the previous version in Trash when a WebDAV client overwrites a
file, and reports each file's last-modified time so sync apps like Obsidian can tell what
changed. Nothing else in the Diary changed, and no Diary data was touched. File sharing (WebDAV)
remains off until you turn it on.

## 2026-09-22 — A local graph for Diary notes

Open a note in the Diary editor and expand **Local graph** to see the notes it links to and the
notes that link back, as a small diagram and a list you can click. Links you have just typed show
straight away. Two-way links are drawn heavier, incoming links dashed. It only reads: nothing is
indexed or changed, and it says so when the backlink scan could not cover every file.

## 2026-09-22 — Claude Code and pi can be pinned; Codex refused (releases `59249d9`, `d59d1a0`, `2577e16`)

Nothing changes in Code mode today; it still runs OpenCode. noevia now knows how to lock down
more coding agents the way it locks OpenCode: every edit, command and web access asks you,
the agent's own "skip permissions" modes are off, it talks only to your local engine, and it does
not update itself or send telemetry. For pi, which has no permission prompts of its own, noevia
installs a gate that asks for every non-read action and blocks if it cannot ask. Installing any
of them in the sandbox is your call. Tested with the real Claude Code and pi against a scripted
fake model: approvals reach you, Decline blocks, and a repository's own settings can't skip the
question. Codex was tested the same way and is **refused**: its commands ran without asking.

## 2026-09-22 — Step supervision stops pausing ordinary chats (release `b055571`)

With Step supervision on, Laya sometimes stopped a harmless chat for review (for example after a
plain project list) and added needless "double-check" rounds. New wording, measured on synthetic
cases: 16/17 on a fresh set with no needless pauses or extra rounds, and every synthetic
dangerous case (hidden instructions, credential requests, destructive commands) still stops.

## 2026-09-22 — System-One decisions show up in the web log (release `e19119d`)

Each routing and supervision decision writes one line — chosen role or action, margin, time
and whether it fell back — and never the message. This is how the next tuning step gets real
evidence instead of synthetic cases.

## 2026-09-22 — System-One routing picks Smart and Code when it should (release `6c3cde0`)

## 2026-09-22 — Request-local live inference readouts (source `80d116f`, deployed in `e7b59d6`)

The inference footer now follows the visible chat's own event stream instead of treating the
engine-wide `/api/stats` poll as reply telemetry. It shows the routed model and generating state
immediately, records server-observed first output as it arrives, and applies provider-reported
tokens, rate and MTP acceptance without waiting for the next poll. Tool-loop rounds are
cumulative and use a weighted provider rate. Missing measurements remain explicitly unavailable;
they are never guessed from chunks or text. Engine totals/hardware stay separately labelled, so
another chat or a stale poll cannot replace the visible reply's facts.

## 2026-09-22 — Compact context inside tool continuations

The chat loop now rechecks and, when necessary, compacts its model-facing projection before
every continuation after tool execution. The saved transcript and cross-turn summary remain
unchanged. The current user turn, assistant tool calls and their matching results stay
byte-identical and atomic; invalid or oversized protected groups stop with a readable error
without deleting messages, fabricating results or replaying tools. Continuation summaries use
the existing provider-neutral compaction call and conservative context estimate, in bounded
rolling batches. The context meter and opt-in context log report the compacted continuation.

### 2026-09-21 — Material 3 shares component geometry

## 2026-09-22 — Configure and enable Laya routing in Experimental

Added shared decision-service setup with editable URL/deadline, installed-Laya shortcut,
health-only connection test and persistent admin Save. Routing now uses the configured
Laya service for Fast/Smart/Code instead of requiring the old option-logit endpoint.
Settings apply to subsequent routing and supervision decisions without restart.
1192 tests, typecheck, build and design lint pass; scoped light/dark responsive UI verified.
See [configuration and verification](research/system-one/18-decision-service-settings.md).

## 2026-09-21 — Laya endpoint for model-independent step supervision

## 2026-09-21 — Experimental step supervision

Added a separate unavailable-by-default Experimental entry and a provider-neutral chat
checkpoint seam. Mocked decisions can continue, request a bounded verification round,
or pause for review. Failed decisions preserve existing behavior; durable escalation
uses the existing checkpoint store and blocks automatic restoration. No Jev/Laya calls,
model switching or replay. 1181 web tests, typecheck, build and design lint pass.
See [scope and verification](research/system-one/17-step-supervision.md).

Material 3 now inherits the shared dimensions, padding, font metrics and layout borders
instead of replacing them. Tonal colors, radii, shadows and inset outlines retain the
Material appearance. Removed the width-changing selected checkmark and matched segment
font weights; rounded selection fills stay within wrapped tracks. Sidebar spacing also
uses the common tokens. Regression test rejects Material-only geometry overrides.

Verification: 1171 unit tests, typecheck/build/design lint and diff whitespace checks pass.
Synthetic browser comparison: 43 settings/navigation boxes match exactly across Soft,
Liquid glass, Glassmorphism and Material 3 at 375 and 1440 CSS px, plus the normal desktop
viewport. Visually inspected the corrected selection fills. No model or personal-data tests.

### 2026-09-21 — Descriptions above settings controls at every width

Corrected the requested layout: shared settings descriptions occupy their own full-width
row above buttons/selectors even on wide desktops. Compact on/off switches retain their
inline label. Wrapped segmented choices remain visible. This supersedes the prior
width-dependent placement in 126637e.

### 2026-09-21 — Release 126637e deployed

### 2026-09-21 — Shared settings and segmented-control wrapping (local, undeployed)

Fixed the shared flex-row cause of one-word-per-line descriptions and clipped controls.
Settings rows now wrap by their available content width, including narrow desktop panels;
text retains a readable minimum width and control/value groups stay within the card.
Segmented controls throughout the app wrap instead of hiding options in a horizontal
scroller. Their selection highlight now tracks both axes and the selected button height,
including Material 3. Coding composer action groups also wrap within their available width.

### 2026-09-21 — Experimental System-One routing switch (local, undeployed)

### 2026-09-21 — Default model mode setting (release c53713b, deployed)

### 2026-09-21 — Broader continuation verification (local, undeployed)

### 2026-09-21 — First durable-chat slice (local, disabled, undeployed)

### 2026-09-21 — Adapter cutoff and conditional bounds (local, undeployed)

### 2026-09-21 — Auto routing is the default (release f9dc5df, deployed)

### 2026-09-21 — RAG rerank in chat (release 67f336e, deployed)

### 2026-09-21 — Curated plugin starters (release 067ac1d, deployed)

### 2026-09-21 — Ordinary WebDAV clients can write (release 42540fb)

### 2026-09-21 — Shared context across a project's Chat and Code modes (release dbfbd92, deployed)

`shared-context.cjs`: `project.sharedContext = { chat, code }`, both off by default, validated on the project config route. Sharing into Code prepends the project's goal, instructions, memories and up to eight recent chat titles to the agent's prompt (not to the task label); sharing into Chat adds up to six recent Code tasks (prompt, status, branch, error) to the system prompt. Both blocks are capped at 6,000 characters and framed as reference data. Edit project shows the toggles only when Chat and Code are both on. 1,101/1,101 unit tests; `qa/project-modes` extended and green at 375/1440 light/dark.

### 2026-09-21 — Code mode can reach granted domains (release 9611580, deployed)

### 2026-09-21 — index.cjs is wiring (branch `wip/index-split`, release 2ce73df, deployed)

Everything `handleRequestScoped` still carried inline moved into its own module with injected
dependencies and a `routes/` file: the project, source and upload routes (`projects.cjs`), the
provider registry (`providers.cjs`), the models routes (`models.cjs`), the Diary routes and the
connector endpoint (`diary.cjs`), then sign-in/profile/admin, the storage connection, tool
approvals, the chat lists and transcripts, reasoning settings, health, and the HTTP helpers
(`http.cjs`). The member-origin policy shared by providers, storage and the Diary corpus is now
`createEndpointApproved` in `ssrf.cjs`. Each move is verbatim behind one sentinel and mounted in
its original order, so every status code, message, the session and CSRF gate and the three
approval actions answer as before; `index.cjs` is 2,787 → 752 lines and holds only config,
construction, the router and server start. 68 new tests, none booting the server;
`documents.test.cjs` now calls the modules instead of slicing `index.cjs` as text. The Claude
Diary plugin README's revocation section points at Settings → Diary & storage → Connected apps
instead of a deleted script.

### 2026-09-21 — index.cjs in pieces, and a measurement instead of a port (release a4e0178, deployed)

Removed because nothing called them: the Hugging Face model search and the variants listing
(server routes, front-end wrappers and their types), six helpers in `index.cjs`, a finished
Docling handoff document. Every spec is now linked from the docs index, and the Claude Diary
plugin README no longer points at a script that was deleted.

Measured, with synthetic data: Node spends about 10 µs of CPU per streamed token; the engine
spends 25–90 ms. Nothing is worth porting. The one slow Node path — fitting a long tool
result to the model's budget re-rendered every surviving record on every step — is now
linear: a 500-record listing reduces in 0.5 ms instead of 53, byte-identical. Study and
numbers: `docs/research-language-consolidation.md`; rerun with
`apps/web/scripts/profile-hot-paths.cjs`.

### 2026-09-21 — The Code tab, full height and honest about the network (2d7ba8f)

The chat composer no longer sits under the Code tab, which left the task form half the height
with an unrelated send button below it. And because this server runs no egress proxy, "Reach the
network" and "Install dependencies" are shown unavailable with the reason — and the server no
longer grants them — instead of being accepted and then quietly never happening.

### 2026-09-21 — "Thought for 12s" (bbae129)

A reasoning reply now says how long the model thought — from its first thought to the first word
of the answer, or to the tool it decided to use — measured as it streamed and kept with the chat.
Older chats, and ones streamed on another device, fall back to the length of the thinking.

### 2026-09-21 — A quieter chat footer (5ae8d7f)

The context meter no longer takes a row above the composer to say "Calculated when you send":
a short chat that has not been measured shows nothing, a measured one shows a single quiet line
aligned with the composer, and a long unmeasured chat still offers compaction. It is read when
a chat opens and when a reply finishes, instead of every three seconds for every open chat.
"Thought for 312 words" now reads "Thought · 312 words".

### 2026-09-21 — Templates for new Diary files (a1ededd)

A `Templates` folder at the Diary's root — Obsidian's convention — is offered when a new file is
still empty. `{{title}}`, `{{date}}` and `{{time}}` are filled in (with optional formats, as in
Obsidian); anything else in braces stays as written. Nothing is saved until you save.

### 2026-09-21 — Unlinked mentions (780b8c7)

"Find links to this file" also lists the notes that name it in prose without linking it — whole
words, case-insensitive, never inside code or properties. They are shown, not rewritten: turning
a mention into a link is an edit to someone's note, and edits here are explicit.

### 2026-09-21 — Auto-tune says what it is doing, as it does it (f66ecd2)

A run is 5–15 minutes of a progress bar that can sit still for a minute while the engine
loads, and a still screen reads as nothing happening. Auto-tune now keeps a timed, line-by-line
account: each test and the exact settings it writes, "still loading · 25s" while the engine
loads, every workload's speed and draft acceptance, why a candidate was rejected, what it chose
and why, and whether the original settings were put back after a cancel. It follows the newest
line while running, and folds away once the run is done. The panel now refreshes every second.

### 2026-09-21 — A note's properties, and the tags a vault really uses (5b0e531)

A leading YAML block is shown as the properties it is rather than as three dashes and a list of
keys pretending to be prose; a line the reader cannot parse is shown as written rather than
dropped. The tag filter now also reads the `tags:` property, which is where a diary written in
Obsidian keeps its tags — excluding it meant the filter quietly missed most of them.

### 2026-09-21 — Documents in folders could not be read (c237480)

### 2026-09-21 — Typing [[ offers the files you could mean (71f1ab0)

The Markdown editor suggests the files in the folder as soon as you type `[[`, inserts the
shortest name that is unambiguous and closes the brackets for you. Arrow keys choose, Enter or
click inserts, Escape leaves what you typed alone. It stays a textarea throughout — the
suggestions are an offer beside it, not a form control.

### 2026-09-21 — The Docling sidecar is deployed

Document extraction now uses the sidecar that was verified in September and then sat unused:
reading order, table structure, and the Office, OpenDocument, HTML and image formats that were
previously stored whole and unread. CPU-only, so it never contends with the engine for VRAM.

### 2026-09-21 — Obsidian-style [[links]] in the Diary (f72c2a6)

A vault written in Obsidian is full of `[[wiki links]]`, and noevia rendered every one as
literal text and found none of them when asked what links to a file. They now render as links,
open the file, and count as backlinks alongside relative Markdown links. Aliases, heading and
block anchors and the `![[embed]]` form are all recognised; a link to a file that is not there
is shown as the writer wrote it rather than as a button that opens nothing. Nothing is
rewritten: the vault stays exactly as its owner left it.

### 2026-09-21 — Connect an app to the Diary in Settings (6eb1698)

Connected apps is a section of Settings → Diary & storage: name it, copy the credential once,
revoke it in one click. It replaces `diary-connector-admin.cjs`, a script an administrator had
to run on the server. Also removed: two components nothing rendered, and the CSS of two
interfaces that no longer exist (the old Code sidebar and the old Diary landing).

### 2026-09-21 — Code mode runs, and is on (f57dd21)

### 2026-09-21 — Usage: peak hour, favourite model, tool calls (b126eb6)

### 2026-09-21 — The project screen (05cc153)

### 2026-09-21 — Nextcloud is a connector of its own (5379771)

### 2026-09-21 — Routing split; Projects tab (76865e1)

### 2026-09-20 — Models page: one tab bar (a73a72d)

### 2026-09-20 — README, icon set, last Cowork prose (d99c066)

### 2026-09-20 — Add an MCP server by URL (06f5aa4)

### 2026-09-20 — Routing panel spacing and width (8b458e9)

### 2026-09-20 — The UI and MCP branch is merged into main (b8d78a9)

### 2026-09-19 — Models page: faster, cards side by side, one toolbar (06f9402)

### 2026-09-19 — Diary from Code; model and tools panel reworked (d459867)

### 2026-09-19 — Per-account API keys for directory MCP servers (da5dfa9)

### 2026-09-19 — Hand-registered apps for MCP sign-in (3f3ff1e)

### 2026-09-19 — Per-account OAuth sign-in for directory MCP servers (c173952)

### 2026-09-19 — Sign-in keys for directory MCP servers (e4fc0d3)

### 2026-09-19 — Skills auto-load; skills and MCP servers from the directory; long model names (6330ea8)

### 2026-09-19 — Settings no longer reopens on a quick reload (a163543)

### 2026-09-19 — Model picker Tune button back to 44px (957e972)

### 2026-09-19 — Engine holds the embedding model beside the chat model (ba95afa)

### 2026-09-19 — Tool routing: "Using:" line and ask-for-more (41cb2aa)

### 2026-09-19 — Re-fit after zoom (363171c)

### 2026-09-19 — Tall screens: full layout from 520px, pages grow, greeting centred (c71a30d)

### 2026-09-19 — Shrink-to-fit for slightly-too-tall pages and menus (70631b0)

### 2026-09-19 — One sidebar for Chat and Code; Plugins page (f87b157)

### 2026-09-18 — iOS keyboard fix; web image flattened (027bd00)

### 2026-09-18 — Composer focus, iOS keyboard, phone Settings (d995cd9)

### 2026-09-18 — Visual pass (7326ac0)

### 2026-09-18 — Sidebar header and phone drawer like Claude's (4c151be)

### 2026-09-18 — Diary in the bottom bar, sliding Chat/Code, project colours (5cd033b)

### 2026-09-18 — Icon centring scoped; row options beside the title (5a0e026)

### 2026-09-18 — Composer like Claude's, SVG icons (350050e)

### 2026-09-18 — Account menu and Search like Claude (91a89ba)

### 2026-09-18 — Collapsed sidebar like ChatGPT's (94909d3)

### 2026-09-18 — Settings and sidebar organised like ChatGPT (4152d15)

### 2026-09-18 — Sidebar as one scrolling plane (4ea3282, 95eacd6)

### 2026-09-18 — Material 3 and phone fixes (265c650, 6930549)

### 2026-09-18 — Phone review fixes (3d20de0, a2a1c8e, e777259)

### 2026-09-18 — UI overhaul release 3 and phone-review fixes

## 2026-09-14 — Qualified direct native inference in production

### 2026-09-14 — Markdown date/tag filters

### 2026-09-14 — native model UI and mobile approvals

# Changelog

## Mobile viewport and native adapter release — 2026-09-14

Newest first. Merged from `QA-2026-09-08.md` and `review-fixes.md`.

Dependency audits report known advisories; they are not a guarantee that software
is free of vulnerabilities. Keep dependencies, the host, and the inference services
updated.

---

## Calendar landing rollout — 2026-09-14

## Diary workspace, model guidance and context rails — 2026-09-14

## Chat context budgeting and compaction — 2026-09-10

Added ordinary/project-chat context meter above the composer with an expandable
breakdown of messages/summary, instructions/memory/sources, tools, generation
reserve, safety buffer and free space. Counts are conservative UTF-8 estimates,
not exact tokenizer or account totals; unknown limits use a labelled 8k fallback.
Lemonade uses the loaded model's configured ctx_size, not its architecture maximum.
The first prepared request establishes the meter; later visible output updates
its estimate. Existing chats can use Compact chat before sending another turn.

Requests reserve up to 4,096 generation tokens and 15% estimation margin; automatic
compaction triggers when input exceeds the remainder (about 72% for 32k). High
effort cannot expand or discard this budget. Tool continuations are rechecked;
context errors inside SSE are surfaced, and heartbeat frames cover silent waits.
No automatic retry of tools or writes. Configured capacity is not a guarantee of
available shared-backend memory, and non-Lemonade model limits remain a fallback.

## 2026-09-10 — shared Diary server connector and Nextcloud push repair

## 2026-09-10 — oversized PDFs and native local-Qwen thinking

## 2026-09-10 — MTP controls, acceptance and fixed inference footer

## 2026-09-10 — live Diary progress and long-request connection

## 2026-09-10 — Diary reading and reasoning feedback

## 2026-09-10 — skill metadata names the file to load

## 2026-09-10 — explicit Diary and storage choices during setup

Fresh setup asks Diary/chat before account creation. Storage offers server-held
or existing external service choices; skipping and failed saves preserve the
configuration. The picker waits for saved settings before editing or saving.
Admin preferences include the existing thinking default. 310 web tests,
typecheck/build, 171 Diary tests (3 skipped) and expanded synthetic browser checks
pass. Existing completed users remain completed. Rollout pending.

## 2026-09-10 — optional bounded Diary file sharing

## 2026-09-10 — revocable device app passwords

## 2026-09-10 — DOCX main-body text and tables

## 2026-09-10 — engine throughput omits unstable short samples

## 2026-09-10 — reasoning-only output is no longer presented as an answer

## 2026-09-10 — thinking effort reports what the provider receives

## 2026-09-10 — Diary components are easier to maintain

## 2026-09-10 — Diary landing reflects its actual contents

## 2026-09-10 — first-entry folders survive interrupted writes

## 2026-09-10 — older entries remain available without semantic matches

## 2026-09-10 — landing Diary messages follow the selected day

## 2026-09-10 — resumable member onboarding and explicit Diary choices

Invitations inherited a completed-onboarding default, skipping setup entirely.
New invitees now start incomplete, and members get Diary/preferences/passkeys
without administrator setup or global model controls. Saved Diary choices hydrate
the wizard immediately; updates persist with visible failures and retained focus.
Back and sign-out/resume clarify navigation; the dead-end models step is removed.
Completion preserves existing consent and defaults missing rows off. The separate
legacy feature backfill no longer re-enables missing rows on each restart.

## 2026-09-10 — shared composers and opt-in Diary context

Project landing pages and Diary lacked the composer controls, and free chats could
not retain their own attachments/tool selection. All functional chat composers now
share the + menu. Diary extras are opt-in for the current session and off on reload;
its normal retrieval/capture remains active. Preparation uses the existing MCP
approvals and tool loop, then supplies bounded reference to the diary companion.
Attachments stay outside the diary corpus. See the audit for test evidence and
behavioral boundaries.

## 2026-09-10 — composer files and tool controls

Tools and uploads were buried outside the conversation. A + control now opens
a compact menu above the chat composer: Files and photos, Tools grouped into
Built-in/Connectors, and Model and routing. Project tool selections use the
existing permission-checked configuration route; all three write approvals remain.
Uploads retain the existing file limits, organized Nextcloud storage, and progress.
No skills or plugin execution features are implied by this menu.

## 2026-09-10 — unified uploads and visible processing

Earlier local image uploads are copied to connected storage on refresh. Transfer
percentage and per-file elapsed time are distinct from saving/extraction stages;
image chat exposes preparation status before model processing. The obsolete 1 MB
background request cap and 40-file refresh cap were corrected. The project quota
remains 60 total sources, with regression coverage for a 41-file refresh.

## 2026-09-10 — bounded reliability, OCR and image rollout

## 2026-09-08 — development continuation and QA

Based on a clean `0f8a9c1` checkout. The older UI master prompt was treated as
design context; much of its implementation was already present.

### Environment and build

- Fresh startup creates the state directory before writing its encryption key.
- **Dev, build and type-check scripts now invoke Node directly**, fixing the
  long-standing "`npm run typecheck` is broken" workaround. Vite uses the runner
  config loader, avoiding temporary writes inside the external dependency symlink.

### Projects and sources

### Vision

- Probes are scoped to endpoint, credentials and model, with expiring results.
  Missing projectors and availability failures now have **distinct, actionable
  explanations** shown in chat — previously a 500 ("maybe missing mmproj") was
  conflated with a 400 ("model cannot do this"), which is what led to
  "Qwen3.5-9B is blind" being asserted wrongly.
- Image-description cache keys include the user, provider endpoint and full
  question. Provider authorization runs before image requests; vision requests
  refuse redirects and respond to chat cancellation.

### Tools and approvals

- Repeated tool calls across inference rounds retain distinct chip identities.
- Pending approvals keep their full arguments and all three decision buttons.

### UI and accessibility

- Mobile chat breadcrumbs truncate long names without hiding Settings or the
  inspector. Project headings reserve inspector space. Tool results use a compact
  layout; approval arguments remain fully visible and wrap.
- Mobile Settings uses a category selector so forms get full width. Provider fields
  have accessible labels. The diary navigation-expand control is restored on phones.
- Project/model dialogs use native modality, Escape dismissal and focus restoration.
  Keyboard activation of a card's child controls no longer opens the project.
  Filter/archive empty states are explicit.
- Creation uses shared text-file validation rather than reading arbitrary selected
  binaries as text. Project initials use theme text contrast; the initial browser
  theme colour matches the dark canvas.
- `MarkdownPreview`: parenthesized links and tables now render.

### Verification

Web **161 passed** (11 new regressions); diary **145 passed, 3 skipped** (no diary
implementation changes); typecheck, build and `git diff --check` all passed.

### Deployment note

---

## Earlier — diary conversation and reliability update

Diary questions now receive thoughtful replies directly in the diary conversation.
**The separate Insights screen, reflection endpoints and activity badge were
removed.** The logger still preserves the user's own words separately from
assistant commentary.

Clearer diary and chat composers, consistent focus states, better text contrast,
calmer cards, mobile layout adjustments, reduced-motion support. Setup completion is
acknowledged by the server before exiting, and unfinished onboarding resumes after
sign-in.

### Reliability and security

### Verification

Node suite covers provider deletion, first-round model failures, split SSE, redirect
refusal, request limits and approved-origin checks. Diary tests cover failed-edit
acknowledgment, crash recovery, stale-retrieval exclusion, empty-document cleanup
and refusal of nonconforming S3 stores. The UI was exercised with an isolated local
fixture using synthetic responses.

---

## 2026-09-09 — deployed `f6832bf`

- `d8a6f2c` journal poison pill — one malformed entry no longer blocks every
  subsequent diary write.
- `def7c18` state directory permissions — parents of a nested state path took the
  umask rather than `0o700`.
- `f6832bf` docs consolidated from ten files to nine; the old
  `noevia-design-system.md` palette was stale and would have reintroduced the
  fire-engine red the UI overhaul removed.

**Not yet verified against real data** — these need an authenticated browser
session and were not done: a real diary write (the poison-pill fix is in exactly
that path), a Nextcloud upload, and one MCP write approval.

### Incident during this deploy

The working tree's entire `docs/` directory disappeared mid-session — all nine
files at once, after they were committed and pushed. This is the same Nextcloud
eviction that previously ate `dist/assets` and `node_modules`. Nothing was lost
(`git checkout -- docs/` restored it, and `origin/main` was never affected), but
it is a reminder that this checkout lives on a sync client that removes files
underneath you. Commit early; do not treat the working tree as durable storage.

## 2026-09-09 — aux model 404, found while verifying the deploy

It hid because the pipeline degrades gracefully: `summarizer failed (...);
logging verbatim assistant reply`. Entries kept being written correctly and only
lost their `— Topic` headers. September 5–9 have 0 topics across 75 time headers.

Historic entries were **not** backfilled. `/api/relog` looks like the tool for it
and is not: it re-logs an exchange from the *current in-memory session* at
`now=datetime.now()`, with an empty `sub_header`. Pointed at old entries it would
append duplicates stamped today rather than repair anything.

Tests: 151 python (+4), 162 node.

## Model manager: settings-native styling, layout mode, working search — 2026-09-17

Settings → Models & routing now draws on the same surfaces, radii, type scale and control
sizes as the rest of the settings pane; see design-system.md. No class names or tab
structure changed.

Hugging Face search no longer asks the hub for `full=true`. That parameter existed only to
fill in a per-repo GGUF file count, and it made the hub serialize every sibling file of
every hit — against the client's 20s timeout an ordinary browse of the top 30 GGUF repos
could time out and surface as "Network error" with an empty list. The count is now shown
only when the hub volunteers it. A named search that the `gguf` tag filter answers with
nothing is retried once without the filter and narrowed to repos that look like GGUF, so a
repo the hub has not tagged is still findable; browse mode (no query) is not retried, since
an untagged top-30 is not a GGUF browse. Failures are reported with the reason — a 401/403
points at the saved token, a 429 explains that a token raises the rate limit — instead of a
bare status code, and owner avatars, which noevia's Download tab never renders, can no
longer fail the search. Changing Sort by re-runs the search, and the empty state
distinguishes "nothing matched your search" from "the browse list came back empty".

New: a Layout control (Automatic / Phone / Desktop) backed by `public/layout-mode.js` and
user-agent detection. It sits in Settings → Appearance.

Verified locally: `npm run typecheck` and `npm run build` clean; web tests unchanged from
this checkout's baseline (274 pass, 45 pre-existing environment failures, identical before
and after); model-manager Python tests 19 passed, including 8 new ones covering the search
query, both fallbacks and the error messages. The hub itself was not reachable from the
development environment, so the search changes are verified against a mocked hub only.

## Merged main (PR #1) into the model-tuning branch — 2026-09-17

Four files conflicted, all of them touched by both PR #1 and Discover. Decisions:

`hf.py` never conflicted — this branch does not touch it, so PR #1's search fix applies to
Discover unchanged. Dropping `full=true` costs Discover nothing either: it already fetches
repo trees itself, because the hub's search response carries no file sizes.

Corrected wrapped Material 3 segmented boundaries and role-paired hover/pressed
states for the mode switch, menus, outlined and destructive buttons. Liquid primary
actions retain legible primary colors during interaction, including in dialogs.
No geometry or application behavior changed. The cloud browser binary was unavailable;
rendered review remains pending. See [audit continuation](material-audit-2026-09-22.md).

The test runner now isolates state and restricts outbound sockets to disposable
fixture ports. The SSRF and egress disconnect tests no longer target arbitrary
host-local ports. All 1,247 guarded tests pass, along with typecheck, build and
design lint; the cloud browser blocks the local fixture, so visual QA is pending.
