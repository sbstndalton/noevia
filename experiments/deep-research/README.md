# Deep research fixture measurement (variants A/B/C)

Offline harness for the gate in `docs/spec-deep-research.md` §8. A static fixture site with
invented facts is served on 127.0.0.1; search and project retrieval are simulated from
`fixtures.json`; only the model endpoint is real, and it must be named explicitly:

```bash
RESEARCH_BASE_URL=http://127.0.0.1:8080/v1 RESEARCH_MODEL=<sandbox model> node experiments/deep-research/run.cjs
```

Per question it records required facts covered, adversarial compliance (forbidden strings in
the report, must be 0), deterministic citation validity, web calls and wall time. Since #707 the
pipeline cites evidence sentences by ID and verifies claim by claim (spec §5), so B/C rows also
record `claims` (total/supported/flagged/dropped/uncited), `withheldSentences` (instruction-like
sentences kept out of the evidence), the dropped and flagged claims with a
reason (`whole-source`, `wrong-sentence`, `unknown-id`, `uncited`) and the report markdown. Facts are
scored on the verified report, so a dropped claim's fact does not count. The summary reports
`uncitedClaims` next to `citationValidity`; validity is not comparable with the pre-#707 B/C runs.

Offline test (scripted models, no endpoint): `node --require ./apps/web/tests/hermetic-network.cjs --test experiments/deep-research/*.test.cjs`.
Re-gate of B only: `RESEARCH_VARIANTS=B RESEARCH_BASE_URL=… RESEARCH_MODEL=… node experiments/deep-research/run.cjs`.

Variants (`RESEARCH_VARIANTS=A,B,C`, default all): **A** one chat-style answer over the same search
results and project notes, **B** the pipeline without a plan, **C** the pipeline with the plan step.

Fixtures now match spec §8: 12 questions (4 need project notes) and 2 adversarial pages. Earlier
stub run (4 questions) completed with citation validity 1.0 but also copied the adversarial pages,
which shows the limit of §5: **citation verification proves a claim is in a cited source, not that
the source is trustworthy.** Adversarial resistance is measured here, not verified.

Status: no real model run yet. Run it on the 9B from inside the web container, outside backup and
mover windows, detached (`nohup … > results.txt 2>&1 &`).
