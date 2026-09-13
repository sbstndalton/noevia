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
docker compose "${compose_args[@]}" config --format json | php "$preflight_dir/check.php" --config-json -
exec docker compose "${compose_args[@]}" up "${up_args[@]}"
