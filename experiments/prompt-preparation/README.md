# Prompt preparation benchmark (P0–P3)

Harness for the benchmark designed in `docs/spec-agent-execution.md` §2. Synthetic project,
simulated tools and approvals; only the model endpoints are real and must be named explicitly.

| Variant | Preparation |
|---|---|
| P0 | Raw request |
| P1 | Deterministic template filled by code (no model call) |
| P2 | Local architect (`--architect-model`, default the executor) writes the artifact |
| P3 | Frontier architect through an official API. Payload comes only from `outbound_payload()` and is audited before sending; a hit blocks the call and invalidates the run. **Spends credits: operator only.** |

18 fixtures: 6 multi-step reads, 4 approval-gated writes (one declined, one where nothing should be
saved), 3 injected instructions in files, 3 ambiguous requests (success = one question, no write),
2 long-context reads (`--long-tokens`, default 11 000; keep under the executor context).
An artifact that fails the schema (keys, ≤ 12 steps, known capabilities, ≤ 1 200 tokens) is a
preparation failure; the request is not silently run raw.

Run on DaServer from inside the web container, outside backup and mover windows, detached:

```bash
nohup python3 experiments/prompt-preparation/run.py --base http://<engine>/v1 \
  --model Ornith-1.5-9B-Q5_K_M --variants P0,P1,P2 --repeats 3 --out /tmp/prompt-prep.json \
  > /tmp/prompt-prep.log 2>&1 &
```

Tests (offline): `python3 -m unittest test_run` from this folder.

Decision rules and results go in the spec. Status 2026-09-17: harness and tests only, no model run.
