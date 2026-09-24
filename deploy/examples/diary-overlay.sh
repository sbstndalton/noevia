#!/bin/bash
# Diary image overlay: FROM the running image, replace agent/ only. Rolls back on any failure.
# Usage (on DaServer, as root): bash diary-overlay.sh <SRC_SHA>. SRC_SHA is an unpacked release
# under releases/ whose services/diary/agent is shipped; it also becomes the new Diary tag
# (cowork-diary:<SRC_SHA>) and DIARY_VERSION in .env. COWORK_VERSION and the web image are untouched.
# Use when only files under services/diary/agent changed since the running image (check
# requirements.txt and Dockerfile are unchanged): no pip install runs, so no dependency can drift.
# Keeps cowork-diary:rollback-before-diary-overlay and config/.env.bak.before-diary-<SRC_SHA>.
set -euo pipefail
V=${1:?source release sha (becomes DIARY_VERSION)}; base=/mnt/docker/appdata/cowork; config=$base/config/.env
cd /boot/config/plugins/compose.manager/projects/Cowork
OLD=$(sed -n 's/^DIARY_VERSION=//p' "$config")
[ -n "$OLD" ] || { echo "DIARY_VERSION is not set in $config; see docs/deployment.md 'Migrating an existing .env'"; exit 1; }
[ "$OLD" != "$V" ] || { echo "DIARY_VERSION is already $V"; exit 1; }
[ -d "$base/releases/$V/services/diary/agent" ] || { echo "no releases/$V/services/diary/agent"; exit 1; }
! docker image inspect cowork-diary:$V >/dev/null 2>&1 || { echo "cowork-diary:$V already exists; refusing to overwrite"; exit 1; }
OLD_ID=$(docker image inspect cowork-diary:$OLD --format '{{.Id}}')
RUN_ID=$(docker inspect cowork-diary-1 --format '{{.Image}}')
[ "$OLD_ID" = "$RUN_ID" ] || { echo "running Diary is not cowork-diary:$OLD"; exit 1; }
echo "current cowork-diary:$OLD $OLD_ID"
php /usr/local/emhttp/plugins/appdata.backup/scripts/backup.php >/tmp/ab-diary.log 2>&1
B=$(ls -td /mnt/disk3/noevia-backups/ab_* | head -1); echo "backup $B"
for f in cowork-diary-1.tar.gz cowork-web-1.tar.gz extra_files.tar.gz; do gzip -t "$B/$f"; done; echo "backup verified"
docker tag "$OLD_ID" cowork-diary:rollback-before-diary-overlay
ctx=$(mktemp -d); trap 'rm -rf "$ctx"' EXIT
cp -r "$base/releases/$V/services/diary/agent" "$ctx/agent"
printf 'FROM cowork-diary:rollback-before-diary-overlay\nCOPY agent/ ./agent/\n' > "$ctx/Dockerfile"
docker build -q -t cowork-diary:$V-candidate "$ctx" >/dev/null
docker run --rm --entrypoint python cowork-diary:$V-candidate -c "import agent.app, agent.workspace_files as w, agent.workspace_ops as o; assert hasattr(w,'_modified'); print('candidate imports ok')"
cp -p "$config" "$config.bak.before-diary-$V"
# Rollback: restore the .env (DIARY_VERSION=$OLD, whose image is untouched) and recreate Diary on it.
rollback() { echo "ROLLING BACK to cowork-diary:$OLD"; cp -p "$config.bak.before-diary-$V" "$config"; docker image rm cowork-diary:$V >/dev/null 2>&1 || true; bash "$base/tools/preflight/up.sh" --env-file "$config" -- -d --no-build --no-deps --wait --wait-timeout 180 diary || true; exit 1; }
docker tag cowork-diary:$V-candidate cowork-diary:$V
sed -i "s/^DIARY_VERSION=.*/DIARY_VERSION=$V/" "$config"
bash "$base/tools/preflight/up.sh" --env-file "$config" -- -d --no-build --no-deps --wait --wait-timeout 180 diary || rollback
! docker exec cowork-diary-1 python -c 'import socket; socket.gethostbyname("model-loader")' >/dev/null 2>&1 || { echo "diary can resolve model-loader"; rollback; }
docker exec cowork-web-1 node -e "fetch('http://diary:8010/api/health',{headers:{Authorization:'Bearer '+process.env.DIARY_AUTH_TOKEN}}).then(r=>{console.log('diary health via web',r.status);process.exit(r.ok?0:1)})" || rollback
docker inspect cowork-diary-1 --format 'diary {{.Config.Image}} {{.State.Health.Status}} restarts={{.RestartCount}} image={{.Image}}'
docker image rm cowork-diary:$V-candidate >/dev/null
rm -f /tmp/ab-diary.log
echo DIARY_OVERLAY_COMPLETE
