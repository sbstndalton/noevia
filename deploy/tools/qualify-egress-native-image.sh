#!/usr/bin/env bash
# Run only in the ephemeral GitHub runner, using exact reviewed companion checkouts.
# All created containers/networks/key files belong to this one synthetic test.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && ${NOEVIA_EGRESS_ISOLATED_QUALIFICATION:-} == 1 ]] || { echo 'isolated GitHub qualification context required' >&2; exit 2; }
[[ $# == 2 ]] || { echo 'usage: qualify-egress-native-image.sh <reviewed-rust> <reviewed-core>' >&2; exit 2; }
root=$(cd "$(dirname "$0")/../.." && pwd)
rs=$(cd "$1" && pwd)
core=$(cd "$2" && pwd)
rs_ref=e4c9f1eb5cf3d58fd55cee737bcebeaa223d4fe3
core_ref=dfa2bd3a9f1c6240a518191ab38723d06ba0935a
[[ $(git -C "$rs" rev-parse HEAD) == "$rs_ref" && -z $(git -C "$rs" status --porcelain) ]] || { echo 'reviewed Rust checkout mismatch' >&2; exit 2; }
[[ $(git -C "$core" rev-parse HEAD) == "$core_ref" && -z $(git -C "$core" status --porcelain) ]] || { echo 'reviewed Core checkout mismatch' >&2; exit 2; }
work=$(mktemp -d)
name="noevia-egress-${work##*/}"
name=${name,,}
name=${name//./-}
created=0
cleanup() {
  if [[ $created == 1 ]]; then
    docker compose -p "$name" -f "$work/native.json" --profile code down --timeout 5 >/dev/null 2>&1 || true
  fi
  # Only this run's owned synthetic files. Never prune Docker or touch operator volumes.
  sudo rm -rf -- "$work"
}
trap cleanup EXIT
git -C "$rs" archive --format=tar HEAD > "$work/expected.tar"
curl --fail --location --retry 2 --max-time 90 "https://codeload.github.com/sbstndalton/noevia-rs/tar.gz/$rs_ref" -o "$work/source.tar.gz"
# Compare path sets, executable modes, types, links and file contents without extracting
# unverified input. The Dockerfile then independently checks this verified archive's hash.
archive_sum=$(python3 "$root/deploy/tools/verify-egress-source-archive.py" "$work/expected.tar" "$work/source.tar.gz" "noevia-rs-$rs_ref")
image="$name:native"
docker build --target native-control --build-arg "NOEVIA_RS_REF=$rs_ref" --build-arg "NOEVIA_RS_SHA256=$archive_sum" -t "$image" "$root/deploy/egress-proxy"
# Prepare only the new owned synthetic profile; never repair an old operator volume.
sudo install -d -m 0750 -o 0 -g 1006 "$work/key"
CODE_EGRESS_CONTROL_KEY_DIR="$work/key" CODE_EGRESS_KEY_UID=0 CODE_EGRESS_KEY_GID=1006 CODE_EGRESS_IMPL=rust CODE_EGRESS_PORT=8040 \
 docker compose --env-file "$root/.env.example" --project-directory "$root" --profile code -f "$root/compose.yaml" \
 -f "$root/deploy/examples/code-sandbox.override.yml" -f "$root/deploy/examples/code-egress-rust.override.yml" config --format json > "$work/profile.json"
python3 "$root/deploy/tools/check-egress-native-profile.py" --project-root "$root" < "$work/profile.json"
python3 - "$work" "$name" "$image" <<'PY'
import json, pathlib, sys
work, name, image = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
config = json.loads((work / 'profile.json').read_text())
service = config['services']['egress-rs']
service.pop('build'); service['image'] = image
# Use the actual rendered native service, with fresh isolated network names.
config = {'services': {'egress-rs': service}, 'networks': {'code': {'name': name + '-code', 'internal': True}, 'default': {'name': name + '-default'}}}
(work / 'native.json').write_text(json.dumps(config))
web = json.loads((work / 'profile.json').read_text())['services']['web']['environment']
(work / 'client.env').write_text('\n'.join(k + '=' + str(v) for k, v in web.items() if k.startswith('CODE_EGRESS_')) + '\nNOEVIA_EGRESS_CORE_SERVER=/reviewed-core/server\n')
PY
# Select the same Node runtime family as build/web.Dockerfile; no model or live web runtime.
docker pull node:22-bookworm
created=1
docker compose -p "$name" -f "$work/native.json" --profile code up -d --no-build egress-rs
container=$(docker compose -p "$name" -f "$work/native.json" --profile code ps -q egress-rs)
[[ -n "$container" && $(docker exec "$container" id -u) == 65532 ]] || { echo 'native runtime UID mismatch' >&2; exit 1; }
docker inspect "$container" > "$work/runtime.json"
python3 - "$work/runtime.json" "$name" "$work/key" <<'PY'
import json, sys
runtime = json.load(open(sys.argv[1]))[0]
name, key = sys.argv[2:]
assert runtime['Config']['User'] == '65532:65532'
host = runtime['HostConfig']
assert host['ReadonlyRootfs'] and 'ALL' in host['CapDrop']
assert '1006' in host['GroupAdd']
assert any(v.startswith('no-new-privileges') for v in host['SecurityOpt'])
assert not host['PortBindings']
mount = next(v for v in runtime['Mounts'] if v['Destination'] == '/run/noevia-egress-control')
assert mount['Type'] == 'bind' and mount['Source'] == key and not mount['RW']
networks = runtime['NetworkSettings']['Networks']
assert 'egress-rs-code' in networks[name + '-code']['Aliases']
assert 'egress-rs-code' not in networks[name + '-default']['Aliases']
PY
# No native published ports, no client external network, no sandbox key access.
docker run --rm --pull never --read-only --cap-drop ALL --security-opt no-new-privileges --pids-limit 128 --memory 512m --cpus 1 \
 --network "$name-code" --group-add 1006 --env-file "$work/client.env" \
 --mount "type=bind,src=$work/key,dst=/run/noevia-egress-control" \
 --mount "type=bind,src=$core,dst=/reviewed-core,readonly" \
 --mount "type=bind,src=$root/deploy/tools/qualify-egress-native-client.cjs,dst=/qualification.cjs,readonly" \
 node:22-bookworm node /qualification.cjs
