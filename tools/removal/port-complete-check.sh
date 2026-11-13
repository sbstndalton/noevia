#!/usr/bin/env bash
# R10 "port complete" check. Read-only: reads git objects at a ref (default origin/main) and,
# optionally, text files an operator captured. Never fetches, checks out, writes, ssh's or runs docker.
#
# Usage:
#   tools/removal/port-complete-check.sh --core DIR --rs DIR --services DIR --noevia DIR \
#       [--ref REF] [--census PATH/port-census.py --census-root DIR] \
#       [--ps-file FILE] [--fallback-json FILE]
#     --census       agents/bin/port-census.py; its Node and Python totals are cross-checked (check 2b, 3b)
#     --census-root  directory that holds the five clones (default: parent of --noevia)
#     --ps-file      output of `docker ps` / `docker top`, captured BY AN OPERATOR on the N5 or MS02
#     --fallback-json {"legacy_fallback_total": N, "window_days": D} exported by the front's counter
# Exit 0 only if every check that ran passes. A SKIP is not a pass: the script exits 1 when any check is skipped
# unless --allow-skip is given (CI default is strict; operator runs pass --ps-file and --fallback-json).
# Every check prints PASS, FAIL or SKIP with the evidence it used.
set -u
CORE= RS= SERVICES= NOEVIA= REF=origin/main PS_FILE= FALLBACK= CENSUS= CENSUS_ROOT= ALLOW_SKIP=0
# Declared engine workers: Python that stays on purpose (plan, "What stays"). llama.cpp is a binary and is not counted.
ALLOW_PY_ENGINES="docling/extract.py docling/isolated_worker.py docling/download_models.py docling/selftest.py docling/fake_converter.py laya/server.py laya/download.py"
# Image bases that may stay Node until the owner decides the code-agent harness (plan, open question Q1).
ALLOW_NODE_IMAGES="code-sandbox"
# Process-list lines (check 5) that may name node or python: the declared engines above, by container name.
ALLOW_PROCESSES="laya|docling|code-sandbox"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --core) CORE=$2; shift 2 ;;
    --rs) RS=$2; shift 2 ;;
    --services) SERVICES=$2; shift 2 ;;
    --noevia) NOEVIA=$2; shift 2 ;;
    --ref) REF=$2; shift 2 ;;
    --census) CENSUS=$2; shift 2 ;;
    --census-root) CENSUS_ROOT=$2; shift 2 ;;
    --ps-file) PS_FILE=$2; shift 2 ;;
    --fallback-json) FALLBACK=$2; shift 2 ;;
    --allow-skip) ALLOW_SKIP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
for v in CORE RS SERVICES NOEVIA; do
  eval "d=\$$v"
  if [ -z "$d" ] || [ ! -d "$d" ]; then echo "missing --$(echo "$v" | tr 'A-Z' 'a-z') DIR" >&2; exit 2; fi
done
[ -n "$CENSUS_ROOT" ] || CENSUS_ROOT=$(dirname "$NOEVIA")

fails=0; skips=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails+1)); }
skip() { echo "SKIP  $1"; skips=$((skips+1)); }
g() { git -C "$1" "${@:2}" 2>/dev/null; }   # read-only git plumbing only

# 1. Routes file has no Node owner or executor; the legacy proxy source is gone.
n=$(g "$RS" show "$REF:contracts/http/routes.toml" | grep -cE '^(owner|executor) *= *"node"' || true)
if [ "${n:-1}" -eq 0 ]; then pass "1a routes.toml has no owner/executor = node"; else fail "1a routes.toml has $n node owner/executor lines"; fi
if g "$RS" cat-file -e "$REF:bins/noevia-server/src/legacy_proxy.rs"; then fail "1b legacy_proxy.rs still exists"; else pass "1b legacy_proxy.rs absent"; fi

# 2. No Node server source (non-test, non-fixture) at the ref.
nodes=$(g "$CORE" ls-tree -r --name-only "$REF" -- server code-sandbox | grep -E '\.(cjs|js|mjs)$' \
  | grep -vE '(\.test\.|/tests?/|/fixtures?/|-oracle\.cjs$|\.probe\.cjs$|test-helper|/qualif)' || true)
lines=0; cnt=0
for f in $nodes; do c=$(g "$CORE" show "$REF:$f" | wc -l); lines=$((lines+c)); cnt=$((cnt+1)); done
if [ "$cnt" -eq 0 ]; then pass "2  no Node server/sandbox source at $REF"; else fail "2  $cnt Node source files, $lines lines still at $REF (first: $(echo "$nodes" | head -3 | tr '\n' ' '))"; fi

# 2b. Cross-check with the census script (same rule, different code path). Only when given.
if [ -n "$CENSUS" ] && [ -r "$CENSUS" ]; then
  tot=$(python3 -I "$CENSUS" --root "$CENSUS_ROOT" 2>/dev/null | sed -n 's/^Total Node server source: \*\*\([0-9]*\)\*\*.*/\1/p')
  if [ -z "$tot" ]; then fail "2b census script gave no Node total"
  elif [ "$tot" -eq 0 ]; then pass "2b census: Node server source 0 lines"
  else fail "2b census: Node server source $tot lines (check 2 counted $lines)"; fi
else skip "2b no --census given"; fi

# 3. No Python source outside the declared engine workers (services repo, whole tree at the ref).
pys=$(g "$SERVICES" ls-tree -r --name-only "$REF" | grep -E '\.py$' \
  | grep -vE '(^|/)(tests?|qualification|qualif[^/]*|fixtures?)/|(^|/)test_[^/]*\.py$|_test\.py$|synthetic_[^/]*\.py$' || true)
bad=""
for f in $pys; do case " $ALLOW_PY_ENGINES " in *" $f "*) ;; *) bad="$bad $f" ;; esac; done
pycount=$(echo "$pys" | grep -c . || true)
if [ -z "$bad" ]; then pass "3  Python source only in declared engine workers ($pycount files at the ref)"; else fail "3  Python outside allowlist:$bad"; fi

# 3b. Python total from the census script, when given.
if [ -n "$CENSUS" ] && [ -r "$CENSUS" ]; then
  ptot=$(python3 -I "$CENSUS" --root "$CENSUS_ROOT" 2>/dev/null | sed -n 's/^Total Python source in services: \*\*\([0-9]*\)\*\*.*/\1/p')
  if [ -z "$ptot" ]; then fail "3b census script gave no Python total"
  else echo "INFO  3b census: Python source in services $ptot lines (declared engines are counted here too)"; fi
fi

# 4. Final stage of each image: no Node or Python base unless declared.
for pair in "$NOEVIA:build/web.Dockerfile:web" "$CORE:code-sandbox/Dockerfile:code-sandbox" "$SERVICES:diary/Dockerfile:diary"; do
  IFS=: read -r repo path name <<<"$pair"
  last=$(g "$repo" show "$REF:$path" | grep -E '^FROM ' | tail -1 || true)
  if [ -z "$last" ]; then fail "4  $name: no FROM found in $path"; continue; fi
  if echo "$last" | grep -qE 'node|python'; then
    case " $ALLOW_NODE_IMAGES " in *" $name "*) pass "4  $name final base is Node/Python but declared: $last" ;;
      *) fail "4  $name final base is Node/Python: $last" ;; esac
  else pass "4  $name final base: $last"; fi
done
hc=$(g "$NOEVIA" show "$REF:build/web.Dockerfile" | grep -cE '^HEALTHCHECK.*node -e' || true)
if [ "${hc:-0}" -eq 0 ]; then pass "4b web HEALTHCHECK does not need node"; else fail "4b web HEALTHCHECK runs node"; fi

# 5. Live processes (only if an operator captured them). This script never runs docker or ssh.
if [ -n "$PS_FILE" ]; then
  if [ -r "$PS_FILE" ]; then
    # Anything named node/python must be an engine we declared; names only, no environment is printed.
    # Only the declared interpreter engines are excused (docling converter, Laya engine worker, the code agent
    # harness in the sandbox). The OCR server and the embedding/inference engines are not interpreters.
    hits=$(grep -nE '(^|[ /])(node|nodejs|python3?)( |$)' "$PS_FILE" | grep -vE "$ALLOW_PROCESSES" || true)
    if [ -z "$hits" ]; then pass "5  captured process list has no node/python outside declared engines"
    else fail "5  node/python processes: $(echo "$hits" | head -3 | cut -c1-120 | tr '\n' ';')"; fi
  else fail "5  --ps-file not readable"; fi
else skip "5  no --ps-file (operator capture on the N5 and MS02 required)"; fi

# 6. No Rust code calls a Node /internal/ bridge.
ints=$(g "$RS" grep -c '/internal/' "$REF" -- bins/noevia-server/src | awk -F: '{s+=$NF} END {print s+0}')
if [ "${ints:-1}" -eq 0 ]; then pass "6  no /internal/ bridge mentions in noevia-server src"; else fail "6  $ints /internal/ mentions in noevia-server src"; fi

# 7. Fallback counter: zero legacy-proxy hits over a full week (evidence file exported by the front).
if [ -n "$FALLBACK" ] && [ -r "$FALLBACK" ]; then
  res=$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("ok" if d.get("legacy_fallback_total")==0 and d.get("window_days",0)>=7 else "bad")' "$FALLBACK" 2>/dev/null || echo bad)
  if [ "$res" = ok ]; then pass "7  fallback counter zero for >= 7 days"; else fail "7  fallback evidence missing, not zero, or under 7 days"; fi
else skip "7  no --fallback-json (the front counter is not built yet on $REF)"; fi

echo "---"; echo "failures: $fails  skipped: $skips"
[ "$fails" -eq 0 ] || exit 1
if [ "$skips" -gt 0 ] && [ "$ALLOW_SKIP" -eq 0 ]; then echo "not complete: $skips check(s) skipped (use --allow-skip for a partial read)"; exit 1; fi
exit 0
