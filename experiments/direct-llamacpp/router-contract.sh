set -eu
contract_dir=$(mktemp -d /tmp/noevia-native-contract.XXXXXX)
contract_name=noevia-native-contract-$(date +%s)
cleanup() { docker rm -f "$contract_name" >/dev/null 2>&1 || true; rm -rf "$contract_dir"; }
trap cleanup EXIT
printf 'version = 1\n[synthetic]\nmodel = /fixtures/missing-synthetic.gguf\nc = 8192\nngl = 0\n' > "$contract_dir/models.ini"
docker run -d --name "$contract_name" --memory 512m --memory-swap 512m -p 127.0.0.1:31882:8080 -v "$contract_dir:/config:ro" sha256:9f88885b46c8af0696d02b6d0d93f39cc0d81f29b99fb45030dcaf3a0193e282 --models-preset /config/models.ini --host 0.0.0.0 --port 8080 --models-max 1 --metrics >/dev/null
base=http://127.0.0.1:31882
for trial in $(seq 1 60); do
  if curl -fsS "$base/models" > "$contract_dir/list.json" 2>/dev/null; then break; fi
  sleep .2
done
jq -e '.data[] | select(.id == "synthetic") | .status.value == "unloaded" and .can_remove == false' "$contract_dir/list.json" >/dev/null
code=$(curl -sS -o /dev/null -w '%{http_code}' "$base/props?model=synthetic&autoload=false")
test "$code" -ge 400
curl -fsS "$base/models" | jq -e '.data[0].status.value == "unloaded"' >/dev/null
code=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "$base/models?model=synthetic")
test "$code" -ge 400
code=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{"model":"synthetic"}' "$base/models/load")
test "$code" -eq 200
for trial in $(seq 1 60); do
  if curl -fsS "$base/models" | jq -e '.data[0].status.failed == true' >/dev/null; then break; fi
  sleep .2
done
curl -fsS "$base/models" | jq -e '.data[0].status.failed == true' >/dev/null
curl -fsS "$base/models?reload=1" > /dev/null
printf '%s\n' 'PASS pinned native image: unloaded preset listing and can_remove; autoload=false does not load; preset deletion rejected; load acknowledges launch before invalid artifact reports failed; explicit reload succeeds. No GPU devices or real model files mounted.'
