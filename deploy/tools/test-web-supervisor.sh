#!/usr/bin/env bash
# Tests build/web-supervisor.sh (the web image entrypoint, NOEVIA_FRONT=node|rust) with stub
# `node` and noevia-server processes. Needs bash >= 4.3 (wait -n), like the image; skips on
# macOS's bash 3.2. CI runs it on Linux.
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

mkdir -p "$work/bin"
# Each stub records its environment, then lives until killed or until its "die" file appears.
stub() {
  cat > "$1" <<STUB
#!/usr/bin/env bash
name=$2
if [ "\${1:-}" = --features ]; then printf '%s\\n' \${STUB_FEATURES-code-net-guard}; exit 0; fi
echo "\$name UI_HOST=\${UI_HOST:-} UI_PORT=\${UI_PORT:-} UPSTREAM=\${NOEVIA_LEGACY_UPSTREAM:-} ARGS=\$* PCONF=\${NOEVIA_RUST_PROJECTS_CONFIRMED:-} CONF=\${NOEVIA_RUST_AUTH_CONFIRMED:-}" >> "$work/log"
trap 'echo "\$name TERM" >> "$work/log"; exit 0' TERM
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
run() { (cd "$work" && env "$@" bash "$sup"); }
reset() { : > "$work/log"; rm -f "$work"/die-*; }
wait_log() { for _ in $(seq 1 100); do grep -q "$1" "$work/log" 2>/dev/null && return 0; sleep 0.05; done; return 1; }

reset; touch "$work/die-node"
run NOEVIA_FRONT= UI_PORT=8021 >/dev/null 2>&1; rc=$?
check "default is node alone, on UI_PORT" 'grep -q "^node UI_HOST= UI_PORT=8021 UPSTREAM= ARGS=server/index.cjs" "$work/log" && ! grep -q "^front" "$work/log"'
check "node mode is an exec (its exit status is the container's)" '[ $rc -eq 3 ]'

reset
run NOEVIA_FRONT=bogus >/dev/null 2>"$work/err"; rc=$?
check "an unknown NOEVIA_FRONT is refused" '[ $rc -eq 2 ] && grep -q "rust or node" "$work/err" && [ ! -s "$work/log" ]'

reset
run NOEVIA_FRONT=rust NOEVIA_SERVER_BIN="$work/missing" >/dev/null 2>"$work/err"; rc=$?
check "rust without the binary is refused, nothing started" '[ $rc -eq 2 ] && grep -q "no noevia-server" "$work/err" && [ ! -s "$work/log" ]'

reset
run NOEVIA_FRONT=rust NOEVIA_SERVER_BIN="$work/noevia-server" STUB_FEATURES= COWORK_CODE_NET_ADDR=egress >/dev/null 2>"$work/err"; rc=$?
check "rust with COWORK_CODE_NET_ADDR and a front without the guard is refused" '[ $rc -eq 2 ] && grep -q "no code-net-guard" "$work/err" && [ ! -s "$work/log" ]'

reset; rm -f "$work/rc"
(run NOEVIA_FRONT=rust NOEVIA_SERVER_BIN="$work/noevia-server" UI_PORT=8021 COWORK_CODE_NET_ADDR=egress >/dev/null 2>&1; echo $? > "$work/rc") &
wait_log "^front" && wait_log "^node"
check "rust with COWORK_CODE_NET_ADDR starts when the front reports code-net-guard" 'grep -q "^front UI_HOST=" "$work/log"'
touch "$work/die-front"
for _ in $(seq 1 100); do [ -s "$work/rc" ] && break; sleep 0.05; done
rm -f "$work/rc"

reset
run NOEVIA_FRONT=rust NOEVIA_RUST_AUTH=1 NOEVIA_SERVER_BIN="$work/noevia-server" STUB_FEATURES=code-net-guard >/dev/null 2>"$work/err"; rc=$?
check "rust with NOEVIA_RUST_AUTH=1 and a front without rust-auth is refused, nothing started" '[ $rc -eq 2 ] && grep -q "no rust-auth" "$work/err" && [ ! -s "$work/log" ]'

reset
run NOEVIA_FRONT=rust NOEVIA_RUST_AUTH=1 NOEVIA_SERVER_BIN="$work/noevia-server" STUB_FEATURES= >/dev/null 2>"$work/err"; rc=$?
check "...also when --features prints nothing" '[ $rc -eq 2 ] && grep -q "no rust-auth" "$work/err" && [ ! -s "$work/log" ]'

reset; rm -f "$work/rc"
(run NOEVIA_FRONT=rust NOEVIA_RUST_AUTH=1 NOEVIA_SERVER_BIN="$work/noevia-server" STUB_FEATURES="code-net-guard rust-auth" UI_PORT=8021 >/dev/null 2>&1; echo $? > "$work/rc") &
wait_log "^front" && wait_log "^node"
check "NOEVIA_RUST_AUTH=1 with a rust-auth front confirms it to Node only" 'grep -q "^node .* CONF=1$" "$work/log" && grep -q "^front .* CONF=$" "$work/log"'
touch "$work/die-front"
for _ in $(seq 1 100); do [ -s "$work/rc" ] && break; sleep 0.05; done
rm -f "$work/rc"

reset; rm -f "$work/rc"
(run NOEVIA_FRONT=rust NOEVIA_RUST_AUTH_CONFIRMED=1 NOEVIA_SERVER_BIN="$work/noevia-server" UI_PORT=8021 >/dev/null 2>&1; echo $? > "$work/rc") &
wait_log "^front" && wait_log "^node"
check "without NOEVIA_RUST_AUTH an inherited confirmation is dropped" 'grep -q "^node .* CONF=$" "$work/log"'
touch "$work/die-front"
for _ in $(seq 1 100); do [ -s "$work/rc" ] && break; sleep 0.05; done
rm -f "$work/rc"

reset; touch "$work/die-node"
run NOEVIA_FRONT=node NOEVIA_RUST_AUTH=1 NOEVIA_RUST_AUTH_CONFIRMED=1 >/dev/null 2>&1
check "node mode never passes a confirmation" 'grep -q "^node .* CONF=$" "$work/log"'

# M4: rust-projects builds on rust-auth and is confirmed the same way.
reset
run NOEVIA_FRONT=rust NOEVIA_RUST_PROJECTS=1 NOEVIA_SERVER_BIN="$work/noevia-server" STUB_FEATURES="code-net-guard rust-auth rust-projects" >/dev/null 2>"$work/err"; rc=$?
check "NOEVIA_RUST_PROJECTS=1 without NOEVIA_RUST_AUTH=1 is refused, nothing started" '[ $rc -eq 2 ] && grep -q "needs NOEVIA_RUST_AUTH=1" "$work/err" && [ ! -s "$work/log" ]'

reset
run NOEVIA_FRONT=rust NOEVIA_RUST_AUTH=1 NOEVIA_RUST_PROJECTS=1 NOEVIA_SERVER_BIN="$work/noevia-server" STUB_FEATURES="code-net-guard rust-auth" >/dev/null 2>"$work/err"; rc=$?
check "a front without rust-projects is refused, nothing started" '[ $rc -eq 2 ] && grep -q "no rust-projects" "$work/err" && [ ! -s "$work/log" ]'

reset; rm -f "$work/rc"
(run NOEVIA_FRONT=rust NOEVIA_RUST_AUTH=1 NOEVIA_RUST_PROJECTS=1 NOEVIA_SERVER_BIN="$work/noevia-server" STUB_FEATURES="code-net-guard rust-auth rust-projects" UI_PORT=8021 >/dev/null 2>&1; echo $? > "$work/rc") &
wait_log "^front" && wait_log "^node"
check "both switches with a rust-projects front confirm both to Node only" 'grep -q "^node .* PCONF=1 CONF=1$" "$work/log" && grep -q "^front .* PCONF= CONF=$" "$work/log"'
touch "$work/die-front"
for _ in $(seq 1 100); do [ -s "$work/rc" ] && break; sleep 0.05; done
rm -f "$work/rc"

reset; rm -f "$work/rc"
(run NOEVIA_FRONT=rust NOEVIA_RUST_AUTH=1 NOEVIA_RUST_PROJECTS_CONFIRMED=1 NOEVIA_SERVER_BIN="$work/noevia-server" STUB_FEATURES="code-net-guard rust-auth rust-projects" UI_PORT=8021 >/dev/null 2>&1; echo $? > "$work/rc") &
wait_log "^front" && wait_log "^node"
check "without NOEVIA_RUST_PROJECTS an inherited projects confirmation is dropped" 'grep -q "^node .* PCONF= CONF=1$" "$work/log"'
touch "$work/die-front"
for _ in $(seq 1 100); do [ -s "$work/rc" ] && break; sleep 0.05; done
rm -f "$work/rc"

reset
run NOEVIA_FRONT=rust NOEVIA_SERVER_BIN="$work/noevia-server" UI_PORT=65000 >/dev/null 2>&1; rc=$?
check "a UI_PORT with no room for +1000 is refused" '[ $rc -eq 2 ]'

reset
(run NOEVIA_FRONT=rust NOEVIA_SERVER_BIN="$work/noevia-server" UI_PORT=8021 UI_HOST=0.0.0.0 COWORK_DAV_PORT=0 >/dev/null 2>"$work/err"; echo $? > "$work/rc") &
wait_log "^front" && wait_log "^node"
check "rust: Node on loopback UI_PORT+1000" 'grep -q "^node UI_HOST=127.0.0.1 UI_PORT=9021 " "$work/log"'
check "rust: the front on UI_HOST:UI_PORT with Node as upstream" 'grep -q "^front UI_HOST=0.0.0.0 UI_PORT=8021 UPSTREAM=http://127.0.0.1:9021 " "$work/log"'
touch "$work/die-front"
for _ in $(seq 1 100); do [ -s "$work/rc" ] && break; sleep 0.05; done
check "the front dying stops Node" 'grep -q "^node TERM" "$work/log"'
check "...and the container exits non-zero" '[ "$(cat "$work/rc")" = 3 ]'

reset; rm -f "$work/rc"
(run NOEVIA_FRONT=rust NOEVIA_SERVER_BIN="$work/noevia-server" UI_PORT=8021 >/dev/null 2>&1; echo $? > "$work/rc") &
wait_log "^front" && wait_log "^node"
touch "$work/die-node"
for _ in $(seq 1 100); do [ -s "$work/rc" ] && break; sleep 0.05; done
check "Node dying stops the front, non-zero exit" 'grep -q "^front TERM" "$work/log" && [ "$(cat "$work/rc")" = 3 ]'

reset; rm -f "$work/rc"
(cd "$work" && exec env NOEVIA_FRONT=rust NOEVIA_SERVER_BIN="$work/noevia-server" UI_PORT=8021 COWORK_DAV_PORT=8040 bash "$sup" >/dev/null 2>"$work/err") &
pid=$!
wait_log "^front" && wait_log "^node"
check "with DAV on, Node keeps UI_HOST (default 0.0.0.0) and says so" 'grep -q "^node UI_HOST=0.0.0.0 UI_PORT=9021 " "$work/log" && grep -q "not loopback only" "$work/err"'
kill -TERM "$pid"; wait "$pid"; rc=$?
check "docker stop (SIGTERM) stops both and exits 0" '[ $rc -eq 0 ] && grep -q "^node TERM" "$work/log" && grep -q "^front TERM" "$work/log"'

echo "passed $passes, failed $fails"
[ "$fails" -eq 0 ]
