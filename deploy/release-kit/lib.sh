# shellcheck shell=bash
# deploy/release-kit/lib.sh: helpers shared by the release kit scripts (sourced, never run). See README.md.
# Every time a kit script prints or records is taken from the clock here (`date -u`), never written by hand (#2632).

kit_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
kit_stamp() { date -u +%Y%m%dT%H%M%SZ; }
kit_epoch() { date -u +%s; }
log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }

# Every key a kit.conf may hold (one kit.conf serves every script of a release kit; README.md describes each).
KIT_CONF_KEYS="APPDATA COMPOSE_DIR PROJECT FLIPS_DIR GATE WEB EGRESS WEB_URL WEB_ANCHOR_KEY WEB_VERSION WEB_IMAGE RELEASE_ID RELEASE_VERSION ROLLBACK_VERSION ROLLBACK_IMAGE RELEASE_KEYS PREFLIGHT_FILES TARGET_TREE DIARY DIARY_VERSION DIARY_IMAGE DIARY_OLD_TAG DIARY_OLD_IMAGE DIARY_STATE DIARY_FLIPS_DIR BACKUP_ROOT DIARY_BACKUP_PREFIX DIARY_HEALTH_URL"
# kit_conf <file>: reads KEY=VALUE lines of a kit.conf (never sourced: no shell runs from it) into
# CONF_<KEY> variables. Blank lines and # comments are skipped; an unknown key, a repeated key or a value with a
# character outside [A-Za-z0-9_./:@+,-] is refused, so a path or id can never carry a command.
kit_conf() {
  local file=$1 line k v allowed=" $KIT_CONF_KEYS " seen=" "
  for k in $KIT_CONF_KEYS; do unset "CONF_$k"; done   # nothing from the caller's environment counts as configuration
  [ -f "$file" ] || { echo "kit_error=conf_missing:$file"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=([A-Za-z0-9_./:@+,-]*)$ ]] || { echo "kit_error=conf_line_unreadable"; return 1; }
    k=${BASH_REMATCH[1]}; v=${BASH_REMATCH[2]}
    [[ "$allowed" == *" $k "* ]] || { echo "kit_error=conf_key_unknown:$k"; return 1; }
    [[ "$seen" != *" $k "* ]] || { echo "kit_error=conf_key_repeated:$k"; return 1; }
    seen="$seen$k "
    printf -v "CONF_$k" '%s' "$v"
  done <"$file"
  return 0
}

# kit_clock <forward|rollback>: no kit step inside the nightly backup window (04:00-04:30 America/New_York); forward
# steps also never 08:00-09:30Z (the host's maintenance window). Prints <prefix>_error=... and returns 1 inside one.
kit_clock() {
  local hm u
  hm=$(TZ=America/New_York date +%H%M)
  if ((10#$hm >= 400 && 10#$hm < 430)); then echo "${KIT_PREFIX:-kit}_error=window_new_york_$hm"; return 1; fi
  [ "$1" = rollback ] && return 0
  u=$(date -u +%H%M)
  if ((10#$u >= 800 && 10#$u < 930)); then echo "${KIT_PREFIX:-kit}_error=window_utc_$u"; return 1; fi
  return 0
}

# kit_running <name...>: how many shell processes run one of these kit scripts: the shell's script argument (its first
# argument that is not an option; never a `-c` command string) has one of these base names. An editor, a pager or a
# process whose command line merely mentions a name is not counted.
kit_running() {
  ps -eo args | awk -v names=" $* " '$1 ~ /(^|\/)(ba|da)?sh$/ {
    for (i = 2; i <= NF; i++) { if ($i == "-c") next; if ($i == "-o" || $i == "+o" || $i == "-O" || $i == "+O" || $i == "--rcfile" || $i == "--init-file") { i++; continue } if ($i !~ /^[-+]/) break }
    if (i > NF) next; b = $i; sub(/^.*\//, "", b); if (index(names, " " b " ")) n++
  } END { print n + 0 }'
}

# .env helpers. env_get <file> <key>: the value of the first KEY= line, or '-' when there is none.
env_get() { awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); f = 1; exit } END { if (!f) print "-" }' "$1"; }
# env_put <file> <key> <value|-> : the file with KEY's line replaced (or appended, or removed for '-'), on stdout.
env_put() {
  if [ "$3" = - ]; then awk -v k="$2" 'index($0, k "=") != 1' "$1"
  elif [ "$(env_get "$1" "$2")" = - ]; then cat "$1"; printf '%s=%s\n' "$2" "$3"
  else awk -v k="$2" -v v="$3" 'index($0, k "=") == 1 { print k "=" v; next } { print }' "$1"; fi
}
# env_keys_differing <a> <b>: key names whose lines differ between two .env files (sorted, one per line; a line that is
# not KEY=... is reported as (non-key-line)). Never prints a value.
env_keys_differing() {
  diff <(LC_ALL=C sort "$1") <(LC_ALL=C sort "$2") | grep -E '^[<>]' \
    | sed -E 's/^[<>] ([A-Za-z_][A-Za-z0-9_]*)=.*/\1/; t; s/^[<>] .*/(non-key-line)/' | LC_ALL=C sort -u || true
}

# The dry-run gate (#2632): a DRY run records a digest of exactly what the real run would write; the real run needs that
# digest's first 12 characters in CONFIRM_DRY, from a DRY at least 60 and at most 3600 seconds old, over byte-identical
# inputs; a confirmation works once. So a dry run and the real run can never be chained in one command line: somebody
# has to read the dry run and come back. Only removals (rollbacks to absent) do without it. The ages are fixed (no
# environment override).
KIT_DRY_MIN_AGE=60; KIT_DRY_MAX_AGE=3600
kit_digest() { cat "$@" | sha256sum | cut -c1-64; }
kit_dry_record() {  # kit_dry_record <state dir> <scope> <digest>
  install -d -m 0700 "$1/dry"; printf '%s %s\n' "$(kit_epoch)" "$3" >"$1/dry/$2"
  echo "DRY recorded at $(kit_now): to run it for real, read the diff above, wait at least $KIT_DRY_MIN_AGE s, then run the same command again with CONFIRM_DRY=${3:0:12} in front (valid for $KIT_DRY_MAX_AGE s while nothing changes)"
}
kit_dry_check() {  # kit_dry_check <state dir> <scope> <digest>: returns 0 when a matching, aged DRY exists
  local f="$1/dry/$2" at dg age
  [ -n "${CONFIRM_DRY:-}" ] || { echo "${KIT_PREFIX:-kit}_error=dry_run_first (run with DRY=1, read it, then CONFIRM_DRY=<digest>)"; return 1; }
  [ -f "$f" ] || { echo "${KIT_PREFIX:-kit}_error=no_dry_run_recorded"; return 1; }
  read -r at dg <"$f"
  [ "$dg" = "$3" ] && [ "${CONFIRM_DRY}" = "${3:0:12}" ] || { echo "${KIT_PREFIX:-kit}_error=dry_run_digest_differs (the files changed since the DRY, or another command): run DRY=1 again"; return 1; }
  age=$(($(kit_epoch) - at))
  [ "$age" -ge "$KIT_DRY_MIN_AGE" ] || { echo "${KIT_PREFIX:-kit}_error=dry_run_too_recent_${age}s (read it first; at least $KIT_DRY_MIN_AGE s)"; return 1; }
  [ "$age" -le "$KIT_DRY_MAX_AGE" ] || { echo "${KIT_PREFIX:-kit}_error=dry_run_too_old_${age}s"; return 1; }
  rm -f "$f"; return 0
}

# Compose override lines of one service's environment list (`      KEY: ${KEY:-}`).
ovr_line() { printf '      %s: ${%s:-}' "$1" "$1"; }
# ovr_block <file> <service>: the lines of that service's block (top-level service keys are indented two spaces).
ovr_block() { awk -v s="$2:" '/^  [A-Za-z0-9_-]+:/ { cur = $1 } cur == s' "$1"; }
# ovr_drop <file> <service> <key>: the file without KEY's switch line in that service's block, on stdout.
ovr_drop() { awk -v s="$2:" -v l="$(ovr_line "$3")" '/^  [A-Za-z0-9_-]+:/ { cur = $1 } !(cur == s && $0 == l)' "$1"; }
