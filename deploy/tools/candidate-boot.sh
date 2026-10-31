#!/usr/bin/env bash
# Synthetic candidate boot of a web image (#1416): no network, read-only root, all capabilities
# dropped, tmpfs for everything writable, throwaway tokens. It proves the image starts and answers
# GET /api/ready with the release sha before anything is switched. The container is removed on exit.
#
# Usage: candidate-boot.sh <release-sha> [image]
#   image defaults to cowork-web:<sha>.
#   CANDIDATE_FRONT=rust        the only front since sbstndalton/noevia#1071 (the web supervisor
#                               refuses node); no switches (#1071: sign-in, the project routes and
#                               the store are the front's with no switch).
#   CANDIDATE_WAIT_SECONDS=N    bound on the readiness wait (default 120).
#   CANDIDATE_EGRESS_IMAGE=I    a native egress image (deploy/egress-proxy, target native-control). The
#                               candidate then boots with CODE_EGRESS_PORT set beside a disposable egress-rs
#                               on an internal network, as an installation with egress does (#2226).
#                               This proves boot and authenticated Ready only: no traffic passes through it.
#   CANDIDATE_EGRESS=off        boot without egress. Says plainly that the egress path was not qualified.
#                               One of these two is required: a boot without egress missed #2226.
#
# Runs on the Docker host. Nothing here reads .env, and the throwaway tokens are never printed.
set -euo pipefail
sha="${1:-}"
if [[ ! "$sha" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "usage: candidate-boot.sh <release-sha> [image]" >&2
  exit 2
fi
image="${2:-cowork-web:$sha}"
front="${CANDIDATE_FRONT:-rust}"
case "$front" in
  rust) ;;
  node) echo "candidate-boot: the node front is gone (sbstndalton/noevia#1071); the web supervisor refuses it" >&2; exit 2 ;;
  *) echo "candidate-boot: CANDIDATE_FRONT must be rust" >&2; exit 2 ;;
esac
wait_s="${CANDIDATE_WAIT_SECONDS:-120}"
if [[ ! "$wait_s" =~ ^[0-9]+$ ]]; then
  echo "candidate-boot: CANDIDATE_WAIT_SECONDS must be a whole number of seconds" >&2
  exit 2
fi

egress_image="${CANDIDATE_EGRESS_IMAGE:-}"
if [ -z "$egress_image" ] && [ "${CANDIDATE_EGRESS:-}" != off ]; then
  echo "candidate-boot: set CANDIDATE_EGRESS_IMAGE to qualify the egress path, or CANDIDATE_EGRESS=off to skip it (#2226)" >&2
  exit 2
fi

name="cowork-candidate-$sha-$$"
# The data dir must be writable on a tmpfs. Startup runs mkdirSync(UI_DATA_DIR) and then writes the
# sqlite database and the secrets key there. The image default (/app/server/ui-data) sits on the
# read-only root, so without UI_DATA_DIR the candidate exits at startup with EROFS.
data_root="/candidate-data"
data_dir="$data_root/ui-data"
random_token() { head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
diary_token="$(random_token)"
ui_token="$(random_token)"

egress_name="$name-egress"; net_name="$name-net"; key_dir=""
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  if [ -n "$egress_image" ]; then
    docker rm -f "$egress_name" >/dev/null 2>&1 || true
    docker network rm "$net_name" >/dev/null 2>&1 || true
    [ -z "$key_dir" ] || rm -rf -- "$key_dir"
  fi
}
trap cleanup EXIT

web_net=(--network none); egress_args=()
if [ -n "$egress_image" ]; then
  # The owner and group the installation's profile uses by default. Web publishes the key, so it keeps CHOWN.
  key_dir="$(mktemp -d)"
  install -d -m 0750 -o 0 -g 1006 "$key_dir/key"
  docker network create --internal "$net_name" >/dev/null
  key_mount=/run/noevia-egress-control
  docker run -d --name "$egress_name" --network "$net_name" --network-alias egress-rs-code \
    --read-only --cap-drop ALL --security-opt no-new-privileges --group-add 1006 \
    -v "$key_dir/key:$key_mount:ro" \
    -e CODE_EGRESS_BIND=egress-rs-code -e CODE_EGRESS_PORT=8040 \
    -e CODE_EGRESS_CONTROL_KEY_FILE="$key_mount/current.key" \
    -e CODE_EGRESS_CONTROL_KEY_UID=0 -e CODE_EGRESS_CONTROL_KEY_GID=1006 \
    "$egress_image" --native-control-v1 >/dev/null
  web_net=(--network "$net_name")
  egress_args=(--cap-add CHOWN -v "$key_dir/key:$key_mount"
    -e CODE_EGRESS_PORT=8040 -e CODE_EGRESS_IMPL=rust -e CODE_EGRESS_RUST_HOST=egress-rs-code
    -e CODE_EGRESS_CONTROL_KEY_FILE="$key_mount/current.key" -e CODE_EGRESS_KEY_UID=0 -e CODE_EGRESS_KEY_GID=1006)
fi

docker run -d --name "$name" \
  "${web_net[@]}" --read-only --cap-drop ALL --security-opt no-new-privileges \
  --tmpfs /tmp:size=64m,mode=1777 \
  --tmpfs "$data_root:size=256m,mode=0777" \
  -e UI_DATA_DIR="$data_dir" \
  -e UI_PORT=8021 \
  -e NOEVIA_FRONT="$front" \
  -e PUBLIC_ORIGIN=http://127.0.0.1:8021 \
  -e LEGACY_AUTH_COMPAT=false \
  -e DIARY_AUTH_TOKEN="$diary_token" \
  -e UI_AUTH_TOKEN="$ui_token" \
  ${egress_args[@]+"${egress_args[@]}"} \
  "$image" >/dev/null

# The probe runs inside the container (the network is disabled, so the host cannot reach it).
probe='fetch("http://127.0.0.1:"+(process.env.UI_PORT||8021)+"/api/ready",{signal:AbortSignal.timeout(4000)})'
probe+='.then(r=>r.text()).then(t=>console.log(t)).catch(()=>process.exit(1))'
deadline=$(( $(date +%s) + wait_s ))
body=""
ready=0
while :; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo false)" != true ]; then
    break
  fi
  body="$(docker exec "$name" node -e "$probe" 2>/dev/null || true)"
  if grep -q '"ready":true' <<<"$body" && grep -q "\"version\":\"$sha\"" <<<"$body"; then
    ready=1
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    break
  fi
  sleep 2
done

# Count, never print, the log lines: they can carry paths and request detail.
errors="$(docker logs "$name" 2>&1 | grep -Eci 'error|EROFS|FATAL' || true)"
if [ "$ready" = 1 ]; then
  if [ -n "$egress_image" ]; then egress_said="qualified beside $egress_image"; else egress_said="NOT qualified"; fi
  echo "ok: $image ready at $sha ($body), error lines: $errors (front $front, egress $egress_said)"
  exit 0
fi
echo "error: $image not ready at $sha within ${wait_s}s (front $front, last answer: ${body:-none}, error lines: $errors)" >&2
exit 1
