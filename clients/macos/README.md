# Native macOS client

Work for [#273](https://github.com/sbstndalton/noevia/issues/273). This directory currently
holds only **NoeviaKit**, a Swift package with a typed async client for the core's v1 API
([api-browser-core-v1.md](../../docs/api-browser-core-v1.md)). It has no app yet.

## What the first slice does

`NoeviaClient` (an actor; Swift 6 language mode, strict concurrency, macOS 15+):

- **Connect.** It calls `GET /api/ready` and checks the `X-Noevia-API` major. A missing
  header counts as the pre-contract v1, following the same rules as the SPA's `api-contract.ts`.
  An explicit major that the client doesn't support is refused with
  `NoeviaError.unsupportedAPIMajor`, and the state becomes `.incompatible`. The check runs on
  every response except a 5xx. It reports the release version from `/api/ready`, which is
  documented to equal the served `/version.json`.
- **Authenticate.** `signIn(username:password:)` calls `POST /api/auth/login/password`.
  The `cowork_session` and `cowork_csrf` cookies are kept in an in-memory jar, never in the
  system cookie store. Mutating requests send `X-CSRF-Token`. `restoreSession()` resumes a
  saved session and verifies it with `GET /api/auth/session`. `signOut()` calls
  `POST /api/auth/logout`. The only thing persisted is the session pair, through the
  `CredentialStore` protocol: `KeychainCredentialStore` in an app (this-device-only, not
  synced) and `InMemoryCredentialStore` in tests. Passwords and service secrets are never
  stored.
- **Owned state.** `workspace()` and `projects()` read `GET /api/workspace`, which returns the
  account's own projects and free chats. The core has no `GET /api/projects`. This is read-only.
- **Disconnect recovery.** Only GET and HEAD are retried. After a transport error or a
  502/503, the client moves to `.reconnecting(attempt:)`, sleeps with exponential backoff and
  equal jitter, re-checks `/api/ready`, and resends. When `RetryPolicy.maxAttempts` is
  exhausted it moves to `.offline`, and `reconnect()` tries again. A POST such as sign-in or
  sign-out is never resent. A 401 on an authenticated route deletes the stored session and
  moves to `.unauthorised`.

## Deliberately not done yet

These are later slices under #273's "Done when":

- The SwiftUI app itself (windows, sign-in screen, project list UI).
- Chat, streaming (`POST /api/chat` SSE), tool approvals, Diary, uploads and every other write.
- The offline Diary replica, plus its ownership, sync, conflict, deletion and migration rules.
  These must be specified before any feature-parity claim.
- An independent client release and update channel.

## Auth gap

The core has no credential designed for a non-browser client, so NoeviaKit imitates a
browser session. See [#555](https://github.com/sbstndalton/noevia/issues/555) for details.

- Password sign-in works for every account. **Passkey sign-in is not possible natively yet.**
  The core serves no `apple-app-site-association` (`webcredentials`) for an app to join the
  passkey's relying party.
- The client sends no `Origin` header. The core's Origin check admits that, as it does for
  curl, but this is not a documented contract.
- When the server's public origin is https, its session cookies are `Secure`. A client
  pointed at a LAN `http://` address therefore cannot keep a session, and fails with
  `insecureSessionCookie`. Use the https address.
- A session expires after 7 idle days or 30 days in total, and then the user signs in again.

## Build and test

```sh
cd clients/macos/NoeviaKit
swift build
swift test
```

The tests use a `URLProtocol` stub and make no network calls and no Keychain writes. They
run in CI (`macOS client (NoeviaKit) tests`) whenever `clients/macos/**` changes.

On a Mac that has only the Command Line Tools and no Xcode, the default SwiftPM build backend
fails with "Unknown error parsing property list", even for an empty package. There, run
`sh scripts/test-clt.sh` (or `swift build --build-system native`).

The fixture JSON in `Tests/NoeviaKitTests/Fixtures` is named after the server file that
produces each shape. `node scripts/generate-fixtures.cjs` regenerates the fixtures by running
the real `routes/health.cjs`, `routes/auth.cjs` and `routes/chat-lists.cjs` factories with
synthetic data. The sign-in body is transcribed from `auth.cjs`, because producing it needs
the server's native modules.
