# Plan: close MCP sessions after partial handshake failure

Issue: #33

Status: plan only; implementation pending.

## Problem

The MCP transport stores a server-issued session ID while processing `initialize`. If response validation or the required initialized notification then fails, `connect()` rejects without returning the session. Discovery and tool callers cannot close it because their cleanup blocks begin only after a successful connect.

## Intended changes

- Put the complete initialize/initialized handshake behind one error boundary that retains access to its mutable session object.
- When any initialize response has supplied a session ID and response status/body/protocol validation or the later notification fails, perform one best-effort DELETE before rethrowing.
- Preserve the original handshake error regardless of DELETE refusal, timeout, malformed response, or network failure.
- Bound cleanup latency to no more than the smaller of the connect caller's timeout and the existing five-second disconnect default.
- Send no DELETE when no session ID was received.
- Keep the existing discovery and tool-call `finally` blocks for failures after connect succeeds; do not add session caching or change authentication scope.

## Acceptance criteria

- A failed initialized notification cannot strand a session ID returned by initialize.
- An initialize error status, malformed body, JSON-RPC error, or mismatched response that nevertheless supplies a session ID receives the same cleanup attempt.
- Cleanup failure never masks or replaces the original connect failure.
- Initialize failures without a session ID make no DELETE request.
- Successful discovery and tool calls continue to close their sessions exactly once with the same credentials and protocol headers.

## Verification

- Add transport tests for successful initialize plus failed notification, initialize error/malformed response with an ID header, and initialize failure without an ID.
- Cover DELETE success, refusal, timeout, and network rejection while asserting the original connect error.
- Assert cleanup carries the issued ID and auth headers and obeys the bounded timeout/redirect policy.
- Retain the existing successful session lifecycle and real-caller wiring tests.
- Run the web unit tests, typecheck, and production build with synthetic transports only.

## Compatibility constraints

Preserve the streamable-HTTP protocol version, response parsing, per-user authentication boundaries, SSRF redirect policy, and caller-visible error text. Do not introduce shared session reuse, live MCP calls, or credential logging.
