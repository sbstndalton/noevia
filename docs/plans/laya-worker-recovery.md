# Laya worker recovery plan

Issue: https://github.com/sbstndalton/noevia/issues/70

When a decision exceeds the local worker deadline, crashes, or loses its pipe, the parent must detach and terminate that worker, return one unavailable response, and start a single replacement in the background. Health stays unready until the replacement completes the existing bounded startup handshake. Inference is never replayed. Consecutive failed replacement starts need finite retries with backoff, followed by a nonzero parent exit so the existing Docker failure policy can surface persistent failure without a hot loop.

Keep one CPU-only worker, the private network and model mount, request validation, and redacted errors. Add fake-worker integration tests for timeout, crash/EOF, recovery readiness, client disconnect, and shutdown. Check that the candidate handles repeated synthetic routes within the live caller deadline before rollout. Update the service documentation and use the separate Laya image rollout and rollback path without touching web, Diary, or model files.
