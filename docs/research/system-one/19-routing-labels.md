# System-One routing labels, measured on Laya — 2026-09-22

Laya (`cowork-laya:0.3.5-noevia1`, CPU, 1500 ms deadline) was probed with the exact requests
production builds (`system-one-router.cjs`, `decision-endpoint.cjs`), from inside the live web
container, using synthetic non-personal messages only. No answering-model inference, no
benchmark suite, no user data. Probe: `apps/web/scripts/system-one-probe.cjs`.

| Option labels | Tuning set (20 decisions) | Held-out set (40 decisions) |
|---|---|---|
| Before: "Short simple questions and small talk" / "Complex reasoning, analysis and multi-step work" / "Writing, reading, debugging or explaining source code" | 12/20 | 23/40 |
| **A (shipped):** "Greetings, thanks, or a one-line factual answer" / "Explaining, comparing, planning, reasoning or writing more than a sentence" / "Anything involving programming code, regex, errors or software" | 20/20 | **36/40** |
| B: role-named labels with a rewritten question | 20/20 | 32/40 |

Each set is scored twice: with and without the Code role configured. The old labels sent most
reasoning and code requests to Fast — the cheap direction to fail, but it made routing close to
"always Fast". A's four held-out misses are near-ties (margins 0.01–0.10); they fall to Fast or
Smart, never to an unsafe path. Manual model choice, the legacy classifier fallback, the circuit
breaker and all approval gates are unchanged.

**Step supervision** (continue / verify / escalate, 9 synthetic cases): 8/9 with the current
wording. The miss was a payment request the model marked "continue"; payment and writes are gated
by approvals regardless, so no change was made on one case.

**Latency:** median 0.45–0.6 s per decision; a few decisions reached ~1.1 s during back-to-back
runs. Inside the 1.5 s deadline; misses fall back to the legacy classifier and three in a row
bench the backend for 60 s.

**End-to-end smoke (2026-09-22, release `e19119d`):** `qa/laya-chat-smoke.cjs` inside the web
container against the model already loaded (`gemma-4-E4B-it-qat-UD-Q4_K_XL`; no model swap), two
capped 256-token requests and a synthetic in-memory tool: the tool ran exactly once, the real Laya
checkpoint returned "continue" (logged as `[system-one] supervise`), and the reply completed.
