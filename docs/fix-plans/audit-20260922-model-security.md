# Model-manager download and experiment security plan

Issues: [#10](https://github.com/sbstndalton/noevia/issues/10), [#11](https://github.com/sbstndalton/noevia/issues/11)

## Scope

Constrain Hugging Face credentials to approved HTTPS origins and make the Docker-socket experiment require authentication when published beyond loopback.

## Implementation

1. Replace substring matching in `downloader.py` with a parsed-origin allowlist shared with Hugging Face URL construction. Reject ambiguous URL forms and attach bearer auth only to exact approved HTTPS hosts.
2. Handle redirects explicitly or use a client policy that demonstrably strips auth before any cross-origin request. Re-evaluate the destination at every hop; retain range/resume behavior.
3. Add `MODEL_LOADER_TOKEN` to the experiment compose with required-variable syntax and document generation/storage. Keep the health endpoint policy explicit.
4. Add a static compose/preflight assertion for any non-loopback, Docker-socket-mounted manager lacking mandatory auth.

## Verification

- Synthetic HTTP servers capture HEAD, ranged GET, and redirect headers for exact Hugging Face, lookalike, and cross-origin destinations.
- URL cases include userinfo, case normalization, ports, and malformed hosts.
- Compose config fails without a token; API tests prove unauthenticated privileged requests return 401 and the synthetic token succeeds.
- Run the model-manager pytest suite and deployment preflight tests.

## Risks

Hugging Face downloads may redirect to content hosts; the allowlist/redirect design must support required hosts without sending the account token to arbitrary storage domains. Do not print tokens in compose diagnostics or tests.
