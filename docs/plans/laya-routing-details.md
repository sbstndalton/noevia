# Auto routing details

Expose the structured Auto role decision beside each assistant reply. The classifier supplies offered role labels, scores, selected role, backend identity, latency and fallback status. Scores are uncalibrated preferences, not a prose thought process or a probability of correctness.

Carry the record on the current chat request into SSE metadata, message state and saved history. Keep it out of the model-facing role/content projection. Show only validated identifiers and finite scores; never include prompts, endpoint URLs, credentials or backend errors. Manual replies have no routing panel.

Acceptance: successful and fallback decisions show the effective role; distinct concurrent requests retain their own details; reloaded and conflict-merged history preserves the panel. Verify router and SSE contracts, history projection, frontend typecheck/build/tests, and synthetic desktop/mobile UI in light and dark themes. Live classifier quality and production deployment remain outside this change.

Implemented: per-request classifier detail is sent with chat metadata, displayed beside its reply and persisted with the transcript. A restored chat now loads its saved history before rendering. Tests cover decision isolation, fallback, actual router-to-chat SSE, role/content-only model replay, and history API conflict copies. A synthetic browser fixture exercised SSE through App state, save, reload and conflict merge, plus a malformed history record; the fixture was removed after QA.
