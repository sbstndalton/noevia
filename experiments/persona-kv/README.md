# Persona-swap KV-cache study

Offline harness for [issue #518](https://github.com/sbstndalton/noevia/issues/518) (part of #511, M7). It measures the cost of switching between the Astra, Sol, Jev and Luna personas on one llama.cpp slot: persona after a stable shared prefix vs at the start, slot save/restore vs cold prefill, and TTFT plus prompt-eval tokens (`timings.cache_n` / `timings.prompt_n`) per switch. Fixtures are synthetic.

**No run without owner approval.** The script refuses to contact a server unless `--i-have-approval` is passed, and the owner approves each run from [docs/handoffs/2026-09-28-run-plan-518.md](../../docs/handoffs/2026-09-28-run-plan-518.md). Nothing imports this directory from the product; it writes only under `--out` and never touches `models.ini` or any server config.

```sh
# tests (fake llama.cpp on 127.0.0.1; no model is contacted)
node --require ./apps/web/tests/hermetic-network.cjs --test experiments/persona-kv/*.test.cjs

# print the planned request matrix (no network)
node experiments/persona-kv/study.cjs --dry-run --base-url http://127.0.0.1:8080 [--smoke]

# real run (owner-approved only)
node experiments/persona-kv/study.cjs --i-have-approval --smoke --base-url <url> --out <dir>
```

Bounds: repeats 1-10, timeout 300 s per request, n-predict 1-64, prefix 1-200 paragraphs, at most 5,000 HTTP calls, abort after 3 consecutive request errors. Restore arms need llama.cpp started with `--slot-save-path`; otherwise they are reported as skipped.
