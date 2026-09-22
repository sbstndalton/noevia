# Shared decision-service configuration — 2026-09-22

Settings → Server → Experimental now contains Decision service setup above the switches:
private Laya-compatible endpoint, deadline (100–1500 ms), Use installed Laya,
Test connection, and Save. Test is GET /health only and requires ready:true; no inference.
The endpoint must pass the existing private-origin allowlist and cannot include credentials,
paths, query strings or redirects. The currently supported decision protocol is the private
typed-decision API, not a remote chat-completions endpoint. Answering models continue to use
AI providers, including OpenRouter/OpenAI-compatible configurations.

Admin-only GET/PUT /api/admin/decision-settings and POST /api/admin/decision-settings/test
reuse the existing auth/CSRF gate and auth database settings table. A single
`decision:configuration` record stores the URL and timeout; deployment environment supplies
the initial default. Saving is audited and takes precedence over that default. Existing
feature flags remain authoritative and operator feature locks still apply. Changes affect
subsequent decisions without restart; in-flight requests keep their captured configuration.
No parallel state store, API-key store, downloader or model manager is introduced.

Both experimental paths now share the configured endpoint. System-One routing uses its
Fast/Smart and optional Code options with the same validated Laya choice transport used by
Step supervision. Manual model selection still bypasses routing. Endpoint replacement
rebuilds the backend and its routing circuit breaker. The old COWORK_SYSTEM_ONE_URL
option-logit backend remains a compatibility fallback when no shared decision service is
configured. It is no longer required for a Laya deployment. Step supervision keeps its
existing verification/review behavior and now respects the saved deadline.

Verification: 1192 web tests pass, including five new shared-configuration/route tests,
plus typecheck, build and design lint. Tests cover persistence, immediate switch availability,
invalid settings preserving active configuration, readiness failures, admin-only access,
mocked Laya Fast/Smart choices and live endpoint replacement. Browser fixture checked save,
reload persistence, connection feedback, invalid URL feedback/focus, activation, dark/light
presentation and no overflow at 375/768/1440 CSS pixels. No all-view sweep or new real
inference/benchmark/paid request was run for this change; production verification uses health.
