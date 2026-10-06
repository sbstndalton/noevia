# Third-party notices

## scratchhax/model-loader

`apps/web/server/gguf-meta.cjs` and `apps/web/server/llamacpp-autoconfig.cjs` adapt the
GGUF metadata reader and KV-cache/projector sizing from
[scratchhax/model-loader](https://github.com/scratchhax/model-loader) at commit
`e11a6ec307fa405144678930d507046163369b46`, under the MIT License. The full source is
folded into `services/model-manager` (see its `UPSTREAM.md`); noevia's changes are in git
history after the import commit:

```
MIT License

Copyright (c) 2026 scratchhax

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Inter and Source Serif 4 (SIL Open Font License 1.1)

`apps/web/src/styles/system/fonts/` self-hosts the variable web fonts (latin subsets, as
packaged by Fontsource):

- Inter, Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter).
- Source Serif 4, Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name
  'Source' (https://github.com/adobe-fonts/source-serif).

Both are licensed under the SIL Open Font License, Version 1.1:
https://openfontlicense.org/open-font-license-official-text/. The fonts are bundled with the
web app unmodified and are not sold on their own.

## Impeccable (Apache-2.0)

`.claude/skills/impeccable/` is the Impeccable agent skill v4.3.1 from
https://github.com/pbakaus/impeccable, Apache License 2.0 (`.claude/skills/impeccable/LICENSE`).
Development tooling only; not part of the shipped image.

## EvanZhouDev/openai-oauth and openai/codex (Apache-2.0)

`apps/web/server/chatgpt-oauth.cjs` (Sign in with ChatGPT, #447) is a CommonJS rewrite, with no
dependency on either package, of logic from two Apache-2.0 projects. Neither package is installed.

- [openai-oauth](https://github.com/EvanZhouDev/openai-oauth) at commit
  `ec7dab2fcd8dab9da970a7a2b5dc34046c94905e`: the OAuth token exchange and refresh requests, the
  ChatGPT account-id claim, the Codex backend request headers and the Responses request
  normalisation (`packages/core/src/runtime.ts`), and the Responses-to-chat-completions mapping
  (`packages/openai-oauth/src/chat-*.ts`). Its NOTICE:

  ```
  OpenAI OAuth
  Copyright 2026 Evan Zhou and OpenAI OAuth contributors

  https://github.com/EvanZhouDev/openai-oauth

  This product is licensed under the Apache License, Version 2.0.
  ```

- [OpenAI Codex](https://github.com/openai/codex): the device-code sign-in endpoints and flow
  (`codex-rs/login/src/device_code_auth.rs`). Its NOTICE begins:

  ```
  OpenAI Codex
  Copyright 2025 OpenAI
  ```

- Fixes from openai-oauth's open pull requests and issues, and from forks, all under the same
  Apache-2.0 licence and re-implemented here rather than copied: tool strictness defaulting to
  false (PR #44, augusto-rehfeldt@27f3a60); `json_schema` response_format (PRs #9/#40,
  cruzanstx@06aa1b0); stripping `prompt_cache_retention` / `safety_identifier` / sampling fields
  (PR #38, issue #22, PR #7, dongmin-j-lee@cb52448); rebuilding output from streamed items (PR #11,
  YangKeao@7633d09); explicit error frames instead of 200 + a cut-off stream (issue #39);
  reasoning summaries (YangKeao@d72dec5, twaldin@b471a45); completed/incomplete terminal handling,
  soft refresh failures and the model allowlist from
  [plgonzalezrx8/openai-oauth](https://github.com/plgonzalezrx8/openai-oauth) (1bc2913, 3b04587).
  Protocol headers were checked against openai/codex itself (commit `985cf47`), not taken from
  QuartzWarrior@7100902.

Changes: rewritten in CommonJS for the web server; per-user encrypted token storage through
`secrets.cjs` instead of `~/.codex/auth.json`; single-flight refresh; the device-code flow instead
of the loopback redirect; no Vercel AI SDK. Full licence text:
`apps/web/server/LICENSE-APACHE-2.0.txt`.
