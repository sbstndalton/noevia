#!/bin/bash
# Host-side bounded qualification window. Run only after reviewing the profiles.
# ROOT is a dedicated qualification directory, never production app state.
set -euo pipefail
cd "${1:?qualification directory required}"
test -f compose.yaml
test -f models.ini
test ! -e started
# Refuse this historical Lemonade-to-native trial while native production is live.
test "$(docker inspect -f '{{.State.Running}}' cowork-llama-1 2>/dev/null || true)" != true
docker compose -f compose.yaml config --format json | php /mnt/docker/appdata/cowork/tools/preflight/check.php --config-json -
touch started heartbeat
candidate=noevia-native-qualification
restore() {
  trap - EXIT TERM INT HUP
  set +e
  docker stop -t 10 "$candidate" >> operations.log 2>&1
  # Never restart production inference unless the candidate is confirmed stopped.
  if test "$(docker inspect -f '{{.State.Running}}' "$candidate" 2>/dev/null)" = true; then
    echo 'FAILED: candidate still running; production held stopped' > restore-failed
    exit 1
  fi
  docker start lemonade >> operations.log 2>&1
  restored=true
  for attempt in $(seq 1 60); do
    curl -fsS --max-time 2 http://127.0.0.1:13305/api/v1/health > /dev/null 2>&1 && break
    sleep 1
  done
  while IFS= read -r payload; do
    if ! curl -fsS --max-time 180 -H 'Content-Type: application/json' -d "$payload" \
      http://127.0.0.1:13305/api/v1/load >> operations.log 2>&1; then restored=false; fi
  done < restore-models.jsonl
  curl -fsS --max-time 10 http://127.0.0.1:13305/api/v1/health > restored-health.json || restored=false
  docker start cowork-diary-1 cowork-web-1 model-loader-test >> operations.log 2>&1 || restored=false
  if "$restored"; then touch restored; else touch restore-failed; fi
}
# Snapshot model options without ever reading app env, credentials, or Diary data.
curl -fsS --max-time 10 http://127.0.0.1:13305/api/v1/health > original-health.json
jq -c '.all_models_loaded[] | select(.loaded) | {model_name} + .recipe_options' original-health.json > restore-models.jsonl
test -s restore-models.jsonl
# Check every current inference child is idle before stopping clients.
while IFS= read -r endpoint; do
  docker exec lemonade curl -fsS "${endpoint%/v1}/slots" | jq -e 'all(.[]; .is_processing == false)' > /dev/null
done < <(jq -r '.all_models_loaded[] | select(.loaded) | .backend_url' original-health.json)
trap restore EXIT TERM INT HUP
docker stop -t 30 cowork-web-1 cowork-diary-1 model-loader-test >> operations.log 2>&1
docker stop -t 30 lemonade >> operations.log 2>&1
test "$(docker inspect -f '{{.State.Running}}' lemonade)" = false
test "$(docker inspect -f '{{.State.Running}}' llama-vulkan-test)" = false
# Shared preset directory; public weights read-only; dedicated cache; no socket.
bash /mnt/docker/appdata/cowork/tools/preflight/up.sh -f compose.yaml -- -d --no-build >> operations.log 2>&1
touch ready
deadline=$((SECONDS + 3600))
while test -e heartbeat && test "$SECONDS" -lt "$deadline"; do
  available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$available" >> memory-kib.log
  if test "$available" -lt 4194304; then echo memory-reserve > guard-event; break; fi
  if test "$(docker inspect -f '{{.State.Running}}' lemonade)" != false; then echo competing-backend > guard-event; break; fi
  if test "$(docker inspect -f '{{.State.Running}}' llama-vulkan-test)" != false; then echo competing-test-backend > guard-event; break; fi
  if test "$(docker inspect -f '{{.State.Running}} {{.State.OOMKilled}}' "$candidate")" != 'true false'; then echo candidate-stopped > guard-event; break; fi
  age=$(( $(date +%s) - $(stat -c %Y heartbeat) ))
  if test "$age" -gt 60; then echo lost-client-heartbeat > guard-event; break; fi
  sleep 2
done
if test "$SECONDS" -ge "$deadline"; then echo window-timeout > guard-event; fi
