#!/usr/bin/env bash
# Tests build/web-supervisor.sh (the web image entrypoint) with stub `node` and noevia-server
# processes. Needs bash >= 4.3 (wait -n), like the image; skips on macOS's bash 3.2. CI runs it on
# Linux.
#
# sbstndalton/noevia#1071: sign-in and the account, the front read routes and the project routes and
# store are the Rust front's permanently, so the supervisor starts nothing unless NOEVIA_FRONT=rust
# and a noevia-server whose --features lists rust-auth and every front route feature.
# NOEVIA_RUST_AUTH and NOEVIA_RUST_PROJECTS are retired: whatever their value, they only warn and
# reach neither process.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
sup="$here/../../build/web-supervisor.sh"
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 3 ]; }; then
  echo "skip - bash ${BASH_VERSION} has no wait -n (the image's bash does)"; exit 0
fi
work="$(mktemp -d "${TMPDIR:-/tmp}/web-supervisor-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; fi; }

# The features build/web-supervisor.sh requires (FRONT_ROUTE_FEATURES), and a front that has them.
ROUTE_FEATURES="rust-chatgpt-status rust-storage-reads rust-storage-browse rust-export rust-free-chats rust-usage rust-stats rust-routing-default rust-sampling-settings rust-reasoning-settings rust-routing-mode rust-projects rust-project-chats rust-project-writes project-store"
BASE_FEATURES="code-net-guard rust-auth $ROUTE_FEATURES"
RETIRED="NOEVIA_RUST_AUTH NOEVIA_RUST_USAGE NOEVIA_RUST_SAMPLING_SETTINGS NOEVIA_RUST_REASONING_SETTINGS NOEVIA_RUST_ROUTING_MODE NOEVIA_RUST_ROUTING_DEFAULT NOEVIA_RUST_STATS NOEVIA_RUST_EXPORT NOEVIA_RUST_CHATGPT_STATUS NOEVIA_RUST_STORAGE_READS NOEVIA_RUST_STORAGE_BROWSE NOEVIA_RUST_PROJECT_WRITES NOEVIA_RUST_PROJECTS NOEVIA_RUST_PROJECT_CHATS NOEVIA_RUST_FREE_CHATS NOEVIA_RUST_PROJECT_STORE"

real_node="$(command -v node)"
mkdir -p "$work/bin"
# Each stub records its environment, then lives until killed or until its "die" file appears.
stub() {
  cat > "$1" <<STUB
#!/usr/bin/env bash
name=$2
if [ "\${1:-}" = -e ]; then exec "$real_node" "\$@"; fi
if [ "\${1:-}" = --features ]; then printf '%s\\n' \${STUB_FEATURES-$BASE_FEATURES}; exit 0; fi
[ "\$name" = node ] && [ -n "\${STUB_NODE_DELAY:-}" ] && sleep "\$STUB_NODE_DELAY"
echo "\$name UI_HOST=\${UI_HOST:-} UI_PORT=\${UI_PORT:-} UPSTREAM=\${NOEVIA_LEGACY_UPSTREAM:-} ARGS=\$* CCONF=\${NOEVIA_RUST_PROJECT_CHATS_CONFIRMED:-} FCONF=\${NOEVIA_RUST_FREE_CHATS_CONFIRMED:-} PCONF=\${NOEVIA_RUST_PROJECTS_CONFIRMED:-} CONF=\${NOEVIA_RUST_AUTH_CONFIRMED:-}" >> "$work/log"
retired=""
for v in $RETIRED; do c="\${v}_CONFIRMED"; [ -n "\${!c:-}" ] && retired="\$retired \$c"; done
echo "\$name RETIRED=\$retired" >> "$work/log"
echo "\$name PROJECTS=\${NOEVIA_RUST_PROJECTS-unset}" >> "$work/log"
echo "\$name WCONF=\${NOEVIA_RUST_PROJECT_WRITES_CONFIRMED:-} WRITES=\${NOEVIA_RUST_PROJECT_WRITES-unset}" >> "$work/log"
echo "\$name SSTORE=\${NOEVIA_RUST_PROJECT_STORE_CONFIRMED:-} SPORT=\${NOEVIA_PROJECT_STORE_PORT:-} STOKLEN=\${#NOEVIA_PROJECT_STORE_TOKEN}" >> "$work/log"
echo "\$name AUTH=\${NOEVIA_RUST_AUTH-unset}" >> "$work/log"
echo "\$name LCLAIM=\${NOEVIA_LEGACY_CLAIM_BIN:-}" >> "$work/log"
echo "\$name START=\${NOEVIA_START_ID-unset}" >> "$work/log"
echo "\$name KCONF=\${NOEVIA_FRONT_CLIENT_IP:-}" >> "$work/log"
trap 'echo "\$name TERM" >> "$work/log"; exit 0' TERM
# The supervisor TERMs the survivor as soon as one child exits. A front told to die at once would
# race Node's startup logging (Node killed mid-write, its later lines lost: #1822), so a dying
# front waits (bounded) until Node's last startup line is in the log.
if [ "\$name" = front ] && [ -f "$work/die-front" ]; then
  for _ in \$(seq 1 200); do grep -q "^node KCONF=" "$work/log" 2>/dev/null && break; sleep 0.05; done
fi
for _ in \$(seq 1 300); do
  [ -f "$work/die-\$name" ] && { echo "\$name died" >> "$work/log"; exit 3; }
  sleep 0.05
done
STUB
  chmod +x "$1"
}
stub "$work/bin/node" node
stub "$work/noevia-server" front
export PATH="$work/bin:$PATH"
# The live deployment; a test overrides any of it by naming the key again (env: last one wins).
run() { (cd "$work" && env NOEVIA_FRONT=rust NOEVIA_SERVER_BIN="$work/noevia-server" "$@" bash "$sup"); }
reset() { : > "$work/log"; rm -f "$work"/die-* "$work/rc"; }
wait_log() { for _ in $(seq 1 100); do grep -q "$1" "$work/log" 2>/dev/null && return 0; sleep 0.05; done; return 1; }
without() { local out="" f; for f in $BASE_FEATURES; do [ "$f" = "$1" ] || out="$out $f"; done; echo "$out"; }

# --- Fail closed before either process starts -----------------------------------------------
reset
touch "$work/die-front"
(cd "$work" && env -u NOEVIA_FRONT NOEVIA_SERVER_BIN="$work/noevia-server" bash "$sup") >/dev/null 2>"$work/err"; rc=$?
check "an unset NOEVIA_FRONT starts as rust (#2094), not refused as node" '[ $rc -eq 3 ] && ! grep -q "NOEVIA_FRONT" "$work/err" && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
reset; touch "$work/die-front"
run NOEVIA_FRONT= >/dev/null 2>"$work/err"; rc=$?
check "an empty NOEVIA_FRONT also starts as rust" '[ $rc -eq 3 ] && ! grep -q "NOEVIA_FRONT" "$work/err" && grep -q "^front " "$work/log"'
reset
run NOEVIA_FRONT=node >/dev/null 2>"$work/err"; rc=$?
check "NOEVIA_FRONT=node is refused, nothing started" '[ $rc -eq 2 ] && grep -q "#1071" "$work/err" && [ ! -s "$work/log" ]'
reset
run NOEVIA_FRONT=bogus >/dev/null 2>"$work/err"; rc=$?
check "an unknown NOEVIA_FRONT is refused" '[ $rc -eq 2 ] && grep -q "must be rust" "$work/err" && [ ! -s "$work/log" ]'
# A Node front cannot be selected by turning either retired switch off.
for value in "" 0 1; do
  reset
  run NOEVIA_FRONT=node NOEVIA_RUST_AUTH="$value" NOEVIA_RUST_PROJECTS="$value" >/dev/null 2>"$work/err"; rc=$?
  check "NOEVIA_FRONT=node with NOEVIA_RUST_AUTH/NOEVIA_RUST_PROJECTS='$value' is refused, nothing started" '[ $rc -eq 2 ] && grep -q "NOEVIA_FRONT=node is no longer supported" "$work/err" && [ ! -s "$work/log" ]'
done
reset
run NOEVIA_SERVER_BIN="$work/missing" >/dev/null 2>"$work/err"; rc=$?
check "no noevia-server binary is refused, nothing started" '[ $rc -eq 2 ] && grep -q "no noevia-server" "$work/err" && [ ! -s "$work/log" ]'
reset
run STUB_FEATURES="$(without code-net-guard)" COWORK_CODE_NET_ADDR=egress >/dev/null 2>"$work/err"; rc=$?
check "COWORK_CODE_NET_ADDR with a front without the guard is refused" '[ $rc -eq 2 ] && grep -q "no code-net-guard" "$work/err" && [ ! -s "$work/log" ]'
reset
run STUB_FEATURES="$(without rust-auth)" >/dev/null 2>"$work/err"; rc=$?
check "a front without rust-auth is refused, nothing started" '[ $rc -eq 2 ] && grep -q "no rust-auth" "$work/err" && [ ! -s "$work/log" ]'
reset
run STUB_FEATURES= >/dev/null 2>"$work/err"; rc=$?
check "a front whose --features prints nothing is refused" '[ $rc -eq 2 ] && [ ! -s "$work/log" ]'
# #1071: every front route feature is required; a missing one fails closed and is named.
for feature in $ROUTE_FEATURES; do
  reset
  run STUB_FEATURES="$(without "$feature")" >/dev/null 2>"$work/err"; rc=$?
  check "a front without $feature is refused, nothing started" '[ $rc -eq 2 ] && grep -q "lacks the front route feature(s): $feature;" "$work/err" && [ ! -s "$work/log" ]'
done
reset
run STUB_FEATURES="code-net-guard rust-auth rust-usage" >/dev/null 2>"$work/err"; rc=$?
check "every missing feature is listed at once" '[ $rc -eq 2 ] && grep -q "rust-chatgpt-status rust-storage-reads rust-storage-browse rust-export rust-free-chats rust-stats .* rust-projects rust-project-chats rust-project-writes project-store;" "$work/err" && [ ! -s "$work/log" ]'
# A manually mixed installed core/front pair fails before either process starts. The
# core result comes from its exported module at runtime, not an inherited environment value.
reset
run STUB_FEATURES="$BASE_FEATURES rust-web-address-read" >/dev/null 2>"$work/err"; rc=$?
check "web-address: new front over old core is refused before launch" '[ $rc -eq 2 ] && grep -q "web-address GET ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
mkdir -p "$work/server"
printf "%s\n" "module.exports = { WEB_ADDRESS_READ_OWNER: 'noevia-web-address-read-rust/1' };" > "$work/server/rust-web-address.cjs"
reset
run >/dev/null 2>"$work/err"; rc=$?
check "web-address: ported core over old front is refused before launch" '[ $rc -eq 2 ] && grep -q "web-address GET ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES rust-web-address-read" >/dev/null 2>"$work/err"; rc=$?
check "web-address: matching exported core and compiled front start together" '[ $rc -eq 3 ] && grep -q "^node " "$work/log" && grep -q "^front " "$work/log"'
printf "%s\n" "module.exports = { WEB_ADDRESS_READ_OWNER: 'noevia-web-address-read-rust/1', WEB_ADDRESS_WRITE_OWNER: 'noevia-web-address-write-rust/1' };" > "$work/server/rust-web-address.cjs"
reset
run STUB_FEATURES="$BASE_FEATURES rust-web-address-read" >/dev/null 2>"$work/err"; rc=$?
check "web-address POST: ported core over read-only front is refused before launch" '[ $rc -eq 2 ] && grep -q "web-address POST ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES rust-web-address-read rust-web-address-write" >/dev/null 2>"$work/err"; rc=$?
check "web-address POST: matching writer pair starts together" '[ $rc -eq 3 ] && grep -q "^node " "$work/log" && grep -q "^front " "$work/log"'
printf "%s\n" "module.exports = { WEB_ADDRESS_READ_OWNER: 'noevia-web-address-read-rust/1' };" > "$work/server/rust-web-address.cjs"
reset
run STUB_FEATURES="$BASE_FEATURES rust-web-address-read rust-web-address-write" >/dev/null 2>"$work/err"; rc=$?
check "web-address POST: writer front over read-only core is refused before launch" '[ $rc -eq 2 ] && grep -q "web-address POST ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
printf "%s\n" "module.exports = { WEB_ADDRESS_READ_OWNER: 'wrong' };" > "$work/server/rust-web-address.cjs"
reset
run STUB_FEATURES="$BASE_FEATURES rust-web-address-read" WEB_ADDRESS_READ_OWNER=noevia-web-address-read-rust/1 >/dev/null 2>"$work/err"; rc=$?
check "web-address: inherited owner value cannot spoof a wrong core" '[ $rc -eq 2 ] && grep -q "web-address GET ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
rm -f "$work/server/rust-web-address.cjs"

reset
run UI_PORT=65000 >/dev/null 2>&1; rc=$?
check "a UI_PORT with no room for +1000 is refused" '[ $rc -eq 2 ] && [ ! -s "$work/log" ]'

# Source-journal pairing probes the actual installed Node export and Rust binary --features.
mkdir -p "$work/server"
cat > "$work/server/project-store-client.cjs" <<'JS'
const SOURCE_JOBS_CLIENT_MARKER = 'noevia-source-jobs-client/1';
module.exports = { SOURCE_JOBS_CLIENT_MARKER };
JS
reset
run >/dev/null 2>"$work/err"; rc=$?
check "new core with old Rust source store is refused before either starts" '[ $rc -eq 2 ] && grep -q "requires noevia-source-jobs-store/1" "$work/err" && [ ! -s "$work/log" ]'
reset
printf '%s\n' "function sourceJobsFor(user) { return { user }; }" "module.exports = { sourceJobsFor };" > "$work/server/project-store-client.cjs"
run >/dev/null 2>"$work/err"; rc=$?
check "ported core with stripped marker is refused beside old Rust" '[ $rc -eq 2 ] && grep -q "does not export its canonical capability" "$work/err" && [ ! -s "$work/log" ]'
reset
printf '%s\n' "/* SOURCE_JOBS_CLIENT_MARKER */" "module.exports = {};" > "$work/server/project-store-client.cjs"
run STUB_FEATURES="$BASE_FEATURES noevia-source-jobs-store/1" >/dev/null 2>"$work/err"; rc=$?
check "comment-only core marker cannot satisfy runtime capability" '[ $rc -eq 2 ] && grep -q "does not export its canonical capability" "$work/err" && [ ! -s "$work/log" ]'
reset
rm -f "$work/server/project-store-client.cjs"
run STUB_FEATURES="$BASE_FEATURES noevia-source-jobs-store/1" >/dev/null 2>"$work/err"; rc=$?
check "new Rust source store with old core is refused before either starts" '[ $rc -eq 2 ] && grep -q "requires a paired core" "$work/err" && [ ! -s "$work/log" ]'
cat > "$work/server/project-store-client.cjs" <<'JS'
const SOURCE_JOBS_CLIENT_MARKER = 'noevia-source-jobs-client/1';
module.exports = { SOURCE_JOBS_CLIENT_MARKER };
JS
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES noevia-source-jobs-store/1" >/dev/null 2>"$work/err"; rc=$?
check "matching source client and store start both processes" '[ $rc -eq 3 ] && grep -q "^node UI_HOST=" "$work/log" && grep -q "^front UI_HOST=" "$work/log"'
rm -f "$work/server/project-store-client.cjs"
# Research journal pairing is independent from source-job pairing.
cat > "$work/server/project-store-client.cjs" <<'JS'
const RESEARCH_JOBS_CLIENT_MARKER = 'noevia-research-jobs-client/1';
module.exports = { RESEARCH_JOBS_CLIENT_MARKER };
JS
reset
run >/dev/null 2>"$work/err"; rc=$?
check "new research core with old Rust is refused before either starts" '[ $rc -eq 2 ] && grep -q "requires noevia-research-jobs-store/1" "$work/err" && [ ! -s "$work/log" ]'
reset
printf '%s
' "function researchJobsFor(user) { return { user }; }" "module.exports = { researchJobsFor };" > "$work/server/project-store-client.cjs"
run >/dev/null 2>"$work/err"; rc=$?
check "ported research core with stripped marker is refused" '[ $rc -eq 2 ] && grep -q "does not export its canonical capability" "$work/err" && [ ! -s "$work/log" ]'
reset
rm -f "$work/server/project-store-client.cjs"
run STUB_FEATURES="$BASE_FEATURES noevia-research-jobs-store/1" >/dev/null 2>"$work/err"; rc=$?
check "new Rust research store with old core is refused before either starts" '[ $rc -eq 2 ] && grep -q "requires a paired core research job client" "$work/err" && [ ! -s "$work/log" ]'
cat > "$work/server/project-store-client.cjs" <<'JS'
const RESEARCH_JOBS_CLIENT_MARKER = 'noevia-research-jobs-client/1';
module.exports = { RESEARCH_JOBS_CLIENT_MARKER };
JS
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES noevia-research-jobs-store/1" >/dev/null 2>"$work/err"; rc=$?
check "matching research client and store start both processes" '[ $rc -eq 3 ] && grep -q "^node UI_HOST=" "$work/log" && grep -q "^front UI_HOST=" "$work/log"'
rm -f "$work/server/project-store-client.cjs"
# --- The live configuration ------------------------------------------------------------------
reset; touch "$work/die-front"
retired_env=(); for v in $RETIRED; do retired_env+=("$v=1" "${v}_CONFIRMED=1"); done
run "${retired_env[@]}" UI_PORT=8021 >/dev/null 2>"$work/err"; rc=$?
check "a full front starts both; Node gets no auth, project or free-chat confirmation" 'grep -q "^node .* CCONF= FCONF= PCONF= CONF=$" "$work/log" && grep -q "^front .* CCONF= FCONF= PCONF= CONF=$" "$work/log"'
check "no retired confirmation reaches either process, inherited or not" 'grep -q "^node RETIRED=$" "$work/log" && grep -q "^front RETIRED=$" "$work/log"'
check "a leftover retired switch earns a warning and changes nothing" 'grep -q "NOEVIA_RUST_STATS is retired" "$work/err" && grep -q "NOEVIA_RUST_EXPORT is retired" "$work/err" && grep -q "NOEVIA_RUST_AUTH is retired" "$work/err" && grep -q "NOEVIA_RUST_PROJECTS is retired" "$work/err"'
check "the retired sign-in and projects switches reach neither process" 'grep -q "^node AUTH=unset$" "$work/log" && grep -q "^front AUTH=unset$" "$work/log" && grep -q "^node PROJECTS=unset$" "$work/log" && grep -q "^front PROJECTS=unset$" "$work/log"'
check "...and the run itself went ahead" '[ $rc -eq 3 ]'

# #1071: NOEVIA_RUST_AUTH is retired. Whatever is left in the environment (the old live 1, a 0 or
# empty) warns, starts both and reaches neither process; the front still owns sign-in.
for v in 1 0 ""; do
  reset; touch "$work/die-front"
  run NOEVIA_RUST_AUTH="$v" NOEVIA_RUST_AUTH_CONFIRMED=1 >/dev/null 2>"$work/err"; rc=$?
  check "a leftover NOEVIA_RUST_AUTH='$v' warns, is passed to neither process, and the run goes ahead" '[ $rc -eq 3 ] && grep -q "NOEVIA_RUST_AUTH is retired" "$work/err" && grep -q "^node AUTH=unset$" "$work/log" && grep -q "^front AUTH=unset$" "$work/log" && grep -q "^node .* CONF=$" "$work/log"'
done
# #1071: NOEVIA_RUST_PROJECTS is retired. Whatever is left in the environment (the old live 1, a 0
# or empty) warns, starts both and reaches neither process; its old confirmations never reach Node,
# and the project store is still set up.
for v in 1 0 ""; do
  reset; touch "$work/die-front"
  run NOEVIA_RUST_PROJECTS="$v" NOEVIA_RUST_PROJECTS_CONFIRMED=1 NOEVIA_RUST_PROJECT_CHATS_CONFIRMED=1 NOEVIA_RUST_FREE_CHATS_CONFIRMED=1 NOEVIA_RUST_PROJECT_STORE_CONFIRMED=1 >/dev/null 2>"$work/err"; rc=$?
  check "a leftover NOEVIA_RUST_PROJECTS='$v' warns, is passed to neither process, and the run goes ahead" '[ $rc -eq 3 ] && grep -q "NOEVIA_RUST_PROJECTS is retired" "$work/err" && grep -q "^node PROJECTS=unset$" "$work/log" && grep -q "^front PROJECTS=unset$" "$work/log" && grep -q "^node .* CCONF= FCONF= PCONF= CONF=$" "$work/log" && grep -q "^node SSTORE= SPORT=" "$work/log"'
done
reset; touch "$work/die-front"
run >/dev/null 2>"$work/err"; rc=$?
check "without NOEVIA_RUST_AUTH or NOEVIA_RUST_PROJECTS both start, with no warning about either" '[ $rc -eq 3 ] && grep -q "^node AUTH=unset$" "$work/log" && ! grep -q "NOEVIA_RUST_AUTH" "$work/err" && ! grep -q "NOEVIA_RUST_PROJECTS" "$work/err"'

# Context ownership is permanent: the capability is required in ROUTE_FEATURES,
# and neither old selector nor a spoofed confirmation reaches either process.
for v in "" 0 1 true; do
  reset; touch "$work/die-front"
  run NOEVIA_RUST_PROJECT_WRITES="$v" NOEVIA_RUST_PROJECT_WRITES_CONFIRMED=1 >/dev/null 2>"$work/err"; rc=$?
  check "retired context selector '$v' warns and cannot restore Node ownership" '[ $rc -eq 3 ] && grep -q "NOEVIA_RUST_PROJECT_WRITES is retired" "$work/err" && grep -q "^node WCONF= WRITES=unset$" "$work/log" && grep -q "^front WCONF= WRITES=unset$" "$work/log"'
done
reset
run STUB_FEATURES="$(without rust-project-writes)" NOEVIA_RUST_PROJECT_WRITES=0 NOEVIA_RUST_PROJECT_WRITES_CONFIRMED=1 >/dev/null 2>"$work/err"; rc=$?
check "spoofed context confirmation cannot bypass the mandatory compiled capability" '[ $rc -eq 2 ] && grep -q "lacks the front route feature(s): rust-project-writes;" "$work/err" && [ ! -s "$work/log" ]'

# The project store (#1264), permanent: always set up, a per-start secret and UI_PORT+2000 for both
# processes; never from the environment; refused without project-store (a front route feature,
# above). The retired NOEVIA_RUST_PROJECT_STORE and its confirmation are not passed on.
for v in "" 0 1; do
  reset; touch "$work/die-front"
  run UI_PORT=8021 NOEVIA_RUST_PROJECT_STORE="$v" NOEVIA_PROJECT_STORE_TOKEN=inherited-secret-0123456789abcdef0123456789 NOEVIA_PROJECT_STORE_PORT=1 NOEVIA_RUST_PROJECT_STORE_CONFIRMED=1 >/dev/null 2>&1
  check "store (retired switch '$v'): both get UI_PORT+2000 and a fresh 64-character secret, never the inherited one or a confirmation" 'grep -q "^node SSTORE= SPORT=10021 STOKLEN=64$" "$work/log" && grep -q "^front SSTORE= SPORT=10021 STOKLEN=64$" "$work/log"'
done
# The start id (#1071): one fresh 32-hex id per start, the same for both processes, never inherited.
start_of() { sed -n "s/^$1 START=//p" "$work/log"; }
reset; touch "$work/die-front"
run NOEVIA_START_ID=0123456789abcdef0123456789abcdef >/dev/null 2>&1
first="$(start_of node)"
check "start id: both processes get the same fresh 32-hex id, not the inherited one" '[[ "$first" =~ ^[0-9a-f]{32}$ ]] && [ "$(start_of front)" = "$first" ] && [ "$first" != 0123456789abcdef0123456789abcdef ]'
reset; touch "$work/die-front"
run >/dev/null 2>&1
check "start id: the next start gets a different one" '[[ "$(start_of node)" =~ ^[0-9a-f]{32}$ ]] && [ "$(start_of node)" != "$first" ] && [ "$(start_of front)" = "$(start_of node)" ]'
reset
run UI_PORT=64000 >/dev/null 2>"$work/err"; rc=$?
check "a UI_PORT with no room for UI_PORT+2000 is refused, nothing started" '[ $rc -eq 2 ] && grep -q "no room for the project store port" "$work/err" && [ ! -s "$work/log" ]'

# The client address (noevia-core server/auth.cjs, #1578): Node is told to believe X-Noevia-Client-Ip
# only when the front reports client-address-header (it strips client copies of the header).
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES client-address-header" >/dev/null 2>&1
check "a front with client-address-header confirms the client address to Node only" 'grep -q "^node KCONF=1$" "$work/log" && grep -q "^front KCONF=$" "$work/log"'
reset; touch "$work/die-front"
run NOEVIA_FRONT_CLIENT_IP=1 >/dev/null 2>"$work/err"
check "a front without it leaves Node unconfirmed (an inherited value is dropped) and still starts" 'grep -q "^node KCONF=$" "$work/log" && grep -q "no client-address-header" "$work/err"'

# #2027: only the verified front can be supplied as the filesystem claim helper.
reset; touch "$work/die-front"
run NOEVIA_LEGACY_CLAIM_BIN=/untrusted/inherited STUB_FEATURES="$BASE_FEATURES legacy-root-claim" >/dev/null 2>&1
check "claim-capable front supplies its own absolute helper path to Node only" 'grep -Fxq "node LCLAIM=$work/noevia-server" "$work/log" && grep -qx "front LCLAIM=" "$work/log"'
reset; touch "$work/die-front"
run NOEVIA_LEGACY_CLAIM_BIN=/untrusted/inherited >/dev/null 2>&1
check "older front cannot pass an inherited claim helper path" 'grep -qx "node LCLAIM=" "$work/log" && grep -qx "front LCLAIM=" "$work/log"'

# #1822 regression: a front that dies at once must not cut a slow-starting Node's startup log short
# (the supervisor TERMs the survivor the moment one child exits).
reset; touch "$work/die-front"
run STUB_NODE_DELAY=0.4 >/dev/null 2>&1
check "a front dying at once does not truncate a slow Node's startup log" 'grep -q "^node WCONF= WRITES=unset$" "$work/log" && grep -q "^node KCONF=" "$work/log"'

# Feature ownership must agree in both directions before either process launches.
mkdir -p "$work/server"
printf '%s\n' "const setup = factory.createReadOnlyFeatures({});" > "$work/server/index.cjs"
reset
run >/dev/null 2>"$work/err"; rc=$?
check "native feature Core with old front refuses before launch" '[ $rc -eq 2 ] && grep -q "feature ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES rust-feature-owner" >/dev/null 2>"$work/err"; rc=$?
check "matching native feature pair starts both processes" '[ $rc -eq 3 ] && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
rm "$work/server/index.cjs"
reset
run STUB_FEATURES="$BASE_FEATURES rust-feature-owner" >/dev/null 2>"$work/err"; rc=$?
check "native feature front with old Core refuses before launch" '[ $rc -eq 2 ] && grep -q "feature ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
# Diary route ownership (sbstndalton/noevia#2185) must agree in both directions before launch.
printf '%s\n' "  if (require('./rust-diary.cjs').refuseOwned(req, res, {})) return;" > "$work/server/index.cjs"
reset
run >/dev/null 2>"$work/err"; rc=$?
check "Diary-refusing Core with an old front refuses before launch" '[ $rc -eq 2 ] && grep -q "Diary route ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES rust-diary" >/dev/null 2>"$work/err"; rc=$?
check "matching native Diary pair starts both processes" '[ $rc -eq 3 ] && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
rm "$work/server/index.cjs"
reset
run STUB_FEATURES="$BASE_FEATURES rust-diary" >/dev/null 2>"$work/err"; rc=$?
check "rust-diary front with old Core refuses before launch" '[ $rc -eq 2 ] && grep -q "Diary route ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
# Model read route ownership (sbstndalton/noevia#2187) must agree in both directions before launch.
printf '%s\n' "  if (require('./rust-models.cjs').refuseOwned(req, res, { parseRequestUrl, json })) return;" > "$work/server/index.cjs"
reset
run >/dev/null 2>"$work/err"; rc=$?
check "model-read-refusing Core with an old front refuses before launch" '[ $rc -eq 2 ] && grep -q "model read route ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES rust-model-reads" >/dev/null 2>"$work/err"; rc=$?
check "matching native model read pair starts both processes" '[ $rc -eq 3 ] && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
rm "$work/server/index.cjs"
reset
run STUB_FEATURES="$BASE_FEATURES rust-model-reads" >/dev/null 2>"$work/err"; rc=$?
check "rust-model-reads front with old Core refuses before launch" '[ $rc -eq 2 ] && grep -q "model read route ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run >/dev/null 2>"$work/err"; rc=$?
check "old model read pair (old Core, old front) still starts for rollback" '[ $rc -eq 3 ] && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
# Project source read route ownership (sbstndalton/noevia#2191) must agree in both directions before launch.
printf '%s\n' "  if (require('./rust-project-reads.cjs').refuseOwned(req, res, { parseRequestUrl, json })) return;" > "$work/server/index.cjs"
reset
run >/dev/null 2>"$work/err"; rc=$?
check "project-read-refusing Core with an old front refuses before launch" '[ $rc -eq 2 ] && grep -q "project source read ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES rust-project-reads" >/dev/null 2>"$work/err"; rc=$?
check "matching native project source read pair starts both processes" '[ $rc -eq 3 ] && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
rm "$work/server/index.cjs"
reset
run STUB_FEATURES="$BASE_FEATURES rust-project-reads" >/dev/null 2>"$work/err"; rc=$?
check "rust-project-reads front with old Core refuses before launch" '[ $rc -eq 2 ] && grep -q "project source read ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run >/dev/null 2>"$work/err"; rc=$?
check "old project source read pair (old Core, old front) still starts for rollback" '[ $rc -eq 3 ] && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
# Project create/delete route ownership (sbstndalton/noevia#2191 round 2) must agree in both directions.
printf '%s\n' "  if (require('./rust-project-lifecycle.cjs').refuseOwned(req, res, { parseRequestUrl, json })) return;" > "$work/server/index.cjs"
reset
run >/dev/null 2>"$work/err"; rc=$?
check "project-lifecycle-refusing Core with an old front refuses before launch" '[ $rc -eq 2 ] && grep -q "project create/delete ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES rust-project-lifecycle" >/dev/null 2>"$work/err"; rc=$?
check "matching native project create/delete pair starts both processes" '[ $rc -eq 3 ] && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
rm "$work/server/index.cjs"
reset
run STUB_FEATURES="$BASE_FEATURES rust-project-lifecycle" >/dev/null 2>"$work/err"; rc=$?
check "rust-project-lifecycle front with old Core refuses before launch" '[ $rc -eq 2 ] && grep -q "project create/delete ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run >/dev/null 2>"$work/err"; rc=$?
check "old project create/delete pair (old Core, old front) still starts for rollback" '[ $rc -eq 3 ] && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
# Project storage write ownership (sbstndalton/noevia#2191 round 3) must agree in both directions.
printf '%s\n' "  kinds: require('./rust-project-storage.cjs').CORE_KINDS," > "$work/server/index.cjs"
reset
run >/dev/null 2>"$work/err"; rc=$?
check "project-storage Core with an old front refuses before launch" '[ $rc -eq 2 ] && grep -q "project storage write ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES rust-project-storage" >/dev/null 2>"$work/err"; rc=$?
check "matching native project storage pair starts both processes" '[ $rc -eq 3 ] && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
rm "$work/server/index.cjs"
reset
run STUB_FEATURES="$BASE_FEATURES rust-project-storage" >/dev/null 2>"$work/err"; rc=$?
check "rust-project-storage front with old Core refuses before launch" '[ $rc -eq 2 ] && grep -q "project storage write ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run >/dev/null 2>"$work/err"; rc=$?
check "old project storage pair (old Core, old front) still starts for rollback" '[ $rc -eq 3 ] && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
# Project file delete ownership (sbstndalton/noevia#2191 round 3) must agree in both directions.
printf '%s\n' "  if (require('./rust-project-files.cjs').refuseOwned(req, res, { parseRequestUrl, json })) return;" > "$work/server/index.cjs"
reset
run >/dev/null 2>"$work/err"; rc=$?
check "project-file-refusing Core with an old front refuses before launch" '[ $rc -eq 2 ] && grep -q "project file delete ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'
reset; touch "$work/die-front"
run STUB_FEATURES="$BASE_FEATURES rust-project-files" >/dev/null 2>"$work/err"; rc=$?
check "matching native project file delete pair starts both processes" '[ $rc -eq 3 ] && grep -q "^front " "$work/log" && grep -q "^node " "$work/log"'
rm "$work/server/index.cjs"
reset
run STUB_FEATURES="$BASE_FEATURES rust-project-files" >/dev/null 2>"$work/err"; rc=$?
check "rust-project-files front with old Core refuses before launch" '[ $rc -eq 2 ] && grep -q "project file delete ownership mismatch" "$work/err" && [ ! -s "$work/log" ]'

# --- Process lifecycle -----------------------------------------------------------------------
reset
(run UI_PORT=8021 UI_HOST=0.0.0.0 COWORK_DAV_PORT=0 >/dev/null 2>"$work/err"; echo $? > "$work/rc") &
wait_log "^front" && wait_log "^node"
check "Node on loopback UI_PORT+1000" 'grep -q "^node UI_HOST=127.0.0.1 UI_PORT=9021 " "$work/log"'
check "the front on UI_HOST:UI_PORT with Node as upstream" 'grep -q "^front UI_HOST=0.0.0.0 UI_PORT=8021 UPSTREAM=http://127.0.0.1:9021 " "$work/log"'
touch "$work/die-front"
for _ in $(seq 1 100); do [ -s "$work/rc" ] && break; sleep 0.05; done
check "the front dying stops Node" 'grep -q "^node TERM" "$work/log"'
check "...and the container exits non-zero" '[ "$(cat "$work/rc")" = 3 ]'

reset
(run UI_PORT=8021 >/dev/null 2>&1; echo $? > "$work/rc") &
wait_log "^front" && wait_log "^node"
touch "$work/die-node"
for _ in $(seq 1 100); do [ -s "$work/rc" ] && break; sleep 0.05; done
check "Node dying stops the front, non-zero exit" 'grep -q "^front TERM" "$work/log" && [ "$(cat "$work/rc")" = 3 ]'

reset
(cd "$work" && exec env NOEVIA_FRONT=rust NOEVIA_SERVER_BIN="$work/noevia-server" UI_PORT=8021 COWORK_DAV_PORT=8040 bash "$sup" >/dev/null 2>"$work/err") &
pid=$!
wait_log "^front" && wait_log "^node"
check "with DAV on, Node keeps UI_HOST (default 0.0.0.0) and says so" 'grep -q "^node UI_HOST=0.0.0.0 UI_PORT=9021 " "$work/log" && grep -q "not loopback only" "$work/err"'
kill -TERM "$pid"; wait "$pid"; rc=$?
check "docker stop (SIGTERM) stops both and exits 0" '[ $rc -eq 0 ] && grep -q "^node TERM" "$work/log" && grep -q "^front TERM" "$work/log"'

echo "passed $passes, failed $fails"
[ "$fails" -eq 0 ]
