# MCP handshake cleanup

Issue: #33

Implemented: `connect()` now owns cleanup until it returns a successfully initialized session. If initialize response validation or the initialized notification fails after a session ID arrives, it attempts DELETE with the same credentials and protocol headers, then rethrows the original error. Cleanup is best effort and bounded by the smaller of the caller timeout and five seconds. No ID means no DELETE; successful connections remain owned by existing caller cleanup blocks.

## Verification

- 51 focused MCP tests passed, including handshake failure stages crossed with DELETE success, refusal, network failure and timeout; no-session and successful-session lifecycle checks.
- Full web suite: 1273 tests passed.
- Typecheck and production build passed.
- Independent Sol review: no actionable findings.
- Synthetic transports only; no live MCP endpoint, credential, or private corpus was used.

## Limits

Cleanup cannot force a remote server to honor DELETE or recover a session ID that was never received. Per-user authentication, response parsing, redirect restrictions, and session ownership after successful connect are unchanged. No shared session cache was introduced.
