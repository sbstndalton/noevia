#!/bin/bash
D=/mnt/docker/appdata/cowork/state/acp-spike; O=$D/results; mkdir -p $O
until docker exec cowork-diary-1 grep -q EXIT /tmp/pp/log2.txt 2>/dev/null; do sleep 60; done
for spec in "Qwen3.5-4B-Q5_K_M:24576" "Ornith-1.5-9B-Q5_K_M:16384"; do
  m=${spec%%:*}; ctx=${spec##*:}
  rm -rf $D/work/task; echo "start $m $(date +%T)" >> $O/phases.txt
  docker run --rm --name acp-sandbox --network noevia-sandbox --read-only --tmpfs /tmp:rw,size=512m --tmpfs /home/agent:rw,size=64m \
    --cap-drop ALL --security-opt no-new-privileges --pids-limit 512 --memory 3g --user 1000:1000 \
    -e HOME=/home/agent -e MODEL_BASE=http://sandbox-llama:8080/v1 -e MODEL=$m -e MODEL_CTX=$ctx -e LIMIT_MS=900000 \
    -v $D/app:/app:ro -v $D/work:/work --workdir /app --entrypoint node cowork-web:127b300 /app/server-spike.mjs > $O/$m.json 2> $O/$m.stderr
  echo "end $m $(date +%T) exit=$?" >> $O/phases.txt
done
echo finished >> $O/phases.txt
