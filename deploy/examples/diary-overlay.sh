#!/bin/bash
# Diary image overlay: FROM the running image, replace agent/ only (plus, when the release pins
# noevia-rs, the tenant-assertion binary built from that pin). Rolls back on any failure.
# Usage (on DaServer, as root): bash diary-overlay.sh <SRC_SHA>. SRC_SHA is an unpacked release
# under releases/ whose services/diary/agent is shipped; it also becomes the new Diary tag
# (cowork-diary:<SRC_SHA>) and DIARY_VERSION in .env. COWORK_VERSION and the web image are untouched.
# Use when only files under services/diary/agent changed since the running image (check
# requirements.txt and Dockerfile are unchanged): no pip install runs, so no dependency can drift.
# Keeps cowork-diary:rollback-before-diary-overlay and config/.env.bak.before-diary-<SRC_SHA>.
set -euo pipefail
V=${1:?source release sha (becomes DIARY_VERSION)}; base=/mnt/docker/appdata/cowork; config=$base/config/.env
# $V becomes a path component, an image tag and a sed replacement below: only a hex SHA is allowed.
[[ $V =~ ^[0-9a-f]{7,40}$ ]] || { echo "source release sha must be 7 to 40 lowercase hex characters, got: $V" >&2; exit 1; }
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
# $marker is older than the backup this run takes, so a leftover ab_* folder from an earlier
# (or failed) run can never be mistaken for it.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
marker=$tmp/backup-start; touch "$marker"; ctx=$tmp/ctx; mkdir "$ctx"
php /usr/local/emhttp/plugins/appdata.backup/scripts/backup.php >/tmp/ab-diary.log 2>&1
# BEGIN backup-pick (deploy/tests/test_overlay_scripts.py runs this block on synthetic folders)
backup_root=${BACKUP_ROOT:-/mnt/disk3/noevia-backups}
B=$(ls -td "$backup_root"/ab_* 2>/dev/null | head -1 || true)
[ -n "$B" ] && [ -d "$B" ] || { echo "no appdata backup (ab_*) under $backup_root; not deploying" >&2; exit 1; }
[ "$B" -nt "$marker" ] || { echo "newest backup $B is older than this run's backup start, so the backup did not produce a new folder; not deploying" >&2; exit 1; }
# END backup-pick
echo "backup $B"
for f in cowork-diary-1.tar.gz cowork-web-1.tar.gz extra_files.tar.gz; do gzip -t "$B/$f"; done; echo "backup verified"
docker tag "$OLD_ID" cowork-diary:rollback-before-diary-overlay
cp -r "$base/releases/$V/services/diary/agent" "$ctx/agent"
# BEGIN rs-stage (deploy/tests/test_overlay_scripts.py runs this block on synthetic Dockerfiles)
# TENANT_ASSERTION_IMPL=rust needs the tenant-assertion binary. When the release's Diary Dockerfile
# pins noevia-rs (ARG NOEVIA_RS_REF / NOEVIA_RS_SHA256), build it here in the same pinned,
# checksum-verified Rust stage and copy only the binary in: no pip install, no Python change, the
# runtime layers stay the running image's. Only the two validated hex pins are taken from the
# release's Dockerfile, never any of its text.
diary_df=$base/releases/$V/services/diary/Dockerfile
rs_ref=$(sed -n 's/^ARG NOEVIA_RS_REF=//p' "$diary_df" 2>/dev/null | head -1 || true)
rs_sum=$(sed -n 's/^ARG NOEVIA_RS_SHA256=//p' "$diary_df" 2>/dev/null | head -1 || true)
if [ -z "$rs_ref$rs_sum" ]; then
  echo "release Diary Dockerfile pins no noevia-rs: no tenant-assertion binary (TENANT_ASSERTION_IMPL must stay python)"
  printf 'FROM cowork-diary:rollback-before-diary-overlay\nCOPY agent/ ./agent/\n' > "$ctx/Dockerfile"
  rs_stage=0
else
  [[ $rs_ref =~ ^[0-9a-f]{40}$ && $rs_sum =~ ^[0-9a-f]{64}$ ]] || { echo "release Diary Dockerfile noevia-rs pin is not a 40-hex ref and 64-hex sha256" >&2; exit 1; }
  cat > "$ctx/Dockerfile" <<DOCKERFILE
FROM rust:1.99-slim-bookworm AS tenant-assertion
ENV RUSTUP_TOOLCHAIN=1.99.0 CARGO_TERM_COLOR=never
WORKDIR /src
ADD https://codeload.github.com/sbstndalton/noevia-rs/tar.gz/$rs_ref /tmp/noevia-rs.tar.gz
RUN echo "$rs_sum  /tmp/noevia-rs.tar.gz" | sha256sum -c - \\
 && tar -xzf /tmp/noevia-rs.tar.gz --strip-components=1 \\
 && rm /tmp/noevia-rs.tar.gz \\
 && cargo build --release --locked -p tenant-assertion-cli \\
 && ./target/release/tenant-assertion self-test | grep -qx ok
FROM cowork-diary:rollback-before-diary-overlay
COPY --from=tenant-assertion /src/target/release/tenant-assertion /usr/local/bin/tenant-assertion
COPY agent/ ./agent/
DOCKERFILE
  rs_stage=1
  echo "tenant-assertion from noevia-rs $rs_ref"
fi
# END rs-stage
docker build -q -t cowork-diary:$V-candidate "$ctx" >/dev/null
docker run --rm --entrypoint python cowork-diary:$V-candidate -c "import agent.app, agent.workspace_files as w, agent.workspace_ops as o; assert hasattr(w,'_modified'); print('candidate imports ok')"
if [ "$rs_stage" = 1 ]; then
  docker run --rm --network none --entrypoint tenant-assertion cowork-diary:$V-candidate self-test | grep -qx ok || { echo "candidate tenant-assertion self-test failed; not deploying" >&2; exit 1; }
  echo "candidate tenant-assertion ok"
fi
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
