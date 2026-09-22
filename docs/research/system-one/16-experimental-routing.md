# Experimental routing switch

Local source implementation, not deployed. Dedicated model selection is still open.
The option-logit adapter remains a comparison baseline, not a quality recommendation.

Settings → Server → Experimental contains System-One routing. It reuses `feature:`
settings in the auth database, admin authorization, CSRF protection, audit and
operator env locking. It is off by default. Admin changes affect subsequent Auto
role decisions; a decision already running completes with its original selection.
Manual model choices bypass this path. It does not switch models mid-turn or enable
durable replay. Tenant identity, tool execution, approval handling and the live
reranker are unchanged.

When on, `system-one-router.cjs` calls the existing validated decision layer with
Fast/Smart, plus Code only if configured. It sends at most 1000 characters of the
current routing message, not conversation histories or tenant records. No prompt
text is logged. A 1500 ms decision deadline aborts the adapter request. Invalid,
failed, tied or timed-out readouts return to the existing Auto classifier, including
its own existing timeout and heuristics. The 1500 ms limit covers the experiment,
not the fallback classifier or the whole chat turn. Repeated deadline misses use
the existing decision-layer circuit breaker. Scores are not calibrated correctness
probabilities.

An operator must set `COWORK_SYSTEM_ONE_URL` to a dedicated compatible llama.cpp
decision endpoint and restart the web process. Only loopback/localhost and private
IPv4 HTTP(S) origins are accepted; credentials, query strings and redirects are
rejected. This initial slice does not support authenticated endpoints or Docker
DNS names. It does not discover a model, start an engine, check quality, or download
weights. Configuration presence is not a health check. The UI refuses enablement
without valid configuration and shows why. Saved activation becomes ineffective
if configuration is removed; disabling remains possible. Operators can pin the
switch with `NOEVIA_FEATURE_SYSTEM_ONE_ROUTING` using the existing feature rules.

## Verification

From `apps/web`, with installed dependencies:

- `npm test`: 1170 passed, 0 failed. Six new tests cover switching and rollback,
  failure/deadline/malformed fallback, bounded isolated message inputs, permitted
  Code routing, endpoint restrictions, and persistent activation/configuration loss.
  Existing feature-route authorization and approval suites also pass.
- `npm run typecheck`: passed.
- `npm run build`: passed.
- `npm run lint:design`: passed.
- `git diff --check`: passed.

`node qa/experimental-fixture.cjs` served the real built UI and feature HTTP routes
with memory-only settings and synthetic APIs. Browser checks verified enable,
reload persistence, keyboard disable, navigation, light/dark presentation, and no
document overflow at 375 CSS pixels. A clean desktop screenshot was inspected at
the browser's normal viewport. The in-app browser's zoom/viewport combination
produced tiled captures under overrides; those captures are not a complete visual
certification. A full 375/768/1440 two-theme, all-view sweep was not repeated for
this settings-only change. Temporary fixture and browser override were removed.

No real inference, quality benchmark, endpoint compatibility check, model download,
engine change, personal source access, deployment or production activation occurred.
Live activation requires a chosen/configured decision endpoint and a deployment;
neither is included in this source-only batch.
