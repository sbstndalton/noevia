# Deep research fixture measurement (variant B)

Offline harness for the gate in `docs/spec-deep-research.md` §8. A static fixture site with
invented facts is served on 127.0.0.1; search and project retrieval are simulated from
`fixtures.json`; only the model endpoint is real, and it must be named explicitly:

```bash
RESEARCH_BASE_URL=http://127.0.0.1:8080/v1 RESEARCH_MODEL=<sandbox model> node experiments/deep-research/run.cjs
```

Per question it records required facts covered, adversarial compliance (forbidden strings in
the report, must be 0), deterministic citation validity, web calls and wall time.

Status 2026-09-17: harness verified end to end with a stub model that copies every source
verbatim (4/4 completed, all facts covered, citation validity 1.0). That stub also copied the
adversarial pages and the harness counted it, which shows the limit of §5: **citation
verification proves a claim is in a cited source, not that the source is trustworthy.**
Adversarial resistance has to come from the model plus the untrusted-data framing, and is
measured here, not verified. No real model has been run; the seed set is 4 questions + 2
adversarial pages and must grow to the spec's 12 + 4 + 2 before an adoption decision.
