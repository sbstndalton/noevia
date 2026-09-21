# 8. OAuth / subscription support matrix (verified 2026-09-21)

**Question:** can a noevia user legitimately bring an existing AI subscription, through officially
supported authentication, instead of a metered API key?

**Short answer:** not for noevia's own chat. The one legitimate subscription path in 2026 is to run
the vendor's **own, unmodified client** (Claude Code, Codex CLI) and let the user sign in to it
through the vendor's own flow. That is a *harness* in Code mode, not an inference provider noevia
calls.

Evidence labels: **[P]** primary source (vendor docs or terms, read directly); **[C]** secondary or
community.

| Provider | Official third-party OAuth? | Does OAuth give inference? | Consumer plan includes programmatic inference? | Official CLI/SDK on subscription auth | Can noevia legitimately use it? |
|---|---|---|---|---|---|
| **Anthropic / Claude** | No for third parties. "Anthropic does not permit third-party developers to offer Claude.ai login … or to route requests through Free, Pro, or Max plan credentials" [P code.claude.com/docs/en/legal-and-compliance]. Server-side enforcement from Jan 2026, terms updated 19–20 Feb 2026 [C] | only inside Claude Code / native apps | No (API is separate, metered via Console) [P] | **Claude Code** (OAuth), Agent SDK is **API key only** for developers [P] | **Chat: no.** **Code mode: yes, narrowly** — running the *unmodified* Claude Code binary where "an end user sign[s] in … with their own Claude subscription" is expressly allowed; noevia must not collect, store or intermediate the credentials, and sign-in must complete through Anthropic's flow [P] |
| **OpenAI / ChatGPT** | No general programme. Codex docs: ChatGPT sign-in is for Codex clients and "isn't intended for third-party integrations" [P learn.chatgpt.com/docs/auth]. OpenAI tolerates third-party harnesses (OpenCode, Cline, pi named in the Codex-for-OSS page) but the page does not grant general subscription use [P developers.openai.com/community/codex-for-oss]; Cline ships a "bring your ChatGPT subscription" integration [C] | only through Codex | No — API billed separately | **Codex CLI / IDE / app**: ChatGPT sign-in or API key; token auto-refresh in `~/.codex/auth.json`; device-code flow (beta) for headless [P] | **Chat: no.** **Code mode: yes via the unmodified Codex CLI**, user signs in inside it (device code for a headless sandbox). Using the Codex OAuth token from noevia's own code: tolerated in practice, **not documented as permitted — do not build on it** |
| **Google / Gemini** | Gemini **API** supports OAuth user credentials (`cloud-platform`, `generative-language.retriever` scopes); app verification needed for external users; billing is the user's Cloud project, not a consumer plan [P ai.google.dev/gemini-api/docs/oauth] | Yes, but API quota, not a subscription | No: using Gemini CLI's OAuth from third-party software "is a violation of applicable terms" [P geminicli.com/docs/resources/tos-privacy]; personal Login-with-Google for Gemini CLI ended 18 Jun 2026 (replaced by Antigravity CLI) [P] | Gemini CLI (now Antigravity CLI for consumers); API keys; Vertex | **Chat: only as a normal Gemini API provider** (API key, or OAuth against the user's own Cloud project — free-tier quota, then metered). No subscription reuse |
| **DeepSeek** | No OAuth | — | No subscription exists at all [C, consistent with api-docs.deepseek.com] | API key only [P api-docs.deepseek.com] | **Metered API key only** |
| **Z.ai / GLM** | No OAuth; Coding Plan uses a plan-specific **API key** [P docs.z.ai/devpack/quick-start] | — | Coding Plan is "strictly limited to use within officially supported tools" — list includes **OpenCode**, Claude Code, Cline, Crush, Goose … [P] | the listed tools | **Chat: no** (not a listed tool). **Code mode: plausibly yes** — noevia's harness *is* OpenCode, a listed tool, so a user's Coding Plan key configured *into OpenCode* is inside the stated scope. Confirm with Z.ai before shipping |
| **Qwen / Alibaba** | Qwen Code's free OAuth tier **discontinued 15 Apr 2026** [C, QwenLM/qwen-code#3316] | — | Alibaba **Coding Plan**: "Do not use the plan's API key for automated scripts, custom application backends, or any non-interactive … scenarios"; interactive coding tools only [P alibabacloud.com/help/en/model-studio/coding-plan] | Qwen Code, Claude Code, OpenClaw… | **Chat: no.** **Code mode: only if OpenCode counts as a supported interactive tool — unclear; treat as no until confirmed.** Model Studio pay-as-you-go API key: yes (metered) |
| **OpenRouter** | **Yes — official OAuth PKCE for third-party apps**; the app receives a user-scoped API key, no client registration [P openrouter.ai/docs/guides/overview/auth/oauth] | Yes | n/a (credit balance, metered) | — | **Yes, metered.** The one clean "sign in with your account" provider flow; cost class METERED |

## Answers to the ten questions, condensed

1. **Official third-party OAuth:** OpenRouter (PKCE) yes; Google yes for the *API* (Cloud project
   billing); Anthropic, OpenAI, DeepSeek, Z.ai and Qwen no.
2. **OAuth gives inference:** OpenRouter and Google API, yes. Anthropic and OpenAI, only inside
   their own clients.
3. **A consumer subscription includes programmatic inference:** no provider verified says so for
   third-party apps.
4. **Official CLIs on subscription auth:** Claude Code, Codex CLI, and Gemini/Antigravity CLI
   (Google-internal only). Coding Plans (Z.ai, Alibaba) use plan keys inside listed tools.
5. **noevia can legitimately use:**
   - OpenRouter PKCE (metered);
   - Gemini API (API key or OAuth, the user's own project);
   - the unmodified Claude Code or Codex CLI as Code-mode harnesses signed in by the user;
   - probably a Z.ai Coding Plan key configured inside OpenCode (to confirm with Z.ai).
6. **Scopes:** OpenRouter issues a key (no scopes). Google uses `cloud-platform` or
   `generative-language.*`. The vendor CLIs manage their own scopes.
7. **Refresh:** Codex refreshes automatically (`auth.json`). Claude Code and the Antigravity CLI
   manage their own tokens. An OpenRouter key does not expire until revoked. Google uses standard
   refresh tokens.
8. **Limits:** plan-defined, variable, and not programmatically queryable in most cases. Claude
   says plan limits "assume ordinary, individual usage" [P].
9. **Terms:** Anthropic and Google forbid reuse of subscription OAuth in third-party software.
   OpenAI is silent-to-negative. Z.ai and Alibaba restrict plan keys to listed interactive tools.
10. **Interactive-only:** yes for every subscription flow.
    - Headless is supported only through vendor device-code flows inside the vendor's own client.
    - Alibaba explicitly forbids non-interactive use.

## Consequences for the design

- **Tier 4 ("subscription") is a Code-mode harness tier, not a chat provider tier.** In chat,
  escalation beyond local is **metered** (Tier 5), full stop, unless a future vendor programme
  changes this. Record the date; this is re-checked each release.
- The subscription path must keep noevia out of the credential path entirely:
  - the vendor binary runs unmodified in the sandbox;
  - the user signs in through the vendor's own flow, in their own browser (device code);
  - the token lives in the sandbox volume that belongs to that user;
  - noevia never reads it.
  This preserves tenant isolation, and fits the existing roadmap item "other harnesses", which the
  user has deferred.
- **What noevia must never do** (and this matrix does not propose): scrape cookies, extract session
  tokens, reuse a CLI's OAuth token from noevia's own HTTP client, impersonate an official client,
  or proxy one user's subscription for another.
