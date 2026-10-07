#!/usr/bin/env bash
# Alert when a Noevia container restarts or is replaced outside a known deploy.
# Compares Id, State.StartedAt, RestartCount and Config.Image of every container
# whose name starts with the prefix against a line-based TSV state file.
#   sidecar-restart-alert.sh [--ack] [--dry-run] [--strict] [--prefix P] [--state FILE]
#                            [--oneshot NAME]... [--oneshot-max N]
# --oneshot NAME: containers whose name contains NAME restart by design after every run (default
# "code-verify"; env NOEVIA_ONESHOT_SERVICES is a comma list). A restart of one with the same
# container and image, exit code 0 and at most N (default 10) restarts since the last run is expected
# and silent; a non-zero exit, a replaced container/image or a burst above N still alerts (crash loop).
# --ack rewrites state without alerting (run right after an intentional deploy).
# Exit status: 0 ok, 2 docker failure, 64 usage error. Notify failures leave the
# old state line in place so the next run retries the alert.
set -uo pipefail

prefix="cowork-"
state="/mnt/docker/appdata/cowork/state/sidecar-restart-alert.tsv"
ack=false
dry_run=false
strict=false
oneshot_max=10
oneshot_names=()
IFS=',' read -r -a oneshot_names <<< "${NOEVIA_ONESHOT_SERVICES-code-verify}"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ack) ack=true ;;
    --dry-run) dry_run=true ;;
    --strict) strict=true ;;
    --prefix) [[ $# -ge 2 ]] || { usage >&2; exit 64; }; prefix="$2"; shift ;;
    --oneshot) [[ $# -ge 2 ]] || { usage >&2; exit 64; }; oneshot_names+=("$2"); shift ;;
    --oneshot-max) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || { usage >&2; exit 64; }; oneshot_max="$2"; shift ;;
    --prefix=*) prefix="${1#*=}" ;;
    --state) [[ $# -ge 2 ]] || { usage >&2; exit 64; }; state="$2"; shift ;;
    --state=*) state="${1#*=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

if command -v notify >/dev/null 2>&1; then
  notify_bin="notify"
else
  notify_bin="/usr/local/emhttp/webGui/scripts/notify"
fi

send() { # level subject description
  if [[ "$dry_run" == true ]]; then
    printf '[dry-run] notify -e Noevia -i %s -s %s\n%s\n\n' "$1" "$2" "$3"
    return 0
  fi
  "$notify_bin" -e "Noevia" -s "$2" -d "$3" -i "$1" >/dev/null
}

names="$(docker ps -a --format '{{.Names}}')" || { echo "docker ps failed" >&2; exit 2; }

tab=$'\t'
current=""
while IFS= read -r name; do
  [[ -n "$name" && "$name" == "$prefix"* ]] || continue
  line="$(docker inspect --format "{{.Name}}${tab}{{.Id}}${tab}{{.State.StartedAt}}${tab}{{.RestartCount}}${tab}{{.Config.Image}}${tab}{{.State.ExitCode}}${tab}{{.State.Status}}" "$name")" \
    || { echo "docker inspect $name failed" >&2; exit 2; }
  current+="${line#/}"$'\n'
done <<< "$names"
current="$(printf '%s' "$current" | sort)"

old=""
[[ -f "$state" ]] && old="$(cat "$state")"
first_run=false
[[ -f "$state" ]] || first_run=true

lookup() { # name text -> matching line
  local n
  while IFS= read -r l; do
    n="${l%%"$tab"*}"
    [[ "$n" == "$1" ]] && { printf '%s' "$l"; return 0; }
  done <<< "$2"
  return 1
}

new_state=""
keep() { new_state+="$1"$'\n'; }

if [[ "$ack" == true || "$first_run" == true ]]; then
  [[ -n "$current" ]] && new_state="$current"$'\n'
else
  while IFS= read -r cur; do
    [[ -n "$cur" ]] || continue
    IFS="$tab" read -r name id started count image exitcode status <<< "$cur"
    if ! prev="$(lookup "$name" "$old")"; then
      if [[ "$strict" == true ]]; then
        if ! send warning "$name appeared" "New container $name (image $image, started $started, status $status)."; then
          echo "notify failed for $name" >&2; continue
        fi
      else
        echo "info: new container $name ($image, started $started)" >&2
      fi
      keep "$cur"; continue
    fi
    IFS="$tab" read -r _ pid pstarted pcount pimage _ pstatus <<< "$prev"
    if [[ "$pid" == "$id" && "$pstarted" == "$started" && "$pcount" == "$count" && "$pimage" == "$image" ]]; then
      # Same run: only a running -> not-running transition is news (stop/death).
      if [[ "$pstatus" == running && "$status" != running ]]; then
        logs="$(docker logs --tail 3 "$name" 2>&1 | cut -c1-200 | awk 'NR>1{printf " | "} {printf "%s", $0}')"
        if ! send alert "$name stopped" "Status running -> ${status}; exit code ${exitcode}; image ${image}; started ${started}; last log lines: ${logs}"; then
          echo "notify failed for $name; will retry next run" >&2; keep "$prev"; continue
        fi
      fi
      keep "$cur"; continue
    fi
    expected=false
    if [[ "$pid" == "$id" && "$pimage" == "$image" && "$exitcode" == 0 && "$count" =~ ^[0-9]+$ && "$pcount" =~ ^[0-9]+$ \
          && "$count" -ge "$pcount" && $((count - pcount)) -le "$oneshot_max" ]]; then
      for o in ${oneshot_names[@]+"${oneshot_names[@]}"}; do
        [[ -n "$o" && "$name" == *"$o"* ]] && expected=true
      done
    fi
    if [[ "$expected" == true ]]; then keep "$cur"; continue; fi
    level=warning
    if [[ "$count" =~ ^[0-9]+$ && "$pcount" =~ ^[0-9]+$ && "$count" -gt "$pcount" ]] || [[ "$exitcode" != 0 ]]; then
      level=alert
    fi
    logs="$(docker logs --tail 3 "$name" 2>&1 | cut -c1-200 | awk 'NR>1{printf " | "} {printf "%s", $0}')"
    idnote="same container"
    [[ "$pid" != "$id" ]] && idnote="container replaced ${pid:0:12} -> ${id:0:12}"
    details="StartedAt ${pstarted} -> ${started}; ${idnote}; image ${pimage} -> ${image}; RestartCount ${pcount} -> ${count}; exit code ${exitcode}; status ${status}; last log lines: ${logs}"
    if send "$level" "$name restarted" "$details"; then
      keep "$cur"
    else
      echo "notify failed for $name; will retry next run" >&2; keep "$prev"
    fi
  done <<< "$current"
  while IFS= read -r prev; do
    [[ -n "$prev" ]] || continue
    name="${prev%%"$tab"*}"
    lookup "$name" "$current" >/dev/null && continue
    IFS="$tab" read -r _ pid pstarted _ pimage _ _ <<< "$prev"
    if ! send alert "$name gone" "Container $name (${pid:0:12}, image $pimage, started $pstarted) no longer exists."; then
      echo "notify failed for $name; will retry next run" >&2; keep "$prev"
    fi
  done <<< "$old"
fi

if [[ "$dry_run" == true ]]; then
  exit 0 # dry-run never moves the baseline
fi
mkdir -p "$(dirname "$state")" || exit 1
tmp="$state.tmp.$$"
printf '%s' "$new_state" > "$tmp" && mv -f "$tmp" "$state"
