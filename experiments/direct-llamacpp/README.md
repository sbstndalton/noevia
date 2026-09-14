# Direct native qualification

`router-contract.sh` is the original no-GPU API contract check.
`qualify.py --run` is an explicitly invoked DaServer GPU maintenance trial:
review its fixed host/container/model/device configuration first. It is not a
production launcher. It stops app clients and Lemonade, runs synthetic native
workloads with one loaded model, and always restores the original loaded models
and options. `maintenance.sh` runs independently on the host, enforcing a 4 GiB
available-memory reserve, heartbeat expiry and one-hour deadline. It refuses to
run while `cowork-llama-1` production is active. Do not start Lemonade to rerun
these tests alongside the now-live native backend.

Before an approved trial from a Lemonade deployment:

```sh
python3 experiments/direct-llamacpp/embedding-reference.py --base http://10.69.0.130:13305
python3 experiments/direct-llamacpp/qualify.py --run
python3 experiments/direct-llamacpp/qualify.py --run --app-only
```

The last command invokes the real web app against native inference with a
memory-only MCP fixture, plus the real Diary LLMClient with synthetic strings.
It never opens the Diary database or corpus. `apps/web/qa/native-live.cjs` checks
all three approval actions, allow-once repetition and chat-scoped grants. Local
state is a fresh temporary directory. Host logs/snapshots stay in a unique private
qualification directory; local results default to `/tmp/noevia-native-qualification`.

The embedding gate compares 18 synthetic vectors across backend builds (cosine
>0.995), and requires all eight expected top matches using both original and new
vectors. The original stricter 0.999 short-string test exposed small arithmetic
drift; matching KV flags did not eliminate it. The accepted threshold is paired
with retrieval assertions, not treated as bitwise identity or permission to
reindex real data. Diary auxiliary generation uses its actual 2048-token allowance,
including reasoning. A 64-token fixture exhausted its reasoning budget before
answering and was corrected; the production code was not changed for that fixture.

Completed workload and application evidence is in
`docs/evidence/native-cutover-2026-09-14.json`; production cutover/rollback is in
`docs/deployment.md`. The exact 4B/Gemma 32k, Qwen 9B 262k and embedding 2k profiles
are recorded in that evidence. No general throughput/concurrency or quality claim.
