#!/bin/bash
# Guarded overlay release for the live DaServer install. Run ON the server as root.
#
# For releases where apps/web dependencies are unchanged since OLD: reuse OLD's
# installed node_modules instead of running npm on the box (its IPv6 route to the
# registry is broken). Replaces the web image's dist/ and server/ only, bumps
# COWORK_VERSION (web only), repoints the release, and rolls back automatically if
# the health wait fails. The native engine must stay untouched. Sidecars (Diary, OCR,
# model manager, Docling, Code sandbox) keep their own DIARY_VERSION / OCR_VERSION /
# MODEL_MANAGER_VERSION / DOCLING_VERSION / CODE_SANDBOX_VERSION tags; nothing is
# retagged forward. A Diary agent change ships separately with diary-overlay.sh.
#
# Before running:
#   1. Locally: `rm -rf /tmp/noevia-qa-dist/*` (keep the folder: dist symlinks to it) then `npm run build` in apps/web
#      (a stale build dir ships dead bundles), then from apps/web:
#      COPYFILE_DISABLE=1 tar -h --no-xattrs -czf app-$NEW.tar.gz dist server
#      (-h: dist is a symlink locally), and FROM THE REPO ROOT `git archive --format=tar.gz -o src-$NEW.tar.gz $NEW`
#      (run in apps/web it archives only apps/web, and the release folder cannot rebuild).
#   2. scp both to /tmp on the server.
#   3. Take the appdata backup:
#      php /usr/local/emhttp/plugins/appdata.backup/scripts/backup.php
# Usage: overlay-release.sh OLD NEW
# Afterwards: record the release in docs/deployment.md and the DaServer changelog.
set -euo pipefail
OLD=${1:?old release sha}; NEW=${2:?new release sha}
base=/mnt/docker/appdata/cowork; config=$base/config/.env
manager=/boot/config/plugins/compose.manager/projects/Cowork

[ "$(readlink -f "$base/current")" = "$base/releases/$OLD" ]
[ "$(sed -n 's/^COWORK_VERSION=//p' "$config")" = "$OLD" ]
# Every sidecar tag the .env pins must already exist locally: this release builds none of
# them and `up --no-build` would otherwise try to pull a tag nobody built.
for pair in diary:DIARY_VERSION ocr:OCR_VERSION model-loader:MODEL_MANAGER_VERSION docling:DOCLING_VERSION code-sandbox:CODE_SANDBOX_VERSION; do
  svc=${pair%%:*}; key=${pair#*:}; tag=$(sed -n "s/^$key=//p" "$config")
  case $key in DIARY_VERSION|OCR_VERSION) [ -n "$tag" ] || { echo "$key is not set in $config; see docs/deployment.md 'Migrating an existing .env'" >&2; exit 1; } ;; esac
  [ -z "$tag" ] || docker image inspect "cowork-$svc:$tag" >/dev/null 2>&1 \
    || { echo "$key=$tag but image cowork-$svc:$tag does not exist; not deploying" >&2; exit 1; }
done
# Any required tag the deployment's compose files use but .env lacks fails here, before anything changes.
(cd "$manager" && docker compose --env-file "$config" --profile code config -q) \
  || { echo "compose config fails with $config; set the missing *_VERSION keys first" >&2; exit 1; }

mkdir -p "$base/releases/$NEW"
tar -xzf "/tmp/src-$NEW.tar.gz" -C "$base/releases/$NEW"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
tar -xzf "/tmp/app-$NEW.tar.gz" -C "$work"
rm -rf "$work/server/node_modules" "$work/server/ui-data"
# A failed local build leaves dist empty or missing; never ship that.
[ -f "$work/dist/index.html" ] && ls "$work"/dist/assets/*.js >/dev/null 2>&1 || { echo "app-$NEW.tar.gz has no built dist/; rebuild locally" >&2; exit 1; }
# Each overlay adds layers on top of the previous image, and Docker refuses to build past 127
# (release 96371d5 failed with "max depth exceeded" on 2026-09-18). Past 100 layers, build the
# release on a flattened copy of OLD instead: one layer with the same files, and the same
# settings (env, workdir, ports, user, entrypoint, cmd, health check) read back from the image.
# ($base is the appdata directory above, so the image lives in $web_image.)
# OLD's own image and tag are untouched, so rollback to OLD is unaffected.
web_image="cowork-web:$OLD"
layers=$(docker image inspect "$web_image" --format '{{len .RootFS.Layers}}')
if [ "$layers" -gt 100 ]; then
  flat="$(mktemp -d)"
  docker image inspect "$web_image" --format '{{json .Config}}' | jq -r --arg src "$web_image" '
    "FROM scratch", "COPY --from=\($src) / /",
    ((.Env // [])[] | (split("=") as $kv | "ENV \($kv[0])=\($kv[1:] | join("=") | @json)")),
    (if (.WorkingDir // "") != "" then "WORKDIR \(.WorkingDir)" else empty end),
    ((.ExposedPorts // {}) | keys[] | "EXPOSE \(.)"),
    (if (.User // "") != "" then "USER \(.User)" else empty end),
    (if .Entrypoint then "ENTRYPOINT \(.Entrypoint | tojson)" else empty end),
    (if .Cmd then "CMD \(.Cmd | tojson)" else empty end),
    (if .Healthcheck and .Healthcheck.Test[0] == "CMD-SHELL" then
      "HEALTHCHECK --interval=\(.Healthcheck.Interval / 1e9 | floor)s --timeout=\(.Healthcheck.Timeout / 1e9 | floor)s --start-period=\(.Healthcheck.StartPeriod / 1e9 | floor)s --retries=\(.Healthcheck.Retries) CMD \(.Healthcheck.Test[1])"
     elif .Healthcheck and .Healthcheck.Test[0] == "CMD" then
      "HEALTHCHECK --interval=\(.Healthcheck.Interval / 1e9 | floor)s --timeout=\(.Healthcheck.Timeout / 1e9 | floor)s --start-period=\(.Healthcheck.StartPeriod / 1e9 | floor)s --retries=\(.Healthcheck.Retries) CMD \(.Healthcheck.Test[1:] | tojson)"
     else empty end)' > "$flat/Dockerfile"
  docker build -q -t "cowork-web:$OLD-flat" "$flat" >/dev/null
  rm -rf "$flat"
  # The flattened copy must carry the same settings as the original before anything uses it.
  for field in .Config.Env .Config.WorkingDir .Config.ExposedPorts .Config.User .Config.Entrypoint .Config.Cmd .Config.Healthcheck; do
    [ "$(docker image inspect "$web_image" --format "{{json $field}}")" = "$(docker image inspect "cowork-web:$OLD-flat" --format "{{json $field}}")" ] \
      || { echo "flattened image differs in $field; not deploying" >&2; exit 1; }
  done
  echo "flattened $web_image ($layers layers) to cowork-web:$OLD-flat ($(docker image inspect "cowork-web:$OLD-flat" --format '{{len .RootFS.Layers}}') layers)"
  web_image="cowork-web:$OLD-flat"
fi
cat > "$work/Dockerfile" <<DOCKER
FROM $web_image
# Replace every application-owned entry, including old nested routes. Dependencies
# and the runtime data mount point stay in place; this runs only in the image build.
RUN find /app/server -mindepth 1 -maxdepth 1 ! -name node_modules ! -name ui-data -exec rm -rf {} + && rm -rf /app/dist
COPY dist /app/dist
COPY server /app/server
DOCKER
docker build -q -t "cowork-web:$NEW" "$work" >/dev/null

cp -p "$config" "$config.bak.before-$NEW"
old_native=$(docker inspect cowork-llama-1 --format '{{.Id}}')
cd "$manager"
ln -sfn "$base/releases/$NEW" "$base/current"
sed -i "s/^COWORK_VERSION=.*/COWORK_VERSION=$NEW/" "$config"
# D1: the preflight blocks a model-loader without MODEL_LOADER_TOKEN or sharing a network with
# diary; after start, confirm at runtime that the Diary sidecar cannot resolve it.
diary_isolated() {
  ! docker exec cowork-diary-1 python -c 'import socket; socket.gethostbyname("model-loader")' >/dev/null 2>&1
}
if ! { bash "$base/tools/preflight/up.sh" --env-file "$config" -- -d --no-build --no-deps --wait --wait-timeout 180 web diary ocr && diary_isolated; }; then
  ln -sfn "$base/releases/$OLD" "$base/current"
  cp -p "$config.bak.before-$NEW" "$config"
  bash "$base/tools/preflight/up.sh" --env-file "$config" -- -d --no-build --no-deps --wait --wait-timeout 180 web diary ocr
  echo "ROLLED BACK to $OLD" >&2; exit 1
fi
[ "$(docker inspect cowork-llama-1 --format '{{.Id}}')" = "$old_native" ]
# Sidecars that live outside the web release (Docling, the Code sandbox) are tagged by what they
# contain (DOCLING_VERSION, CODE_SANDBOX_VERSION), not by COWORK_VERSION, so a release does not replace them. Make sure the ones this
# deployment defines are running -- `--no-deps` and by name, so nothing else (the model loader,
# the engine) is recreated as a side effect.
sidecars=$(docker compose --env-file "$config" --profile code config --services 2>/dev/null | grep -xE 'docling|code-sandbox' || true)
if [ -n "$sidecars" ]; then
  docker compose --env-file "$config" --profile code up -d --no-deps $sidecars >/dev/null
  for s in $sidecars; do docker inspect "cowork-$s-1" --format "{{.Name}} {{.State.Status}}"; done
fi
docker inspect cowork-web-1 cowork-diary-1 cowork-ocr-1 cowork-llama-1 cowork-model-loader-1 \
  --format '{{.Name}} {{.State.Health.Status}} restarts={{.RestartCount}}'
rm -f "/tmp/src-$NEW.tar.gz" "/tmp/app-$NEW.tar.gz"
echo "RELEASE_${NEW}_COMPLETE"
