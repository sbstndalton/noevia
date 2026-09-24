#!/usr/bin/env bash
# Stubs docker and notify with PATH shims; runs on macOS bash 3.2 and Linux.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
script="$here/sidecar-restart-alert.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/sidecar-alert-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/fix"
fix="$work/fix"; state="$work/state.tsv"; sent="$work/sent.log"
cat > "$work/bin/docker" <<SHIM
#!/usr/bin/env bash
[ -f "$fix/fail" ] && exit 1
case "\$1" in
  ps) cat "$fix/names" ;;
  inspect) name="\${!#}"; [ -f "$fix/\$name" ] || exit 1; cat "$fix/\$name" ;;
  logs) echo "log a"; echo "log b"; echo "log c" ;;
esac
SHIM
cat > "$work/bin/notify" <<SHIM
#!/usr/bin/env bash
{ printf 'CALL|'; printf '%s|' "\$@" | tr '\\n' ' '; echo; } >> "$sent"
SHIM
chmod +x "$work/bin/docker" "$work/bin/notify"
export PATH="$work/bin:$PATH"
t=$'\t'
set_c() { # name id started count exit
  printf '/%s\t%s\t%s\t%s\timg:1\t%s\t%s' "$1" "$2" "$3" "$4" "${5:-0}" "${6:-running}" > "$fix/$1"
}
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; fi; }
count() { [ -f "$sent" ] && grep -c '^CALL|' "$sent" || echo 0; }
run() { bash "$script" --state "$state" "$@"; }

printf 'cowork-web-1\ncowork-diary-1\nother-thing\n' > "$fix/names"
set_c cowork-web-1 aaa 2026-09-24T01:00:00Z 0
set_c cowork-diary-1 bbb 2026-09-24T01:00:00Z 0
run; rc=$?
check "first run exits 0" '[ $rc -eq 0 ]'
check "first run silent" '[ "$(count)" -eq 0 ]'
check "first run writes state for prefixed containers only" '[ "$(grep -c . "$state")" -eq 2 ]'
run
check "unchanged run silent" '[ "$(count)" -eq 0 ]'

set_c cowork-diary-1 bbb 2026-09-24T08:10:13Z 0
run
check "StartedAt change alerts once" '[ "$(count)" -eq 1 ] && grep -q "cowork-diary-1 restarted" "$sent"'
check "graceful restart is warning" 'grep -q "|-i|warning|" "$sent"'
check "details carry old->new and logs" 'grep -q "01:00:00Z -> 2026-09-24T08:10:13Z" "$sent" && grep -q "log c" "$sent"'
run
check "same change not re-alerted" '[ "$(count)" -eq 1 ]'

set_c cowork-web-1 aaa 2026-09-24T09:00:00Z 1 137
run
check "RestartCount growth is alert level" '[ "$(count)" -eq 2 ] && tail -1 "$sent" | grep -q "|-i|alert|"'

set_c cowork-web-1 ccc 2026-09-24T10:00:00Z 0
run --ack
check "--ack silences" '[ "$(count)" -eq 2 ] && grep -q ccc "$state"'
run
check "after ack no alert" '[ "$(count)" -eq 2 ]'

set_c cowork-web-1 ddd 2026-09-24T11:00:00Z 0
run --dry-run > "$work/dry.out"
check "--dry-run prints, does not notify or move state" '[ "$(count)" -eq 2 ] && grep -q "cowork-web-1 restarted" "$work/dry.out" && grep -q ccc "$state"'
run --ack

printf 'cowork-web-1\n' > "$fix/names"
run
check "gone container alerts" '[ "$(count)" -eq 3 ] && tail -1 "$sent" | grep -q "cowork-diary-1 gone"'
run
check "gone alerted once" '[ "$(count)" -eq 3 ]'

printf 'cowork-web-1\ncowork-new-1\n' > "$fix/names"
set_c cowork-new-1 eee 2026-09-24T12:00:00Z 0
run 2>/dev/null
check "new container is info only" '[ "$(count)" -eq 3 ] && grep -q cowork-new-1 "$state"'

set_c cowork-new-1 eee 2026-09-24T12:00:00Z 0 137 exited
run
check "running -> exited alerts once" '[ "$(count)" -eq 4 ] && tail -1 "$sent" | grep -q "cowork-new-1 stopped" && tail -1 "$sent" | grep -q "|-i|alert|"'
run
check "stopped container not re-alerted" '[ "$(count)" -eq 4 ]'

touch "$fix/fail"
cp "$state" "$work/before"
run 2>/dev/null; rc=$?
check "docker failure exits non-zero, state untouched" '[ $rc -ne 0 ] && cmp -s "$state" "$work/before"'

echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
