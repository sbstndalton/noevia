#!/bin/bash
# stamp.sh <file> <GATE|GO|NOGO|LIVE|DONE|AMEND> [--append] < body : writes a release/flip record file whose time comes
# from the clock (#2632: GATE and GO files carried hand-written times 5-12 minutes off the moment they were written).
# The first line is "<KIND> written <date -u> on <host>"; the body follows unchanged. A new file is never overwritten;
# --append adds "---- <KIND> appended <date -u> on <host> ----" and the body. Write times into the body only from
# `date -u` too (e.g. "$(date -u +%TZ)"), never by hand.
# stamp.sh --check <file> : names every HH:MMZ time on the first line that differs from the file's write time by more
# than 120 s (exit 3), so a reviewer can see a hand-written time.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "$0")" && pwd); . "$HERE/lib.sh"
if [ "${1:-}" = --check ]; then
  f=${2:?file}; m=$(date -u -r "$f" +%s); bad=0
  for t in $(head -1 "$f" | grep -oE '[0-2][0-9]:[0-5][0-9](:[0-5][0-9])?Z' || true); do
    d=$(date -u -r "$f" +%F); e=$(date -u -d "$d ${t%Z}" +%s)
    off=$((e - m)); [ "${off#-}" -le 120 ] || { echo "stamp_check: first-line time $t is $off s from the file's write time $(date -u -r "$f" +%TZ)"; bad=1; }
  done
  [ $bad = 0 ] && echo "stamp_check=ok $f" || exit 3; exit 0
fi
f=${1:?file}; kind=${2:?kind}; mode=${3:-}
[[ "$kind" =~ ^(GATE|GATE2|GO|GO2|NOGO|NOGO2|LIVE|DONE|AMEND[0-9]*)$ ]] || { echo stamp_error=kind; exit 64; }
body=$(cat)
if [ "$mode" = --append ]; then
  [ -f "$f" ] || { echo stamp_error=append_to_missing_file; exit 1; }
  printf '%s\n%s\n' "---- $kind appended $(kit_now) on $(hostname -s) ----" "$body" >>"$f"
else
  [ -z "$mode" ] || { echo stamp_error=unknown_option; exit 64; }
  [ ! -e "$f" ] || { echo "stamp_error=exists (use --append)"; exit 1; }
  printf '%s\n%s\n' "$kind written $(kit_now) on $(hostname -s)" "$body" >"$f"
fi
echo "stamped $f $(kit_now)"
