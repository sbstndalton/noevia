#!/bin/bash
# Diary image overlay: FROM the running image, replace /app/agent ONLY (the companion rule: a Diary companion
# overlay ships agent/ code from the running image; config/ and scripts/ stay the running image's, #2112 review)
# and, when the release pins noevia-rs, add the tenant-assertion and workspace-restore-verify binaries built from
# that pin, plus the Diary Rust leaves (rust_leaves below) when the release ships the smoke that proves them
# (noevia#1071 P0), and the Rust Diary server noevia-diary (D4-D5).
# With a pin, every native binary inherited from the running image is removed first, so the candidate holds only
# binaries built from the selected pin. Rolls back on any failure.
# Usage (on DaServer, as root): bash diary-overlay.sh <SRC_SHA>. SRC_SHA is an unpacked release
# under releases/ whose services/diary/{agent,config,scripts} are shipped; it also becomes the new Diary tag
# (cowork-diary:<SRC_SHA>) and DIARY_VERSION in .env. COWORK_VERSION and the web image are untouched.
# agent/ is replaced whole: files the release no longer has are removed (#1624), and the candidate's /app/agent
# must hold exactly the release's files (names and sha256) before anything is stopped. config/ (the system prompt and
# config.yaml) and scripts/ are never replaced: the release's own config/ and scripts/ must already equal the running
# image's (names and sha256; scripts/smoke_diary_leaves.py aside, below) or the overlay refuses and the image must be
# rebuilt, and the candidate's are proven equal to the running image's. The one release asset the overlay needs,
# scripts/smoke_diary_leaves.py, is run from the release by a read-only bind mount and is not installed in the image.
# The directory lists below are checked against the release's own Diary Dockerfile: when its COPY lines into /app name
# a different set of directories, the overlay refuses instead of silently leaving one out.
# Use when only files under services/diary/agent changed since the running image (the overlay refuses when
# requirements.txt, config/ or scripts/ differ from the running image's): no pip install runs, so no dependency can drift.
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
# The directories the Diary Dockerfile copies into /app (COPY agent/ ./agent/, COPY config/ ./config/,
# COPY scripts/ ./scripts/). Only overlay_dirs are replaced; preserved_dirs (and everything else in the image: the
# dependencies, the Rust binaries) stay the running image's. The Dockerfile must copy exactly the two lists together.
overlay_dirs="agent"
preserved_dirs="config scripts"
# The release asset the candidate's smoke needs from scripts/ (run from the release, never installed).
smoke_asset=smoke_diary_leaves.py
# Names and sha256 of one directory's files, run inside the directory.
dir_listing='find . -type f ! -path "*/__pycache__/*" -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum'
# The comparison listing of a preserved directory: scripts/ without the smoke asset.
preserved_filter() { if [ "$1" = scripts ]; then grep -v -x "[0-9a-f]\{64\}  \./$smoke_asset" || true; else cat; fi; }
# The Dockerfile tail that replaces each directory whole: delete first (COPY only adds and replaces), then copy.
overlay_copy_lines() {
  local d rm_list=""
  for d in $overlay_dirs; do rm_list="$rm_list ./$d"; done
  printf 'RUN rm -rf%s\n' "$rm_list"
  for d in $overlay_dirs; do printf 'COPY %s/ ./%s/\n' "$d" "$d"; done
}
# END overlay-dirs
for d in $overlay_dirs $preserved_dirs; do
  [ -d "$base/releases/$V/services/diary/$d" ] || { echo "no releases/$V/services/diary/$d"; exit 1; }
done
# #2112: keep the list in step with the release's Diary Dockerfile. A directory it copies that is not listed here
# would be left out of the overlay without a word (the bug this fixes); a listed one it no longer copies is not
# part of the image. Either way the overlay stops before anything is built, stopped or changed.
diary_df_check=$base/releases/$V/services/diary/Dockerfile
[ -f "$diary_df_check" ] || { echo "no releases/$V/services/diary/Dockerfile to check the overlay directories against; not deploying" >&2; exit 1; }
# BEGIN dockerfile-copy-check (deploy/tests/test_overlay_scripts.py runs this block)
# Every COPY and ADD of the final stage is significant. Known shapes are the dependency list, the generated
# /out/ binary bundle, the release's two exact individual binary copies, and COPY <dir>/ ./<dir>/ for app directories.
# An arbitrary source/destination from the Rust stage is not accepted. Any other line that copies something
# (a file, a hyphenated directory, --chown, ADD, JSON form, a continued line) would put content into the image that
# this overlay does not ship, so it stops the overlay instead of being ignored.
final_stage=$(awk 'tolower($0) ~ /^[ \t]*from[ \t]/ { buf = ""; next } { buf = buf $0 "\n" } END { printf "%s", buf }' "$diary_df_check")
df_dirs=""; df_unknown=""
while IFS= read -r df_line || [ -n "$df_line" ]; do
  df_line="${df_line#"${df_line%%[![:space:]]*}"}"; df_line="${df_line%"${df_line##*[![:space:]]}"}"
  case "$(printf '%s' "$df_line" | tr 'A-Z' 'a-z')" in copy|copy[[:space:]]*|add|add[[:space:]]*) ;; *) continue ;; esac
  if [ "$df_line" = "COPY requirements.txt ." ]; then continue
  elif [ "$df_line" = "COPY --from=tenant-assertion /out/ /usr/local/bin/" ]; then continue
  elif [ "$df_line" = "COPY --from=tenant-assertion /src/target/release/tenant-assertion /usr/local/bin/tenant-assertion" ]; then continue
  elif [ "$df_line" = "COPY --from=tenant-assertion /src/target/release/workspace-restore-verify /usr/local/bin/workspace-restore-verify" ]; then continue
  elif [[ $df_line =~ ^COPY\ ([a-z_][a-z0-9_]*)/\ \./([a-z_][a-z0-9_]*)/$ ]] && [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ]; then
    df_dirs="$df_dirs${BASH_REMATCH[1]}"$'\n'
  else df_unknown="$df_unknown$df_line"$'\n'
  fi
done <<< "$final_stage"
if [ -n "$df_unknown" ]; then
  echo "the release Diary Dockerfile copies something into the image that this overlay does not know how to ship:" >&2
  printf '%s' "$df_unknown" | head -n 5 | sed 's/^/  /' >&2
  echo "Rust COPY must be the exact /out/ bundle or an exact tenant-assertion/workspace-restore-verify release binary path into /usr/local/bin/" >&2
  echo "update diary-overlay.sh (and its test) for these lines, or rebuild the image; not deploying" >&2
  exit 1
fi
df_dirs=$(printf '%s' "$df_dirs" | LC_ALL=C sort -u)
my_dirs=$(printf '%s\n' $overlay_dirs $preserved_dirs | LC_ALL=C sort -u)
if [ "$df_dirs" != "$my_dirs" ]; then
  echo "the release Diary Dockerfile copies these directories into /app: ${df_dirs//$'\n'/ }; this overlay handles: ${my_dirs//$'\n'/ }." >&2
  for d in $df_dirs; do case " ${my_dirs//$'\n'/ } " in *" $d "*) ;; *) echo "  the Dockerfile copies $d/ but this overlay would leave it out" >&2 ;; esac; done
  for d in $my_dirs; do case " ${df_dirs//$'\n'/ } " in *" $d "*) ;; *) echo "  this overlay handles $d/ but the Dockerfile does not copy it" >&2 ;; esac; done
  echo "update overlay_dirs/preserved_dirs in diary-overlay.sh (and its test) before overlaying this release; not deploying" >&2
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
# BEGIN preserved-dirs-check (deploy/tests/test_overlay_scripts.py runs this block with stub docker)
# The overlay never replaces preserved_dirs. A release whose config/ (system prompt, config.yaml) or scripts/ differs from
# the running image's would otherwise run its new agent code against the old files (#2112), so it is refused: rebuild the
# image instead. scripts/$smoke_asset is the one release asset the overlay uses; it is run from the release (below)
# and is left out of this comparison. The running image's listing is kept to prove the candidate leaves it untouched.
for d in $preserved_dirs; do
  want=$(cd "$base/releases/$V/services/diary/$d" && sh -c "$dir_listing" | preserved_filter "$d") \
    || { echo "could not list releases/$V/services/diary/$d; not deploying" >&2; exit 1; }
  have=$(docker run --rm --network none --read-only --pull never --entrypoint sh cowork-diary:$OLD -c "cd /app/$d && $dir_listing" | preserved_filter "$d"; exit "${PIPESTATUS[0]}") \
    || { echo "could not list /app/$d in the running image; not deploying" >&2; exit 1; }
  if [ "$want" != "$have" ]; then
    echo "releases/$V/services/diary/$d differs from the running image's /app/$d: the overlay replaces only agent/ and never $d/; rebuild the image instead; not deploying:" >&2
    diff <(printf '%s\n' "$have") <(printf '%s\n' "$want") >&2 || true
    exit 1
  fi
  printf -v "preserved_have_$d" '%s' "$have"
done
# END preserved-dirs-check
# The scoped backup below needs both; checked here so a bad layout fails before anything is built (#1487).
backup_root=${BACKUP_ROOT:-/mnt/disk3/noevia-backups}
[ -d "$backup_root" ] || { echo "backup root $backup_root is missing; not deploying" >&2; exit 1; }
[ -d "$base/state/diary" ] && [ -f "$config" ] || { echo "$base/state/diary or $config is missing; not deploying" >&2; exit 1; }
tmp=$(mktemp -d); ctx=$tmp/ctx; mkdir "$ctx"
# Set while cowork-diary-1 is stopped for the scoped backup (#1487). Cleared once the recreate below
# is the next step, because from then on rollback() owns the Diary container. Any earlier exit
# starts Diary again on the image .env still names (the old one), so a failed run never leaves it down.
diary_stopped=0
# Set once `docker build` of the candidate starts, and once the overlay completes. Any other exit after the build
# removes cowork-diary:$V-candidate (P3-1: every refused or rolled-back run would otherwise leave one behind,
# and Docker resources are never pruned), unless cowork-diary:$V exists, which then names the same image.
candidate_built=0; overlay_complete=0
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
  if [ "$candidate_built" = 1 ] && [ "$overlay_complete" != 1 ] && ! docker image inspect cowork-diary:$V >/dev/null 2>&1; then
    docker image rm cowork-diary:$V-candidate >/dev/null 2>&1 || true
  fi
  if [ "$diary_stopped" = 1 ]; then
    echo "restarting cowork-diary-1 on its previous image after an interrupted run" >&2
    recover_diary || echo "cowork-diary-1 did not restart; start it by hand (docker start cowork-diary-1)" >&2
  fi
}
trap on_exit EXIT
docker tag "$OLD_ID" cowork-diary:rollback-before-diary-overlay
for d in $overlay_dirs; do cp -r "$base/releases/$V/services/diary/$d" "$ctx/$d"; done
# BEGIN rust-leaves (deploy/tests/test_overlay_scripts.py runs this block with rs-stage and leaf-smoke)
# noevia#1071 P0: the Diary Rust leaves whose Python adapters already exist (and, last, the D4-D5 server process
# noevia-diary, which Python starts only when DIARY_RUST_ROUTES/DIARY_RUST_WRITES is set), one per line as
# <source directory in noevia-rs>:<cargo package>:<binary installed in /usr/local/bin>. Each is built only when
# the pinned noevia-rs has its directory, and only for a release that ships scripts/smoke_diary_leaves.py, which
# the candidate then runs on every leaf it has. The image ships them; every selector stays python.
rust_leaves="crates/diary-backup-run:diary-backup-run:diary-backup-run
crates/diary-entity-focus:diary-entity-focus:diary-entity-focus
crates/diary-index-transform:diary-index-transform:diary-index-transform
crates/diary-storage-backoff:diary-storage-backoff:diary-storage-backoff
crates/diary-workspace-rules:diary-workspace-rules:diary-workspace-rules
crates/diary-backup-format:diary-backup-format:diary-backup-format
bins/diary-corpus-write:diary-corpus-write-cli:diary-corpus-write-cli
crates/diary-corpus-parse:diary-corpus-parse:diary-corpus-parse
crates/diary-score-gap:diary-score-gap:diary-score-gap
crates/diary-temporal-focus:diary-temporal-focus:diary-temporal-cli
crates/diary-workspace-export:diary-workspace-export:diary-workspace-export
crates/diary-workspace-import-apply:diary-workspace-import-apply:diary-workspace-import-apply
bins/noevia-diary:noevia-diary:noevia-diary"
leaf_smoke=scripts/smoke_diary_leaves.py
# The RUN continuation lines that build each declared leaf into /out/ (nothing when the release has no smoke).
rust_leaf_lines() {
  local spec dir rest pkg bin
  [ "$rs_leaves" = 1 ] || return 0
  for spec in $rust_leaves; do
    dir=${spec%%:*}; rest=${spec#*:}; pkg=${rest%%:*}; bin=${rest#*:}
    printf ' \\\n && if [ -d %s ]; then cargo build --release --locked -p %s && cp target/release/%s /out/; fi' "$dir" "$pkg" "$bin"
  done
}
# Every native binary this overlay installs under /usr/local/bin (the two self-tested ones and every leaf above).
# The final stage starts FROM the running image and COPY only adds and replaces, so a binary an earlier release
# installed would otherwise survive when the selected noevia-rs pin no longer has its crate (the build skips an
# absent directory) and could pass the smoke and native-required as if it came from this pin. When the release
# pins noevia-rs the Dockerfile removes all of them first: whatever native binary the candidate has was built
# from exactly that pin.
native_bin_names() {
  local spec
  echo tenant-assertion; echo workspace-restore-verify
  for spec in $rust_leaves; do echo "${spec##*:}"; done
}
stale_native_bins_line() {
  local name
  printf 'RUN cd /usr/local/bin && rm -f --'
  for name in $(native_bin_names); do printf ' %s' "$name"; done
}
# END rust-leaves
# BEGIN rs-stage (deploy/tests/test_overlay_scripts.py runs this block on synthetic Dockerfiles)
# TENANT_ASSERTION_IMPL=rust needs the tenant-assertion binary, WORKSPACE_RESTORE_VERIFY_IMPL=rust
# the workspace-restore-verify binary (noevia#982; built only when the pinned noevia-rs has it, so
# older releases still overlay). When the release's Diary Dockerfile pins noevia-rs
# (ARG NOEVIA_RS_REF / NOEVIA_RS_SHA256), build them here in the same pinned, checksum-verified
# Rust stage and copy only the binaries in: no pip install, no Python change, the runtime layers
# stay the running image's. Only the two validated hex pins are taken from the release's
# Dockerfile, never any of its text.
diary_df=$base/releases/$V/services/diary/Dockerfile
rs_leaves=0
if [ -f "$base/releases/$V/services/diary/$leaf_smoke" ]; then rs_leaves=1; fi
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
ENV RUSTUP_TOOLCHAIN=1.99.0 CARGO_TERM_COLOR=never CARGO_BUILD_JOBS=2
ARG NOEVIA_RS_REF=$rs_ref
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
      && cp target/release/workspace-restore-verify /out/; fi$(rust_leaf_lines) \\
 && rm -rf /src/target /usr/local/cargo/registry
FROM cowork-diary:rollback-before-diary-overlay
$(stale_native_bins_line)
COPY --from=tenant-assertion /out/ /usr/local/bin/
$(overlay_copy_lines)
DOCKERFILE
  rs_stage=1
  echo "tenant-assertion from noevia-rs $rs_ref"
  if [ "$rs_leaves" = 1 ]; then echo "Diary Rust leaves from noevia-rs $rs_ref (selectors stay python)"; fi
fi
# END rs-stage
candidate_built=1
docker build -q -t cowork-diary:$V-candidate "$ctx" >/dev/null
docker run --rm --entrypoint python cowork-diary:$V-candidate -c "import agent.app, agent.workspace_files as w, agent.workspace_ops as o; assert hasattr(w,'_modified'); print('candidate imports ok')"
# BEGIN dirs-exact (#1624, #2112: deploy/tests/test_overlay_scripts.py runs this through the whole script)
# COPY only adds and replaces, so the Dockerfile above deletes each directory first. This proves the result: the
# candidate's /app/<dir> must hold exactly the release's files (names and sha256), nothing stale or missing, for
# every directory the overlay replaces (agent/). The preserved directories (config/, scripts/) must still be exactly the
# running image's, as listed before the build.
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
for d in $preserved_dirs; do
  got=$(docker run --rm --network none --entrypoint sh cowork-diary:$V-candidate -c "cd /app/$d && $dir_listing" | preserved_filter "$d"; exit "${PIPESTATUS[0]}") \
    || { echo "could not list /app/$d in the candidate; not deploying" >&2; exit 1; }
  var="preserved_have_$d"
  if [ "$got" != "${!var}" ]; then
    echo "candidate /app/$d differs from the running image's; the overlay must leave it untouched; not deploying:" >&2
    diff <(printf '%s\n' "${!var}") <(printf '%s\n' "$got") >&2 || true
    docker image rm cowork-diary:$V-candidate >/dev/null 2>&1 || true
    exit 1
  fi
  echo "candidate $d/ is the running image's, untouched"
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
# BEGIN leaf-smoke (deploy/tests/test_overlay_scripts.py runs this block with a stub docker)
# noevia#1071 P0: the leaves have no self-test command. The release's own smoke runs each leaf the candidate has through
# its real adapter (the candidate's agent/, proven equal to the release above) on synthetic data and compares it with
# Python, selecting Rust only inside that process. The smoke script is the release's own file, bind-mounted read-only at
# its place in /app/scripts for this container only: it is not copied into the image, so scripts/ stays the running
# image's. Any leaf that fails stops the overlay.
if [ "$rs_stage" = 1 ] && [ "$rs_leaves" = 1 ]; then
  leaf_names=""
  for spec in $rust_leaves; do leaf_names="$leaf_names ${spec##*:}"; done
  leaves_present=$(docker run --rm --network none --entrypoint sh cowork-diary:$V-candidate -c \
    "cd /usr/local/bin && for b in$leaf_names; do if [ -f \"\$b\" ] && [ -x \"\$b\" ]; then echo \"\$b\"; fi; done") \
    || { echo "could not list the Diary Rust leaves in the candidate; not deploying" >&2; exit 1; }
  leaves_present=$(printf '%s\n' $leaves_present)
  for b in $leaves_present; do
    case " $leaf_names " in *" $b "*) ;; *) echo "unexpected leaf name from the candidate listing; not deploying" >&2; exit 1 ;; esac
  done
  if [ -n "$leaves_present" ]; then
    docker run --rm --network none -v "$base/releases/$V/services/diary/$leaf_smoke:/app/$leaf_smoke:ro" \
      --entrypoint python cowork-diary:$V-candidate $leaf_smoke $leaves_present \
      || { echo "candidate Diary Rust leaf smoke failed; not deploying" >&2; exit 1; }
    echo "candidate Diary Rust leaves ok:" $leaves_present
  else
    echo "candidate has none of the Diary Rust leaves (pinned noevia-rs predates them): their selectors must stay python"
  fi
fi
# END leaf-smoke
# BEGIN native-required (deploy/tests/test_overlay_scripts.py runs this block with a stub docker)
# D4-D5: a release that ships the forwarder (agent/rust_forward.py) starts noevia-diary, verifies tenants with
# tenant-assertion and exports with diary-workspace-export. Its candidate must carry all three, executable at the
# fixed paths the code defaults to (DIARY_RUST_SERVER_BIN, TENANT_ASSERTION_BIN and DIARY_WORKSPACE_EXPORT_BIN
# are those same paths); otherwise the overlay would ship a server nothing can start, so it stops before anything
# is stopped. DIARY_RUST_ROUTES and DIARY_RUST_WRITES are the owner's to set in .env and are not touched here.
if [ -f "$base/releases/$V/services/diary/agent/rust_forward.py" ]; then
  native_bins="noevia-diary tenant-assertion diary-workspace-export"
  [ "$rs_stage" = 1 ] && [ "$rs_leaves" = 1 ] \
    || { echo "this release ships the Rust Diary server forwarder but its Diary Dockerfile pins no noevia-rs, or the release has no $leaf_smoke; not deploying" >&2; exit 1; }
  native_missing=$(docker run --rm --network none --entrypoint sh cowork-diary:$V-candidate -c \
    "for b in $native_bins; do if [ ! -f \"/usr/local/bin/\$b\" ] || [ ! -x \"/usr/local/bin/\$b\" ]; then echo \"\$b\"; fi; done") \
    || { echo "could not check the native Diary binaries in the candidate; not deploying" >&2; exit 1; }
  if [ -n "$native_missing" ]; then
    echo "this release ships the Rust Diary server forwarder but the candidate lacks (or cannot execute): $(printf '%s ' $native_missing) (the pinned noevia-rs predates them); not deploying" >&2
    exit 1
  fi
  echo "candidate native Diary binaries present: $native_bins"
fi
# END native-required
# BEGIN native-provenance (deploy/tests/test_overlay_scripts.py runs this block with a stub check script)
# D4-D5: image-level provenance of the candidate, the real assurance beside the static Dockerfile guard. The check
# (deploy/tools/check-diary-image-native.sh, shipped in the release's noevia/ tree) runs the candidate with no network
# and no data: every native binary present and executable, `noevia-diary --version` carrying exactly the pinned
# noevia-rs ref (the builder stage above passes it to cargo as the NOEVIA_RS_REF ARG), and the self-tests answering ok.
# A candidate that fails it, or a release without the script, is not deployed.
if [ -f "$base/releases/$V/services/diary/agent/rust_forward.py" ]; then
  provenance_check=$base/releases/$V/noevia/deploy/tools/check-diary-image-native.sh
  [ -f "$provenance_check" ] \
    || { echo "this release ships the Rust Diary server forwarder but not noevia/deploy/tools/check-diary-image-native.sh; not deploying" >&2; exit 1; }
  bash "$provenance_check" cowork-diary:$V-candidate "$rs_ref" \
    || { echo "candidate Diary image native provenance check failed; not deploying" >&2; exit 1; }
fi
# END native-provenance
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
overlay_complete=1
echo DIARY_OVERLAY_COMPLETE
