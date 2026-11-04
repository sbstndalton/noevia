# Embedding background pair rollback

The supervisor enforces the compiled `rust-embedding-background-v1` pairing guard
and serializes pair lifetimes using `UI_DATA_DIR/embedding-pair.lock`. Do not
unlink that lock file. An ownership-aware Core never starts Node fallback workers.

Every release kit enabling this ownership protocol **must** implement and qualify
this rollback sequence:

1. Stop the current supervisor/container. Its required order is TERM the front,
   wait for front shutdown to join its embedding task and release its native lock,
   then TERM Core and wait for both children to exit.
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
rollback uses this supervisor. The container stop grace period must allow native
cancellation/join; a forced stop must establish that **all** prior processes have
exited before the replacement starts. No Core-only hot rollback is supported.

`deploy/tools/test-web-supervisor.sh` checks capability combinations, rejection
while the previous pair lock is held, and delayed front drain completing before
Core receives TERM. Release-specific image binding and real container rollback
qualification remain required for each release kit.
