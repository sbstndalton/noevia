#!/bin/bash
# diary-rollback-switch.sh KEY [TO] : rolls one Diary switch back from its live .env value. TO defaults to '-' (absent),
# or for a leaf (*_IMPL) to the value recorded at its flip (python or absent). Replaces the per-release
# flips/rollback-*.sh and rollback-*-v2.sh wrappers. Runs on the previous Diary image too (#2636). See diary-switch.sh.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "$0")" && pwd); . "$HERE/lib.sh"
KEY=${1:?KEY}
kit_conf "${KIT_CONF:-$HERE/kit.conf}" || exit 1
A=${CONF_APPDATA:-/mnt/docker/appdata/cowork}; F=${CONF_FLIPS_DIR:-$A/release-prep/flips}; DF=${CONF_DIARY_FLIPS_DIR:-$F/diary}
cur=$(env_get "$A/config/.env" "$KEY")
[ "$cur" != - ] || { echo "switch_error=${KEY}_not_set (nothing to roll back)"; exit 64; }
TO=${2:-}
if [ -z "$TO" ]; then TO=-; if [[ "$KEY" == *_IMPL ]] && [ "$(cat "$DF/state/$KEY.before" 2>/dev/null)" = python ]; then TO=python; fi; fi
ROLLBACK=1 exec bash "$HERE/diary-switch.sh" "$KEY" "$TO" "$cur"
