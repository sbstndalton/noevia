# Diary conversation and reliability update

Diary questions now receive thoughtful replies directly in the diary conversation.
The separate Insights screen, reflection endpoints, and activity badge were removed.
The logger still preserves the user's own words separately from assistant commentary.

The interface has clearer diary and chat composers, consistent focus states,
better text contrast, calmer cards, mobile layout adjustments, and reduced-motion
support. Setup completion is acknowledged by the server before exiting, and
unfinished onboarding resumes after sign-in.

## Reliability and security fixes

- Streaming errors use SSE after headers are sent. Split SSE lines are retained;
  all provider fetch paths refuse redirects and respect cancellation signals.
- Retry identifies the exact failed final message and preserves earlier history.
- Provider deletion updates the correct private/shared collection.
- Diary edits report pending writes honestly. Durable invalidation prevents stale
  retrieval after a crash, and pending operations replay in order.
- S3 storage must enforce conditional writes. A disposable capability probe
  rejects unsupported servers before writing diary data; bucket listings paginate.
- Members can connect only to operator-approved origins, avoiding DNS-rebinding
  exposure from arbitrary member-controlled endpoints. Existing shared providers
  remain usable. See SECURITY.md for MEMBER_OUTBOUND_ORIGINS.
- External import folders require administrator access. Requests, import reads,
  session histories, and pending Nextcloud login flows are bounded.
- Tenant UUID validation is strict, and legacy migration applies only to the
  designated owner. Cache eviction no longer closes active requests' resources.
- Browser security headers protect against framing and MIME sniffing. Node runtime
  builds use the lockfile without falling back to an unlocked install.
- Auxiliary inference uses the documented endpoint/key fallback. The deployment
  playbook now checks per-user storage paths and describes actual setup defaults.
- The Python installer is upgraded to a version without the identified advisory.

## Verification

The Node suite includes HTTP regressions for provider deletion, first-round model
failures, split SSE, redirect refusal, request limits, and approved-origin checks.
Diary tests cover failed edit acknowledgment, crash recovery, stale retrieval
exclusion, empty-document cleanup, and refusal of nonconforming S3 stores.

The UI was exercised with an isolated local fixture: resume onboarding, provider
skip, local storage selection, preferences, passkey skip, and a diary question
whose answer appeared in the conversation. Light/dark views and mobile layout
bounds were inspected. Synthetic responses were used for this UI check.

Dependency audits report known advisories, not a guarantee that software is free
of vulnerabilities. Keep dependencies, the host, and the inference services updated.
