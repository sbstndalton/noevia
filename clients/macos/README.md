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
- **Sign in with a code (#555).** Where the server offers it (its `nativeClientAuth`
  feature is off by default and can only be switched on with `TRUST_PROXY=true`), this is
  the preferred sign-in. It follows the OAuth 2.0 device
  flow (RFC 8628):

  ```swift
  let pending = try await client.startDeviceSignIn(clientName: "Noevia for Mac")
  // Show pending.userCode (e.g. BCDF-GHJK) and open pending.verificationURLComplete.
  let user = try await client.completeDeviceSignIn(pending)   // polls until approved
  ```

  The person approves the request at `/device` in a browser where they are already signed
  in. That page shows the app's name and the code to compare. The client then holds this
  device's own access token (one hour) and refresh token, and sends
  `Authorization: Bearer` with no cookies and no CSRF header. The refresh token is single
  use. The client renews the access token with it a minute before expiry, or after a 401,
  one refresh at a time, so concurrent requests never present the same refresh token twice.
  A refresh is never resent. A refused refresh (the device was revoked, or the server saw a
  refresh token reused) drops the credential and moves to `.unauthorised`.
  `signOut()` revokes the device on the server. The device also appears in the web app's
  Settings → Security and login, with a Revoke button. `deviceSignInUnavailable` means the
  server does not offer this (the feature is off, or the core is older). A device token
  never acts as an administrator, and security settings refuse it with
  `browserSessionRequired`.
- **Sign in with a password.** `signIn(username:password:)` calls
  `POST /api/auth/login/password`. The `cowork_session` and `cowork_csrf` cookies are kept in
  an in-memory jar, never in the system cookie store. Mutating requests send `X-CSRF-Token`.
  A password sign-in replaces a device token, and vice versa. Only one is ever sent.
- **Persistence.** `restoreSession()` resumes whichever credential was saved and verifies it
  with `GET /api/auth/session`. `credential` says which one is in use. The only thing
  persisted is that credential (the session pair, or the device's two tokens), through the
  `CredentialStore` protocol: `KeychainCredentialStore` in an app (this-device-only, not
  synced) and `InMemoryCredentialStore` in tests. Items saved before #555 still load.
  Passwords and service secrets are never stored.
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

## Sign-in limits

[#555](https://github.com/sbstndalton/noevia/issues/555) added the device sign-in above. While
the server's `nativeClientAuth` feature is off, the password path below is the only one.

- **Passkeys are not available natively.** The core serves no `apple-app-site-association`
  (`webcredentials`) for an app to join the passkey's relying party. With device sign-in,
  the person can still use a passkey, in the browser where they approve the code.
- The client sends no `Origin` header. The v1 contract now documents this: a request
  without `Origin` passes the Origin check (docs/api-browser-core-v1.md, "Native clients").
- **Password sign-in over LAN http.** When the server's public origin is https, its session
  cookies are `Secure`. A client pointed at a LAN `http://` address therefore cannot keep a
  cookie session, and fails with `insecureSessionCookie`. A device token has no such limit,
  because it is not a cookie.
- A device grant, like a session, ends after 7 idle days or 30 days in total. The person then
  approves a new code.
- **Lost refresh answers.** Refresh tokens rotate and are single use. If the answer to a
  refresh never arrives, the client keeps its old pair and retries with the same refresh
  token. The server accepts that retry for 60 seconds, while the new pair it issued has not
  been used. After that, the retry counts as reuse and revokes the device, so the person
  approves a new code. If someone else replayed a stolen refresh token inside that window,
  this client's next refresh is refused as reuse and the device is revoked for both of
  them. That surfaces as `.unauthorised`, and the server audits it.
- **The Keychain is the source of truth.** A new pair is saved first and used only once the
  save succeeded. If the Keychain refuses the save, the refresh or sign-in throws
  `credentialStore(_:)` and the client keeps the pair it had.
- **Turning the server's feature off signs every device out.** Turning it on again does not
  bring them back.

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
synthetic data. The device sign-in shapes come from the real `device-auth.cjs` and
`routes/device-auth.cjs`, run on Node's built-in `node:sqlite` (Node 22.5 or later). Only the
random codes and tokens are replaced with fixed synthetic values. The password sign-in body
is transcribed from `auth.cjs`, because producing it needs the server's native modules.
