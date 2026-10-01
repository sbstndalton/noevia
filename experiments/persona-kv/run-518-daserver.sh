#!/bin/bash
# #518 live study orchestrator for DaServer (owner-approved run, 2026-10-01). Run with nohup on the host.
# Safety: memory watchdog container (kills pk518-* runs and unloads models below 4096 MiB MemAvailable),
# temporary nextcloud-aio disconnect of cowork-llama-1 with trap + timed failsafe reconnect, throwaway
# run containers on cowork_models with the current release mounted read-only, one model resident.
# Never edits models.ini, never restarts containers, never sets flags. Touch $D/STOP to halt between blocks.
set -u
D=${D:?}
R=$(readlink -f /mnt/docker/appdata/cowork/current)
IMG=cowork-web:$(basename "$R")
MODEL=gemma-4-E4B-it-qat-UD-Q4_K_XL
INI=/mnt/docker/appdata/cowork/config/llamacpp/models.ini
LOG=$D/orchestrate.log
log(){ echo "$(date -Iseconds) $*" >> "$LOG"; }
ctl(){ docker run --rm --name pk518-ctl-$RANDOM --network cowork_models --entrypoint node "$IMG" -e "$1" 2>&1; }
router(){ ctl "fetch('http://cowork-llama-1:8080/models/$1',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({model:'$2'})}).then(async r=>console.log(r.status,(await r.text()).slice(0,160)))"; }
status(){ ctl "fetch('http://cowork-llama-1:8080/models').then(r=>r.json()).then(j=>console.log(j.data.filter(m=>m.status&&m.status.value!=='unloaded').map(m=>m.id+':'+m.status.value).join(' ')||'none'))"; }
mem(){ echo "memavail_mib=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo) gtt_mib=$(( $(cat /sys/class/drm/card1/device/mem_info_gtt_used) / 1048576 )) llama=$(docker stats --no-stream --format '{{.MemUsage}}' cowork-llama-1 | cut -d/ -f1)"; }
slots_since(){ docker logs --since "$1" cowork-llama-1 2>&1 | grep -c "launch_slot_"; }

cleanup(){
  log "cleanup start"
  docker ps -q --filter name=pk518-run- | xargs -r docker kill >/dev/null 2>&1
  for m in $(status); do id=${m%%:*}; [ "$id" = none ] || log "unload $id: $(router unload "$id")"; done
  docker network connect nextcloud-aio cowork-llama-1 >/dev/null 2>&1 && log "reconnected nextcloud-aio" || log "nextcloud-aio connect: already connected or failed"
  docker inspect cowork-llama-1 --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' | grep -q nextcloud-aio && log "nextcloud-aio attached: yes" || log "nextcloud-aio attached: NO"
  [ -n "${FAILSAFE:-}" ] && kill "$FAILSAFE" 2>/dev/null
  sleep 20; log "post: $(mem) models=$(status)"
  docker kill pk518-watchdog >/dev/null 2>&1; docker rm -f pk518-watchdog >/dev/null 2>&1
  log "ini sha after: $(sha256sum $INI | cut -c1-16)"
  log "containers left: $(docker ps -a --filter name=pk518- --format '{{.Names}}' | tr '\n' ' ')"
  log "done"
}

log "begin release=$R image=$IMG"
log "ini sha before: $(sha256sum $INI | cut -c1-16)"
log "pre: $(mem) models=$(status)"
busy=$(docker logs --since 5m cowork-llama-1 2>&1 | grep -c launch_slot_)
if [ "$busy" -gt 0 ]; then log "ABORT: $busy engine requests in the last 5 min (owner active?)"; exit 3; fi

# memory watchdog (5 s samples, docker stats every 30 s)
cat > $D/watchdog.sh <<'EOF'
#!/bin/sh
LOG=/out/watchdog.log; n=0
echo "$(date -Iseconds) start kill<4096" >> $LOG
while true; do
  a=$(awk '/^MemAvailable:/ {print int($2/1024)}' /host/meminfo); g=$(( $(cat /host/gtt_used) / 1048576 ))
  n=$((n+1)); s=""; [ $((n % 6)) -eq 0 ] && s=" llama=$(docker stats --no-stream --format '{{.MemUsage}}' cowork-llama-1 | cut -d/ -f1 | tr -d ' ')"
  echo "$(date -Iseconds) memavail_mib=$a gtt_mib=$g$s" >> $LOG
  if [ "$a" -lt 4096 ]; then
    echo "$(date -Iseconds) KILL memavail_mib=$a" >> $LOG
    docker ps -q --filter name=pk518-run- | xargs -r docker kill >> $LOG 2>&1
    touch /out/STOP
    docker exec cowork-llama-1 curl -s -m 30 -X POST http://localhost:8080/models/unload -H 'Content-Type: application/json' -d '{"model":"gemma-4-E4B-it-qat-UD-Q4_K_XL"}' >> $LOG 2>&1
  fi
  sleep 5
done
EOF
chmod +x $D/watchdog.sh
docker run -d --rm --name pk518-watchdog -v /var/run/docker.sock:/var/run/docker.sock -v /proc/meminfo:/host/meminfo:ro \
  -v /sys/class/drm/card1/device/mem_info_gtt_used:/host/gtt_used:ro -v $D:/out docker:cli sh /out/watchdog.sh >/dev/null || { log "watchdog failed to start"; exit 4; }

trap cleanup EXIT
# failsafe reconnect even if this script is killed hard
nohup sh -c 'sleep 6000; docker network connect nextcloud-aio cowork-llama-1' >/dev/null 2>&1 &
FAILSAFE=$!
docker network disconnect nextcloud-aio cowork-llama-1 && log "disconnected nextcloud-aio" || { log "disconnect failed"; exit 5; }

LOADTS=$(date -Iseconds)
log "load: $(router load $MODEL)"
for i in $(seq 1 60); do s=$(status); [[ "$s" == *"$MODEL:loaded"* ]] && break; sleep 5; done
log "status: $(status)"; [[ "$(status)" == *"$MODEL:loaded"* ]] || { log "load failed"; exit 6; }
sleep 10; log "loaded-idle: $(mem)"
docker logs --since "$LOADTS" cowork-llama-1 2>&1 | grep -iE "kv|cache|buffer size|n_ctx|swa|slot" | grep -v -iE "token|key=" | head -80 > $D/load-llama.log

run_block(){ # block timeout_s
  [ -e $D/STOP ] && { log "STOP before $1"; return 1; }
  if [ -n "${LASTEND:-}" ]; then
    since=$(slots_since "$LASTEND"); [ "$since" -gt 0 ] && { log "STOP: $since foreign engine requests between blocks (owner active)"; return 1; }
  fi
  ts=$(date -Iseconds); log "start $1 $(mem)"
  timeout --signal=KILL "$2" docker run --rm --name pk518-run-$1 --network cowork_models -v $R:/src:ro -v $D/src:/study:ro -v $D/results:/out \
    -w /study --entrypoint node "$IMG" live-518.cjs --i-have-approval --block $1 --base-url http://cowork-llama-1:8080 --model $MODEL --out /out >> $D/$1.log 2>&1
  rc=$?; [ $rc -eq 137 ] && docker kill pk518-run-$1 >/dev/null 2>&1
  LASTEND=$(date -Iseconds)
  n=$(slots_since "$ts"); want=$(sed -n 's/.*"studyRequests":\([0-9]*\).*/\1/p' $D/results/$1.done 2>/dev/null)
  log "end $1 rc=$rc engine_requests=$n study_requests=${want:-?} $(mem)"
  docker logs --since "$ts" cowork-llama-1 2>&1 | grep -E "launch_slot_|print_timing|release|cancel|stop processing|n_gen" > $D/llama-$1.log
  [ $rc -eq 0 ] || return 1
  [ -n "$want" ] && [ "$n" -gt "$want" ] && { log "STOP: $((n - want)) foreign engine requests during $1 (owner active)"; return 2; }
  return 0
}
run_block probe 300 || exit 7
grep -q '"metricsVia"' $D/results/probe.jsonl && log "probe: $(head -c 600 $D/results/probe.jsonl)"
for b in ab interrupt interleave halt; do
  case $b in ab) to=3000;; *) to=1200;; esac
  run_block $b $to; rc=$?
  [ $rc -eq 0 ] || { log "stopping after $b (rc=$rc)"; break; }
done
docker run --rm --name pk518-run-report -v $D/src:/study:ro -v $D/results:/out -w /study --entrypoint node "$IMG" live-518.cjs --block report --out /out > $D/report.log 2>&1
log "report rc=$?"
