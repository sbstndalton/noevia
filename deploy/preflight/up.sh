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
# Compose resolves the project (compose file, .env, project name) from the cwd, so
# a caller in the wrong directory used to fail closed with a confusing error (#574).
# Resolve it here: COWORK_PROJECT_DIR, else the Compose Manager default when it
# exists, else the caller's cwd only if it holds a Compose file. Skipped when the
# caller already pins the project with -f/--file/--project-directory.
default_project_dir=/boot/config/plugins/compose.manager/projects/Cowork
pinned=false
for argument in "${compose_args[@]+"${compose_args[@]}"}"; do
  case "$argument" in -f|--file|-f?*|--file=*|--project-directory|--project-directory=*) pinned=true ;; esac
done
if [[ "$pinned" == false ]]; then
  project_dir="${COWORK_PROJECT_DIR:-}"
  if [[ -z "$project_dir" && -d "$default_project_dir" ]]; then
    project_dir="$default_project_dir"
  fi
  if [[ -n "$project_dir" ]]; then
    if [[ ! -d "$project_dir" ]]; then
      echo "error: Compose project directory not found: $project_dir" >&2
      exit 2
    fi
    cd -- "$project_dir"
  elif ! compgen -G 'compose.y*ml' >/dev/null && ! compgen -G 'docker-compose.y*ml' >/dev/null; then
    echo "error: no Compose file in $PWD and $default_project_dir does not exist; set COWORK_PROJECT_DIR to the project directory" >&2
    exit 2
  fi
fi
expect_args=()
# The live Compose file is a hand-maintained third copy; a key dropped while
# copying it turns MCP off silently. Advisory only — it never blocks the start.
if [[ -f "$preflight_dir/web-env-keys.txt" ]]; then
  expect_args=(--expect-env "$preflight_dir/web-env-keys.txt")
fi
# ${arr[@]+...} keeps empty arrays safe under set -u on bash 3.2 (macOS).
docker compose ${compose_args[@]+"${compose_args[@]}"} config --format json \
  | php "$preflight_dir/check.php" --config-json - ${expect_args[@]+"${expect_args[@]}"}
docker compose ${compose_args[@]+"${compose_args[@]}"} up ${up_args[@]+"${up_args[@]}"}
# A successful up is a known deploy: re-baseline the restart alert if installed
# (../sidecar-restart-alert.sh). Set SIDECAR_ALERT_ACK=0 to skip. Never fatal.
alert_script="${SIDECAR_ALERT_SCRIPT:-$preflight_dir/../sidecar-restart-alert.sh}"
if [[ "${SIDECAR_ALERT_ACK:-1}" != 0 && -x "$alert_script" ]]; then
  "$alert_script" --ack || echo "warning: sidecar-restart-alert --ack failed" >&2
fi
