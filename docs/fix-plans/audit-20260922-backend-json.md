# Backend malformed JSON implementation plan

Issue: [#4](https://github.com/sbstndalton/noevia/issues/4)

## Scope

Normalize malformed-body handling for background project source operations, Diary local exchange, and the authenticated Diary connector. Preserve each endpoint's existing size limit and valid request behavior.

## Implementation

1. Add or extend a bounded JSON parsing helper in `server/http.cjs` so parse failures carry status 400 and a stable public message. Allow callers to supply their existing body-size limit.
2. Inject that helper through the project and Diary route factories. Parse each body once; serialize the already validated value only where the source-job dispatcher requires a new stream.
3. In local exchange, use the parsed value to choose streaming while forwarding a canonical JSON body. In the connector, validate before calling `operate` or auditing.
4. Keep the top-level error boundary for unexpected failures; do not broadly convert arbitrary route errors into 400 responses.

## Verification

- Route tests send malformed JSON to all three background source variants, local exchange, and Diary connector, asserting 400 with `invalid JSON`.
- Spies prove no source job, sidecar request, stream proxy, connector operation, or audit write starts.
- Existing valid streaming and connector write tests remain green.
- Run `npm test`, `npm run typecheck`, and `npm run build` from `apps/web`.

## Risks

Changing serialization can affect large uploads or streaming selection. Preserve endpoint-specific limits and avoid reading a body twice. Connector authentication and CSRF/origin boundaries remain unchanged.
