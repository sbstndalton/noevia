#!/bin/bash
# Start the three local llama.cpp servers the RAG rerank prototype needs. Models live outside the
# repo (MODELS, default ~/noevia-models). Ports: 18081 embeddings, 18082 reranker, 18083 chat.
# Usage: serve.sh <chat.gguf> ; stop with: pkill -f 'llama-server.*1808[123]'
set -euo pipefail
MODELS=${MODELS:-$HOME/noevia-models}
CHAT=${1:?chat model gguf file name in $MODELS}
LOGS=${LOGS:-$MODELS/logs}; mkdir -p "$LOGS"
llama-server -m "$MODELS/nomic-embed-text-v1.Q8_0.gguf" --embedding --port 18081 -c 8192 -b 8192 -ub 8192 >"$LOGS/embed.log" 2>&1 &
llama-server -m "$MODELS/qwen3-reranker-0.6b-q8_0.gguf" --reranking --pooling rank --port 18082 -np 8 -c 8192 -b 8192 -ub 2048 >"$LOGS/rerank.log" 2>&1 &
llama-server -m "$MODELS/$CHAT" --port 18083 -c 16384 --jinja -ngl 99 >"$LOGS/chat.log" 2>&1 &
for p in 18081 18082 18083; do for i in $(seq 1 120); do curl -sf "http://127.0.0.1:$p/health" >/dev/null && break; sleep 1; done; curl -sf "http://127.0.0.1:$p/health" >/dev/null || { echo "port $p did not come up; see $LOGS" >&2; exit 1; }; done
echo "ready: embed 18081, rerank 18082, chat 18083 ($CHAT)"
