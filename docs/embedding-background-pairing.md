# Embedding background pair rollback

The supervisor enforces the compiled `rust-embedding-background-v1` pairing guard
and serializes pair lifetimes using `UI_DATA_DIR/embedding-pair.lock`. Do not
unlink that lock file. An ownership-aware Core never starts Node fallback workers.

Every release kit enabling this ownership protocol **must** implement and qualify
this rollback sequence:

1. Stop the current supervisor/container. Its required order is TERM the front,
   allow at most 5 seconds for front shutdown to join its embedding task and
   release its native lock, then KILL and reap the front if that deadline expires.
   Only after front exit, TERM Core and wait for its shutdown hooks and exit.
2. Confirm the prior container/process pair has exited and the pair-lifetime lock
   is available. Failure to establish quiescence must stop rollback promotion.
3. Start the coherent rollback Core/front image together through the supervisor,
   with a newly generated start ID. Never replace or restart Core alone while the
   prior native owner is alive. Never reuse an ownership proof from a prior start.
4. Verify readiness and retrieval health, and verify the selected rollback pair's
   single background owner using synthetic indexes. Keep custom RAG directories
   and active tenant/orphan indexes in the qualification fixture.

A missing proof suspends future native passes; it cannot retract a batch already
admitted. A lock excludes replacement supervisors only when every start and
rollback uses this supervisor. The front's TERM wait is bounded at 5 seconds,
reserving Core's 3-second shutdown-hook budget within the default 10-second container stop timeout. Release
kits must set `stop_grace_period` to at least 10 seconds (15 seconds recommended
for scheduling/reaping margin) and qualify the stuck-front forced-stop path. A
forced stop must establish that **all** prior processes have exited before the
replacement starts. No Core-only hot rollback is supported.

`deploy/tools/test-web-supervisor.sh` checks capability combinations, rejection
while the previous pair lock is held, and delayed front drain completing before
Core receives TERM, plus a stuck front being killed/reaped before Core
shutdown hooks complete within the stop budget. Release-specific image binding
and real container rollback qualification remain required for each release kit.
