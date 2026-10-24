#!/bin/bash
# Diary image overlay: FROM the running image, replace exactly the directories the Diary Dockerfile copies into
# /app (agent/, config/ and scripts/; #2112) and, when the release pins noevia-rs, add the tenant-assertion and
# workspace-restore-verify binaries built from that pin. Rolls back on any failure.
# Usage (on DaServer, as root): bash diary-overlay.sh <SRC_SHA>. SRC_SHA is an unpacked release
# under releases/ whose services/diary/{agent,config,scripts} are shipped; it also becomes the new Diary tag
# (cowork-diary:<SRC_SHA>) and DIARY_VERSION in .env. COWORK_VERSION and the web image are untouched.
# Each directory is replaced whole: files the release no longer has are removed (#1624), and the candidate's
# /app/<dir> must hold exactly the release's files (names and sha256) before anything is stopped. config/ carries
# the system prompt and config.yaml, so a prompt or config change ships with the agent code that needs it.
# The list below is checked against the release's own Diary Dockerfile: when its COPY lines into /app name a
# different set of directories, the overlay refuses instead of silently leaving one out.
# Use when only files under services/diary/{agent,config,scripts} changed since the running image (the overlay
# refuses when requirements.txt differs from the running image's): no pip install runs, so no dependency can drift.
# Keeps cowork-diary:rollback-before-diary-overlay and config/.env.bak.before-diary-<SRC_SHA>.
# Backup (#1487): the Diary state and .env are archived into a new diary_<SRC_SHA>_<UTC> folder under
# /mnt/disk3/noevia-backups. The Appdata Backup plugin is NOT run: it stops whichever containers its own
# configuration selects. Only cowork-diary-1 is ever stopped, and only while that archive is taken.
set -euo pipefail
# #1148: the only place allowed to build or tag cowork-diary:* (deploy/preflight/diary-image-guard.sh
# refuses it everywhere else).
export NOEVIA_DIARY_OVERLAY=1
V=${1:?source release sha (becomes DIARY_VERSION)}; base=/mnt/docker/appdata/cowork; config=$base/config/.env
# $V becomes a path component, an image tag and a sed replacement below: only a hex SHA is allowed.
[[ $V =~ ^[0-9a-f]{7,40}$ ]] || { echo "source release sha must be 7 to 40 lowercase hex characters, got: $V" >&2; exit 1; }
# BEGIN preflight-installed (deploy/tests/test_overlay_scripts.py runs this block)
# #1597: up.sh fails closed unless the rest of deploy/preflight is installed beside it. Check the installed
# copy before anything is built, stopped or changed, so a partial install cannot strand a service.
for f in up.sh diary-image-guard.sh check.php diary-models-check.sh; do
  [ -f "$base/tools/preflight/$f" ] || { echo "$base/tools/preflight/$f is missing; install the whole deploy/preflight directory with deploy/preflight/install.sh; not deploying" >&2; exit 1; }
done
# END preflight-installed
cd /boot/config/plugins/compose.manager/projects/Cowork
# BEGIN diary-models-check (deploy/tests/test_diary_models_check_2105.py)
# #2105: the diary refuses every answer when the chat or aux model id it receives is not served by the chat router
# (services#2099). Resolve the Compose project this cutover deploys with the same .env, read the diary service's
# environment, and compare it with the router's model list (one read-only GET, nothing is woken). Refuse here, before
# anything is built, stopped or changed. Fails closed.
bash "$base/tools/preflight/diary-models-check.sh" --env-file "$config" \
  || { echo "the diary model settings the cutover would deploy name models the chat router does not serve (or could not be checked); not deploying (#2105)" >&2; exit 1; }
# END diary-models-check
OLD=$(sed -n 's/^DIARY_VERSION=//p' "$config")
[ -n "$OLD" ] || { echo "DIARY_VERSION is not set in $config; see docs/deployment.md 'Migrating an existing .env'"; exit 1; }
[ "$OLD" != "$V" ] || { echo "DIARY_VERSION is already $V"; exit 1; }
# BEGIN overlay-dirs (deploy/tests/test_overlay_scripts.py runs this block)
# #2112: the directories the Diary Dockerfile copies into /app (COPY agent/ ./agent/, COPY config/ ./config/,
# COPY scripts/ ./scripts/). Everything else in the image (the dependencies, the Rust binaries) is the running image's.
overlay_dirs="agent config scripts"
# The Dockerfile tail that replaces each directory whole: delete first (COPY only adds and replaces), then copy.
overlay_copy_lines() {
  local d rm_list=""
  for d in $overlay_dirs; do rm_list="$rm_list ./$d"; done
  printf 'RUN rm -rf%s\n' "$rm_list"
  for d in $overlay_dirs; do printf 'COPY %s/ ./%s/\n' "$d" "$d"; done
}
# END overlay-dirs
for d in $overlay_dirs; do
  [ -d "$base/releases/$V/services/diary/$d" ] || { echo "no releases/$V/services/diary/$d"; exit 1; }
done
# #2112: keep the list in step with the release's Diary Dockerfile. A directory it copies that is not listed here
# would be left out of the overlay without a word (the bug this fixes); a listed one it no longer copies is not
# part of the image. Either way the overlay stops before anything is built, stopped or changed.
diary_df_check=$base/releases/$V/services/diary/Dockerfile
[ -f "$diary_df_check" ] || { echo "no releases/$V/services/diary/Dockerfile to check the overlay directories against; not deploying" >&2; exit 1; }
# BEGIN dockerfile-copy-check (deploy/tests/test_overlay_scripts.py runs this block)
# Every COPY and ADD of the final stage is significant. Only three shapes are known: the dependency list, the binaries
# copied by `COPY --from=tenant-assertion /out/ /usr/local/bin/`, and `COPY <dir>/ ./<dir>/` for a directory
# of the app. Any other line that copies something
# (a file, a hyphenated directory, --chown, ADD, JSON form, a continued line) would put content into the image that
# this overlay does not ship, so it stops the overlay instead of being ignored.
final_stage=$(awk 'tolower($0) ~ /^[ \t]*from[ \t]/ { buf = ""; next } { buf = buf $0 "\n" } END { printf "%s", buf }' "$diary_df_check")
df_dirs=""; df_unknown=""
while IFS= read -r df_line || [ -n "$df_line" ]; do
  df_line="${df_line#"${df_line%%[![:space:]]*}"}"; df_line="${df_line%"${df_line##*[![:space:]]}"}"
  case "$(printf '%s' "$df_line" | tr 'A-Z' 'a-z')" in copy|copy[[:space:]]*|add|add[[:space:]]*) ;; *) continue ;; esac
  if [ "$df_line" = "COPY requirements.txt ." ]; then continue
  elif [ "$df_line" = "COPY --from=tenant-assertion /out/ /usr/local/bin/" ]; then continue
  elif [[ $df_line =~ ^COPY\ ([a-z_][a-z0-9_]*)/\ \./([a-z_][a-z0-9_]*)/$ ]] && [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ]; then
    df_dirs="$df_dirs${BASH_REMATCH[1]}"$'\n'
  else df_unknown="$df_unknown$df_line"$'\n'
  fi
done <<< "$final_stage"
if [ -n "$df_unknown" ]; then
  echo "the release Diary Dockerfile copies something into the image that this overlay does not know how to ship:" >&2
  printf '%s' "$df_unknown" | head -n 5 | sed 's/^/  /' >&2
  echo "the only Rust COPY allowed is: COPY --from=tenant-assertion /out/ /usr/local/bin/" >&2
  echo "update diary-overlay.sh (and its test) for these lines, or rebuild the image; not deploying" >&2
  exit 1
fi
df_dirs=$(printf '%s' "$df_dirs" | LC_ALL=C sort -u)
my_dirs=$(printf '%s\n' $overlay_dirs | LC_ALL=C sort -u)
if [ "$df_dirs" != "$my_dirs" ]; then
  echo "the release Diary Dockerfile copies these directories into /app: ${df_dirs//$'\n'/ }; this overlay ships: ${my_dirs//$'\n'/ }." >&2
  for d in $df_dirs; do case " ${my_dirs//$'\n'/ } " in *" $d "*) ;; *) echo "  the Dockerfile copies $d/ but this overlay would leave it out" >&2 ;; esac; done
  for d in $my_dirs; do case " ${df_dirs//$'\n'/ } " in *" $d "*) ;; *) echo "  this overlay ships $d/ but the Dockerfile does not copy it" >&2 ;; esac; done
  echo "update overlay_dirs in diary-overlay.sh (and its test) before overlaying this release; not deploying" >&2
  exit 1
fi
# END dockerfile-copy-check
! docker image inspect cowork-diary:$V >/dev/null 2>&1 || { echo "cowork-diary:$V already exists; refusing to overwrite"; exit 1; }
OLD_ID=$(docker image inspect cowork-diary:$OLD --format '{{.Id}}')
RUN_ID=$(docker inspect cowork-diary-1 --format '{{.Image}}')
[ "$OLD_ID" = "$RUN_ID" ] || { echo "running Diary is not cowork-diary:$OLD"; exit 1; }
echo "current cowork-diary:$OLD $OLD_ID"
# #2112: the overlay keeps the running image's dependencies, so requirements.txt must be the one the release has.
# BEGIN requirements-check (deploy/tests/test_overlay_scripts.py runs this block with stub docker)
# Read the existing image without network access, a writable root filesystem or an image pull.
req_want=$(sha256sum "$base/releases/$V/services/diary/requirements.txt" 2>/dev/null | cut -d' ' -f1) || req_want=""
req_have=$(docker run --rm --network none --read-only --pull never --entrypoint sh cowork-diary:$OLD -c 'sha256sum /app/requirements.txt' 2>/dev/null | cut -d' ' -f1) || req_have=""
[ -n "$req_want" ] && [ "$req_want" = "$req_have" ] \
  || { echo "requirements.txt in releases/$V/services/diary is missing or differs from the running image's (or could not be read there): the overlay installs no dependencies, rebuild the image instead; not deploying" >&2; exit 1; }
# END requirements-check
# The scoped backup below needs both; checked here so a bad layout fails before anything is built (#1487).
backup_root=${BACKUP_ROOT:-/mnt/disk3/noevia-backups}
[ -d "$backup_root" ] || { echo "backup root $backup_root is missing; not deploying" >&2; exit 1; }
[ -d "$base/state/diary" ] && [ -f "$config" ] || { echo "$base/state/diary or $config is missing; not deploying" >&2; exit 1; }
tmp=$(mktemp -d); ctx=$tmp/ctx; mkdir "$ctx"
# Set while cowork-diary-1 is stopped for the scoped backup (#1487). Cleared once the recreate below
# is the next step, because from then on rollback() owns the Diary container. Any earlier exit
# starts Diary again on the image .env still names (the old one), so a failed run never leaves it down.
diary_stopped=0
# Brings Diary back on the image .env names. If up.sh cannot run at all (#1597: an incomplete preflight
# install), the container is still the stopped, unchanged one: start it directly, but only while it is
# still the old image, so a half-recreated new container is never started by accident.
recover_diary() {
  bash "$base/tools/preflight/up.sh" --env-file "$config" -- -d --no-build --no-deps --wait --wait-timeout 180 diary >&2 && return 0
  if [ "$(docker inspect cowork-diary-1 --format '{{.Image}}' 2>/dev/null)" = "$OLD_ID" ]; then
    echo "up.sh could not run; starting the unchanged cowork-diary-1 directly" >&2
    docker start cowork-diary-1 >&2 && return 0
  fi
  return 1
}
on_exit() {
  rm -rf "$tmp"
  if [ "$diary_stopped" = 1 ]; then
    echo "restarting cowork-diary-1 on its previous image after an interrupted run" >&2
    recover_diary || echo "cowork-diary-1 did not restart; start it by hand (docker start cowork-diary-1)" >&2
  fi
}
trap on_exit EXIT
docker tag "$OLD_ID" cowork-diary:rollback-before-diary-overlay
for d in $overlay_dirs; do cp -r "$base/releases/$V/services/diary/$d" "$ctx/$d"; done
# BEGIN rs-stage (deploy/tests/test_overlay_scripts.py runs this block on synthetic Dockerfiles)
# TENANT_ASSERTION_IMPL=rust needs the tenant-assertion binary, WORKSPACE_RESTORE_VERIFY_IMPL=rust
# the workspace-restore-verify binary (noevia#982; built only when the pinned noevia-rs has it, so
# older releases still overlay). When the release's Diary Dockerfile pins noevia-rs
# (ARG NOEVIA_RS_REF / NOEVIA_RS_SHA256), build them here in the same pinned, checksum-verified
# Rust stage and copy only the binaries in: no pip install, no Python change, the runtime layers
# stay the running image's. Only the two validated hex pins are taken from the release's
# Dockerfile, never any of its text.
diary_df=$base/releases/$V/services/diary/Dockerfile
rs_ref=$(sed -n 's/^ARG NOEVIA_RS_REF=//p' "$diary_df" 2>/dev/null | head -1 || true)
rs_sum=$(sed -n 's/^ARG NOEVIA_RS_SHA256=//p' "$diary_df" 2>/dev/null | head -1 || true)
if [ -z "$rs_ref$rs_sum" ]; then
  echo "release Diary Dockerfile pins no noevia-rs: no tenant-assertion binary (TENANT_ASSERTION_IMPL must stay python)"
  { printf 'FROM cowork-diary:rollback-before-diary-overlay\n'; overlay_copy_lines; } > "$ctx/Dockerfile"
  rs_stage=0
else
  [[ $rs_ref =~ ^[0-9a-f]{40}$ && $rs_sum =~ ^[0-9a-f]{64}$ ]] || { echo "release Diary Dockerfile noevia-rs pin is not a 40-hex ref and 64-hex sha256" >&2; exit 1; }
  cat > "$ctx/Dockerfile" <<DOCKERFILE
FROM rust:1.99-slim-bookworm@sha256:2c3a22f0a5533ea2dd5a16627bc841228151faa2d4de2644ac9987e4a2f1f2fa AS tenant-assertion
ENV RUSTUP_TOOLCHAIN=1.99.0 CARGO_TERM_COLOR=never
WORKDIR /src
ADD https://codeload.github.com/sbstndalton/noevia-rs/tar.gz/$rs_ref /tmp/noevia-rs.tar.gz
RUN echo "$rs_sum  /tmp/noevia-rs.tar.gz" | sha256sum -c - \\
 && tar -xzf /tmp/noevia-rs.tar.gz --strip-components=1 \\
 && rm /tmp/noevia-rs.tar.gz \\
 && cargo build --release --locked -p tenant-assertion-cli \\
 && ./target/release/tenant-assertion self-test | grep -qx ok \\
 && mkdir /out && cp target/release/tenant-assertion /out/ \\
 && if [ -d bins/workspace-restore-verify ]; then \\
      cargo build --release --locked -p workspace-restore-verify-cli \\
      && ./target/release/workspace-restore-verify self-test | grep -qx ok \\
      && cp target/release/workspace-restore-verify /out/; fi
FROM cowork-diary:rollback-before-diary-overlay
COPY --from=tenant-assertion /out/ /usr/local/bin/
$(overlay_copy_lines)
DOCKERFILE
  rs_stage=1
  echo "tenant-assertion from noevia-rs $rs_ref"
fi
# END rs-stage
docker build -q -t cowork-diary:$V-candidate "$ctx" >/dev/null
docker run --rm --entrypoint python cowork-diary:$V-candidate -c "import agent.app, agent.workspace_files as w, agent.workspace_ops as o; assert hasattr(w,'_modified'); print('candidate imports ok')"
# BEGIN dirs-exact (#1624, #2112: deploy/tests/test_overlay_scripts.py runs this through the whole script)
# COPY only adds and replaces, so the Dockerfile above deletes each directory first. This proves the result: the
# candidate's /app/<dir> must hold exactly the release's files (names and sha256), nothing stale or missing, for
# every directory the overlay ships (agent/, config/, scripts/).
dir_listing='find . -type f ! -path "*/__pycache__/*" -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum'
for d in $overlay_dirs; do
  want=$(cd "$ctx/$d" && sh -c "$dir_listing")
  got=$(docker run --rm --network none --entrypoint sh cowork-diary:$V-candidate -c "cd /app/$d && $dir_listing") \
    || { echo "could not list /app/$d in the candidate; not deploying" >&2; exit 1; }
  if [ "$want" != "$got" ]; then
    echo "candidate /app/$d differs from releases/$V/services/diary/$d; not deploying:" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") >&2 || true
    docker image rm cowork-diary:$V-candidate >/dev/null 2>&1 || true
    exit 1
  fi
  echo "candidate $d/ matches the release ($(printf '%s\n' "$want" | grep -c .) files)"
done
# END dirs-exact
if [ "$rs_stage" = 1 ]; then
  docker run --rm --network none --entrypoint tenant-assertion cowork-diary:$V-candidate self-test | grep -qx ok || { echo "candidate tenant-assertion self-test failed; not deploying" >&2; exit 1; }
  echo "candidate tenant-assertion ok"
  # Present only when the pinned noevia-rs builds it; if present it must pass (noevia#982).
  if docker run --rm --network none --entrypoint sh cowork-diary:$V-candidate -c 'test -x /usr/local/bin/workspace-restore-verify'; then
    docker run --rm --network none --entrypoint workspace-restore-verify cowork-diary:$V-candidate self-test | grep -qx ok || { echo "candidate workspace-restore-verify self-test failed; not deploying" >&2; exit 1; }
    echo "candidate workspace-restore-verify ok"
  else
    echo "candidate has no workspace-restore-verify (pinned noevia-rs predates it): WORKSPACE_RESTORE_VERIFY_IMPL must stay python"
  fi
fi
cp -p "$config" "$config.bak.before-diary-$V"
# BEGIN diary-backup (deploy/tests/test_overlay_scripts.py runs this block through the whole script, with stub docker, gzip and php)
# Scoped backup (#1487): the Diary state directory and .env only, in a new folder that the Appdata Backup
# plugin never sees (no ab_ prefix). Nothing here stops or restarts any container but cowork-diary-1.
B="$backup_root/diary_${V}_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -m 700 "$B" || { echo "backup folder $B already exists; not deploying" >&2; exit 1; }
# Diary is stopped only while its SQLite files are copied, so they cannot change under the archive.
diary_stopped=1
docker stop --time 30 cowork-diary-1 >/dev/null
(umask 077; COPYFILE_DISABLE=1 tar -czf "$B/diary-appdata.tar.gz" -C "$base" state/diary config/.env)
gzip -t "$B/diary-appdata.tar.gz"
tar -tzf "$B/diary-appdata.tar.gz" > "$B/listing.txt"
grep -qx 'config/.env' "$B/listing.txt" && grep -qE '^state/diary(/|$)' "$B/listing.txt" \
  || { echo "backup $B does not list config/.env and state/diary; not deploying" >&2; exit 1; }
echo "backup $B"
echo "backup verified"
# END diary-backup
# Rollback: restore the .env (DIARY_VERSION=$OLD, whose image is untouched) and recreate Diary on it.
rollback() { echo "ROLLING BACK to cowork-diary:$OLD"; cp -p "$config.bak.before-diary-$V" "$config"; docker image rm cowork-diary:$V >/dev/null 2>&1 || true; recover_diary || echo "cowork-diary-1 is not running on cowork-diary:$OLD; start it by hand" >&2; exit 1; }
docker tag cowork-diary:$V-candidate cowork-diary:$V
sed -i "s/^DIARY_VERSION=.*/DIARY_VERSION=$V/" "$config"
diary_stopped=0
bash "$base/tools/preflight/up.sh" --env-file "$config" -- -d --no-build --no-deps --wait --wait-timeout 180 diary || rollback
! docker exec cowork-diary-1 python -c 'import socket; socket.gethostbyname("model-loader")' >/dev/null 2>&1 || { echo "diary can resolve model-loader"; rollback; }
docker exec cowork-web-1 node -e "fetch('http://diary:8010/api/health',{headers:{Authorization:'Bearer '+process.env.DIARY_AUTH_TOKEN}}).then(r=>{console.log('diary health via web',r.status);process.exit(r.ok?0:1)})" || rollback
docker inspect cowork-diary-1 --format 'diary {{.Config.Image}} {{.State.Health.Status}} restarts={{.RestartCount}} image={{.Image}}'
docker image rm cowork-diary:$V-candidate >/dev/null
echo DIARY_OVERLAY_COMPLETE
