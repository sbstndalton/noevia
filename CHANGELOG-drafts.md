# Changelog drafts — `DaServer.md` rows, written before execution (rule: never after the fact)

These rows are appended to `DaServer.md`'s Changelog table as each gated step executes
(copy the row text verbatim; dates updated to the execution date).

## Row 0 — openwork/Lemonade provider config (Mac-side, spec §3)

| 2026-09-02 | OpenWork (Mac) configured against Lemonade: `~/.config/opencode/opencode.json` adds custom OpenAI-compatible provider at `http://10.69.0.130:13305/v1` (E4B default model, E2B small_model, GPT-OSS-20B listed). Config-only change on the Mac; Lemonade endpoint untouched and remains directly reachable. | Spec §3 first step — Mac-native visible-action track wired to the existing inference boundary; no build item, one-line changelog per spec. |

## Row 1 — doc-drift fix (Step A)

| 2026-09-02 | Diary Companion doc-drift fix: server `config/config.yaml` `llm.embed_model` corrected `nomic-embed-text-v1.5.Q4_K_M` → `nomic-embed-text-v1-GGUF`, aligning the file with the runtime value already set via `.env` (2026-09-02 changelog). Retrieval index still empty → zero re-index cost; no container restart needed (runtime env unchanged). | Spec §4 flagged item resolved before any retrieval work; file now matches the live embedding lock. |

## Row 2 — stack staged (Step B)

| 2026-09-02 | Cowork Workspace stack staged at `/mnt/docker/appdata/cowork/` (compose: anythingllm + litellm + diary-companion sidecar; joins `lemonade_default`, no new exposed inference ports; AnythingLLM on port 8020). Secrets: LITELLM_MASTER_KEY/SALT_KEY + AnythingLLM JWT_SECRET generated fresh; DIARY_AUTH_TOKEN and all WebDAV credentials COPIED from the standalone diary-companion `.env` (nothing regenerated). LiteLLM config: aliases diary→sidecar `/v1`, e4b/e2b→Lemonade; gpt-oss-20b alias staged but commented (model absent from Lemonade's current catalog — second doc-drift noted, Phase 1b decides); cloud escape-hatch blocks present but commented (Phase 2, enabled:false-equivalent). Spike scratch corpus `Diary-spike-test/` created in Nextcloud for gated verification. | Build-spec v0.4 §2/§4/§5 with researched correction: AnythingLLM Generic OpenAI base URL is instance-wide (upstream #4243/#4493/#5084), so per-workspace endpoint routing is provided by a LiteLLM gateway container (user decision 2026-09-02); v1 customization = vanilla image + theming (user decision). Standalone container left running untouched. |

## Row 3 — stack up (Step C)

| 2026-09-02 | Cowork Workspace stack started (`docker compose up -d`): cowork-anythingllm (8020), cowork-litellm (internal), cowork-diary-companion (internal sidecar, separate `data/` SQLite, corpus root overridden to `Diary-spike-test` for the spike). Port 8020 confirmed free before up. | Spec §10.2 spike — verify workspace model + alias routing against live Lemonade and the sidecar pipeline before any cutover decision. |

## Row 4 — spike verified + cleanup (Steps D/E)

| 2026-09-02 | Cowork spike verification complete: [RESULTS PLACEHOLDER — fill with actual observed outcomes: E4B via LiteLLM ok; diary round-trip to Diary-spike-test (format/markers/INDEX.md); skip-classifier skip; real Diary/ untouched]. Scratch corpus `Diary-spike-test/` removed (user sign-off); cowork stack stopped or left running: [STATE]. Real diary corpus unmodified throughout. | Spec §10.2 gate evidence for the §4 sidecar path; standalone container continues to serve production traffic until cutover sign-off. |
