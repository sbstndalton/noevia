#!/usr/bin/env bash
# Guard (noevia#2387): the Rust front reads models.ini itself (GET /api/models/preset, the conditional
# writes' revision, the reload baseline). It runs inside the `web` container beside Node
# (build/web-supervisor.sh), so that service must carry the same LLAMACPP_PRESET_PATH and the config
# bind mount that preset reload already needs, and no separate front service may exist that lacks them.
# Runs on macOS bash 3.2 and Linux; plain awk, no YAML library.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
root="$(cd -- "$here/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/preset-mount-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
passes=0; fails=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; fi; }

# The lines of one top-level service (two-space indent) of a compose file.
service() { awk -v s="  $2:" '
  $0 == s { on = 1; next }
  on && /^  [A-Za-z0-9_-]+:/ { on = 0 }
  on && /^[^ ]/ { on = 0 }
  on { print }' "$1"; }
# Prints "ok" when the file's web service reads models.ini through a bind mount that holds the path.
mounts_preset() {
  local body path dir
  body="$(service "$1" web)"
  path="$(sed -nE 's/^[[:space:]]+LLAMACPP_PRESET_PATH:[[:space:]]*(\/[^[:space:]#]+).*/\1/p' <<<"$body" | head -1)"
  [ -n "$path" ] || { echo "no absolute LLAMACPP_PRESET_PATH on web"; return 1; }
  dir="${path%/*}"
  grep -qE "^[[:space:]]+-[[:space:]]+\\$\\{LLAMACPP_CONFIG_DIR[^}]*\\}:${dir}(:ro)?[[:space:]]*(#.*)?$" <<<"$body" \
    || { echo "web does not bind LLAMACPP_CONFIG_DIR at $dir"; return 1; }
  return 0
}
no_split_front() { ! grep -qE '^  (noevia-server|noevia-front|front):' "$1"; }

for f in compose.llamacpp.yaml deploy/examples/unraid-llamacpp.override.yml; do
  check "$f: web reads LLAMACPP_PRESET_PATH through the LLAMACPP_CONFIG_DIR mount" 'mounts_preset "$root/$f" >/dev/null'
  check "$f: the Rust front is not a separate service" 'no_split_front "$root/$f"'
done

# The guard must fail without the mount, without the variable, and with a mount at another place.
f="$root/compose.llamacpp.yaml"
grep -v 'LLAMACPP_CONFIG_DIR}:/llamacpp-config' "$f" > "$work/no-mount.yaml"
check "a web service without the config mount is refused" '! mounts_preset "$work/no-mount.yaml" >/dev/null'
grep -v 'LLAMACPP_PRESET_PATH' "$f" > "$work/no-path.yaml"
check "a web service without LLAMACPP_PRESET_PATH is refused" '! mounts_preset "$work/no-path.yaml" >/dev/null'
sed 's#LLAMACPP_CONFIG_DIR}:/llamacpp-config#LLAMACPP_CONFIG_DIR}:/elsewhere#' "$f" > "$work/moved.yaml"
check "a mount at another path than the preset file is refused" '! mounts_preset "$work/moved.yaml" >/dev/null'
{ cat "$f"; printf '\n  noevia-server:\n    image: example\n'; } > "$work/split.yaml"
check "a separate Rust front service is refused" '! no_split_front "$work/split.yaml"'
rw="$(sed 's#:/llamacpp-config:ro#:/llamacpp-config#' "$f")"; printf '%s\n' "$rw" > "$work/rw.yaml"
check "a writable mount (the web-writer rollback) still counts" 'mounts_preset "$work/rw.yaml" >/dev/null'
echo "passed $passes, failed $fails"
[ "$fails" -eq 0 ]
