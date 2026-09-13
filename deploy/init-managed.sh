#!/usr/bin/env bash
# Fresh installs only. Never migrate, overwrite or reuse an existing deployment.
set -euo pipefail
install_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$install_root"
fail() { printf 'Stopped: %s\n' "$1" >&2; exit 1; }
[[ ! -e .env && ! -L .env ]] || fail 'An .env already exists; keep its storage configuration.'
[[ ! -e state && ! -L state ]] || fail 'A state path already exists; use the existing installation procedure.'
[[ -z ${COWORK_STATE_DIR:-} && -z ${COWORK_WEB_STORAGE:-} && -z ${COWORK_DIARY_STORAGE:-} && -z ${COMPOSE_PROJECT_NAME:-} ]] || fail 'Explicit storage/project environment is set; preserve it and configure manually.'
[[ -f compose.yaml && -f .env.example ]] || fail 'Run from a complete checkout.'
docker info >/dev/null 2>&1 || fail 'Docker is unavailable; existing deployments cannot be checked.'
docker compose version >/dev/null 2>&1 || fail 'Docker Compose v2 is required.'
containers="$(docker ps -aq --filter label=com.docker.compose.project=cowork)" || fail 'Could not inspect existing containers.'
[[ -z "$containers" ]] || fail 'A Cowork deployment already exists on this Docker engine.'
project_volumes="$(docker volume ls --filter label=com.docker.compose.project=cowork --format '{{.Name}}')" || fail 'Could not inspect project volumes.'
[[ -z "$project_volumes" ]] || fail 'Cowork project volumes already exist; use a restore or existing-install procedure.'
volumes="$(docker volume ls --format '{{.Name}}')" || fail 'Could not inspect existing volumes.'
while IFS= read -r volume; do
  case "$volume" in cowork_web-data|cowork_diary-data) fail 'Cowork managed state already exists; use a restore or existing-install procedure.';; esac
done <<< "$volumes"
umask 077
fresh_env="$(mktemp "$install_root/.env.fresh.XXXXXX")"
trap 'rm -f -- "$fresh_env"' EXIT
sed -e 's/^COWORK_WEB_STORAGE=.*/COWORK_WEB_STORAGE=web-data/' \
    -e 's/^COWORK_DIARY_STORAGE=.*/COWORK_DIARY_STORAGE=diary-data/' .env.example > "$fresh_env"
# An exclusive hard link also refuses a concurrently created .env or symlink.
ln "$fresh_env" .env || fail 'Could not create .env exclusively; no existing configuration was replaced.'
printf '%s\n' 'Created private .env for a fresh install using Docker-managed web and Diary volumes.' \
  'Review provider/origin settings, then follow DEPLOY.md. No containers or volumes were started or created.'
