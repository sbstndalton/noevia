#!/usr/bin/env bash
# Deliberate pinned-runtime qualification, NOT floating Core CI. Synthetic-only loopback HTTP.
# Usage: bash deploy/tools/qualify-machines-depth.sh /path/to/core
set -euo pipefail
core=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
image=sha256:4018d741e3e56c274268d55d606410d756c50268c4d476ff0d3b0890c4cb3d8c
boundary=3086
probe() {
  docker run --pull=never --rm --network none --memory 1g -e CORE=/core -e NODE_PATH=/app/server/node_modules \
    -v "$core:/core:ro" -v "$here/machines-depth-probe.cjs:/qualification/probe.cjs:ro" \
    --entrypoint node "$image" /qualification/probe.cjs "$1" "$2"
}
docker run --pull=never --rm --network none --entrypoint node "$image" -p \
 'JSON.stringify({node:process.version,v8:process.versions.v8,arch:process.arch,platform:process.platform,execArgv:process.execArgv,nodeOptionsPresent:!!process.env.NODE_OPTIONS})'
echo "image=$image deterministic-first-refusal=$boundary"
minimum=100000
for run in 1 2; do
  for context in http-cold http-warm; do
    lo=2000; hi=3300
    while [ $((hi-lo)) -gt 1 ]; do
      mid=$(((hi+lo)/2)); result=$(probe "$context" "$mid"); echo "$result"
      if grep -q '"ok":true' <<<"$result"; then lo=$mid; else hi=$mid; fi
    done
    echo "BOUNDARY run=$run context=$context max-pass=$lo first-fail=$hi"
    [ "$hi" -ge "$boundary" ]; [ "$hi" -ge "$minimum" ] || minimum=$hi
    for depth in $((hi-1)) "$hi" $((hi+1)); do
      result=$(probe "$context" "$depth"); echo "$result"
      printf '%s' "$result" | python3 -c 'import json,sys; v=json.load(sys.stdin); d=int(sys.argv[1]); b=int(sys.argv[2]); assert v["node"]=="v22.23.3" and v["v8"]=="12.4.254.21-node.57" and v["execArgv"]==[]; assert (v["status"],v["writes"])==((201,1) if d<b else (500,0)); assert d<b or v["body"]=={"error":"The inference machines could not be changed."}' "$depth" "$hi"
    done
  done
done
[ "$minimum" -eq "$boundary" ]
echo 'Pinned HTTP qualification passed; do not raise the native exception automatically.'
