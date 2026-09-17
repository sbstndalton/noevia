# Deep research fixture measurement (variants A/B/C)

Offline harness for the gate in `docs/spec-deep-research.md` §8. A static fixture site with
invented facts is served on 127.0.0.1; search and project retrieval are simulated from
`fixtures.json`; only the model endpoint is real, and it must be named explicitly:

```bash
RESEARCH_BASE_URL=http://127.0.0.1:8080/v1 RESEARCH_MODEL=<sandbox model> node experiments/deep-research/run.cjs
```

Per question it records required facts covered, adversarial compliance (forbidden strings in
the report, must be 0), deterministic citation validity, web calls and wall time.

Variants (`RESEARCH_VARIANTS=A,B,C`, default all): **A** one chat-style answer over the same search
results and project notes, **B** the pipeline without a plan, **C** the pipeline with the plan step.

Fixtures now match spec §8: 12 questions (4 need project notes) and 2 adversarial pages. Earlier
stub run (4 questions) completed with citation validity 1.0 but also copied the adversarial pages,
which shows the limit of §5: **citation verification proves a claim is in a cited source, not that
the source is trustworthy.** Adversarial resistance is measured here, not verified.

Status: no real model run yet. Run it on the 9B from inside the web container, outside backup and
mover windows, detached (`nohup … > results.txt 2>&1 &`).
