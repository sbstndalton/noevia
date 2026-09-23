# Constrain download credentials and require experiment authentication

Implemented for review; not merged or deployed. Issues: [#10](https://github.com/sbstndalton/noevia/issues/10), [#11](https://github.com/sbstndalton/noevia/issues/11).

Hugging Face download authentication now uses an exact parsed HTTPS origin, rejects userinfo and non-default ports, and normalizes host case. A request hook re-evaluates authorization on every HEAD/GET and redirect, including parallel ranged GETs sent to the URL resolved by HEAD. Account tokens are removed before CDN/cross-origin requests; resume and range behavior remain covered.

The Docker-socket-mounted, LAN-published model-loader experiment now requires a non-empty `MODEL_LOADER_TOKEN` through Compose required-variable interpolation. Its README documents private token storage and the header; only health is public.

Validation: 67 model-manager tests pass (four existing FastAPI deprecation warnings). Synthetic HTTPX transports capture exact-origin, lookalike/path/query/downgrade, redirect, resumed and parallel-range requests; URL cases include userinfo, ports, malformed hosts and case normalization. The compose regression asserts required auth; existing API tests verify 401 without/wrong token, success with the synthetic token, and public health. 1,247 web tests, typecheck, production build and design lint pass.

Limits: Docker/Compose is unavailable locally, so actual Compose interpolation and image startup were not executed. No real token, download, model operation or production service was used.
