#!/usr/bin/env bash
# Compose global options precede --; up options follow it. Run on the Docker host.
set -euo pipefail
preflight_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
compose_args=()
up_args=()
reading_up=false
for argument in "$@"; do
  if [[ "$reading_up" == false && "$argument" == -- ]]; then
    reading_up=true
  elif [[ "$reading_up" == true ]]; then
    up_args+=("$argument")
  else
    compose_args+=("$argument")
  fi
done
expect_args=()
# The live Compose file is a hand-maintained third copy; a key dropped while
# copying it turns MCP off silently. Advisory only — it never blocks the start.
if [[ -f "$preflight_dir/web-env-keys.txt" ]]; then
  expect_args=(--expect-env "$preflight_dir/web-env-keys.txt")
fi
docker compose "${compose_args[@]}" config --format json \
  | php "$preflight_dir/check.php" --config-json - "${expect_args[@]}"
docker compose "${compose_args[@]}" up "${up_args[@]}"
# A successful up is a known deploy: re-baseline the restart alert if installed
# (../sidecar-restart-alert.sh). Set SIDECAR_ALERT_ACK=0 to skip. Never fatal.
alert_script="${SIDECAR_ALERT_SCRIPT:-$preflight_dir/../sidecar-restart-alert.sh}"
if [[ "${SIDECAR_ALERT_ACK:-1}" != 0 && -x "$alert_script" ]]; then
  "$alert_script" --ack || echo "warning: sidecar-restart-alert --ack failed" >&2
fi
