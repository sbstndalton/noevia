#!/bin/bash
# Fake preflight/up.sh: (re)creates the named service's fake container from the env file and the Compose files.
set -u
echo "up $*" >>"$FAKE/events"
envf=; files=(); svc=${@: -1}; while [ $# -gt 0 ]; do case "$1" in --env-file) envf=$2; shift;; -f) files+=("$2"); shift;; esac; shift; done
[ ! -f "$FAKE/up_fail" ] || { rm -f "$FAKE/up_fail"; echo "fake up failure" >&2; exit 1; }
here=$(dirname "$0"); fake=$(dirname "$(command -v docker)")
eget() { awk -v k="$1" 'index($0,k"=")==1{print substr($0,length(k)+2);exit}' "$envf"; }
name=cowork-$svc-1; [ -z "${FAKE_NAME_PREFIX:-}" ] || name=$FAKE_NAME_PREFIX-$svc-1; d=$FAKE/c/$name; mkdir -p "$d"
case "$svc" in web) ref=cowork-web:$(eget COWORK_VERSION);; diary) ref=cowork-diary:$(eget DIARY_VERSION);; *) ref=x;; esac
id=$(cat "$FAKE/img/$(printf '%s' "$ref" | tr '/:' '__')" 2>/dev/null) || { echo "no image $ref" >&2; exit 1; }
echo "$id" >"$d/Image"; echo "$ref" >"$d/ConfigImage"; echo running >"$d/Status"; echo 0 >"$d/RC"; echo cowork >"$d/Project"
n=$(( $(cat "$FAKE/seq" 2>/dev/null || echo 0) + 1 )); echo $n >"$FAKE/seq"; echo "id-$svc-$n" >"$d/Id"; echo "2026-01-01T00:00:$(printf %02d $((n % 60)))Z" >"$d/Started"
cat "$FAKE/next_health" 2>/dev/null >"$d/Health" || echo healthy >"$d/Health"; [ -s "$d/Health" ] || echo healthy >"$d/Health"
bash "$fake/compose-render" "$envf" "${files[@]}" | jq -r --arg s "$svc" '.services[$s].environment // {} | to_entries[] | .key + "=" + .value' >"$d/Env"
if [ "$svc" = web ]; then
  printf '%s\n' '2026-01-01T00:00:01Z {"event":"egress.issuer_started","key":"kept"}' '2026-01-01T00:00:02Z {"event":"egress.control_ready"}' >"$d/logs"
  printf '{"ready":true,"version":"%s"}\n' "$(eget COWORK_VERSION)" >"$d/ready"
else
  : >"$d/logs"; if grep -qE '^DIARY_RUST_(ANSWER|INDEX)=(shadow|on)$|^DIARY_RUST_(ROUTES|WRITES)=.' "$d/Env"; then echo '1 /usr/local/bin/noevia-diary' >"$d/top"; else : >"$d/top"; fi
fi
