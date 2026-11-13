#!/usr/bin/env bash
# Tests deploy/tools/assemble-release.sh against a synthetic git repo (no network: curl is a
# PATH shim). Runs on macOS bash 3.2 and Linux.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/assemble-release-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; fi; }
g() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid "$@"; }

repo="$work/repo"; out="$work/out"; mkdir -p "$repo/deploy/tools" "$repo/release" "$out" "$work/bin"
cp "$here/assemble-release.sh" "$repo/deploy/tools/"
# A small synthetic stand-in for deploy/tools/diary-dockerfile.template: the mechanism is what the fixtures below
# test; the real template is exercised separately against its own rendering (and the real services Dockerfile).
cat > "$repo/deploy/tools/diary-dockerfile.template" <<'TPL'
[build-stage]
FROM rust:1 AS tenant-assertion
ARG NOEVIA_RS_REF=@NOEVIA_RS_REF@
ARG NOEVIA_RS_SHA256=@NOEVIA_RS_SHA256@
RUN cargo build --release --locked -p tenant-assertion-cli -p diary-workspace-export -p noevia-diary && mkdir /out && cd target/release && cp tenant-assertion diary-workspace-export noevia-diary /out/
[final-from]
FROM python:3.12-slim
[install]
COPY --from=tenant-assertion /out/ /usr/local/bin/
[env-fixed]
DIARY_RUST_SERVER_BIN=/usr/local/bin/noevia-diary
[final-allowed]
- RUN test -x /usr/local/bin/noevia-diary
- COPY agent/ ./agent/
TPL
cp -R "$here/lib" "$repo/deploy/tools/"
w="$repo/apps/web"
mkdir -p "$w/src" "$w/public" "$w/scripts" "$w/contracts" "$w/tests/client" "$w/tests/server" "$w/tests/fixtures" "$w/qa" "$w/server"
for f in src/main.tsx public/icon.svg scripts/build.cjs contracts/project-limits.json tests/client/a.test.cjs \
         tests/server/b.test.cjs tests/fixtures/f.json qa/q.cjs server/index.cjs server/package.json \
         index.html vite.config.ts tsconfig.json package.json package-lock.json Dockerfile \
         tests/hermetic-network.cjs .gitignore .dockerignore; do
  echo "synthetic $f" > "$w/$f"
done
for svc in code-sandbox diary docling laya model-manager ocr; do
  mkdir -p "$repo/services/$svc" && echo "synthetic $svc" > "$repo/services/$svc/Dockerfile"
done
printf 'NOEVIA_RS_REF=%040d\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\nNOEVIA_SERVICES_REF=self\n' 0 > "$repo/release/versions.lock"
mkdir -p "$w/server/ui-data"; echo synthetic-runtime-key > "$w/server/ui-data/secrets.key"
git init -q "$repo" && g add -A && g commit -qm one
sha="$(g rev-parse --short=12 HEAD)"; full="$(g rev-parse HEAD)"

bash "$repo/deploy/tools/assemble-release.sh" "$sha" "$out" >/dev/null 2>"$work/err"; rc=$?
tgz="$out/noevia-release-$sha.tar.gz"
check "self mode exits 0" '[ $rc -eq 0 ]'
check "writes noevia-release-<sha>.tar.gz" '[ -f "$tgz" ]'
x="$work/x"; mkdir -p "$x"; tar -xzf "$tgz" -C "$x" 2>/dev/null
check "noevia/ is the whole repo" '[ -f "$x/noevia/release/versions.lock" ] && [ -f "$x/noevia/apps/web/server/index.cjs" ]'
check "web/ has the client parts" '[ -f "$x/web/src/main.tsx" ] && [ -f "$x/web/package-lock.json" ] && [ -f "$x/web/contracts/project-limits.json" ] && [ -f "$x/web/tests/client/a.test.cjs" ] && [ -f "$x/web/qa/q.cjs" ]'
check "web/ has no server" '[ ! -e "$x/web/server" ] && [ ! -e "$x/web/tests/server" ] && [ ! -e "$x/web/Dockerfile" ]'
check "core/ has server, contracts, server tests" '[ -f "$x/core/server/index.cjs" ] && [ -f "$x/core/contracts/project-limits.json" ] && [ -f "$x/core/tests/server/b.test.cjs" ] && [ -f "$x/core/tests/fixtures/f.json" ]'
check "runtime state is excluded from the entire assembled tree" '[ -z "$(find "$x" -path "*/server/ui-data/secrets.key" -print)" ]'
check "core/ has no client" '[ ! -e "$x/core/src" ] && [ ! -e "$x/core/tests/client" ]'
check "web/ and core/ carry tests/hermetic-network.cjs, web/ its ignore files" \
  '[ -f "$x/web/tests/hermetic-network.cjs" ] && [ -f "$x/core/tests/hermetic-network.cjs" ] && [ -f "$x/web/.gitignore" ] && [ -f "$x/web/.dockerignore" ]'
check "core/ has code-sandbox (noevia-core layout)" '[ -f "$x/core/code-sandbox/Dockerfile" ] && [ ! -e "$x/services/code-sandbox" ]'
check "services/ has the five sidecars at top level" \
  'for s in diary docling laya model-manager ocr; do [ -f "$x/services/$s/Dockerfile" ] || exit 1; done'
check "release-refs records the services sha" 'grep -qx "NOEVIA_SERVICES_SHA=$full" "$x/release-refs"'
check ".dockerignore keeps services/ out of the web context" 'grep -qx services "$x/.dockerignore"'
check "release-refs: version is the given sha, web/core the full sha" \
  'grep -qx "NOEVIA_SHA=$sha" "$x/release-refs" && grep -qx "NOEVIA_WEB_SHA=$full" "$x/release-refs" && grep -qx "NOEVIA_CORE_SHA=$full" "$x/release-refs"'
check ".dockerignore keeps noevia/ out of the context" 'grep -qx noevia "$x/.dockerignore"'
check ".dockerignore lets the web supervisor in" 'grep -qx "!noevia/build/web-supervisor.sh" "$x/.dockerignore"'
check "a lock without NOEVIA_RS_SHA256 gives an empty rs/ and no NOEVIA_RS_SHA" \
  '[ -d "$x/rs" ] && [ -z "$(ls -A "$x/rs")" ] && grep -qx "NOEVIA_RS_SHA=" "$x/release-refs"'

: > "$work/err"
bash "$repo/deploy/tools/assemble-release.sh" "ABC1234" "$out" >/dev/null 2>&1; rc=$?
check "uppercase / non-hex sha refused" '[ $rc -ne 0 ]'
bash "$repo/deploy/tools/assemble-release.sh" "1234567" "$out" >/dev/null 2>&1; rc=$?
check "unknown sha refused" '[ $rc -ne 0 ] && [ ! -f "$out/noevia-release-1234567.tar.gz" ]'
bash "$repo/deploy/tools/assemble-release.sh" "$sha" "$work/missing" >/dev/null 2>&1; rc=$?
check "missing out-dir refused" '[ $rc -ne 0 ]'

echo dirty >> "$w/index.html"
rm -f "$tgz"
bash "$repo/deploy/tools/assemble-release.sh" "$sha" "$out" >/dev/null 2>&1; rc=$?
check "dirty checkout refused" '[ $rc -ne 0 ] && [ ! -f "$tgz" ]'
g checkout -q -- apps/web/index.html

# A lock from before #952 has no NOEVIA_SERVICES_REF: services are exported from the checkout.
printf 'NOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' > "$repo/release/versions.lock"
g commit -qam pre952; psha="$(g rev-parse --short HEAD)"
bash "$repo/deploy/tools/assemble-release.sh" "$psha" "$out" >/dev/null 2>"$work/err"; rc=$?
p="$work/p"; mkdir -p "$p"; tar -xzf "$out/noevia-release-$psha.tar.gz" -C "$p" 2>/dev/null
check "lock without NOEVIA_SERVICES_REF means self" '[ $rc -eq 0 ] && [ -f "$p/services/ocr/Dockerfile" ]'
printf 'NOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\nNOEVIA_SERVICES_REF=\n' > "$repo/release/versions.lock"
g commit -qam emptysvc; esha="$(g rev-parse --short HEAD)"
bash "$repo/deploy/tools/assemble-release.sh" "$esha" "$out" >/dev/null 2>"$work/err"; rc=$?
check "an empty NOEVIA_SERVICES_REF is refused" '[ $rc -ne 0 ] && grep -q NOEVIA_SERVICES_REF "$work/err"'

# --lock reads the refs from a file instead of the committed lock (dry run, #952).
printf 'NOEVIA_WEB_REF=main\n' > "$work/override.lock"
CI=true bash "$repo/deploy/tools/assemble-release.sh" --lock "$work/override.lock" "$psha" "$out" >/dev/null 2>"$work/err"; rc=$?
check "--lock file is used instead of the committed lock" '[ $rc -ne 0 ] && grep -q "NOEVIA_WEB_REF" "$work/err" && grep -q "dry run" "$work/err"'
CI=true bash "$repo/deploy/tools/assemble-release.sh" --lock "$work/nope.lock" "$psha" "$out" >/dev/null 2>&1; rc=$?
check "missing --lock file refused" '[ $rc -ne 0 ]'
printf 'NOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' > "$work/self.lock"
CI= bash "$repo/deploy/tools/assemble-release.sh" --lock "$work/self.lock" "$psha" "$out" >/dev/null 2>"$work/err"; rc=$?
check "--lock refused outside CI" '[ $rc -ne 0 ] && grep -q "CI dry runs only" "$work/err"'

# A lock ref that is neither self nor a 40-hex sha.
sed -i.bak 's/^NOEVIA_WEB_REF=.*/NOEVIA_WEB_REF=main/' "$repo/release/versions.lock" && rm -f "$repo/release/versions.lock.bak"
g commit -qam bad-ref; bad="$(g rev-parse --short HEAD)"
bash "$repo/deploy/tools/assemble-release.sh" "$bad" "$out" >/dev/null 2>"$work/err"; rc=$?
check "non-sha lock ref refused" '[ $rc -ne 0 ] && grep -q NOEVIA_WEB_REF "$work/err" && [ ! -f "$out/noevia-release-$bad.tar.gz" ]'

# Pinned remote refs: curl shim serves a synthetic codeload tarball (top dir stripped).
mkdir -p "$work/remote/noevia-web-x/src" "$work/remote/noevia-web-x/contracts"
echo remote > "$work/remote/noevia-web-x/src/main.tsx"
for f in package.json package-lock.json index.html; do echo remote > "$work/remote/noevia-web-x/$f"; done
tar -czf "$work/web.tgz" -C "$work/remote" noevia-web-x
sum="$( (sha256sum "$work/web.tgz" 2>/dev/null || shasum -a 256 "$work/web.tgz") | cut -d' ' -f1)"
cat > "$work/bin/curl" <<SHIM
#!/usr/bin/env bash
echo "\$*" >> "$work/curl-calls"
while [ \$# -gt 0 ]; do [ "\$1" = -o ] && { cp "$work/web.tgz" "\$2"; exit 0; }; shift; done
exit 1
SHIM
chmod +x "$work/bin/curl"
ref="$(printf 'a%.0s' $(seq 1 40))"
printf 'NOEVIA_WEB_REF=%s\nNOEVIA_WEB_SHA256=%s\nNOEVIA_CORE_REF=self\n' "$ref" "$sum" > "$repo/release/versions.lock"
g commit -qam remote; rsha="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$rsha" "$out" >/dev/null 2>"$work/err"; rc=$?
check "pinned web ref with matching checksum assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$rsha.tar.gz" ]'
check "fetches the anonymous codeload url" 'grep -q "https://codeload.github.com/sbstndalton/noevia-web/tar.gz/$ref" "$work/curl-calls"'
y="$work/y"; mkdir -p "$y"; tar -xzf "$out/noevia-release-$rsha.tar.gz" -C "$y" 2>/dev/null
check "remote repo root becomes web/, refs record the pinned sha" \
  'grep -qx remote "$y/web/src/main.tsx" && grep -qx "NOEVIA_WEB_SHA=$ref" "$y/release-refs"'

printf 'NOEVIA_WEB_REF=%s\nNOEVIA_WEB_SHA256=%064d\nNOEVIA_CORE_REF=self\n' "$ref" 0 > "$repo/release/versions.lock"
g commit -qam badsum; bsha="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$bsha" "$out" >/dev/null 2>"$work/err"; rc=$?
check "checksum mismatch refused" '[ $rc -ne 0 ] && grep -q "checksum mismatch" "$work/err" && [ ! -f "$out/noevia-release-$bsha.tar.gz" ]'

printf 'NOEVIA_WEB_REF=%s\nNOEVIA_CORE_REF=self\n' "$ref" > "$repo/release/versions.lock"
g commit -qam nosum; nsha="$(g rev-parse --short HEAD)"; : > "$work/curl-calls"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$nsha" "$out" >/dev/null 2>"$work/err"; rc=$?
check "pinned ref without a checksum refused before download" \
  '[ $rc -ne 0 ] && grep -q NOEVIA_WEB_SHA256 "$work/err" && [ ! -s "$work/curl-calls" ] && [ ! -f "$out/noevia-release-$nsha.tar.gz" ]'

# noevia-rs (M1): with NOEVIA_RS_SHA256 the tarball at NOEVIA_RS_REF becomes rs/.
mkdir -p "$work/remote/noevia-rs-x/bins/noevia-server"
echo '[workspace]' > "$work/remote/noevia-rs-x/Cargo.toml"
echo synthetic > "$work/remote/noevia-rs-x/bins/noevia-server/Cargo.toml"
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-x
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
cat > "$work/bin/curl" <<SHIM
#!/usr/bin/env bash
echo "\$*" >> "$work/curl-calls"
src="$work/web.tgz"; case "\$*" in *noevia-rs*) src="$work/rs.tgz" ;; esac
while [ \$# -gt 0 ]; do [ "\$1" = -o ] && { cp "\$src" "\$2"; exit 0; }; shift; done
exit 1
SHIM
chmod +x "$work/bin/curl"
rref="$(printf 'c%.0s' $(seq 1 40))"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g commit -qam rs; rssha="$(g rev-parse --short HEAD)"; : > "$work/curl-calls"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$rssha" "$out" >/dev/null 2>"$work/err"; rc=$?
z="$work/z"; mkdir -p "$z"; tar -xzf "$out/noevia-release-$rssha.tar.gz" -C "$z" 2>/dev/null
check "pinned noevia-rs with its checksum becomes rs/" '[ $rc -eq 0 ] && [ -f "$z/rs/bins/noevia-server/Cargo.toml" ] && [ -f "$z/rs/Cargo.toml" ]'
check "fetches noevia-rs from codeload at NOEVIA_RS_REF" 'grep -q "https://codeload.github.com/sbstndalton/noevia-rs/tar.gz/$rref" "$work/curl-calls"'
check "release-refs records NOEVIA_RS_SHA" 'grep -qx "NOEVIA_RS_SHA=$rref" "$z/release-refs"'
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%064d\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" 0 > "$repo/release/versions.lock"
g commit -qam rsbad; rbsha="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$rbsha" "$out" >/dev/null 2>"$work/err"; rc=$?
check "noevia-rs checksum mismatch refused" '[ $rc -ne 0 ] && grep -q "noevia-rs tarball checksum mismatch" "$work/err" && [ ! -f "$out/noevia-release-$rbsha.tar.gz" ]'
printf 'NOEVIA_RS_REF=main\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rsum" > "$repo/release/versions.lock"
g commit -qam rsref; rrsha="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$rrsha" "$out" >/dev/null 2>"$work/err"; rc=$?
check "a non-sha NOEVIA_RS_REF with a checksum is refused" '[ $rc -ne 0 ] && grep -q NOEVIA_RS_REF "$work/err"'

# M4 (#1409): a front that owns project routes its core's rust-projects.cjs OWNED_ROUTES does not
# list (a chat-list front over a core from before noevia-core#75) is refused; names of path
# placeholders do not matter. Since sbstndalton/noevia#1071 those routes have no switch (the
# supervisor no longer passes NOEVIA_RUST_PROJECTS): a front or core that still waits on it is
# refused first.
mkdir -p "$work/remote/noevia-rs-old/bins/noevia-server" "$work/remote/noevia-rs-old/contracts/http"
echo '[workspace]' > "$work/remote/noevia-rs-old/Cargo.toml"
echo synthetic > "$work/remote/noevia-rs-old/bins/noevia-server/Cargo.toml"
cat > "$work/remote/noevia-rs-old/contracts/http/routes.toml" <<'TOML'
[[route]]
path = "/api/projects/{id}/assets"
owner = "rust"
switch = "NOEVIA_RUST_PROJECTS"
methods = ["POST"]
TOML
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-old
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
cat > "$w/server/rust-projects.cjs" <<'JS'
function refuseOwnedRoute() {}
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{id}/assets',
]));
JS
g add -A && g commit -qm rs-switched; po="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$po" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071: a front that still gates the project routes on NOEVIA_RUST_PROJECTS is refused, even over a current core" \
  '[ $rc -ne 0 ] && grep -q "still gates the project routes on NOEVIA_RUST_PROJECTS" "$work/err" && [ ! -f "$out/noevia-release-$po.tar.gz" ]'
g rm -q apps/web/server/rust-projects.cjs && g commit -qm core-plain-again

mkdir -p "$work/remote/noevia-rs-y/bins/noevia-server" "$work/remote/noevia-rs-y/contracts/http"
echo '[workspace]' > "$work/remote/noevia-rs-y/Cargo.toml"
echo synthetic > "$work/remote/noevia-rs-y/bins/noevia-server/Cargo.toml"
# sbstndalton/noevia#1931: every rs pinned under this supervisor must own sign-in with no switch
# (rs#146 level), and its core must carry the unconditional rust-auth guard.
printf '%s\n' "function refuseOwned(req, res, pathname, json) { return false; }" > "$w/server/rust-auth.cjs"
g add -A
cat > "$work/remote/noevia-rs-y/contracts/http/routes.toml" <<'TOML'
[[route]]
path = "/api/auth/session"
owner = "rust"
methods = ["GET"]

[[route]]
path = "/api/projects/{id}/assets"
owner = "rust"
methods = ["POST"]
client = false

[[route]]
path = "/api/projects/{projectId}/chats"
owner = "rust"
methods = ["GET", "POST"]

[[route]]
path = "/api/projects/{projectId}/chats/{chatId}"
owner = "node"

[[route]]
path = "/api/usage"
owner = "rust"
methods = ["GET"]
TOML
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g commit -qam rs-projects; pa="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pa" "$out" >/dev/null 2>"$work/err"; rc=$?
check "a front owning project routes over a core without rust-projects.cjs is refused" \
  '[ $rc -ne 0 ] && grep -q "refuseOwnedRoute" "$work/err" && [ ! -f "$out/noevia-release-$pa.tar.gz" ]'
# #1071: a core that lists the routes but still gates its refusal on the switch (no refuseOwnedRoute).
cat > "$w/server/rust-projects.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{id}/assets',
  'GET /api/projects/{id}/chats',
  'POST /api/projects/{id}/chats',
]));
JS
g add -A && g commit -qm core-switched; pq="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pq" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071: an unswitched front over a core that still gates its project routes on NOEVIA_RUST_PROJECTS is refused" \
  '[ $rc -ne 0 ] && grep -q "still gates its project routes on NOEVIA_RUST_PROJECTS" "$work/err" && [ ! -f "$out/noevia-release-$pq.tar.gz" ]'
cat > "$w/server/rust-projects.cjs" <<'JS'
function refuseOwnedRoute() {}
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{id}/assets',
  'GET /api/projects/{id}/assets/{assetId}',
  'DELETE /api/projects/{id}/assets/{assetId}',
]));
JS
g add -A && g commit -qm core-images; pb="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pb" "$out" >/dev/null 2>"$work/err"; rc=$?
check "a chat-list front over a core that lists only the image routes is refused, naming both methods" \
  '[ $rc -ne 0 ] && grep -q "GET /api/projects/{}/chats;POST /api/projects/{}/chats$" "$work/err" && ! grep -q "assets" "$work/err" && [ ! -f "$out/noevia-release-$pb.tar.gz" ]'
cat > "$w/server/rust-projects.cjs" <<'JS'
function refuseOwnedRoute() {}
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{id}/assets',
  'GET /api/projects/{id}/assets/{assetId}',
  'DELETE /api/projects/{id}/assets/{assetId}',
  'GET /api/projects/{id}/chats',
  'POST /api/projects/{id}/chats',
]));
JS
g add -A && g commit -qm core-chats; pc="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pc" "$out" >/dev/null 2>"$work/err"; rc=$?
check "the same front over a core that lists the chat routes assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$pc.tar.gz" ]'
# #1071: a front that reads NOEVIA_START_ID needs this release's supervisor to hand it to both
# processes; without that the release is refused, with it the same pins assemble.
mkdir -p "$work/remote/noevia-rs-y/bins/noevia-server/src"
echo 'let start_id = get("NOEVIA_START_ID");' > "$work/remote/noevia-rs-y/bins/noevia-server/src/config.rs"
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
mkdir -p "$repo/build"
printf '%s\n' 'NOEVIA_START_ID="$start_id" node server/index.cjs &' > "$repo/build/web-supervisor.sh"
g add -A && g commit -qm rs-start-id-one; ps1="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ps1" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071: a start-id front whose supervisor hands the id to only one process is refused" \
  '[ $rc -ne 0 ] && grep -q "does not hand it to both processes" "$work/err" && [ ! -f "$out/noevia-release-$ps1.tar.gz" ]'
printf '%s\n' 'NOEVIA_START_ID="$start_id" "$bin" &' >> "$repo/build/web-supervisor.sh"
g add -A && g commit -qm rs-start-id-both; ps2="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ps2" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071: ...and assembles once the supervisor hands it to both" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$ps2.tar.gz" ]'
# #2146 (NIT): the check is not fooled by the file moving: the variable named in another source
# of the front, or only its `start-id` --features entry, needs the supervisor just the same.
printf '%s\n' 'NOEVIA_START_ID="$start_id" node server/index.cjs &' > "$repo/build/web-supervisor.sh"
g add -A && g commit -qm rs-start-id-one-again
for moved in "settings.rs:let start_id = get(\"NOEVIA_START_ID\");" "lib.rs:pub const FEATURES: &[&str] = &[\"start-id\"];"; do
  rm -f "$work/remote/noevia-rs-y/bins/noevia-server/src/"*.rs
  printf '%s\n' "${moved#*:}" > "$work/remote/noevia-rs-y/bins/noevia-server/src/${moved%%:*}"
  tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
  rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
  printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
  g commit -qam "rs-start-id-${moved%%:*}"; pm="$(g rev-parse --short HEAD)"
  PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pm" "$out" >/dev/null 2>"$work/err"; rc=$?
  check "#2146: a start-id front keyed by ${moved%%:*} (config.rs gone) is still refused with a one-process supervisor" \
    '[ $rc -ne 0 ] && grep -q "does not hand it to both processes" "$work/err" && [ ! -f "$out/noevia-release-$pm.tar.gz" ]'
done
rm -f "$work/remote/noevia-rs-y/bins/noevia-server/src/"*.rs
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g rm -q build/web-supervisor.sh && g commit -qam supervisor-plain-again
# The free-chat slice: a front that also owns GET/POST /api/freechats over a core whose
# OWNED_ROUTES lacks them (from before noevia-core#76, whose free-list writers would drop the
# front's saves by a whole-file write) is refused, naming only those; the core that lists them
# assembles. The delete route stays Node's and is not asked for.
cat >> "$work/remote/noevia-rs-y/contracts/http/routes.toml" <<'TOML'

[[route]]
path = "/api/freechats"
owner = "rust"
methods = ["GET", "POST"]

[[route]]
path = "/api/freechats/{chatId}"
owner = "node"
TOML
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g commit -qam rs-free-chats; pd="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pd" "$out" >/dev/null 2>"$work/err"; rc=$?
check "a free-chat front over a core that lists only the project routes is refused, naming both methods" \
  '[ $rc -ne 0 ] && grep -q "GET /api/freechats;POST /api/freechats$" "$work/err" && ! grep -q "/api/projects" "$work/err" && [ ! -f "$out/noevia-release-$pd.tar.gz" ]'
cat > "$w/server/rust-projects.cjs" <<'JS'
function refuseOwnedRoute() {}
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{id}/assets',
  'GET /api/projects/{id}/assets/{assetId}',
  'DELETE /api/projects/{id}/assets/{assetId}',
  'GET /api/projects/{id}/chats',
  'POST /api/projects/{id}/chats',
  'GET /api/freechats',
  'POST /api/freechats',
]));
JS
g add -A && g commit -qm core-free-chats; pe="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pe" "$out" >/dev/null 2>"$work/err"; rc=$?
check "the same front over a core that lists the free-chat routes assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$pe.tar.gz" ]'
# #1071 slice 2: a front that answers GET /api/chats/{chatId}/history needs a core that marks a
# running reply's partial (noevia-core#245) and unmarks an unremovable finished one (#2146).
cat >> "$work/remote/noevia-rs-y/contracts/http/routes.toml" <<'TOML'

[[route]]
path = "/api/chats/{chatId}/history"
owner = "rust"
methods = ["GET"]
TOML
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g commit -qam rs-history-get; ph1="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph1" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071: a history-GET front over a core without the running marker is refused" \
  '[ $rc -ne 0 ] && grep -q "does not mark a running reply" "$work/err" && [ ! -f "$out/noevia-release-$ph1.tar.gz" ]'
printf '%s\n' "fs.writeFileSync(tmp, JSON.stringify({ ...bounded(entry), interrupted: true, running: { start: START_ID } }));" > "$w/server/chat-partial.cjs"
g add -A && g commit -qm core-marker; ph2="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph2" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#2146: ...and over a core that marks it but can leave a finished reply's marker behind" \
  '[ $rc -ne 0 ] && grep -q "no endPartial" "$work/err" && [ ! -f "$out/noevia-release-$ph2.tar.gz" ]'
printf '%s\n' 'function endPartial(dir, chatId) {}' >> "$w/server/chat-partial.cjs"
g add -A && g commit -qm core-end-partial; ph3="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph3" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071: ...and assembles over a core with both" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$ph3.tar.gz" ]'
sed -i.bak 's/methods = \["GET"\]$/methods = ["POST"]/' "$work/remote/noevia-rs-y/contracts/http/routes.toml" && rm -f "$work/remote/noevia-rs-y/contracts/http/routes.toml.bak"
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g rm -q apps/web/server/chat-partial.cjs && g commit -qam rs-history-post-only; ph4="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph4" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071 slice 5: a front that owns only the history save needs no marker, but is refused over a core that writes transcripts itself" \
  '[ $rc -ne 0 ] && ! grep -q "running reply" "$work/err" && grep -q "still writes transcripts itself" "$work/err" && [ ! -f "$out/noevia-release-$ph4.tar.gz" ]'
# #1071 slice 4: a core whose writers use the store's history ops needs a front that serves them.
printf '%s\n' 'async historyAppendIfLast(user, chat, message, entry) {}' > "$w/server/project-store-client.cjs"
printf '%s\n' 'return workspace.transcripts.appendIfLast(id, message, entry);' > "$w/server/chat-interrupted-turn.cjs"
printf '%s\n' 'let published = await ctx.transcripts.write(chat.id, history, { ifAbsent: true });' > "$w/server/conversation-import.cjs"
g add -A && g commit -qm core-history-store; ph5="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph5" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071 slice 4: a core saving transcripts through the store over a front without the history ops is refused" \
  '[ $rc -ne 0 ] && grep -q "does not serve them" "$work/err" && [ ! -f "$out/noevia-release-$ph5.tar.gz" ]'
mkdir -p "$work/remote/noevia-rs-y/bins/noevia-server/src"
printf '%s\n' '.route("/v1/history/append-if-last", history_route(Op::Append))' > "$work/remote/noevia-rs-y/bins/noevia-server/src/project_store.rs"
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g commit -qam rs-history-ops; ph6="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph6" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071 slice 5: ...a save-owning front over that core is still refused while Node answers the save too" \
  '[ $rc -ne 0 ] && grep -q "does not refuse it" "$work/err" && [ ! -f "$out/noevia-release-$ph6.tar.gz" ]'
printf '%s\n' 'function writeHistory(spaceId, history) {}' > "$w/server/projects.cjs"
sed -i.bak "s#  'POST /api/freechats',#  'POST /api/freechats',\n  'POST /api/chats/{chatId}/history',#" "$w/server/rust-projects.cjs" && rm -f "$w/server/rust-projects.cjs.bak"
g add -A && g commit -qm core-refuses-history-post-but-writes; ph7="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph7" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071 slice 5: ...and refused while the core keeps a local writeHistory" \
  '[ $rc -ne 0 ] && grep -q "still writes transcripts itself" "$work/err" && [ ! -f "$out/noevia-release-$ph7.tar.gz" ]'
g rm -q apps/web/server/projects.cjs && g commit -qm core-history-store-only; ph8="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph8" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#2153: ...but is refused while the core does not tail the chat change journal" \
  '[ $rc -ne 0 ] && grep -q "does not tail the chat change journal" "$work/err" && [ ! -f "$out/noevia-release-$ph8.tar.gz" ]'
printf '%s\n' "const JOURNAL_READER_MARKER = 'noevia-chat-change-journal-reader/1';" > "$w/server/chat-change-journal.cjs"
g add -A && g commit -qm core-journal-reader; ph9="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph9" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#2153: ...and refused while the front does not journal transcript changes" \
  '[ $rc -ne 0 ] && grep -q "does not journal transcript changes" "$work/err" && [ ! -f "$out/noevia-release-$ph9.tar.gz" ]'
printf '%s\n' '.route("/v1/changes/read", post(handle_changes))' >> "$work/remote/noevia-rs-y/bins/noevia-server/src/project_store.rs"
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g commit -qam rs-change-journal; ph10="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph10" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071 slice 5: ...and assembles once the core refuses the save, writes only through the store and tails the journal the front writes" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$ph10.tar.gz" ]'
# #2191 round 4: a core without conversation-import.cjs passes the transcript check only when it really
# refuses that import. The import pair guard runs first in a full assembly, so test the function itself.
{
  saved_tree="${tree:-}"; tree="$work/import-tree"; c="$tree/core/server"; mkdir -p "$c/routes"
  eval "$(sed -n -e '/^code_lines() {/p' -e '/^core_refuses_conversation_import() {/,/^}/p' "$here/assemble-release.sh")"
  call="  if (require('./rust-conversation-import.cjs').refuseOwned(req, res, {})) return;"
  route="    if (authn && await importRoutes(req, res, { path: p, authn })) return;"
  printf '%s\n' "const OWNED_ROUTES = new Set(['POST /api/import/conversations']);" 'function refuseOwned(req, res) { return true; }' > "$c/rust-conversation-import.cjs"
  printf '%s\n' "$call" "$route" > "$c/index.cjs"
  check "#2191: a real refusal that runs before the import route passes" 'core_refuses_conversation_import'
  printf '%s\n' "$route" "$call" > "$c/index.cjs"
  check "#2191: a refusal after the import route is refused" '! core_refuses_conversation_import'
  printf '%s\n' "require('./rust-conversation-import.cjs');" > "$c/index.cjs"
  check "#2191: only naming the helper is refused" '! core_refuses_conversation_import'
  printf '%s\n' "$call" "$route" > "$c/index.cjs"
  printf '%s\n' 'function refuseOwned() { return true; }' > "$c/rust-conversation-import.cjs"
  check "#2191: a helper that does not own the import route is refused" '! core_refuses_conversation_import'
  printf '%s\n' "const OWNED_ROUTES = new Set(['POST /api/import/conversations']);" 'function refuseOwned(req, res) { return true; }' > "$c/rust-conversation-import.cjs"
  printf '%s\n' 'ctx.transcripts.write(id, history);' > "$c/routes/import.cjs"
  check "#2191: an import route that still writes transcripts is refused" '! core_refuses_conversation_import'
  rm "$c/routes/import.cjs"; printf '%s\n' 'x' > "$c/conversation-import.cjs"
  check "#2191: a core that still has conversation-import.cjs is refused" '! core_refuses_conversation_import'
  tree="$saved_tree"
}
# #2252 (review of #2250): the core's origin test in any ordinary spelling is still that test. Optional chaining
# (`e?.origin === 'history'`), a bracket read, loose equality, and the string on the left all turn the
# pairing guard on; a comment that names the test, and an origin compared with another value, do not.
{
  saved_tree="${tree:-}"; tree="$work/origin-tree"; c="$tree/core/server"; mkdir -p "$c"
  eval "$(sed -n -e '/^code_lines() {/p' -e '/^core_needs_journal_origin() {/,/^}/p' "$here/assemble-release.sh")"
  while IFS='|' read -r want label line; do
    printf '%s\n' "$line" > "$c/chat-change-journal.cjs"
    if [ "$want" = yes ]; then check "#2252: $label is the journal origin test" 'core_needs_journal_origin'
    else check "#2252: $label is not the journal origin test" '! core_needs_journal_origin'; fi
  done <<'FORMS'
yes|e.origin === 'history'|const ok = e.origin === 'history';
yes|e?.origin === 'history'|const ok = e?.origin === 'history';
yes|entry?.origin === "history"|const ok = !!entry && entry?.origin === "history";
yes|a loose equality|const ok = e.origin == 'history';
yes|e['origin'] === 'history'|const ok = e['origin'] === 'history';
yes|e?.['origin'] === "history"|const ok = e?.['origin'] === "history";
yes|the string on the left|const ok = 'history' === e?.origin;
yes|a negated test (#2255)|if (e.origin !== 'history') return;
yes|a loosely negated test (#2255)|if (e?.origin != "history") return;
yes|a destructured origin (#2255)|const { op, origin } = e; if (origin === 'history') build();
yes|a destructured origin, negated (#2255)|const { origin } = e; if (origin !== 'history') return;
yes|a destructured origin, string on the left (#2255)|if ('history' === origin) build();
no|a destructured origin against another value (#2255)|const { origin } = e; if (origin === 'import') return;
no|a name that only ends in origin (#2255)|if (previous_origin === 'history') return;
no|a property named like a prefix (#2255)|if (e.origins === 'history') return;
no|a comment|// builds a brain when e.origin === 'history'
no|another origin value|const ok = e?.origin === 'import';
no|a doc block|/* e?.origin === 'history' */
FORMS
  tree="$saved_tree"
}
# #2153: a core that builds brains only for origin "history" entries needs a front that journals it.
printf '%s\n' "const JOURNAL_READER_MARKER = 'noevia-chat-change-journal-reader/1';" "function isHistorySave(e) { return !!e && e.op === 'write' && e.origin === 'history'; }" > "$w/server/chat-change-journal.cjs"
g add -A && g commit -qm core-journal-origin; ph10o="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph10o" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#2153: ...but a core that needs the journal origin is refused beside a front that journals none" \
  '[ $rc -ne 0 ] && grep -q "journals no origin" "$work/err" && [ ! -f "$out/noevia-release-$ph10o.tar.gz" ]'
# #2161: the front's journal source only MENTIONS an origin in a doc comment (as the real file's header does);
# that is not journaling one.
mkdir -p "$work/remote/noevia-rs-y/crates/server-projects/src"
printf '%s\n' '//! `{"seq":7,"op":"write","origin":"history"|"import"}`' > "$work/remote/noevia-rs-y/crates/server-projects/src/journal.rs"
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g commit -qam rs-journal-origin-comment-only; ph10c="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph10c" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#2161: ...and a doc comment that mentions an origin does not count as the front journaling one" \
  '[ $rc -ne 0 ] && grep -q "journals no origin" "$work/err" && [ ! -f "$out/noevia-release-$ph10c.tar.gz" ]'
# #2161: the core's origin test under another variable name is still that test.
printf '%s\n' "const JOURNAL_READER_MARKER = 'noevia-chat-change-journal-reader/1';" "function isHistorySave(entry) { return !!entry && entry.op === 'write' && entry.origin === \"history\"; }" > "$w/server/chat-change-journal.cjs"
g add -A && g commit -qm core-journal-origin-renamed; ph10r="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph10r" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#2161: ...and a core that tests the origin under another variable name is still refused beside a front that journals none" \
  '[ $rc -ne 0 ] && grep -q "journals no origin" "$work/err" && [ ! -f "$out/noevia-release-$ph10r.tar.gz" ]'
printf '%s\n' '        "origin": origin.as_str(),' >> "$work/remote/noevia-rs-y/crates/server-projects/src/journal.rs"
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g commit -qam rs-journal-origin; ph10p="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph10p" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#2153: ...and assembles once the front journals the origin" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$ph10p.tar.gz" ]'
# #1071 slice 6: a chat's delete is one store operation in the front. Pairings by explicit
# markers (#2161): the front's store "noevia-chat-delete-store/1", the core's client
# 'noevia-chat-delete-client/1'.
rs_lock() {
  tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
  rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
  printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
}
assemble_at() { PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$1" "$out" >/dev/null 2>"$work/err"; }
rt="$work/remote/noevia-rs-y/contracts/http/routes.toml"
# Both delete routes are listed owner "node" in the fixture (once each): flip them in place.
for route in '/api/freechats/{chatId}' '/api/projects/{projectId}/chats/{chatId}'; do
  [ "$(grep -c "^path = \"$route\"$" "$rt")" -eq 1 ] || { echo "FAIL - $route is not listed exactly once in the fixture"; fails=$((fails+1)); }
  sed -i.bak "\#^path = \"$route\"\$#{n;s/^owner = \"node\"\$/owner = \"rust\"\nmethods = [\"DELETE\"]/;}" "$rt" && rm -f "$rt.bak"
done
[ "$(grep -c '^methods = \["DELETE"\]$' "$rt")" -eq 2 ] || { echo "FAIL - the chat delete routes were not given to the fixture front"; fails=$((fails+1)); }
rs_lock; g commit -qam rs-chat-delete; pcd1="$(g rev-parse --short HEAD)"
assemble_at "$pcd1"; rc=$?
check "#1071 slice 6: a front that answers a chat's DELETE over a core that does not refuse it is refused, naming both routes" \
  '[ $rc -ne 0 ] && grep -q "OWNED_ROUTES" "$work/err" && grep -q "DELETE /api/freechats/{};DELETE /api/projects/{}/chats/{}" "$work/err" && [ ! -f "$out/noevia-release-$pcd1.tar.gz" ]'
sed -i.bak "s#  'POST /api/chats/{chatId}/history',#  'POST /api/chats/{chatId}/history',\n  'DELETE /api/freechats/{chatId}',\n  'DELETE /api/projects/{id}/chats/{chatId}',#" "$w/server/rust-projects.cjs" && rm -f "$w/server/rust-projects.cjs.bak"
g add -A && g commit -qm core-refuses-chat-delete; pcd2="$(g rev-parse --short HEAD)"
assemble_at "$pcd2"; rc=$?
check "#1071 slice 6: ...and refused over a core that refuses the routes but still deletes chats itself" \
  '[ $rc -ne 0 ] && grep -q "still deletes chats itself" "$work/err" && [ ! -f "$out/noevia-release-$pcd2.tar.gz" ]'
printf '%s\n' "const CHAT_DELETE_CLIENT_MARKER = 'noevia-chat-delete-client/1';" >> "$w/server/project-store-client.cjs"
g add -A && g commit -qm core-chat-delete-client; pcd3="$(g rev-parse --short HEAD)"
assemble_at "$pcd3"; rc=$?
check "#1071 slice 6: ...and refused while the front's store does not serve the delete operation" \
  '[ $rc -ne 0 ] && grep -q "does not serve it" "$work/err" && grep -q "noevia-chat-delete-store/1" "$work/err" && [ ! -f "$out/noevia-release-$pcd3.tar.gz" ]'
# A doc comment or a route string is not the marker: only the quoted constant counts.
printf '%s\n' '//! serves /v1/chat/delete (noevia-chat-delete-store/1 lands with slice 6)' > "$work/remote/noevia-rs-y/crates/server-projects/src/chat_delete.rs"
rs_lock; g commit -qam rs-chat-delete-comment-only; pcd4="$(g rev-parse --short HEAD)"
assemble_at "$pcd4"; rc=$?
check "#2161: an unquoted mention of the store marker does not satisfy the pairing" \
  '[ $rc -ne 0 ] && grep -q "does not serve it" "$work/err" && [ ! -f "$out/noevia-release-$pcd4.tar.gz" ]'
printf '%s\n' 'pub const CHAT_DELETE_STORE_MARKER: &str = "noevia-chat-delete-store/1";' >> "$work/remote/noevia-rs-y/crates/server-projects/src/chat_delete.rs"
rs_lock; g commit -qam rs-chat-delete-store; pcd5="$(g rev-parse --short HEAD)"
assemble_at "$pcd5"; rc=$?
check "#1071 slice 6: ...and assembles once the core refuses the routes and deletes through the store the front serves" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$pcd5.tar.gz" ]'
# #2168: one DELETE returned to Node must fail even while the other remains Rust-owned.
for route in '/api/freechats/{chatId}' '/api/projects/{projectId}/chats/{chatId}'; do
  cp "$rt" "$work/routes-chat-delete-both.toml"
  sed -i.bak "\#^path = \"$route\"\$#{n;s/^owner = \"rust\"\$/owner = \"node\"/;n;/^methods = \[\"DELETE\"\]\$/d;}" "$rt" && rm -f "$rt.bak"
  rs_lock; g commit -qam rs-one-delete-node; mixed="$(g rev-parse --short HEAD)"
  assemble_at "$mixed"; rc=$?
  normalized="$(printf '%s' "$route" | sed 's/{[^}]*}/{}/g')"
  check "#2168: core refusal of DELETE $route requires that individual Rust route" \
    '[ $rc -ne 0 ] && grep -q "refuses a chat" "$work/err" && grep -qF "DELETE $normalized in" "$work/err" && [ ! -f "$out/noevia-release-$mixed.tar.gz" ]'
  cp "$work/routes-chat-delete-both.toml" "$rt"
done
# The other way round: a core that refuses the delete beside a front that hands it back to Node.
for route in '/api/freechats/{chatId}' '/api/projects/{projectId}/chats/{chatId}'; do
  sed -i.bak "\#^path = \"$route\"\$#{n;s/^owner = \"rust\"\$/owner = \"node\"/;n;/^methods = \[\"DELETE\"\]\$/d;}" "$rt" && rm -f "$rt.bak"
done
! grep -q 'methods = \["DELETE"\]' "$rt" || { echo "FAIL - the delete routes were not handed back to Node in the fixture"; fails=$((fails+1)); }
rs_lock; g commit -qam rs-chat-delete-node-again; pcd6="$(g rev-parse --short HEAD)"
assemble_at "$pcd6"; rc=$?
check "#1071 slice 6: a core that refuses a chat's DELETE beside a front that does not answer it is refused" \
  '[ $rc -ne 0 ] && grep -q "refuses a chat'"'"'s DELETE" "$work/err" && grep -q "does not answer it" "$work/err" && [ ! -f "$out/noevia-release-$pcd6.tar.gz" ]'
# A core that deletes through the store but answers the routes itself beside that front assembles.
sed -i.bak "/^  'DELETE \/api\/freechats\/{chatId}',$/d; /^  'DELETE \/api\/projects\/{id}\/chats\/{chatId}',$/d" "$w/server/rust-projects.cjs" && rm -f "$w/server/rust-projects.cjs.bak"
g add -A && g commit -qm core-chat-delete-node-again; pcd7="$(g rev-parse --short HEAD)"
assemble_at "$pcd7"; rc=$?
check "#1071 slice 6: ...and assembles once that core answers the routes again (its deletes still through the store)" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$pcd7.tar.gz" ]'
# Conversely, a single Rust DELETE requires the corresponding individual core refusal.
for route in '/api/freechats/{chatId}' '/api/projects/{projectId}/chats/{chatId}'; do
  cp "$rt" "$work/routes-chat-delete-node.toml"
  sed -i.bak "\#^path = \"$route\"\$#{n;s/^owner = \"node\"\$/owner = \"rust\"\nmethods = [\"DELETE\"]/;}" "$rt" && rm -f "$rt.bak"
  rs_lock; g commit -qam rs-one-delete-rust; mixed="$(g rev-parse --short HEAD)"
  assemble_at "$mixed"; rc=$?
  normalized="$(printf '%s' "$route" | sed 's/{[^}]*}/{}/g')"
  check "#2168: DELETE $route in Rust requires that individual core refusal" \
    '[ $rc -ne 0 ] && grep -q "OWNED_ROUTES" "$work/err" && grep -qF "DELETE $normalized" "$work/err" && [ ! -f "$out/noevia-release-$mixed.tar.gz" ]'
  cp "$work/routes-chat-delete-node.toml" "$rt"
done
# The history route goes back to Node for the checks below (they swap the core's guard files).
hn="$(grep -n '^path = "/api/chats/{chatId}/history"$' "$work/remote/noevia-rs-y/contracts/http/routes.toml" | cut -d: -f1)"
sed -i.bak "$((hn-2)),$((hn+2))d" "$work/remote/noevia-rs-y/contracts/http/routes.toml" && rm -f "$work/remote/noevia-rs-y/contracts/http/routes.toml.bak"
! grep -q 'chats/{chatId}/history' "$work/remote/noevia-rs-y/contracts/http/routes.toml" || { echo "FAIL - the history route was not taken out of the fixture"; fails=$((fails+1)); }
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g commit -qam rs-history-node-again; ph11="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph11" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#1071 slice 5: a core that refuses the history save beside a front that does not answer it is refused" \
  '[ $rc -ne 0 ] && grep -q "refuses POST /api/chats/{chatId}/history" "$work/err" && grep -q "does not answer it" "$work/err" && [ ! -f "$out/noevia-release-$ph11.tar.gz" ]'
# ...so the core hands the save back to Node too.
sed -i.bak "/^  'POST \/api\/chats\/{chatId}\/history',$/d" "$w/server/rust-projects.cjs" && rm -f "$w/server/rust-projects.cjs.bak"
! grep -q "POST /api/chats/{chatId}/history" "$w/server/rust-projects.cjs" || { echo "FAIL - the history save was not taken out of the core fixture"; fails=$((fails+1)); }
g commit -qam core-history-node-again
# ...and the core's history-op client goes too, since the fronts below serve no history ops.
g rm -q apps/web/server/project-store-client.cjs && g commit -qm core-no-history-ops
# #1264/#1071: context is permanent. Old switched Rust must be refused even
# with a core listing its old conditional routes; no confirmation can rescue it.
cat >> "$work/remote/noevia-rs-y/contracts/http/routes.toml" <<'TOML'

[[route]]
path = "/api/chats/{chatId}/context"
owner = "rust"
switch = "NOEVIA_RUST_PROJECT_WRITES"
methods = ["GET", "POST"]
TOML
cat >> "$w/server/rust-projects.cjs" <<'JS'
const PROJECT_WRITE_ROUTES = Object.freeze(new Set([
  'GET /api/chats/{chatId}/context',
  'POST /api/chats/{chatId}/context',
]));
JS
context_lock() {
  tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
  rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
  printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
}
context_lock
g add -A && g commit -qm rs-context-switched; pf="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pf" "$out" >/dev/null 2>"$work/err"; rc=$?
check "old switched context is refused even with the matching old conditional core" \
  '[ $rc -ne 0 ] && grep -q "still gates chat context on NOEVIA_RUST_PROJECT_WRITES" "$work/err" && [ ! -f "$out/noevia-release-$pf.tar.gz" ]'
# Remove only the selector in the synthetic table. The old core list must not
# count as unconditional ownership: both methods must be named in OWNED_ROUTES.
sed '/^switch = "NOEVIA_RUST_PROJECT_WRITES"$/d' "$work/remote/noevia-rs-y/contracts/http/routes.toml" > "$work/routes.unswitched"
cp "$work/routes.unswitched" "$work/remote/noevia-rs-y/contracts/http/routes.toml"
context_lock
g commit -qam rs-context-permanent; pf="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pf" "$out" >/dev/null 2>"$work/err"; rc=$?
check "permanent context over old conditional core is refused, naming both missing methods" \
  '[ $rc -ne 0 ] && grep -q "OWNED_ROUTES" "$work/err" && grep -q "GET /api/chats/{}/context;POST /api/chats/{}/context$" "$work/err" && [ ! -f "$out/noevia-release-$pf.tar.gz" ]'
# Build the matched permanent table (the conditional export is gone).
cat > "$w/server/rust-projects.cjs" <<'JS'
function refuseOwnedRoute() {}
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{id}/assets',
  'GET /api/projects/{id}/assets/{assetId}',
  'DELETE /api/projects/{id}/assets/{assetId}',
  'GET /api/projects/{id}/chats',
  'POST /api/projects/{id}/chats',
  'GET /api/freechats',
  'POST /api/freechats',
  'GET /api/chats/{chatId}/context',
]));
JS
g add -A && g commit -qm core-context-get-only; pf="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pf" "$out" >/dev/null 2>"$work/err"; rc=$?
check "GET alone cannot satisfy the permanent context pairing gate" \
  '[ $rc -ne 0 ] && grep -q "POST /api/chats/{}/context$" "$work/err" && [ ! -f "$out/noevia-release-$pf.tar.gz" ]'
awk '/^\]\)\);/ { print "  '\''POST /api/chats/{chatId}/context'\''," } { print }' "$w/server/rust-projects.cjs" > "$work/core.context"
cp "$work/core.context" "$w/server/rust-projects.cjs"
g add -A && g commit -qm core-context-permanent; pg="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pg" "$out" >/dev/null 2>"$work/err"; rc=$?
check "the matched permanent GET/POST context pair assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$pg.tar.gz" ]'
# Reverse mismatch: new core may not be paired with the old switched table.
cat >> "$work/remote/noevia-rs-y/contracts/http/routes.toml" <<'TOML'
switch = "NOEVIA_RUST_PROJECT_WRITES"
TOML
context_lock
g commit -qam rs-context-old-with-permanent-core; pf="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pf" "$out" >/dev/null 2>"$work/err"; rc=$?
check "new permanent core with old switched Rust is refused" \
  '[ $rc -ne 0 ] && grep -q "still gates chat context" "$work/err" && [ ! -f "$out/noevia-release-$pf.tar.gz" ]'
cp "$work/routes.unswitched" "$work/remote/noevia-rs-y/contracts/http/routes.toml"
context_lock
g commit -qam restore-permanent-context
# sbstndalton/noevia#1071: a front that owns sign-in with no switch over a core whose rust-auth guard
# still waits for NOEVIA_RUST_AUTH (which the supervisor no longer passes, so Node would write the
# account tables too) is refused; a core with the unconditional guard (refuseOwned) assembles.
cat >> "$work/remote/noevia-rs-y/contracts/http/routes.toml" <<'TOML'

[[route]]
path = "/api/auth/session"
owner = "rust"
methods = ["GET"]
TOML
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g rm -q apps/web/server/rust-auth.cjs
g commit -qam rs-auth-unswitched; ph="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph" "$out" >/dev/null 2>"$work/err"; rc=$?
check "an unswitched sign-in front over a core without server/rust-auth.cjs is refused" \
  '[ $rc -ne 0 ] && grep -q "still gates its rust-auth guard on NOEVIA_RUST_AUTH" "$work/err" && [ ! -f "$out/noevia-release-$ph.tar.gz" ]'
printf '%s\n' "function enabledFrom(env) { return env.NOEVIA_RUST_AUTH === '1' && env.NOEVIA_RUST_AUTH_CONFIRMED === '1'; }" > "$w/server/rust-auth.cjs"
g add -A && g commit -qm core-switched-auth; pi="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pi" "$out" >/dev/null 2>"$work/err"; rc=$?
check "...and over a core whose guard still waits for the switch" \
  '[ $rc -ne 0 ] && grep -q "still gates its rust-auth guard" "$work/err" && [ ! -f "$out/noevia-release-$pi.tar.gz" ]'
printf '%s\n' "function refuseOwned(req, res, pathname, json) { return false; }" > "$w/server/rust-auth.cjs"
g add -A && g commit -qm core-unconditional-auth; pj="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pj" "$out" >/dev/null 2>"$work/err"; rc=$?
check "the same front over a core with the unconditional guard assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$pj.tar.gz" ]'
# sbstndalton/noevia#1931: a front that still gates sign-in on NOEVIA_RUST_AUTH (a pre-rs#146 pin)
# under this supervisor, which no longer passes that switch, is refused even over a good core.
rt="$work/remote/noevia-rs-y/contracts/http/routes.toml"
awk '{ print } s && /^owner = "rust"$/ { print "switch = \"NOEVIA_RUST_AUTH\""; s = 0 } /^path = "\/api\/auth\/session"$/ { s = 1 }' "$rt" > "$rt.new" && mv "$rt.new" "$rt"
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-y
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g commit -qam rs-auth-switched; pk="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$pk" "$out" >/dev/null 2>"$work/err"; rc=$?
check "a switched sign-in front (pre-rs#146) under this supervisor is refused" \
  '[ $rc -ne 0 ] && grep -q "still gates sign-in on NOEVIA_RUST_AUTH" "$work/err" && [ ! -f "$out/noevia-release-$pk.tar.gz" ]'
g rm -q apps/web/server/rust-auth.cjs && g commit -qm core-no-auth
g rm -q apps/web/server/rust-projects.cjs && g commit -qm core-plain

# sbstndalton/noevia#2096: routes.toml is read as TOML, not as one spelling of it. A switch written
# indented, tab-separated, single-quoted, without spaces or with a trailing comment is still a
# switch (and is refused), a comment that merely mentions a switch is not, and any other switched
# route is refused too instead of being silently left out of the ownership comparison.
rz="$work/remote/noevia-rs-t"
mkdir -p "$rz/bins/noevia-server" "$rz/contracts/http"
echo '[workspace]' > "$rz/Cargo.toml"
echo synthetic > "$rz/bins/noevia-server/Cargo.toml"
cat > "$w/server/rust-projects.cjs" <<'JS'
function refuseOwnedRoute() {}
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{id}/assets',
]));
JS
printf '%s\n' "function refuseOwned(req, res, pathname, json) { return false; }" > "$w/server/rust-auth.cjs"
# try_routes <name>: routes.toml = the sign-in route (unless auth_route=0), then stdin; pins it and assembles. Sets rc, tsha.
try_routes() {
  { [ "${auth_route:-1}" = 0 ] || printf '[[route]]\npath = "/api/auth/session"\nowner = "rust"\nmethods = ["GET"]\n\n'; cat; } > "$rz/contracts/http/routes.toml"
  [ "${omit_routes:-0}" != 1 ] || rm -f "$rz/contracts/http/routes.toml"
  tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-t
  rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
  printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
  [ -z "${try_hook:-}" ] || "$try_hook"
  g add -A && g commit -qm "$1"; tsha="$(g rev-parse --short HEAD)"
  PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$tsha" "$out" >/dev/null 2>"$work/err"; rc=$?
}
refused() { [ $rc -ne 0 ] && grep -q "$1" "$work/err" && [ ! -f "$out/noevia-release-$tsha.tar.gz" ]; }

# Diary native packaging (D4-D5): services that forward to the Rust Diary server (agent/rust_forward.py) are paired
# with a noevia-rs that has the three sources, and their Dockerfile must equal the reviewed template (an allow-list:
# deploy/tools/diary-dockerfile.template) with the lock's pin.
diary_native_try() { try_hook=diary_write_df; try_routes "$1" </dev/null; try_hook=; }
diary_run=""; diary_raw=""; diary_pin_ref=""; diary_pin_sum=""
# diary_raw is a Dockerfile text with __REF__/__SUM__ for the lock's pin; try_hook writes it after try_routes has
# written the lock. Without diary_raw, diary_run is the build stage's RUN of a template-shaped Dockerfile.
diary_write_df() {
  if [ -n "$diary_raw" ]; then
    printf '%s\n' "$diary_raw" | sed -e "s/__REF__/${diary_pin_ref:-$rref}/g" -e "s/__SUM__/${diary_pin_sum:-$rsum}/g" > "$repo/services/diary/Dockerfile"
    return 0
  fi
  [ -n "$diary_run" ] || return 0
  printf 'FROM rust:1 AS tenant-assertion\nARG NOEVIA_RS_REF=%s\nARG NOEVIA_RS_SHA256=%s\n%s\nFROM python:3.12-slim\nCOPY --from=tenant-assertion /out/ /usr/local/bin/\n' \
    "${diary_pin_ref:-$rref}" "${diary_pin_sum:-$rsum}" "$diary_run" > "$repo/services/diary/Dockerfile"
}
dn_build='cargo build --release --locked -p tenant-assertion-cli -p diary-workspace-export -p noevia-diary'
dn_cp='cd target/release && cp tenant-assertion diary-workspace-export noevia-diary /out/'
diary_good="RUN $dn_build && mkdir /out && $dn_cp"
dn_head='FROM rust:1 AS tenant-assertion
ARG NOEVIA_RS_REF=__REF__
ARG NOEVIA_RS_SHA256=__SUM__'
dn_tail='FROM python:3.12-slim
COPY --from=tenant-assertion /out/ /usr/local/bin/'
dn_raw() { diary_raw="$dn_head
$2
$dn_tail${3:-}"; diary_native_try "$1"; diary_raw=""; }
dn_drift='refused "deviates from deploy/tools/diary-dockerfile.template"'
diary_native_try dn-baseline
check "Diary native: without the forwarder nothing about noevia-diary is required" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
mkdir -p "$repo/services/diary/agent"
echo '# synthetic forwarder' > "$repo/services/diary/agent/rust_forward.py"
diary_run="$diary_good"
diary_native_try dn-no-rs-bins
check "Diary native: the forwarder over a noevia-rs without noevia-diary is refused" 'refused "Diary native packaging: services/diary forwards to the Rust Diary server but noevia-rs.*bins/noevia-diary"'
mkdir -p "$rz/bins/noevia-diary" "$rz/bins/tenant-assertion" "$rz/crates/diary-workspace-export"
echo synthetic > "$rz/bins/noevia-diary/Cargo.toml"; echo synthetic > "$rz/bins/tenant-assertion/Cargo.toml"
diary_native_try dn-no-export
check "Diary native: a noevia-rs without the workspace exporter crate is refused" 'refused "Diary native packaging.*crates/diary-workspace-export"'
echo synthetic > "$rz/crates/diary-workspace-export/Cargo.toml"
rm -f "$rz/bins/tenant-assertion/Cargo.toml"
diary_native_try dn-no-assertion
check "Diary native: a noevia-rs without tenant-assertion is refused" 'refused "Diary native packaging.*bins/tenant-assertion"'
echo synthetic > "$rz/bins/tenant-assertion/Cargo.toml"
diary_native_try dn-paired
check "Diary native: the forwarder, all three sources and a template-shaped Dockerfile assemble" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
dn_raw dn-paired-extras "RUN $dn_build && mkdir /out && $dn_cp" '
RUN test -x /usr/local/bin/noevia-diary
COPY agent/ ./agent/
ENV FOO=bar BAZ="a b"
LABEL a=b
EXPOSE 8010'
check "Diary native: the template exact RUN/COPY lines and free-form ENV/LABEL/EXPOSE may follow the install" '[ $rc -eq 0 ]'
diary_pin_ref="$(printf 'd%.0s' $(seq 1 40))"
diary_native_try dn-pin-ref
check "Diary native: a Diary Dockerfile pinned to another noevia-rs ref than the lock is refused" 'refused "NOEVIA_RS_REF differs from release/versions.lock"'
diary_pin_ref=""; diary_pin_sum="$(printf 'e%.0s' $(seq 1 64))"
diary_native_try dn-pin-sum
check "Diary native: a Diary Dockerfile with another noevia-rs checksum than the lock is refused" 'refused "NOEVIA_RS_SHA256 differs from release/versions.lock"'
diary_pin_sum=""
# --- template drift: any change to the build stage or the install shape is refused, however harmless it looks
dn_raw dn-drift-pkg "RUN ${dn_build} -p diary-corpus-parse && mkdir /out && $dn_cp"
check "Diary native: template drift: an extra cargo package is refused" "$dn_drift"
dn_raw dn-drift-flag "RUN ${dn_build/--locked/--locked --offline} && mkdir /out && $dn_cp"
check "Diary native: template drift: an extra cargo flag is refused" "$dn_drift"
dn_raw dn-drift-path "RUN $dn_build && mkdir /out && cp target/release/tenant-assertion target/release/diary-workspace-export target/release/noevia-diary /out/"
check "Diary native: template drift: a different but equivalent copy form is refused" "$dn_drift"
dn_raw dn-drift-pipe "RUN echo x | sha256sum -c - && $dn_build && mkdir /out && $dn_cp"
check "Diary native: template drift: an extra pipe in the build RUN is refused" "$dn_drift"
diary_raw="FROM rust:1 AS tenant-assertion
ARG NOEVIA_RS_REF=__REF__
ARG NOEVIA_RS_SHA256=__SUM__
RUN $dn_build && mkdir /out && $dn_cp
FROM python:3.12-slim AS final-base
COPY --from=tenant-assertion /out/ /usr/local/bin/
FROM final-base"
diary_native_try dn-drift-stages; diary_raw=""
check "Diary native: template drift: a third stage / a different final FROM is refused" "$dn_drift"
diary_raw="$(printf '%s' "$dn_head
RUN $dn_build && mkdir /out && $dn_cp
$dn_tail" | sed 's/^FROM python:3.12-slim$/FROM python:3.13-slim/')"
diary_native_try dn-drift-base; diary_raw=""
check "Diary native: template drift: a changed base image is refused" "$dn_drift"
# --- the old deny-list cases: all refused (they all deviate from the template)
dn_case() { diary_run="$2"; diary_native_try "$1"; }
dn_case dn-neg-nobuild 'RUN cargo build --release --locked -p tenant-assertion-cli -p diary-workspace-export && cp tenant-assertion diary-workspace-export noevia-diary /out/'
check "Diary native: a Dockerfile that never builds noevia-diary is refused" "$dn_drift"
dn_case dn-neg-commented 'RUN cargo build --release -p tenant-assertion-cli
# RUN cargo build --release -p noevia-diary
# RUN cp target/release/noevia-diary /out/'
check "Diary native: whole-line comments are not a build" "$dn_drift"
dn_case dn-neg-inline 'RUN true # cargo build --release -p noevia-diary && cp noevia-diary /out/'
check "Diary native: an inline comment is not a build" "$dn_drift"
dn_case dn-neg-echo 'RUN echo cargo build --release -p noevia-diary && echo cp noevia-diary /out/'
check "Diary native: echo is not a build" "$dn_drift"
dn_case dn-neg-quoted 'RUN "cargo build --release -p noevia-diary" && sh -c "cargo build --release -p noevia-diary && cp target/release/noevia-diary /out/"'
check "Diary native: a quoted string or sh -c is not a build" "$dn_drift"
dn_case dn-neg-heredoc 'RUN <<EOF
cargo build --release -p noevia-diary
cp target/release/noevia-diary /out/
EOF'
check "Diary native: a heredoc body is not a build" "$dn_drift"
dn_case dn-neg-cond 'RUN if [ -d bins/noevia-diary ]; then cargo build --release -p noevia-diary && cp target/release/noevia-diary /out/; fi'
check "Diary native: a build behind a condition is not unconditional" "$dn_drift"
dn_case dn-neg-lookalike 'RUN cargo build --release -p noevia-diary-extra && cp target/release/noevia-diary-extra /out/'
check "Diary native: a package that only starts with the name does not count" "$dn_drift"
dn_case dn-neg-debug 'RUN cargo build -p noevia-diary && cp target/release/noevia-diary /out/'
check "Diary native: a build without --release does not feed target/release" "$dn_drift"
dn_case dn-neg-nocopy "RUN $dn_build && mkdir /out && cp target/release/tenant-assertion /out/"
check "Diary native: a Dockerfile that builds but does not bundle noevia-diary is refused" "$dn_drift"
dn_case dn-neg-fakecp "RUN $dn_build && mkdir /out && cd target/release && fakecp tenant-assertion diary-workspace-export noevia-diary /out/"
check "Diary native: another command spelled like cp is not a bundle" "$dn_drift"
dn_case dn-neg-dest "RUN $dn_build && mkdir /out && cd target/release && cp tenant-assertion diary-workspace-export noevia-diary /out/not-the-binary"
check "Diary native: a copy to another destination is not a bundle" "$dn_drift"
dn_case dn-neg-order "RUN mkdir /out && $dn_cp && $dn_build"
check "Diary native: a copy before the build is not a bundle" "$dn_drift"
dn_case dn-neg-echo-cp "RUN $dn_build && mkdir /out && echo $dn_cp"
check "Diary native: an echoed copy is not a bundle" "$dn_drift"
dn_case dn-neg-inline-cp "RUN $dn_build # && mkdir /out && $dn_cp"
check "Diary native: a copy behind an inline comment is not a bundle" "$dn_drift"
for dn_op in "true || $dn_build" "if false; then $dn_build; fi" "$dn_build; true" "$dn_build &" "($dn_build)" "{ $dn_build; }" "case x in x) $dn_build ;; esac" "while false; do $dn_build; done" "$dn_build | tee /tmp/build.log" "false || true && $dn_build" "exit 0 && $dn_build" "exec true && $dn_build"; do
  dn_raw dn-chain "RUN $dn_op && mkdir /out && $dn_cp"
  check "Diary native: the build behind \`$dn_op\` is refused" "$dn_drift"
done
diary_raw="$dn_head
RUN exec true \\
 && $dn_build \\
 && mkdir /out && $dn_cp
$dn_tail"
diary_native_try dn-exec-continuation; diary_raw=""
check "Diary native: exec across a line continuation is refused" "$dn_drift"
dn_raw dn-mount-tmpfs "RUN --mount=type=tmpfs,target=/out $dn_build && $dn_cp"
check "Diary native: a tmpfs mounted on /out is refused" "$dn_drift"
dn_raw dn-mount-cache "RUN --mount=type=cache,target=/usr/local/cargo/registry $dn_build && mkdir /out && $dn_cp"
check "Diary native: any RUN --mount is refused" "$dn_drift"
dn_raw dn-trailing-from "RUN $dn_build && mkdir /out && $dn_cp" '
FROM python:3.12-slim'
check "Diary native: an install in a discarded stage followed by another FROM is refused" "$dn_drift"
# --- the pin: declared once, never set by ENV in any spelling
diary_raw="FROM rust:1 AS tenant-assertion
ARG NOEVIA_RS_REF=__REF__
ARG NOEVIA_RS_SHA256=__SUM__
ARG NOEVIA_RS_REF=$(printf 'f%.0s' $(seq 1 40))
RUN $dn_build && mkdir /out && $dn_cp
$dn_tail"
diary_native_try dn-arg-dup2; diary_raw=""
check "Diary native: a second NOEVIA_RS_REF declaration is refused" "$dn_drift"
for dn_env in 'ENV NOEVIA_RS_REF=ffff' 'ENV "NOEVIA_RS_REF"=ffff' "ENV 'NOEVIA_RS_SHA256'=ffff" 'ENV NOEVIA_RS\_REF=ffff' 'ENV "NOEVIA_RS_REF" ffff' 'ENV A=1 "NOEVIA_RS_SHA256"=ffff' 'ENV DIARY_CORPUS_PARSE_IMPL=rust' 'ENV DIARY_RUST_ROUTES=/api/months' 'ENV DIARY_RUST_SERVER_BIN=/tmp/x' 'ENV PATH=/tmp/evil:/usr/bin' 'ENV LD_PRELOAD=/tmp/x.so' 'ENV PYTHONPATH=/tmp' 'ENV OTHER_BIN=/x' 'ENV "PATH"=/tmp/evil' 'ENV "A"=1' 'ENV A\_B=1'; do
  dn_raw dn-env "RUN $dn_build && mkdir /out && $dn_cp" "
$dn_env"
  check "Diary native: final-stage \`$dn_env\` is refused" "$dn_drift"
done
# --- what may follow the install, and what may not (the delta review of 90cbea1c)
for dn_after in 'ENTRYPOINT ["/bin/true"]' 'CMD ["/bin/true"]' 'USER nonexistent' 'WORKDIR /usr/local/bin' 'HEALTHCHECK CMD rm -f /usr/local/bin/noevia-diary' 'HEALTHCHECK NONE' 'COPY evil /usr/local/bin/noevia-diary' 'RUN rm -f /usr/local/bin/noevia-diary' 'RUN rm /usr/local/bin/noevia-diary' 'ONBUILD RUN rm /usr/local/bin/noevia-diary' 'ADD x /usr/local/bin/noevia-diary' 'COPY --chmod=0644 --from=tenant-assertion /out/ /usr/local/bin/' 'COPY --from=tenant-assertion /out/ /usr/local/bin/' 'ARG X=1' 'SHELL ["/bin/false"]' 'VOLUME /usr/local/bin'; do
  dn_raw dn-after "RUN $dn_build && mkdir /out && $dn_cp" "
$dn_after"
  check "Diary native: after the install, \`$dn_after\` is refused" "$dn_drift"
done
diary_raw="$dn_head
RUN $dn_build && mkdir /out && $dn_cp
FROM python:3.12-slim
COPY --chmod=0644 --from=tenant-assertion /out/ /usr/local/bin/"
diary_native_try dn-chmod; diary_raw=""
check "Diary native: COPY --chmod making the installed binary non-executable is not the install" "$dn_drift"
for dn_dir in '# syntax=evil/frontend' '# SyNtAx=evil/frontend' '#escape=`' '# EsCaPe = `' '#   CHECK=skip=all' '# foo=bar'; do
  diary_raw="$dn_dir
$dn_head
RUN $dn_build && mkdir /out && $dn_cp
$dn_tail"
  diary_native_try dn-directive; diary_raw=""
  check "Diary native: the leading parser directive \`$dn_dir\` is refused" "$dn_drift"
done
diary_raw="# a plain comment about FOO and bar, not a key=value directive
$dn_head
RUN $dn_build && mkdir /out && $dn_cp
$dn_tail"
diary_native_try dn-comment-ok; diary_raw=""
check "Diary native: an ordinary leading comment is fine" '[ $rc -eq 0 ]'
# --- continuations are joined the way Docker joins them: a backslash-newline is removed with nothing inserted
diary_raw="$dn_head
RUN cargo\\
build --release --locked -p tenant-assertion-cli -p diary-workspace-export -p noevia-diary && mkdir /out && $dn_cp
$dn_tail"
diary_native_try dn-cont-split; diary_raw=""
check "Diary native: cargo<backslash-newline>build (joined to cargobuild) is refused" "$dn_drift"
diary_raw="$dn_head
RUN $dn_build \\
 && mkdir /out \\
 && $dn_cp
$dn_tail"
diary_native_try dn-cont-ok; diary_raw=""
check "Diary native: continuation lines that keep their separating space still match the template" '[ $rc -eq 0 ]'
# --- continuation by an odd number of backslashes only; an even count is refused; only printable ASCII, tab, LF/CRLF
dn_bs2='\\'
diary_raw="$dn_head
RUN $dn_build && mkdir /out && $dn_cp
$dn_tail
LABEL review=ok$dn_bs2
RUN rm -f /usr/local/bin/noevia-diary"
diary_native_try dn-even-backslash; diary_raw=""
check "Diary native: a line ending in an even number of backslashes (the reviewer's LABEL review=ok\\\\ then RUN rm) is refused" "$dn_drift"
diary_raw="$dn_head
RUN $dn_build && mkdir /out && $dn_cp
$dn_tail
LABEL review=ok\\
RUN rm -f /usr/local/bin/noevia-diary"
diary_native_try dn-odd-backslash; diary_raw=""
check "Diary native: a single trailing backslash continues the LABEL, as Docker does, so the RUN is not an instruction of its own" '[ $rc -eq 0 ]'
for dn_bad in "LABEL a=b$(printf '\r')RUN rm -f /usr/local/bin/noevia-diary" "LABEL a=b$(printf '\v')x" "LABEL a=b$(printf '\f')x" "LABEL a=b$(printf '\302\240')x" "# caf$(printf '\303\251')" "LABEL a=b$(printf '\177')" "ENV A=1$(printf '\r')PATH=/tmp" "ENV A=1$(printf '\v')PATH=/tmp" "ENV A=1$(printf '\f')PATH=/tmp" "ENV A=1$(printf '\302\240')PATH=/tmp"; do
  dn_raw dn-bytes "RUN $dn_build && mkdir /out && $dn_cp" "
$dn_bad"
  check "Diary native: a forbidden byte is refused: $(printf '%s' "$dn_bad" | od -An -c | tr -s ' ' | cut -c1-70)" "$dn_drift"
done
dn_raw dn-tab "RUN $dn_build && mkdir /out && $dn_cp" "
ENV A=1$(printf '\t')B=2"
check "Diary native: a tab between ENV words is fine (it separates words like a space)" '[ $rc -eq 0 ]'
# --- the REAL template: it renders a Dockerfile it accepts, and every drift of that rendering is refused
dfsrc="$work/dfcheck.sh"; sed -n '/^# BEGIN diary-df-check/,/^# END diary-df-check/p' "$here/assemble-release.sh" > "$dfsrc"; . "$dfsrc"
rtpl="$here/diary-dockerfile.template"; rref="$(printf '1%.0s' $(seq 1 40))"; rsum2="$(printf '2%.0s' $(seq 1 64))"
awk '/^#/ || /^$/ {next} /^\[/ {s=$0; next}
  s=="[build-stage]" {b[++nb]=$0} s=="[final-from]" {ff=$0} s=="[install]" {ins=$0} s=="[final-runtime]" {rt[++nrt]=$0} s=="[env-fixed]" {e[++ne]=$0} s=="[final-allowed]" {a[++na]=substr($0,3)}
  END {for(i=1;i<=nb;i++)print b[i]; print ff; print ins; for(i=1;i<=ne;i++)print "ENV " e[i]; for(i=1;i<=nrt;i++)print rt[i]; for(i=1;i<=na;i++)print a[i]}' "$rtpl" \
  | sed -e "s/@NOEVIA_RS_REF@/$rref/g" -e "s/@NOEVIA_RS_SHA256@/$rsum2/g" > "$work/real.df"
rcheck() { diary_dockerfile_check "$rtpl" "$rref" "$rsum2" "$1"; }
rmut() { # rmut <name> <python-expression on t>: writes the mutated rendering to $work/mut.df
  python3 - "$work/real.df" "$work/mut.df" "$2" <<'PY'
import sys
t = open(sys.argv[1], newline='').read()
exec(sys.argv[3])
open(sys.argv[2], 'w', newline='', encoding='utf-8').write(t)
PY
}
check "Diary native: the real template accepts the Dockerfile rendered from it" '[ "$(rcheck "$work/real.df")" = ok ]'
check "Diary native: the real template has the pinned cargo build of noevia-diary, the bundle and the install" \
  'grep -q -- "-p noevia-diary" "$rtpl" && grep -q "cp .* noevia-diary /out/" "$rtpl" && grep -qx "COPY --from=tenant-assertion /out/ /usr/local/bin/" "$rtpl"'
for dn_m in \
  't += "ENV \"NOEVIA_RS_REF\"=ffff\n"' \
  't += "ENV NOEVIA_RS\\_SHA256=ffff\n"' \
  't = t.replace(" && cargo build", " && exit 0 && cargo build", 1)' \
  't = t.replace(" && cargo build", " && exec true \\\n && cargo build", 1)' \
  't += "COPY evil /usr/local/bin/noevia-diary\n"' \
  't += "RUN rm -f /usr/local/bin/noevia-diary\n"' \
  't += "ONBUILD RUN rm /usr/local/bin/noevia-diary\n"' \
  't = t.replace("COPY --from=tenant-assertion /out/", "COPY --chmod=0644 --from=tenant-assertion /out/", 1)' \
  't += "ENV DIARY_RUST_ROUTES=/api/months\n"' \
  't += "ENTRYPOINT [\"/bin/true\"]\n"' \
  't += "CMD [\"/bin/true\"]\n"' \
  't += "USER nonexistent\n"' \
  't = t.replace("WORKDIR /app", "WORKDIR /usr/local/bin", 1)' \
  't = t.replace("HEALTHCHECK --interval=60s", "HEALTHCHECK --interval=60s CMD rm -f /usr/local/bin/noevia-diary #", 1)' \
  't = t.replace("HEALTHCHECK", "HEALTHCHECK NONE\n#", 1)' \
  'import re; m = re.search(r"(?m)^WORKDIR /app\n", t); t = t.replace(m.group(0), "", 1) + m.group(0)' \
  't += "ENV PATH=/tmp/evil:/usr/bin\n"' \
  't += "ENV LD_PRELOAD=/tmp/x.so\n"' \
  't += "ENV PYTHONPATH=/tmp\n"' \
  't += "ENV OTHER_BIN=/x\n"' \
  't = "# SyNtAx=evil/frontend\n" + t' \
  't = "# EsCaPe=`\n" + t' \
  't = t.replace("cargo build --release", "cargo\\\nbuild --release", 1)' \
  't += "LABEL review=ok\\\\\nRUN rm -f /usr/local/bin/noevia-diary\n"' \
  't += "LABEL a=b\rRUN rm -f /usr/local/bin/noevia-diary\n"' \
  't += "LABEL a=b\r"' \
  't += "LABEL a=b\x0bx\n"' \
  't += "LABEL a=b\x0cx\n"' \
  't += "LABEL a=b\xa0x\n"' \
  't += "LABEL a=b\x00PATH=/x\n"' \
  't += "LABEL a=b\x7f\n"' \
  't += "# caf\xe9\n"' \
  't += "ENV A=1\rPATH=/tmp\n"' \
  't += "ENV A=1\x0bPATH=/tmp\n"' \
  't += "ENV A=1\x0cPATH=/tmp\n"' \
  't += "ENV A=1\xa0PATH=/tmp\n"' \
  't += "ENV A=1\tPATH=/tmp\n"' \
  't += "ENV \"A\"=1\n"' \
  't += "ENV A\\_B=1\n"' \
  't = t.replace("--locked", "--locked --offline", 1)' \
  't = t.replace("python:3.12-slim", "python:3.13-slim", 1)' \
  't = t.replace(" -p noevia-diary", "", 1)' \
  't = t.replace("RUN python scripts/smoke_diary_leaves.py --all\n", "", 1)' \
  't += "COPY --from=tenant-assertion /out/ /usr/local/bin/\n"' \
  't += "FROM python:3.12-slim\n"'; do
  rmut x "$dn_m"
  check "Diary native: the real template refuses $dn_m" '[ "$(rcheck "$work/mut.df")" != ok ]'
done
# Every CR byte counts, not lines (delta review of b6852b3c): an interior CR on a line that also ends in CRLF, a CR
# directly before the final CRLF, and a file mixing LF and CRLF endings are all refused.
dn_crlf='t = t.replace("\n", "\r\n"); '
for dn_m in \
  "${dn_crlf}"'t += "ENV A=1\rPATH=/tmp\r\n"' \
  "${dn_crlf}"'t += "ENV A=1\rDIARY_RUST_ROUTES=/api/months\r\n"' \
  "${dn_crlf}"'t += "ENV A=1\rDIARY_RUST_WRITES=synthetic\r\n"' \
  "${dn_crlf}"'t += "LABEL a=b\r\r\n"' \
  "${dn_crlf}"'t += "\r\r\n"' \
  't += "ENV A=1\rPATH=/tmp\r\n"' \
  't += "ENV A=1\rDIARY_RUST_ROUTES=/api/months\r\n"' \
  't += "ENV A=1\rDIARY_RUST_WRITES=synthetic\r\n"' \
  't += "LABEL a=b\r\r\n"' \
  't += "LABEL a=b\r\n"' \
  "${dn_crlf}"'t += "LABEL a=b\n"' \
  "${dn_crlf}"'t = t[:-2]'; do
  rmut x "$dn_m"
  check "Diary native: the real template refuses the CR/ending case: $dn_m" '[ "$(rcheck "$work/mut.df")" != ok ]'
done
rmut x "${dn_crlf}"'t += "LABEL a=b\r\n"'
check "Diary native: an all-CRLF file with only line-ending CRs is still accepted" '[ "$(rcheck "$work/mut.df")" = ok ]'
rmut x 't += "ENV FOO=bar PYTHONUNBUFFERED=1\nLABEL a=b\nEXPOSE 8010\n"'
check "Diary native: the real template still accepts harmless ENV/LABEL/EXPOSE additions" '[ "$(rcheck "$work/mut.df")" = ok ]'
# the template is normalized like the Dockerfile: wrapping its long lines with backslash-newline changes nothing
sed -e 's/ && / \\\
    \&\& /g' "$rtpl" > "$work/wrapped.tpl"
check "Diary native: the real template wrapped with line continuations still accepts the rendering" \
  '[ "$(diary_dockerfile_check "$work/wrapped.tpl" "$rref" "$rsum2" "$work/real.df")" = ok ] && grep -q " \\\\$" "$work/wrapped.tpl"'
sed "s/\$/$(printf '\r')/" "$work/real.df" > "$work/crlf.df"
check "Diary native: the real template accepts the same Dockerfile with CRLF line endings" '[ "$(rcheck "$work/crlf.df")" = ok ]'
rmut x 't = t.replace("'"$rref"'", "'"$(printf '3%.0s' $(seq 1 40))"'")'
check "Diary native: the real template refuses a pin that is not the lock's" '[ "$(rcheck "$work/mut.df")" != ok ]'
if [ -n "${NOEVIA_SERVICES_DIR:-}" ] && [ -f "$NOEVIA_SERVICES_DIR/diary/Dockerfile" ]; then
  svc_ref="$(sed -n 's/^ARG NOEVIA_RS_REF=//p' "$NOEVIA_SERVICES_DIR/diary/Dockerfile" | head -1)"; svc_sum="$(sed -n 's/^ARG NOEVIA_RS_SHA256=//p' "$NOEVIA_SERVICES_DIR/diary/Dockerfile" | head -1)"
  check "Diary native: the real template accepts the real services Diary Dockerfile (NOEVIA_SERVICES_DIR)" '[ "$(diary_dockerfile_check "$rtpl" "$svc_ref" "$svc_sum" "$NOEVIA_SERVICES_DIR/diary/Dockerfile")" = ok ]'
fi
# The REAL services Diary Dockerfile at the lock's NOEVIA_SERVICES_REF (ae1e13ef, a byte copy in fixtures/, 
# 20da02ca...). It must pass the template against the lock's own pin, and a Dockerfile with an extra unknown COPY or a
# changed ENTRYPOINT must still be refused.
svc_df="$here/fixtures/services-diary-Dockerfile.ae1e13ef"
lk_ref="$(sed -n 's/^NOEVIA_RS_REF=//p' "$here/../../release/versions.lock" | head -1)"; lk_sum="$(sed -n 's/^NOEVIA_RS_SHA256=//p' "$here/../../release/versions.lock" | head -1)"
check "Diary native: the real template accepts the pinned services Diary Dockerfile (ae1e13ef) against the lock pin" \
  '[ "$(diary_dockerfile_check "$rtpl" "$lk_ref" "$lk_sum" "$svc_df")" = ok ]'
sed 's/^ENTRYPOINT \["diary-entrypoint"\]$/COPY evil \/usr\/local\/bin\/evil\n&/' "$svc_df" > "$work/real-extra-copy.df"
check "Diary native: the pinned services Dockerfile plus an unknown COPY is refused" \
  '[ "$(diary_dockerfile_check "$rtpl" "$lk_ref" "$lk_sum" "$work/real-extra-copy.df")" != ok ] && diary_dockerfile_check "$rtpl" "$lk_ref" "$lk_sum" "$work/real-extra-copy.df" | grep -q "^bad: "'
sed 's/^ENTRYPOINT \["diary-entrypoint"\]$/ENTRYPOINT ["\/bin\/true"]/' "$svc_df" > "$work/real-entrypoint.df"
check "Diary native: the pinned services Dockerfile with a changed ENTRYPOINT is refused" \
  '! grep -qx "ENTRYPOINT \[\"/bin/true\"\]" "$svc_df" && grep -qx "ENTRYPOINT \[\"/bin/true\"\]" "$work/real-entrypoint.df" && [ "$(diary_dockerfile_check "$rtpl" "$lk_ref" "$lk_sum" "$work/real-entrypoint.df")" != ok ] && diary_dockerfile_check "$rtpl" "$lk_ref" "$lk_sum" "$work/real-entrypoint.df" | grep -q "^bad: "'
diary_raw=""
# Leave the fixture as it was for the checks below: no forwarder, the synthetic Dockerfile, no Diary sources.
g rm -q -f services/diary/agent/rust_forward.py
echo "synthetic diary" > "$repo/services/diary/Dockerfile"
diary_run=""
rm -rf "$rz/bins/noevia-diary" "$rz/bins/tenant-assertion" "$rz/crates"
g add -A && g commit -qm dn-restore

# #1071 web-address GET read pairing: either side alone fails; exact three pair, other
# methods remain with Node. The synthetic core guard mirrors its exported source contract.
cat > "$w/server/rust-web-address.cjs" <<'JS'
const WEB_ADDRESS_READ_OWNER = 'noevia-web-address-read-rust/1';
const OWNED_GET_PATHS = Object.freeze(['/api/instance', '/.well-known/webauthn', '/api/admin/web-address']);
const ROUTE_REFUSAL = {};
function ownedRead(method, pathname) {
  return method === 'GET' && OWNED_GET_PATHS.includes(pathname);
}
function refuseOwnedRead(req, res, pathname, json) { if (!ownedRead(req.method, pathname)) return false; json(res, 503, ROUTE_REFUSAL); return true; }
module.exports = { WEB_ADDRESS_READ_OWNER, OWNED_GET_PATHS, ROUTE_REFUSAL, ownedRead, refuseOwnedRead };
JS
printf '%s\n' "    if (require('./rust-web-address.cjs').refuseOwnedRead(req, res, p, json)) return;" >> "$w/server/index.cjs"
mkdir -p "$rz/bins/noevia-server/src" "$repo/build"
printf '%s\n' 'pub const FEATURES: &[&str] = &["rust-web-address-read"];' > "$rz/bins/noevia-server/src/lib.rs"
cp "$here/../../build/web-supervisor.sh" "$repo/build/web-supervisor.sh"
try_routes web-core-only </dev/null
check "#1071 web-address: core refusal without Rust GETs is refused" 'refused "web-address ownership pairing"'
web_routes() {
  for path in '/api/instance' '/.well-known/webauthn' '/api/admin/web-address'; do
    [ "$path" = "${web_skip:-}" ] && continue
    method=GET
    [ "$path" = "${web_extra_path:-}" ] && method='GET", "POST'
    printf '[[route]]\npath = "%s"\nowner = "rust"\nmethods = ["%s"]\n\n' "$path" "$method"
  done
}
web_try() { web_routes > "$work/web-routes"; try_routes "$1" < "$work/web-routes"; }
web_try web-paired
check "#1071 web-address: exact three GETs pair with Node refusal" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
cp "$rz/bins/noevia-server/src/lib.rs" "$work/web-features.saved"
printf '%s\n' '//! "rust-web-address-read" is planned' > "$rz/bins/noevia-server/src/lib.rs"
web_try web-feature-comment-only
check "#1071 web-address: a comment does not grant the compiled feature" 'refused "lacks a compiled --features declaration"'
printf '%s\n' 'pub const OTHER: &[&str] = &["rust-web-address-read"];' 'pub const FEATURES: &[&str] = &[];' > "$rz/bins/noevia-server/src/lib.rs"
web_try web-feature-outside-list
check "#1071 web-address: a feature outside FEATURES does not grant the capability" 'refused "lacks a compiled --features declaration"'
cp "$work/web-features.saved" "$rz/bins/noevia-server/src/lib.rs"
omit_routes=1 web_try web-no-routes
check "#1071 web-address: ported core with missing Rust routes.toml is refused" 'refused "web-address GET ownership pairing: core refuses GETs but Rust routes.toml is missing"'
for web_skip in '/api/instance' '/.well-known/webauthn' '/api/admin/web-address'; do
  web_try "web-missing-${web_skip##*/}"
  check "#1071 web-address: Rust missing $web_skip is refused individually" 'refused "web-address ownership pairing"'
done
unset web_skip
web_extra_path='/api/admin/web-address' web_try web-post-too
check "#1071 web-address: Rust POST ownership is refused" 'refused "web-address ownership pairing"'
sed -i.bak "s#'/api/admin/web-address'##" "$w/server/rust-web-address.cjs" && rm -f "$w/server/rust-web-address.cjs.bak"
web_try web-core-missing-admin
check "#1071 web-address: core missing one GET refusal is refused" 'refused "web-address ownership pairing"'
# The dependent writer pair adds both POSTs, an exported Node marker, and a hard
# settings guard. Either POST alone, or a comment-only feature, cannot assemble.
cat > "$w/server/rust-web-address.cjs" <<'JS'
const WEB_ADDRESS_READ_OWNER = 'noevia-web-address-read-rust/1';
const WEB_ADDRESS_WRITE_OWNER = 'noevia-web-address-write-rust/1';
const OWNED_GET_PATHS = Object.freeze(['/api/instance', '/.well-known/webauthn', '/api/admin/web-address']);
const OWNED_POST_PATHS = Object.freeze(['/api/admin/web-address', '/api/admin/web-address/remove']);
const ROUTE_REFUSAL = {};
const WRITE_REFUSAL = {};
function ownedRead(method, pathname) {
  return method === 'GET' && OWNED_GET_PATHS.includes(pathname);
}
function ownedWrite(method, pathname) {
  return method === 'POST' && OWNED_POST_PATHS.includes(pathname);
}
function refuseOwnedRead() {}
function refuseOwnedWrite() {}
function refuseOwned(req, res, pathname, json) {
  return refuseOwnedRead(req, res, pathname, json) || refuseOwnedWrite(req, res, pathname, json);
}
module.exports = { WEB_ADDRESS_READ_OWNER, WEB_ADDRESS_WRITE_OWNER, OWNED_GET_PATHS, OWNED_POST_PATHS, ROUTE_REFUSAL, WRITE_REFUSAL, ownedRead, ownedWrite, refuseOwnedRead, refuseOwnedWrite, refuseOwned };
JS
sed -i.bak "s#refuseOwnedRead(req, res, p, json)#refuseOwned(req, res, p, json)#" "$w/server/index.cjs" && rm -f "$w/server/index.cjs.bak"
cp "$w/server/rust-auth.cjs" "$work/web-rust-auth.saved"
printf "%s\n" "  previous_origins: ['Web address changes are owned by the Rust front.', 'RUST_WEB_ADDRESS_WRITE_OWNED']," >> "$w/server/rust-auth.cjs"
web_writer_routes() {
  printf '[[route]]\npath = "/api/instance"\nowner = "rust"\nmethods = ["GET"]\n\n'
  printf '[[route]]\npath = "/.well-known/webauthn"\nowner = "rust"\nmethods = ["GET"]\n\n'
  printf '[[route]]\npath = "/api/admin/web-address"\nowner = "rust"\nmethods = ["GET", "POST"]\n\n'
  [ "${web_writer_skip:-}" = remove ] || printf '[[route]]\npath = "/api/admin/web-address/remove"\nowner = "rust"\nmethods = ["POST"]\nclient = false\n\n'
}
web_writer_try() { web_writer_routes > "$work/web-writer-routes"; try_routes "$1" < "$work/web-writer-routes"; }
web_try web-write-core-over-GET-only
check "#1071 web-address POST: writer core over GET-only routes is refused" 'refused "web-address ownership pairing"'
web_writer_try web-write-core-only
check "#1071 web-address POST: writer core without compiled writer feature is refused" 'refused "web-address POST ownership pairing"'
printf '%s\n' 'pub const FEATURES: &[&str] = &["rust-web-address-read", "rust-web-address-write"];' > "$rz/bins/noevia-server/src/lib.rs"
web_writer_try web-write-paired
check "#1071 web-address POST: both writers pair with Node refusal" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# The real lib.rs documents routes such as `/v1/chatgpt/*` in its `///` lines: a `/*` there is not a block comment, and
# must not hide the FEATURES list that follows (the assembler found no capability in the real file since 2026-10-29).
printf '%s\n' '/// the internal store (`/v1/chatgpt/*`) and the routes the paired core refuses' 'pub const FEATURES: &[&str] = &["rust-web-address-read", "rust-web-address-write"];' > "$rz/bins/noevia-server/src/lib.rs"
web_writer_try web-write-slash-star-doc
check "a '/*' inside a /// doc line does not hide the FEATURES list" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
printf '%s\n' 'pub const FEATURES: &[&str] = &["rust-web-address-read", "rust-web-address-write"];' > "$rz/bins/noevia-server/src/lib.rs"
cp "$w/server/rust-web-address.cjs" "$work/web-write-core.saved"
sed -i.bak 's#return refuseOwnedRead(req, res, pathname, json) || refuseOwnedWrite(req, res, pathname, json);#return refuseOwnedRead(req, res, pathname, json);#' "$w/server/rust-web-address.cjs" && rm -f "$w/server/rust-web-address.cjs.bak"
web_writer_try web-write-unwired
check "#1071 web-address POST: exported marker without invoked POST refusal cannot pair" 'refused "web-address ownership pairing"'
cp "$work/web-write-core.saved" "$w/server/rust-web-address.cjs"
web_writer_skip=remove web_writer_try web-write-missing-remove
check "#1071 web-address POST: missing removal cannot pair" 'refused "web-address ownership pairing"'
printf '%s\n' '//! "rust-web-address-write" planned' 'pub const FEATURES: &[&str] = &["rust-web-address-read"];' > "$rz/bins/noevia-server/src/lib.rs"
web_writer_try web-write-comment-feature
check "#1071 web-address POST: comment-only feature cannot pair" 'refused "web-address POST ownership pairing"'
rm -f "$rz/bins/noevia-server/src/lib.rs"
g rm -q apps/web/server/rust-web-address.cjs build/web-supervisor.sh
cp "$work/web-rust-auth.saved" "$w/server/rust-auth.cjs"
sed -i.bak "/require('.\/rust-web-address.cjs').refuseOwnedRead/d" "$w/server/index.cjs" && rm -f "$w/server/index.cjs.bak"
g add -A && g commit -qm web-guard-fixture-restored

try_routes comments-only <<'TOML'
# The old switch = "NOEVIA_RUST_PROJECTS" and switch = "NOEVIA_RUST_PROJECT_WRITES" are retired.
[[route]]
  # switch = "NOEVIA_RUST_PROJECTS"
path = "/api/projects/{id}/assets"
owner = "rust" # not switch = "NOEVIA_RUST_AUTH"
methods = ["POST"]
TOML
check "#2096: comments that name a switch do not refuse the assembly" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

try_routes indented <<'TOML'
[[route]]
  path = "/api/projects/{id}/assets"
  owner = "rust"
  switch = "NOEVIA_RUST_PROJECTS"
  methods = ["POST"]
TOML
check "#2096: an indented project switch is refused" 'refused "still gates the project routes on NOEVIA_RUST_PROJECTS"'

printf '[[route]]\npath = "/api/projects/{id}/assets"\nowner = "rust"\nswitch\t=\t"NOEVIA_RUST_PROJECTS"\nmethods = ["POST"]\n' > "$work/t.toml"
try_routes tabbed < "$work/t.toml"
check "#2096: a tab-separated project switch is refused" 'refused "still gates the project routes on NOEVIA_RUST_PROJECTS"'

try_routes single-quoted <<'TOML'
[[route]]
path = '/api/projects/{id}/assets'
owner = 'rust'
switch = 'NOEVIA_RUST_PROJECTS'
methods = ['POST']
TOML
check "#2096: a single-quoted project switch is refused" 'refused "still gates the project routes on NOEVIA_RUST_PROJECTS"'

try_routes tight-trailing <<'TOML'
[[route]]
path = "/api/chats/{id}/context"
owner = "rust"
switch="NOEVIA_RUST_PROJECT_WRITES"   # old
methods = ["GET", "POST"]
TOML
check "#2096: a spaceless context switch with a trailing comment is refused" 'refused "still gates chat context on NOEVIA_RUST_PROJECT_WRITES"'

auth_route=0 try_routes auth-indented <<'TOML'
[[route]]
path = "/api/auth/session"
owner = "rust"
    switch = 'NOEVIA_RUST_AUTH'
methods = ["GET"]
TOML
check "#2096: an indented sign-in switch is refused" 'refused "still gates sign-in on NOEVIA_RUST_AUTH"'

try_routes unknown-switch <<'TOML'
[[route]]
path = "/api/usage"
owner = "rust"
switch = "NOEVIA_RUST_SOMETHING_ELSE"
methods = ["GET"]
TOML
check "#2096: a route with any other switch is refused (fail closed)" 'refused "has switched routes in routes.toml (NOEVIA_RUST_SOMETHING_ELSE /api/usage)"'

printf '[[route]]\npath = "/api/usage"\nowner = "node"\n\tswitch = "NOEVIA_RUST_SOMETHING_ELSE"\n' > "$work/t.toml"
try_routes unknown-switch-node < "$work/t.toml"
check "#2096: ...whatever the owner and however it is spelled" 'refused "has switched routes in routes.toml"'

try_routes other-table <<'TOML'
[meta]
switch = "NOT_A_ROUTE_SWITCH"

[[route]]
path = "/api/projects/{id}/assets"
owner = "rust"
methods = ["POST"]
TOML
check "#2096: a switch key outside a [[route]] table is not a route switch" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# Multi-line methods arrays, indentation, a spaced [[ route ]] header and CRLF line endings are read
# the same: PUT is not in the core's OWNED_ROUTES, so the assembly is refused naming exactly it.
{
  printf '[[ route ]]\r\n  path = "/api/projects/{id}/assets"\r\n  owner = "rust"\r\n'
  printf '  methods = [\r\n    "POST", # listed\r\n    "PUT",\r\n  ]\r\n'
} > "$work/t.toml"
try_routes multiline-crlf < "$work/t.toml"
check "#2096: multi-line methods in CRLF TOML are compared per method" 'refused "PUT /api/projects/{}/assets"'
check "#2096: ...and POST, which the core lists, is not named" '! grep -q "POST /api/projects" "$work/err"'

# #2096 review: the reader fails closed. Anything it cannot classify is an error naming the line,
# never a switch that quietly reads as absent.
unreadable() { refused "routes.toml cannot be read safely.*line"; }
bom="$(printf '\357\273\277')"
proj='path = "/api/projects/{id}/assets"\nowner = "rust"\nmethods = ["POST"]\n'
auth='[[route]]\npath = "/api/auth/session"\nowner = "rust"\nmethods = ["GET"]\n\n'

printf "${bom}[[route]]\n${proj}switch = \"NOEVIA_RUST_PROJECTS\"\n" > "$work/t.toml"
auth_route=0 try_routes bom-switched < "$work/t.toml"
check "#2096: a switch after a leading BOM is still found and refused" 'refused "still gates the project routes on NOEVIA_RUST_PROJECTS"'
printf "${bom}${auth}[[route]]\n${proj}" > "$work/t.toml"
auth_route=0 try_routes bom-clean < "$work/t.toml"
check "#2096: ...and a clean file with a BOM assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

printf '[["route"]]\npath = "/api/projects/{id}/assets"\nowner = "rust"\nswitch = "NOEVIA_RUST_PROJECTS"\nmethods = ["POST"]\n' > "$work/t.toml"
try_routes quoted-header < "$work/t.toml"
check "#2096: a quoted [[\"route\"]] header is an error, not skipped" 'unreadable'

printf "route = [ { path = \"/api/projects/{id}/assets\", owner = \"rust\", switch = \"NOEVIA_RUST_PROJECTS\" } ]\n\n${auth}" > "$work/t.toml"
auth_route=0 try_routes inline-route < "$work/t.toml"
check "#2096: a top-level route = [ {...} ] inline array is an error" 'unreadable'

printf "[[route]]\n${proj}switch.x = \"NOEVIA_RUST_PROJECTS\"\n" > "$work/t.toml"
try_routes dotted-key < "$work/t.toml"
check "#2096: a dotted key inside a route is an error" 'unreadable'

printf "[[route]]\n${proj}this is not toml\n" > "$work/t.toml"
try_routes unclassified < "$work/t.toml"
check "#2096: any other unclassifiable line in a route is an error" 'unreadable'

printf "[[route.sub]]\nswitch = \"X\"\n" > "$work/t.toml"
try_routes route-subtable < "$work/t.toml"
check "#2096: a sub-table of route is an error" 'unreadable'

printf 'path = "/api/projects/{id}/assets"\n[[route]]\npath = "/api/usage"\nmethods = ["GET",\n' > "$work/t.toml"
try_routes unterminated-array < "$work/t.toml"
check "#2096: an unterminated array is an error" 'unreadable'

printf "[[route]]\npath = \"/api/projects/{id}/assets\"\nowner = \"rust\"\nmethods = [\n  \"POST#note\", \"PUT\", # PUT is listed\n]\n" > "$work/t.toml"
try_routes hash-in-array < "$work/t.toml"
check "#2096: a # inside a quoted array element is text, so PUT after it is still compared" 'refused "PUT /api/projects/{}/assets"'

printf "[[route]]\npath = \"/api/projects/{id}/assets\"\nowner = \"\"\"rust\"\"\"\nswitch = \"NOEVIA_RUST_PROJECTS\"\n" > "$work/t.toml"
try_routes triple-in-route < "$work/t.toml"
check "#2096: a \"\"\" multi-line string in a route is refused explicitly" 'unreadable && grep -q "multi-line strings are not read" "$work/err"'

printf "[meta]\nnote = '''\n[[route]]\nswitch = \"X\"\n'''\n\n[[route]]\npath = \"/api/projects/{id}/assets\"\nowner = \"rust\"\nmethods = [\"POST\"]\n" > "$work/t.toml"
try_routes triple-in-meta < "$work/t.toml"
check "#2096: ...and in another table, where it could hide a header" 'unreadable && grep -q "multi-line strings are not read" "$work/err"'


# Slice7 exact declarations/exports, real delegation/refusal, method and owner matrix.
mkdir -p "$rz/crates/server-projects/src" "$rz/bins/noevia-server/src" "$w/server/routes"
echo 'pub const MOVE_MARKER: &str = "noevia-chat-move-foundation/1";' > "$rz/crates/server-projects/src/chat_move.rs"
echo 'pub const CHAT_MOVE_JOURNAL_MARKER: &str = "noevia-chat-move-journal/1";' > "$rz/crates/server-projects/src/journal.rs"
echo 'pub const FEATURES: &[&str] = &["start-id"];' > "$rz/bins/noevia-server/src/lib.rs"
echo 'fn route() { let op = "/v1/changes/read"; }' > "$rz/bins/noevia-server/src/main.rs"
cat > "$w/server/project-store-client.cjs" <<'JS'
const CHAT_MOVE_CLIENT_MARKER = 'noevia-chat-move-client/1';
module.exports = { CHAT_MOVE_CLIENT_MARKER };
JS
cat > "$w/server/chat.cjs" <<'JS'
const CHAT_MOVE_ENFORCEMENT_MARKER = 'noevia-chat-move-enforcement/1';
module.exports = { CHAT_MOVE_ENFORCEMENT_MARKER };
JS
cat > "$w/server/chat-change-journal.cjs" <<'JS'
const JOURNAL_READER_MARKER = 'noevia-chat-change-journal-reader/1';
const CHAT_MOVE_READER_MARKER = 'noevia-chat-move-reader/1';
module.exports = { CHAT_MOVE_READER_MARKER, JOURNAL_READER_MARKER };
JS
cat > "$w/server/routes/chat-lists.cjs" <<'JS'
async function chatMoveRoute(store,user,chat,target) {
  return store.chatMove(user,chat,target);
}
module.exports = { chatMoveRoute };
JS
cat > "$w/server/rust-projects.cjs" <<'JS'
const CHAT_MOVE_PUBLIC_OWNER = 'node';
function refuseOwnedRoute() { return false; }
const OWNED_ROUTES = Object.freeze(new Set([
]));
module.exports = { CHAT_MOVE_PUBLIC_OWNER, refuseOwnedRoute };
JS
node - "$w/server/routes/chat-lists.cjs" <<'JS'
const assert=require('node:assert/strict'),{chatMoveRoute}=require(process.argv[2]);let calls=0;
(async()=>{const r=await chatMoveRoute({chatMove:async(...args)=>{calls++;assert.deepEqual(args,['qa-user','qa-chat',null]);return{status:200};}},'qa-user','qa-chat',null);assert.equal(r.status,200);assert.equal(calls,1);})().catch(()=>process.exit(1));
JS
node_rc=$?
check "slice7 fixture really delegates one move to its store" '[ $node_rc -eq 0 ]'
move_owner=node; move_method=POST
move_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "$move_owner"
methods = ["$move_method"]
TOML
}
move_try move-transitional
check "slice7 complete declared Node transition assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Source-job internal store pairing is independent of public routes.toml. It requires the
# core's real export, the Rust store declaration, its compiled FEATURES reference and routes.
cp "$w/server/project-store-client.cjs" "$work/source-move-client.saved"
cp "$rz/bins/noevia-server/src/lib.rs" "$work/source-move-features.saved"
cat > "$w/server/project-store-client.cjs" <<'JS'
const CHAT_MOVE_CLIENT_MARKER = 'noevia-chat-move-client/1';
const SOURCE_JOBS_CLIENT_MARKER = 'noevia-source-jobs-client/1';
function sourceJobsFor(user) { return { user }; }
module.exports = { CHAT_MOVE_CLIENT_MARKER, SOURCE_JOBS_CLIENT_MARKER, sourceJobsFor };
JS
source_try() {
  move_try "$1" <<'TOML'
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "node"
methods = ["POST"]
TOML
}
source_try source-new-core-old-rust
check "source job new core with old Rust is refused" 'refused "source job store pairing"'
rm -f "$rz/contracts/http/routes.toml"
tar -czf "$work/rs.tgz" -C "$work/remote" noevia-rs-t
rsum="$( (sha256sum "$work/rs.tgz" 2>/dev/null || shasum -a 256 "$work/rs.tgz") | cut -d' ' -f1)"
printf 'NOEVIA_RS_REF=%s\nNOEVIA_RS_SHA256=%s\nNOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' "$rref" "$rsum" > "$repo/release/versions.lock"
g add -A && g commit -qm source-no-routes; tsha="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$tsha" "$out" >/dev/null 2>"$work/err"; rc=$?
check "source pairing is checked even without Rust public routes.toml" 'refused "source job store pairing"'
mkdir -p "$rz/crates/server-projects/src"
echo 'pub const SOURCE_JOBS_STORE_MARKER: &str = "noevia-source-jobs-store/1";' > "$rz/crates/server-projects/src/source_jobs.rs"
echo 'pub mod source_jobs;' > "$rz/crates/server-projects/src/lib.rs"
printf '%s\n' 'pub const FEATURES: &[&str] = &["start-id", server_projects::source_jobs::SOURCE_JOBS_STORE_MARKER];' > "$rz/bins/noevia-server/src/lib.rs"
{
  echo 'use server_projects::source_jobs as jobs;'
  for op in recover start abandon progress finish read; do
    echo ".route(\"/v1/source-jobs/$op\", source_route(SourceOp::Start))"
  done
} > "$rz/bins/noevia-server/src/project_store.rs"
source_try source-matched
check "matching exported source client and compiled Rust store assemble" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
cp "$w/server/project-store-client.cjs" "$work/source-client.saved"
printf '%s\n' 'function sourceJobsFor(user) { return { user }; }' 'module.exports = { sourceJobsFor };' > "$w/server/project-store-client.cjs"
source_try source-stripped-core-marker
check "ported core with stripped source marker is refused" 'refused "source job store pairing"'
cp "$work/source-client.saved" "$w/server/project-store-client.cjs"
grep -v '^module.exports' "$w/server/project-store-client.cjs" > "$work/source-unexported"
cp "$work/source-unexported" "$w/server/project-store-client.cjs"
source_try source-unexported-core-marker
check "unexported source client marker is refused" 'refused "source job store pairing"'
cp "$work/source-client.saved" "$w/server/project-store-client.cjs"
cp "$rz/crates/server-projects/src/source_jobs.rs" "$work/source-store.saved"
printf '%s\n' '/* pub const SOURCE_JOBS_STORE_MARKER: &str = "noevia-source-jobs-store/1"; */' > "$rz/crates/server-projects/src/source_jobs.rs"
source_try source-comment-only-rust-marker
check "comment-only Rust source marker is refused" 'refused "source job store pairing"'
cp "$work/source-store.saved" "$rz/crates/server-projects/src/source_jobs.rs"
cp "$rz/bins/noevia-server/src/lib.rs" "$work/source-features.saved"
printf '%s\n' 'pub const FEATURES: &[&str] = &["start-id"];' > "$rz/bins/noevia-server/src/lib.rs"
source_try source-uncompiled-rust-marker
check "uncompiled Rust source marker is refused" 'refused "source job store pairing"'
cp "$work/source-features.saved" "$rz/bins/noevia-server/src/lib.rs"
cp "$rz/bins/noevia-server/src/project_store.rs" "$work/source-routes.saved"
grep -v '/v1/source-jobs/finish' "$rz/bins/noevia-server/src/project_store.rs" > "$work/source-missing-route"
cp "$work/source-missing-route" "$rz/bins/noevia-server/src/project_store.rs"
source_try source-missing-finish
check "missing live source store route is refused" 'refused "source job store pairing"'
cp "$work/source-routes.saved" "$rz/bins/noevia-server/src/project_store.rs"
cp "$work/source-move-client.saved" "$w/server/project-store-client.cjs"
cp "$work/source-move-features.saved" "$rz/bins/noevia-server/src/lib.rs"
rm -f "$rz/crates/server-projects/src/source_jobs.rs" "$rz/crates/server-projects/src/lib.rs" "$rz/bins/noevia-server/src/project_store.rs"

# Port contract row J: Core's maintenance lease client and the front's lease authority move together
# (f57a4e3-style detectors: Core's real export under node:vm, Rust's FEATURES tokenizer).
cp "$rz/bins/noevia-server/src/lib.rs" "$work/lease-features.saved"
lease_core_js() { printf '%s\n' "$@" > "$w/server/model-maintenance-lease.cjs"; }
lease_core() { lease_core_js "const LEASE_CLIENT_MARKER = 'noevia-maintenance-lease-client/1';" 'module.exports = { LEASE_CLIENT_MARKER };'; }
# lease_rs_el TEXT: lib.rs's FEATURES with TEXT as its first element(s).
lease_rs_el() { LEASE_EL="$1" perl -pe 's/pub const FEATURES: &\[&str\] = &\[/$&$ENV{LEASE_EL}, /' "$work/lease-features.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
lease_rs() { lease_rs_el '"noevia-maintenance-lease-authority/1"'; }
lease_clear() { rm -f "$w/server/model-maintenance-lease.cjs"; cp "$work/lease-features.saved" "$rz/bins/noevia-server/src/lib.rs"; }
lease_ok() { source_try "$1"; check "$2" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'; }
lease_no() { source_try "$1"; check "$2" 'refused "maintenance lease pairing"'; }
lease_clear; lease_ok lease-legacy-legacy "legacy core with legacy Rust lease owner assembles"
lease_core; lease_rs; lease_ok lease-paired "native lease client with native lease authority assembles"
lease_core_js "const LEASE_CLIENT_MARKER = 'noevia-maintenance-lease-client/2';" 'module.exports = { LEASE_CLIENT_MARKER };'
lease_no lease-new-core-old-rust "v2 incident completion client refuses v1 authority"
lease_rs_el '"noevia-maintenance-lease-authority/2"'; lease_ok lease-v2-paired "v2 captured-incident repair pair assembles"
lease_core; lease_no lease-old-core-new-rust "v1 client refuses v2 incident completion authority"
lease_rs
lease_core_js "const LEASE_CLIENT_MARKER = ['noevia-maintenance-lease-', 'client/1'].join('');" "const { x } = require('./missing.cjs');" 'module.exports = { LEASE_CLIENT_MARKER, x };'
lease_ok lease-computed-core-export "a computed core export with stubbed requires is read by its value"
lease_clear; lease_core; lease_no lease-core-only "native lease client with a legacy front is refused"
lease_clear; lease_rs; lease_no lease-rs-only "native lease authority with a legacy core is refused"
# Adversarial Core markers (front paired at v1).
lease_rs
lease_core_js "// const LEASE_CLIENT_MARKER = 'noevia-maintenance-lease-client/1';" 'module.exports = {};'
lease_no lease-comment-only-core "comment-only core lease marker is refused"
lease_core_js "const LEASE_CLIENT_MARKER = 'noevia-maintenance-lease-client/1';" 'module.exports = {};'
lease_no lease-unexported-core "unexported core lease marker is refused"
lease_core_js "const LEASE_CLIENT_MARKER = 'noevia-maintenance-lease-client/3';" 'module.exports = { LEASE_CLIENT_MARKER };'
lease_no lease-unknown-core-version "unknown core lease marker version is refused"
lease_core_js "module.exports = { LEASE_CLIENT_MARKER: { toString: () => 'noevia-maintenance-lease-client/1' } };"
lease_no lease-object-core-export "a non-string core lease export is refused"
lease_core_js "const LEASE_CLIENT_MARKER = 'noevia-maintenance-lease-client/1';" 'for (;;) {}' 'module.exports = { LEASE_CLIENT_MARKER };'
lease_no lease-hanging-core "a core lease module that never finishes evaluating is refused"
# Adversarial Rust markers (core paired at v1).
lease_core
lease_rs_el '#[cfg(feature = "lease")] "noevia-maintenance-lease-authority/1"'; lease_no lease-cfg-rust "cfg-gated Rust lease marker is refused"
lease_rs_el '"noevia-maintenance-lease-authority/1", "noevia-maintenance-lease-authority/1"'; lease_no lease-duplicate-rust "duplicate Rust lease markers are refused"
lease_rs_el '"noevia-maintenance-lease-authority/1", "noevia-maintenance-lease-authority\x2f1"'; lease_no lease-escaped-duplicate-rust "escaped duplicate Rust lease markers are refused"
lease_rs_el 'b"noevia-maintenance-lease-authority/1"'; lease_no lease-byte-rust "byte-string Rust lease marker is refused"
lease_rs_el 'r#"noevia-maintenance-lease-authority/1"#'; lease_no lease-raw-rust "raw-string Rust lease marker is refused"
lease_rs_el 'concat!("noevia-maintenance-lease-", "authority/1")'; lease_no lease-concat-rust "concat! Rust lease marker is refused"
lease_rs_el '"noevia-maintenance-lease-authority/3"'; lease_no lease-unknown-rust-version "unknown Rust lease marker version is refused"
lease_rs_el '/* "noevia-maintenance-lease-authority/1", */ "start-id-x"'; lease_no lease-comment-only-rust "comment-only Rust lease marker is refused"
lease_rs; printf '%s\n' 'pub const FEATURES: &[&str] = &["noevia-maintenance-lease-authority/1"];' >> "$rz/bins/noevia-server/src/lib.rs"
lease_no lease-two-features-rust "a second FEATURES array is refused"
lease_rs_el '"noevia-maintenance-lease-\u{61}uthority/1"'; lease_ok lease-escaped-single-rust "one escaped Rust lease literal is read by its value"
# Review P2: the declaration's own scope. lease_rs_wrap BEFORE AFTER wraps lib.rs's FEATURES line.
lease_rs_wrap() { lease_rs; LB="$1" LA="$2" perl -0pi -e 's/^(pub const FEATURES: &\[&str\] = &\[.*?\];)$/$ENV{LB}$1$ENV{LA}/m' "$rz/bins/noevia-server/src/lib.rs"; }
lease_rs_wrap '#[cfg(any())] ' ''; lease_no lease-cfg-declaration "cfg on the FEATURES declaration is refused"
lease_rs_wrap '#[cfg(feature = "lease")]'$'\n' ''; lease_no lease-cfg-declaration-line "cfg on its own line above the declaration is refused"
lease_rs_wrap '#[cfg(any())] mod disabled { ' ' }'; lease_no lease-cfg-module "a declaration inside a cfg-disabled module is refused"
lease_rs_wrap 'mod inner { ' ' }'; lease_no lease-nested-module "a declaration inside a nested module is refused"
lease_rs_wrap 'macro_rules! hidden { () => { ' ' }; }'; lease_no lease-macro-rules "a declaration inside macro_rules! is refused"
lease_rs_wrap 'cfg_if::cfg_if! { if #[cfg(any())] { ' ' } }'; lease_no lease-macro-wrapped "a macro-wrapped declaration is refused"
lease_rs; printf '%s\n' '#![cfg(any())]' | cat - "$rz/bins/noevia-server/src/lib.rs" > "$work/lease-crate-cfg" && cp "$work/lease-crate-cfg" "$rz/bins/noevia-server/src/lib.rs"
lease_no lease-crate-cfg "a crate-level cfg attribute is refused"
# Delta review P3: a harmless crate inner attribute directly before the declaration still assembles;
# crate cfg_attr and an outer attribute on the declaration are still refused.
lease_rs_wrap '#![allow(dead_code)]'$'\n' ''; lease_ok lease-crate-allow "a crate inner attribute before the declaration assembles"
lease_rs_wrap '#![allow(dead_code)] #![warn(missing_docs)]'$'\n' ''; lease_ok lease-crate-allow-two "two crate inner attributes before the declaration assemble"
lease_rs_wrap '#![cfg_attr(any(), allow(dead_code))]'$'\n' ''; lease_no lease-crate-cfg-attr "a crate cfg_attr before the declaration is refused"
lease_rs_wrap '#![allow(dead_code)]'$'\n''#[cfg(any())]'$'\n' ''; lease_no lease-crate-allow-then-cfg "an outer cfg after a crate attribute is refused"
lease_rs_wrap '#![allow(dead_code)]'$'\n''#[doc(hidden)]'$'\n' ''; lease_no lease-crate-allow-then-outer "an outer attribute on the declaration is refused"
lease_rs_wrap '/// The capabilities.'$'\n''// plain comment'$'\n' ''; lease_ok lease-doc-commented-declaration "a doc-commented unconditional declaration assembles"
lease_clear
# Port contract row H: Core's admission latch and the front's admission authority move together
# (f57a4e3-style detectors: Core's real export under node:vm, Rust's FEATURES tokenizer).
cp "$rz/bins/noevia-server/src/lib.rs" "$work/adm-features.saved"
adm_core_js() { printf '%s\n' "$@" > "$w/server/inference-admission-lease.cjs"; }
adm_core() { adm_core_js "const LATCH_MARKER = 'noevia-inference-admission-latch/1';" 'module.exports = { LATCH_MARKER };'; }
# adm_rs_el TEXT: lib.rs's FEATURES with TEXT as its first element(s).
adm_rs_el() { ADM_EL="$1" perl -pe 's/pub const FEATURES: &\[&str\] = &\[/$&$ENV{ADM_EL}, /' "$work/adm-features.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
adm_rs() { adm_rs_el '"noevia-inference-admission-authority/1"'; }
adm_clear() { rm -f "$w/server/inference-admission-lease.cjs"; cp "$work/adm-features.saved" "$rz/bins/noevia-server/src/lib.rs"; }
adm_ok() { source_try "$1"; check "$2" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'; }
# Row J's tokenizer reads the same FEATURES array and refuses a non-literal or misplaced element first, so either pairing's refusal counts.
adm_no() { source_try "$1"; check "$2" 'refused "\(inference admission\|maintenance lease\) pairing"'; }
adm_clear; adm_ok adm-legacy-legacy "legacy core with legacy Rust lease owner assembles"
adm_core; adm_rs; adm_ok adm-paired "native lease client with native lease authority assembles"
adm_core_js "const LATCH_MARKER = ['noevia-inference-admission-', 'latch/1'].join('');" "const { x } = require('./missing.cjs');" 'module.exports = { LATCH_MARKER, x };'
adm_ok adm-computed-core-export "a computed core export with stubbed requires is read by its value"
adm_clear; adm_core; adm_no adm-core-only "native lease client with a legacy front is refused"
adm_clear; adm_rs; adm_no adm-rs-only "native lease authority with a legacy core is refused"
# Adversarial Core markers (front paired at v1).
adm_rs
adm_core_js "// const LATCH_MARKER = 'noevia-inference-admission-latch/1';" 'module.exports = {};'
adm_no adm-comment-only-core "comment-only core lease marker is refused"
adm_core_js "const LATCH_MARKER = 'noevia-inference-admission-latch/1';" 'module.exports = {};'
adm_no adm-unexported-core "unexported core lease marker is refused"
adm_core_js "const LATCH_MARKER = 'noevia-inference-admission-latch/2';" 'module.exports = { LATCH_MARKER };'
adm_no adm-unknown-core-version "unknown core lease marker version is refused"
adm_core_js "module.exports = { LATCH_MARKER: { toString: () => 'noevia-inference-admission-latch/1' } };"
adm_no adm-object-core-export "a non-string core lease export is refused"
adm_core_js "const LATCH_MARKER = 'noevia-inference-admission-latch/1';" 'for (;;) {}' 'module.exports = { LATCH_MARKER };'
adm_no adm-hanging-core "a core lease module that never finishes evaluating is refused"
# Adversarial Rust markers (core paired at v1).
adm_core
adm_rs_el '#[cfg(feature = "adm")] "noevia-inference-admission-authority/1"'; adm_no adm-cfg-rust "cfg-gated Rust lease marker is refused"
adm_rs_el '"noevia-inference-admission-authority/1", "noevia-inference-admission-authority/1"'; adm_no adm-duplicate-rust "duplicate Rust lease markers are refused"
adm_rs_el '"noevia-inference-admission-authority/1", "noevia-inference-admission-authority\x2f1"'; adm_no adm-escaped-duplicate-rust "escaped duplicate Rust lease markers are refused"
adm_rs_el 'b"noevia-inference-admission-authority/1"'; adm_no adm-byte-rust "byte-string Rust lease marker is refused"
adm_rs_el 'r#"noevia-inference-admission-authority/1"#'; adm_no adm-raw-rust "raw-string Rust lease marker is refused"
adm_rs_el 'concat!("noevia-inference-admission-", "authority/1")'; adm_no adm-concat-rust "concat! Rust lease marker is refused"
adm_rs_el '"noevia-inference-admission-authority/2"'; adm_no adm-unknown-rust-version "unknown Rust lease marker version is refused"
adm_rs_el '/* "noevia-inference-admission-authority/1", */ "start-id-x"'; adm_no adm-comment-only-rust "comment-only Rust lease marker is refused"
adm_rs; printf '%s\n' 'pub const FEATURES: &[&str] = &["noevia-inference-admission-authority/1"];' >> "$rz/bins/noevia-server/src/lib.rs"
adm_no adm-two-features-rust "a second FEATURES array is refused"
adm_rs_el '"noevia-inference-admission-\u{61}uthority/1"'; adm_ok adm-escaped-single-rust "one escaped Rust lease literal is read by its value"
# Review P2: the declaration's own scope. adm_rs_wrap BEFORE AFTER wraps lib.rs's FEATURES line.
adm_rs_wrap() { adm_rs; LB="$1" LA="$2" perl -0pi -e 's/^(pub const FEATURES: &\[&str\] = &\[.*?\];)$/$ENV{LB}$1$ENV{LA}/m' "$rz/bins/noevia-server/src/lib.rs"; }
adm_rs_wrap '#[cfg(any())] ' ''; adm_no adm-cfg-declaration "cfg on the FEATURES declaration is refused"
adm_rs_wrap '#[cfg(feature = "adm")]'$'\n' ''; adm_no adm-cfg-declaration-line "cfg on its own line above the declaration is refused"
adm_rs_wrap '#[cfg(any())] mod disabled { ' ' }'; adm_no adm-cfg-module "a declaration inside a cfg-disabled module is refused"
adm_rs_wrap 'mod inner { ' ' }'; adm_no adm-nested-module "a declaration inside a nested module is refused"
adm_rs_wrap 'macro_rules! hidden { () => { ' ' }; }'; adm_no adm-macro-rules "a declaration inside macro_rules! is refused"
adm_rs_wrap 'cfg_if::cfg_if! { if #[cfg(any())] { ' ' } }'; adm_no adm-macro-wrapped "a macro-wrapped declaration is refused"
adm_rs; printf '%s\n' '#![cfg(any())]' | cat - "$rz/bins/noevia-server/src/lib.rs" > "$work/adm-crate-cfg" && cp "$work/adm-crate-cfg" "$rz/bins/noevia-server/src/lib.rs"
adm_no adm-crate-cfg "a crate-level cfg attribute is refused"
adm_rs_wrap '/// The capabilities.'$'\n''// plain comment'$'\n' ''; adm_ok adm-doc-commented-declaration "a doc-commented unconditional declaration assembles"
adm_clear

for item in "rs:chat_move.rs:MOVE_MARKER" "rs:journal.rs:CHAT_MOVE_JOURNAL_MARKER" \
 "features:lib.rs:FEATURES" "core:project-store-client.cjs:CHAT_MOVE_CLIENT_MARKER" \
 "core:chat.cjs:CHAT_MOVE_ENFORCEMENT_MARKER" "core:chat-change-journal.cjs:CHAT_MOVE_READER_MARKER" \
 "core:rust-projects.cjs:CHAT_MOVE_PUBLIC_OWNER"; do
 kind="$(echo "$item"|cut -d: -f1)"; file="$(echo "$item"|cut -d: -f2)"; name="$(echo "$item"|cut -d: -f3)"
 if [ "$kind" = rs ]; then target="$rz/crates/server-projects/src/$file"
 elif [ "$kind" = features ]; then target="$rz/bins/noevia-server/src/$file"
 else target="$w/server/$file"; fi
 cp "$target" "$work/move-cap.saved"
 { echo '/*'; cat "$work/move-cap.saved"; echo '*/'; } > "$target"
 move_try "move-comment-$name"
 check "slice7 comment-only $name cannot grant capability" 'refused "chat move capability pairing"'
 cp "$work/move-cap.saved" "$target"
 if [ "$name" = CHAT_MOVE_PUBLIC_OWNER ]; then
  grep -v "^const CHAT_MOVE_PUBLIC_OWNER =" "$work/move-cap.saved" > "$target"
 else : > "$target"; fi
 move_try "move-missing-$name"
 check "slice7 missing $name cannot grant capability" 'refused "chat move capability pairing"'
 cp "$work/move-cap.saved" "$target"
 if [ "$kind" = core ]; then
  grep -v '^module.exports' "$target" > "$work/move-unexported"; cp "$work/move-unexported" "$target"
  move_try "move-unexported-$name"
  check "slice7 unexported $name cannot grant capability" 'refused "chat move capability pairing"'
  cp "$work/move-cap.saved" "$target"
 fi
done
cp "$w/server/rust-projects.cjs" "$work/move-node-owner.saved"
cp "$w/server/routes/chat-lists.cjs" "$work/move-handler.saved"
sed "s/'node'/'unknown'/" "$work/move-node-owner.saved" > "$w/server/rust-projects.cjs"
move_try move-unknown-owner
check "slice7 unknown declared owner refuses" 'refused "CHAT_MOVE_PUBLIC_OWNER"'
cp "$work/move-node-owner.saved" "$w/server/rust-projects.cjs"
printf '%s\n' 'module.exports = {};' > "$w/server/routes/chat-lists.cjs"
move_try move-missing-handler
check "slice7 declared node without real exported handler refuses" 'refused "declared node requires"'
cp "$work/move-handler.saved" "$w/server/routes/chat-lists.cjs"
move_owner=rust; move_try move-native-with-node-core
check "slice7 Rust POST requires that exact core refusal" 'refused "POST /api/chats/{}/move"'
cat > "$w/server/rust-projects.cjs" <<'JS'
const CHAT_MOVE_PUBLIC_OWNER = 'rust';
function refuseOwnedRoute(req,res,path,json) {
  if(req.method==='POST'&&/^\/api\/chats\/[^/]+\/move$/.test(path))return json(res,503,{code:'RUST_PROJECTS_OWNED'});
  return false;
}
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/chats/{chatId}/move',
]));
module.exports = { CHAT_MOVE_PUBLIC_OWNER, refuseOwnedRoute };
JS
printf '%s\n' 'module.exports = {};' > "$w/server/routes/chat-lists.cjs"
node - "$w/server/rust-projects.cjs" <<'JS'
const assert=require('node:assert/strict'),{refuseOwnedRoute}=require(process.argv[2]);const replies=[];
refuseOwnedRoute({method:'POST'},{},'/api/chats/qa/move',(_r,status,body)=>replies.push({status,body}));
assert.equal(replies[0].status,503);assert.equal(replies[0].body.code,'RUST_PROJECTS_OWNED');
assert.equal(refuseOwnedRoute({method:'GET'},{},'/api/chats/qa/move',()=>{throw Error('GET refused');}),false);
JS
node_rc=$?
check "slice7 final fixture really returns503 for POST only" '[ $node_rc -eq 0 ]'
move_try move-native
check "slice7 exact native POST and Node refusal assemble" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
move_owner=node;move_try move-refusal-with-node-route
check "slice7 Node refusal cannot pair with Node public owner" 'refused "exact native POST"'
move_owner=rust;move_method=GET;move_try move-get-only
check "slice7 GET-only cannot satisfy POST refusal" 'refused "GET /api/chats/{}/move\\|exact native POST"'
move_method=ALL;move_try move-all
check "slice7 ALL cannot claim the non-POST fallback" 'refused "ALL /api/chats/{}/move\\|non-POST"'
move_method=POST;cp "$work/move-handler.saved" "$w/server/routes/chat-lists.cjs"
move_try move-duplicate
check "slice7 native owner with duplicate Node handler refuses" 'refused "owner/handler contradiction"'
# Feature owner release matrix. Keep the previously qualified move pair coherent.
printf '%s\n' 'module.exports = {};' > "$w/server/routes/chat-lists.cjs"
cp "$w/server/index.cjs" "$work/feature-index.saved"
cp "$rz/bins/noevia-server/src/lib.rs" "$work/feature-lib.saved"
feature_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/features"
owner = "rust"
[[route]]
path = "/api/admin/features"
owner = "rust"
[[route]]
path = "/api/admin/features/{name}"
owner = "rust"
$feature_limit
TOML
}
feature_limit=""
printf '%s\n' 'const setup = factory.createReadOnlyFeatures({});' >> "$w/server/index.cjs"
feature_try feature-core-only
check "feature Core retirement requires the native capability" 'refused "feature ownership pairing"'
# Add the real FEATURES declaration entry, preserving all unrelated capabilities.
sed 's/"start-id"/"start-id", "rust-feature-owner"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
feature_try feature-pair
check "matching feature pair with all three all-method namespaces assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
feature_limit='methods = ["GET"]'
feature_try feature-get-only
check "GET-only feature suffix ownership is refused" 'refused "feature ownership pairing"'
feature_limit=""
cp "$work/feature-index.saved" "$w/server/index.cjs"
feature_try feature-front-only
check "native feature front cannot pair with the old Core writer" 'refused "feature ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try feature-old-pair
check "historic feature old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Diary owner release matrix (sbstndalton/noevia#2185): the five proxy-only routes, all methods.
diary_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/diary/source"
owner = "rust"
[[route]]
path = "/api/diary/today"
owner = "rust"
[[route]]
path = "/api/diary/storage-import"
owner = "rust"
[[route]]
path = "/api/diary/workspace-export"
owner = "rust"
[[route]]
path = "$diary_last"
owner = "rust"
$diary_limit
TOML
}
diary_last="/api/diary/workspace-import"; diary_limit=""
printf '%s\n' "  if (require('./rust-diary.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
diary_try diary-core-only
check "Diary Core refusal requires the native capability" 'refused "Diary ownership pairing"'
sed 's/"start-id"/"start-id", "rust-diary"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
diary_try diary-pair
check "matching Diary pair with all five all-method routes assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
diary_limit='methods = ["GET"]'
diary_try diary-get-only
check "a GET-only Diary route is refused" 'refused "Diary ownership pairing"'
diary_limit=""; diary_last="/api/diary/workspace-importx"
diary_try diary-incomplete
check "an incomplete Diary route set is refused" 'refused "Diary ownership pairing"'
diary_last="/api/diary/workspace-import"
cp "$work/feature-index.saved" "$w/server/index.cjs"
diary_try diary-front-only
check "a rust-diary front cannot pair with the old Core proxy" 'refused "Diary ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try diary-old-pair
check "historic Diary old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# The rest of the Diary routes (sbstndalton/noevia#2206): Core's rust-diary-routes.cjs refusal beside the
# front's rust-diary-routes capability, with the exact methods Node answered.
dr_routes() {
  local base='[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'
  printf "$base"
  printf '[[route]]\npath = "/api/diary"\nowner = "rust"\n%s\n' "${dr_all:-}"
  printf '[[route]]\npath = "/api/diary-connector"\nowner = "rust"\n\n'
  printf '[[route]]\npath = "/api/diary/storage-status"\nowner = "rust"\n\n'
  printf '[[route]]\npath = "/api/diary/context"\nowner = "rust"\nmethods = %s\n\n' "${dr_context:-[\"GET\", \"POST\"]}"
  printf '[[route]]\npath = "/api/diary/exchanges"\nowner = "rust"\nmethods = %s\n\n' "${dr_exchanges:-[\"GET\", \"POST\"]}"
  printf '[[route]]\npath = "/api/profile/diary-connectors"\nowner = "rust"\nmethods = %s\n\n' "${dr_connectors:-[\"GET\", \"POST\"]}"
  printf '[[route]]\npath = "%s"\nowner = "rust"\nmethods = %s\n\n' "${dr_one:-/api/profile/diary-connectors/{*\}}" "${dr_delete:-[\"DELETE\"]}"
  printf '[[route]]\npath = "/api/diary/local-exchange"\nowner = "%s"\n%s\n' "${dr_local:-node}" "${dr_local_methods:-}"
}
dr_try() { dr_routes > "$work/dr-routes"; try_routes "$1" < "$work/dr-routes"; }
dr_refusal() {
  printf "%s\n" "const FIXED = { '/api/diary': 0, '/api/diary-connector': 0, '/api/diary/storage-status': 0, '/api/diary/context': 0, '/api/diary/exchanges': 0, '/api/profile/diary-connectors': 0 };" > "$w/server/rust-diary-routes.cjs"
  [ -z "${dr_skip:-}" ] || sed -i.bak "s#'${dr_skip}': 0,##" "$w/server/rust-diary-routes.cjs" && rm -f "$w/server/rust-diary-routes.cjs.bak"
}
cp "$w/server/rust-auth.cjs" "$work/dr-auth.saved"
dr_all=""
dr_refusal
printf '%s\n' "  if (require('./rust-diary-routes.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
printf '%s\n' "const t = require('./rust-diary-routes.cjs').TABLE;" >> "$w/server/rust-auth.cjs"
dr_try dr-core-only
check "Diary routes Core refusal requires the native capability" 'refused "Diary route ownership pairing: Core and Rust must move together"'
sed 's/"start-id"/"start-id", "rust-diary-routes"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
dr_try dr-pair
check "matching Diary routes pair with the exact methods assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
dr_context='["GET"]'; dr_try dr-context-get-only
check "a GET-only Diary context is refused (Node answered POST too)" 'refused "Diary route ownership pairing"'
dr_context='["GET", "POST", "PUT"]'; dr_try dr-context-more
check "a Diary context with more methods than Node answered is refused" 'refused "Diary route ownership pairing"'
dr_context='["GET", "POST"]'
dr_exchanges='["POST"]'; dr_try dr-exchanges-post-only
check "a POST-only Diary exchanges route is refused" 'refused "Diary route ownership pairing"'
dr_exchanges='["GET", "GET", "POST"]'; dr_try dr-exchanges-duplicate
check "a repeated method in the Diary exchanges route is refused" 'refused "Diary route ownership pairing"'
dr_exchanges='["GET", "POST"]'
dr_connectors='["GET"]'; dr_try dr-connectors-get-only
check "a GET-only connector list is refused" 'refused "Diary route ownership pairing"'
dr_connectors='["GET", "POST"]'
dr_delete='["DELETE", "GET"]'; dr_try dr-delete-more
check "a connector route with more than DELETE is refused" 'refused "Diary route ownership pairing"'
dr_delete='["DELETE"]'
dr_all=$'methods = ["GET"]'; dr_try dr-bare-diary-get
check "a GET-only /api/diary is refused (it has no methods in Node)" 'refused "Diary route ownership pairing"'
dr_all=""
dr_one="/api/profile/diary-connectors/{id}"; dr_try dr-one-renamed
check "an incomplete Diary route set is refused" 'refused "Diary route ownership pairing"'
dr_one='/api/profile/diary-connectors/{*}'
dr_local=rust; dr_try dr-local-exchange-moved
check "the local exchange moving to Rust without its own pair is refused (Node still answers it)" 'refused "Diary route ownership pairing"'
# The Diary local exchange: Core's rust-diary-local-exchange.cjs refusal and its admission lease's
# diaryExchange ask beside the front's rust-diary-local-exchange capability, every method Rust's.
cp "$w/server/index.cjs" "$work/lx-index.saved"
cp "$rz/bins/noevia-server/src/lib.rs" "$work/lx-lib.saved"
printf '%s\n' "  if (require('./rust-diary-local-exchange.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
cp "$w/server/index.cjs" "$work/lx-index-wired.saved"
printf '%s\n' "  diaryExchange: { rateLimited: (userId) => llmRateLimited(userId), foreground: () => rag.foreground() }," >> "$w/server/index.cjs"
printf '%s\n' "function admit(ask) {" "  if (ask && typeof ask === 'object' && 'diaryExchange' in ask) { return ask; }" "}"  "module.exports = { admit };" > "$w/server/inference-admission-lease.cjs"
dr_try lx-core-only
check "a Core that refuses the local exchange requires the native capability" 'refused "Diary local exchange ownership pairing: Core and Rust must move together"'
sed 's/"rust-diary-routes"/"rust-diary-routes", "rust-diary-local-exchange"/' "$work/lx-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
dr_try lx-pair
check "a matching local exchange pair, every method Rust's, assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
dr_local_methods='methods = ["POST"]'; dr_try lx-post-only
check "a local exchange that is Rust's for only some methods is refused" 'refused "Diary local exchange ownership pairing: every method must belong to Rust"'
dr_local_methods=""
dr_local=node; dr_try lx-route-still-node
check "a local exchange pair whose route table still gives Node the route is refused" 'refused "Diary local exchange ownership pairing"'
dr_local=rust
printf '%s\n' "// no exchange ask" > "$w/server/inference-admission-lease.cjs"
dr_try lx-no-lease
check "a Core whose admission lease cannot take the exchange is refused" 'refused "admission lease does not take the exchange"'
printf '%s\n' "function admit(ask) {" "  if (ask && typeof ask === 'object' && 'diaryExchange' in ask) { return ask; }" "}"  "module.exports = { admit };" > "$w/server/inference-admission-lease.cjs"
cp "$w/server/index.cjs" "$work/lx-index-full.saved"
cp "$work/lx-index-wired.saved" "$w/server/index.cjs"
dr_try lx-no-throttle
check "a Core that does not give the lease chat's throttle is refused" 'refused "is not given the chat throttle"'
cp "$work/lx-index-full.saved" "$w/server/index.cjs"
cp "$work/lx-index.saved" "$w/server/index.cjs"
dr_try lx-front-only
check "a rust-diary-local-exchange front cannot pair with a Core that still answers the exchange" 'refused "Diary local exchange ownership pairing: Core and Rust must move together"'
cp "$work/lx-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
rm -f "$w/server/inference-admission-lease.cjs"
dr_local=node
dr_skip="/api/diary/exchanges"; dr_refusal; dr_try dr-core-not-refusing
check "a Core that does not refuse a Diary path the front answers is refused" 'refused "Core does not refuse /api/diary/exchanges"'
dr_skip=""; dr_refusal
cp "$work/dr-auth.saved" "$w/server/rust-auth.cjs"
dr_try dr-table-not-guarded
check "a Core whose guard leaves the connector table to Node is refused" 'refused "still lets Node write the connector table"'
printf '%s\n' "const t = require('./rust-diary-routes.cjs').TABLE;" >> "$w/server/rust-auth.cjs"
cp "$work/feature-index.saved" "$w/server/index.cjs"
dr_try dr-front-only
check "a rust-diary-routes front cannot pair with the old Core" 'refused "Diary route ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
rm -f "$w/server/rust-diary-routes.cjs"
cp "$work/dr-auth.saved" "$w/server/rust-auth.cjs"
move_try dr-old-pair
check "historic Diary routes old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Model read owner release matrix (sbstndalton/noevia#2187): two routes, GET only.
models_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/models/capabilities"
owner = "rust"
methods = ["GET"]
[[route]]
path = "$models_last"
owner = "rust"
$models_limit
TOML
}
models_last="/api/models/hardware"; models_limit='methods = ["GET"]'
printf '%s\n' "  if (require('./rust-models.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
models_try models-core-only
check "model read Core refusal requires the native capability" 'refused "model read ownership pairing"'
sed 's/"start-id"/"start-id", "rust-model-reads"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
models_try models-pair
check "matching model read pair with both GET-only routes assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
models_limit=""
models_try models-all-methods
check "an all-method model read route is refused (Node keeps the other methods)" 'refused "model read ownership pairing"'
models_limit='methods = ["GET", "PUT"]'
models_try models-get-put
check "a model read route with more than GET is refused" 'refused "model read ownership pairing"'
models_limit='methods = ["GET"]'; models_last="/api/models/hardwarex"
models_try models-incomplete
check "an incomplete model read route set is refused" 'refused "model read ownership pairing"'
models_last="/api/models/hardware"
cp "$work/feature-index.saved" "$w/server/index.cjs"
models_try models-front-only
check "a rust-model-reads front cannot pair with the old Core handlers" 'refused "model read ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try models-old-pair
check "historic model read old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Project source read owner release matrix (sbstndalton/noevia#2191): three routes, GET only.
project_reads_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{id}/sources/text"
owner = "rust"
methods = ["GET"]
[[route]]
path = "/api/projects/{id}/documents/original"
owner = "rust"
methods = ["GET"]
[[route]]
path = "$project_reads_last"
owner = "rust"
$project_reads_limit
TOML
}
project_reads_last="/api/projects/{id}/{*}/original"; project_reads_limit='methods = ["GET"]'
printf '%s\n' "  if (require('./rust-project-reads.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
cat > "$w/server/rust-project-reads.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'GET /api/projects/{id}/sources/text',
  'GET /api/projects/{id}/documents/original',
  'GET /api/projects/{id}/{*}/original',
]));
module.exports = { OWNED_ROUTES };
JS
project_reads_try project-reads-core-only
check "project source read Core refusal requires the native capability" 'refused "project source read ownership pairing"'
sed 's/"start-id"/"start-id", "rust-project-reads"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
project_reads_try project-reads-pair
check "matching project source read pair with three GET-only routes assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
mv "$w/server/rust-project-reads.cjs" "$work/rust-project-reads.saved"
project_reads_try project-reads-unlisted
check "a front owning the source reads needs a Core that lists them (OWNED_ROUTES)" 'refused "does not list in server/rust-projects.cjs OWNED_ROUTES"'
mv "$work/rust-project-reads.saved" "$w/server/rust-project-reads.cjs"
project_reads_limit=""
project_reads_try project-reads-all-methods
check "an all-method project source read route is refused (Node keeps the other methods)" 'refused "project source read ownership pairing"'
project_reads_limit='methods = ["GET", "DELETE"]'
project_reads_try project-reads-get-delete
check "a project source read route with more than GET is refused" 'refused "project source read ownership pairing"'
project_reads_limit='methods = ["GET"]'; project_reads_last="/api/projects/{id}/documents/pages"
project_reads_try project-reads-incomplete
check "an incomplete project source read route set is refused" 'refused "project source read ownership pairing"'
project_reads_last="/api/projects/{id}/{*}/original"
cp "$work/feature-index.saved" "$w/server/index.cjs"
project_reads_try project-reads-front-only
check "a rust-project-reads front cannot pair with the old Core handlers" 'refused "project source read ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try project-reads-old-pair
check "historic project source read old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
rm -f "$w/server/rust-project-reads.cjs"
# Project create/delete owner release matrix (sbstndalton/noevia#2191 round 2): POST /api/projects and
# DELETE /api/projects/{projectId}, nothing else.
project_lifecycle_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects"
owner = "rust"
$project_lifecycle_create
[[route]]
path = "$project_lifecycle_one"
owner = "rust"
methods = ["DELETE"]
TOML
}
project_lifecycle_create='methods = ["POST"]'; project_lifecycle_one="/api/projects/{projectId}"
printf '%s\n' "  if (require('./rust-project-lifecycle.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
cat > "$w/server/rust-project-lifecycle.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects',
  'DELETE /api/projects/{projectId}',
]));
module.exports = { OWNED_ROUTES };
JS
project_lifecycle_try project-lifecycle-core-only
check "project create/delete Core refusal requires the native capability" 'refused "project create/delete ownership pairing"'
sed 's/"start-id"/"start-id", "rust-project-lifecycle"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
project_lifecycle_try project-lifecycle-pair
check "matching project create/delete pair with POST and DELETE only assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
mv "$w/server/rust-project-lifecycle.cjs" "$work/rust-project-lifecycle.saved"
project_lifecycle_try project-lifecycle-unlisted
check "a front owning the project delete needs a Core that lists it (OWNED_ROUTES)" 'refused "does not list in server/rust-projects.cjs OWNED_ROUTES"'
mv "$work/rust-project-lifecycle.saved" "$w/server/rust-project-lifecycle.cjs"
project_lifecycle_create=""
project_lifecycle_try project-lifecycle-all-methods
check "an all-method /api/projects route is refused (Node keeps the other methods)" 'refused "project create/delete ownership pairing"'
project_lifecycle_create='methods = ["POST", "GET"]'
project_lifecycle_try project-lifecycle-post-get
check "a /api/projects route with more than POST is refused" 'refused "project create/delete ownership pairing"'
project_lifecycle_create='methods = ["POST"]'; project_lifecycle_one="/api/projects/{projectId}/config"
project_lifecycle_try project-lifecycle-incomplete
check "an incomplete project create/delete route set is refused" 'refused "project create/delete ownership pairing"'
project_lifecycle_one="/api/projects/{projectId}"
cp "$work/feature-index.saved" "$w/server/index.cjs"
project_lifecycle_try project-lifecycle-front-only
check "a rust-project-lifecycle front cannot pair with the old Core handlers" 'refused "project create/delete ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try project-lifecycle-old-pair
check "historic project create/delete old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Project storage write owner release matrix (sbstndalton/noevia#2191 round 3): no route of its own, on
# top of the create/delete pair.
printf '%s\n' "  if (require('./rust-project-lifecycle.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
printf '%s\n' "  kinds: require('./rust-project-storage.cjs').CORE_KINDS," >> "$w/server/index.cjs"
cat > "$w/server/rust-project-storage.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set());
module.exports = { OWNED_ROUTES, CORE_KINDS: ['index'], FRONT_KINDS: ['sweep'] };
JS
sed 's/"start-id"/"start-id", "rust-project-lifecycle"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
project_lifecycle_try project-storage-core-only
check "project storage Core split requires the native capability" 'refused "project storage write ownership pairing"'
sed 's/"start-id"/"start-id", "rust-project-lifecycle", "rust-project-storage"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
project_lifecycle_try project-storage-pair
check "matching project storage pair on the create/delete pair assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-project-lifecycle.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
project_lifecycle_try project-storage-front-only
check "a rust-project-storage front cannot pair with a Core that runs every job kind" 'refused "project storage write ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  kinds: require('./rust-project-storage.cjs').CORE_KINDS," >> "$w/server/index.cjs"
sed 's/"start-id"/"start-id", "rust-project-storage"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
move_try project-storage-without-lifecycle
check "a project storage pair without the create/delete pair is refused" 'refused "needs the project create/delete pair"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try project-storage-old-pair
check "historic project storage old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Since noevia-core b6e2238 Core loads the split through its outbox view: index.cjs requires
# rust-index-outbox.cjs, which requires rust-project-storage.cjs. Each link must be a real require call.
storage_mismatch='refused "project storage write ownership pairing: Core and Rust must move together"'
cat > "$work/outbox-link.real" <<'JS'
const indexOutbox = require('./rust-index-outbox.cjs').createIndexOutbox({ dir: 'synthetic' });
JS
cat > "$work/outbox-link.spelled" <<'JS'
// const indexOutbox = require('./rust-index-outbox.cjs').createIndexOutbox({ dir: 'synthetic' });
/* require('./rust-index-outbox.cjs') */
const note = "require('./rust-index-outbox.cjs')", tmpl = `require('./rust-index-outbox.cjs')`;
const viaProperty = loader.require('./rust-index-outbox.cjs');
JS
cat > "$work/outbox-body.real" <<'JS'
'use strict';
const { CORE_KINDS } = require('./rust-project-storage.cjs');
function kindSql(kinds) {
  if (!kinds.every((k) => /^[a-z]+$/.test(k))) throw new Error('outbox kinds must be lower-case identifiers');
  return `kind IN (${kinds.map((k) => `'${k}'`).join(', ')})`;
}
module.exports = { createIndexOutbox: () => ({ where: kindSql(CORE_KINDS) }) };
JS
cat > "$work/outbox-body.spelled" <<'JS'
'use strict';
// const { CORE_KINDS } = require('./rust-project-storage.cjs');
/* require('./rust-project-storage.cjs') */
const note = "require('./rust-project-storage.cjs')", tmpl = `${"require('./rust-project-storage.cjs')"}`;
const loader = { require: () => ({}) };
const viaProperty = loader.require('./rust-project-storage.cjs');
const dynamic = require(`./rust-project-${'storage'}.cjs`);
module.exports = { createIndexOutbox: () => ({}) };
JS
cat > "$work/outbox-body.escaped" <<'JS'
// node reads both literals as './rust-project-storage.cjs', so each is a real require of the split.
const { CORE_KINDS } = require('./rust\x2dproject-storage.cjs');
const again = require(`./rust-project-storage.cjs`);
module.exports = { createIndexOutbox: () => ({ CORE_KINDS, again }) };
JS
cat > "$work/outbox-body.unterminated" <<'JS'
const { CORE_KINDS } = require('./rust-project-storage.cjs');
const broken = 'never closed
JS
# storage_chain <index link fixture|none> <outbox body fixture|none> <front FEATURES addition>
storage_chain() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  printf '%s\n' "  if (require('./rust-project-lifecycle.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  [ "$1" = none ] || cat "$work/outbox-link.$1" >> "$w/server/index.cjs"
  rm -f "$w/server/rust-index-outbox.cjs"
  [ "$2" = none ] || cp "$work/outbox-body.$2" "$w/server/rust-index-outbox.cjs"
  sed "s/\"start-id\"/\"start-id\", \"rust-project-lifecycle\"$3/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
}
node -e 'const fs = require("node:fs"), vm = require("node:vm");
  for (const f of process.argv.slice(1)) new vm.Script(fs.readFileSync(f, "utf8"), { filename: f });' \
  "$work/outbox-link.real" "$work/outbox-link.spelled" "$work/outbox-body.real" "$work/outbox-body.spelled" "$work/outbox-body.escaped" 2>/dev/null; node_rc=$?
check "storage chain fixtures are valid JavaScript (only the unterminated one is not)" '[ $node_rc -eq 0 ]'
# Outbox pairing guards evaluate rust-index-outbox.cjs (every require stubbed), so its fixtures must run.
node -e 'const fs = require("node:fs"), vm = require("node:vm");
  const stub = new Proxy(function () {}, { get: () => stub, apply: () => stub, construct: () => stub });
  for (const f of process.argv.slice(1)) {
    const module = { exports: {} };
    vm.runInNewContext("(function (require, module, exports) {" + fs.readFileSync(f, "utf8") + "\n})", {})(() => stub, module, module.exports);
  }' "$work/outbox-body.real" "$work/outbox-body.spelled" "$work/outbox-body.escaped" 2>/dev/null; node_rc=$?
check "storage chain outbox fixtures evaluate with stubbed requires" '[ $node_rc -eq 0 ]'
storage_chain real real ', "rust-project-storage"'
project_lifecycle_try project-storage-chain-pair
check "a Core split loaded through the outbox view pairs with the native storage capability" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
storage_chain real real ''
project_lifecycle_try project-storage-chain-core-only
check "a chained Core split without the native storage capability is refused" "$storage_mismatch"
storage_chain spelled real ', "rust-project-storage"'
project_lifecycle_try project-storage-chain-link1-spelled
check "chain broken at index.cjs (outbox require only in a comment, string, template or property) is refused" "$storage_mismatch"
storage_chain none real ', "rust-project-storage"'
project_lifecycle_try project-storage-chain-link1-unloaded
check "chain broken at index.cjs (an outbox file index.cjs does not load) is refused" "$storage_mismatch"
storage_chain none real ''
project_lifecycle_try project-storage-chain-unloaded-old
check "a storage require in an outbox file index.cjs does not load is not Core's split (old/old assembles)" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
storage_chain real spelled ', "rust-project-storage"'
project_lifecycle_try project-storage-chain-link2-spelled
check "chain broken at the outbox (storage require only in a comment, string, template, substitution or property) is refused" "$storage_mismatch"
storage_chain real escaped ''
project_lifecycle_try project-storage-chain-escaped-old-front
check "an escaped or template-literal storage require is still Core's split (an old front is refused)" "$storage_mismatch"
storage_chain real escaped ', "rust-project-storage"'
project_lifecycle_try project-storage-chain-escaped-pair
check "an escaped or template-literal storage require pairs with the native capability" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
storage_chain real none ', "rust-project-storage"'
project_lifecycle_try project-storage-chain-link2-missing
check "chain broken at the outbox (index.cjs requires a missing outbox file) is refused" "$storage_mismatch"
storage_chain real spelled ''
project_lifecycle_try project-storage-chain-link2-old
check "an outbox view without the storage require is an old Core (old/old assembles)" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
storage_chain real unterminated ''
project_lifecycle_try project-storage-chain-unreadable
check "an outbox view that cannot be tokenized refuses instead of reading as absent" 'refused "project storage write ownership pairing: Core wiring could not be read"'
storage_chain spelled none ''
printf '%s\n' "// kinds: require('./rust-project-storage.cjs').CORE_KINDS," "const s = \"require('./rust-project-storage.cjs')\";" >> "$w/server/index.cjs"
sed "s/\"start-id\"/\"start-id\", \"rust-project-lifecycle\", \"rust-project-storage\"/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
project_lifecycle_try project-storage-direct-spelled
check "a direct storage require only in a comment or string is not Core's split" "$storage_mismatch"
storage_chain real real ', "rust-project-storage"'
printf '%s\n' "  kinds: require('./rust-project-storage.cjs').CORE_KINDS," >> "$w/server/index.cjs"
project_lifecycle_try project-storage-direct-and-chain
check "the direct require and the chain together still pair" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
rm -f "$w/server/rust-index-outbox.cjs"
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
rm -f "$w/server/rust-project-storage.cjs"
# Project file delete owner release matrix (sbstndalton/noevia#2191 round 3): DELETE
# /api/projects/{id}/files only, on top of the create/delete and storage pairs.
project_files_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{projectId}"
owner = "rust"
methods = ["DELETE"]
[[route]]
path = "/api/projects/{id}/files"
owner = "rust"
$project_files_methods
TOML
}
project_files_methods='methods = ["DELETE"]'
cat > "$w/server/rust-project-storage.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set());
module.exports = { OWNED_ROUTES, CORE_KINDS: ['index', 'unindex'], FRONT_KINDS: ['sweep'] };
JS
cat > "$w/server/rust-project-files.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'DELETE /api/projects/{id}/files',
]));
module.exports = { OWNED_ROUTES };
JS
files_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  printf '%s\n' "  if (require('./rust-project-lifecycle.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  printf '%s\n' "  kinds: require('./rust-project-storage.cjs').CORE_KINDS," >> "$w/server/index.cjs"
  [ "${1:-}" = files ] && printf '%s\n' "  if (require('./rust-project-files.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  return 0
}
files_front() { sed "s/\"start-id\"/\"start-id\", \"rust-project-lifecycle\", \"rust-project-storage\"$1/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
files_core files; files_front ""
project_files_try project-files-core-only
check "project file delete Core refusal requires the native capability" 'refused "project file delete ownership pairing"'
files_front ', \"rust-project-files\"'
project_files_try project-files-pair
check "matching project file delete pair with DELETE only assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
mv "$w/server/rust-project-files.cjs" "$work/rust-project-files.saved"
project_files_try project-files-unlisted
check "a front owning the file delete needs a Core that lists it (OWNED_ROUTES)" 'refused "does not list in server/rust-projects.cjs OWNED_ROUTES"'
mv "$work/rust-project-files.saved" "$w/server/rust-project-files.cjs"
project_files_methods=""
project_files_try project-files-all-methods
check "an all-method project files route is refused (Node keeps the other methods)" 'refused "project file delete ownership pairing"'
project_files_methods='methods = ["DELETE"]'
files_core
project_files_try project-files-front-only
check "a rust-project-files front cannot pair with the old Core handler" 'refused "project file delete ownership pairing"'
files_core files
sed "s/\"start-id\"/\"start-id\", \"rust-project-lifecycle\", \"rust-project-files\"/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-project-lifecycle.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-project-files.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
project_files_try project-files-without-storage
check "a project file delete pair without the storage pair is refused" 'refused "needs the project storage pair"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
rm -f "$w/server/rust-project-files.cjs" "$w/server/rust-project-storage.cjs"
rm -f "$w/server/rust-project-lifecycle.cjs"
# Project configuration owner release matrix (sbstndalton/noevia#2191 round 9): POST config, GET and PUT
# instruction-skills, GET manifests and a manifest's content, POST install. Moved browser rows alone are the task read pairing's to refuse.
pc_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{projectId}/config"
owner = "rust"
$pc_config_methods
[[route]]
path = "/api/projects/{projectId}/instruction-skills"
owner = "rust"
$pc_skills_methods
[[route]]
path = "/api/projects/{projectId}/instruction-skills/manifests"
owner = "rust"
methods = ["GET"]
[[route]]
path = "/api/projects/{projectId}/instruction-skills/manifests/{skillId}/content"
owner = "rust"
methods = ["GET"]
[[route]]
path = "/api/projects/{project}/skills/install"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{projectId}/browser"
owner = "$pc_browser_owner"
TOML
}
pc_config_methods='methods = ["POST"]'; pc_skills_methods='methods = ["GET", "PUT"]'; pc_browser_owner=node
cat > "$w/server/rust-project-config.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{projectId}/config',
  'GET /api/projects/{projectId}/instruction-skills',
  'PUT /api/projects/{projectId}/instruction-skills',
  'GET /api/projects/{projectId}/instruction-skills/manifests',
  'GET /api/projects/{projectId}/instruction-skills/manifests/{skillId}/content',
  'POST /api/projects/{project}/skills/install',
]));
module.exports = { OWNED_ROUTES };
JS
pc_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  printf '%s\n' "  if (require('./rust-project-config.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  [ "${1:-}" = noknown ] || printf '%s\n' "    known: allToolboxes().map((b) => b.id)," >> "$w/server/index.cjs"
  [ "${1:-}" = mount ] && printf '%s\n' "const projectRoutes = require('./routes/projects.cjs');" >> "$w/server/index.cjs"
  return 0
}
pc_front() { sed "s/\"start-id\"/\"start-id\", \"rust-project-config\"/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
pc_core; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
pc_try project-config-core-only
check "project configuration Core refusal requires the native capability" 'refused "project configuration ownership pairing"'
pc_front
pc_try project-config-pair
check "matching project configuration pair with the exact routes assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
pc_config_methods=""
pc_try project-config-all-methods
check "an all-method config route is refused (Node keeps the other methods)" 'refused "project configuration ownership pairing"'
pc_config_methods='methods = ["POST"]'; pc_skills_methods='methods = ["GET"]'
pc_try project-config-get-only
check "an instruction-skills route without its PUT is refused" 'refused "project configuration ownership pairing"'
pc_skills_methods='methods = ["GET", "PUT", "POST"]'
pc_try project-config-extra-method
check "an instruction-skills route with a method Node never answered is refused" 'refused "project configuration ownership pairing"'
pc_skills_methods='methods = ["GET", "PUT"]'; pc_browser_owner=rust
pc_try project-config-browser-moved
check "a browser row moved without the task read pair is refused" 'refused "task read ownership pairing"'
pc_browser_owner=node
mv "$w/server/rust-project-config.cjs" "$work/rust-project-config.saved"
printf 'module.exports = {};\n' > "$w/server/rust-project-config.cjs"
pc_try project-config-unlisted
check "a front owning the config routes needs a Core that refuses exactly those six" 'refused "Core must refuse exactly the six routes"'
mv "$work/rust-project-config.saved" "$w/server/rust-project-config.cjs"
pc_core mount; mkdir -p "$w/server/routes"; echo "// the old mount" > "$w/server/routes/projects.cjs"
pc_try project-config-mount
check "a Core that still mounts the project routes is refused" 'refused "Core still mounts the project routes"'
rm -f "$w/server/routes/projects.cjs"; rmdir "$w/server/routes" 2>/dev/null || true
pc_core noknown
pc_try project-config-no-known
check "a Core that does not publish the known toolboxes is refused" 'refused "does not publish the toolbox ids"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
pc_try project-config-front-only
check "a rust-project-config front cannot pair with the old Core handlers" 'refused "project configuration ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try project-config-old-pair
check "historic project configuration old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
rm -f "$w/server/rust-project-config.cjs"
# Deep research owner release matrix (sbstndalton/noevia#2218): all five paths, every method.
rr_rows() {
  for path in research research/plan 'research/{job}' 'research/{job}/cancel' 'research/{job}/save'; do
    [ "$path" = "${rr_skip:-}" ] && continue
    printf '[[route]]\npath = "/api/projects/{projectId}/%s"\nowner = "%s"\n' "$path" "$rr_owner"
    [ -n "${rr_methods:-}" ] && [ "$path" = research ] && printf '%s\n' "$rr_methods"
  done
  return 0
}
rr_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; rr_rows)
}
cat > "$w/server/rust-research.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'ALL /api/projects/{projectId}/research',
  'ALL /api/projects/{projectId}/research/plan',
  'ALL /api/projects/{projectId}/research/{job}',
  'ALL /api/projects/{projectId}/research/{job}/cancel',
  'ALL /api/projects/{projectId}/research/{job}/save',
]));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/inference-admission-lease.cjs" "$w/server/rust-research-bridge.cjs"
# Core's index.cjs for a research pair: the marker, both routes mounted, and the front's secret captured before
# clientFromEnv deletes it from process.env and handed to the lease and the bridge (review H1).
rr_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const PROJECT_STORE = require('./project-store-client.cjs').clientFromEnv(process.env);
const inferenceAdmission = require('./inference-admission-lease.cjs').createAdmissionRoutes({
  secret: FRONT_SECRET, modelManager, json, readJson,
});
const researchBridge = require('./rust-research-bridge.cjs').createResearchBridge({
  secret: FRONT_SECRET, json, readJson,
});
  if (require('./rust-research.cjs').refuseOwned(req, res, {})) return;
  if (await inferenceAdmission.handle(req, res)) return;
  if (await researchBridge(req, res)) return;
JS
}
rr_front() { sed "s/\"start-id\"/\"start-id\", \"rust-research\"/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
rr_core; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"; rr_owner=rust
rr_try research-core-only
check "deep research Core refusal requires the native capability" 'refused "deep research ownership pairing"'
rr_front
rr_try research-pair
check "matching deep research pair with all five paths assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
rr_methods='methods = ["GET"]'
rr_try research-one-method
check "a research path with only some methods is refused (Node's matcher took them all)" 'refused "deep research ownership pairing"'
rr_methods=""; rr_skip='research/{job}/save'
rr_try research-missing-path
check "a pair missing one research path is refused" 'refused "incomplete route ownership"'
rr_skip=""; rr_owner=node
rr_try research-node-rows
check "a rust-research front with Node's rows is refused" 'refused "deep research ownership pairing"'
rr_owner=rust
mv "$w/server/rust-research.cjs" "$work/rust-research.saved"; printf 'module.exports = {};\n' > "$w/server/rust-research.cjs"
rr_try research-unlisted
check "a front owning research needs a Core refusing exactly its paths" 'refused "Core must refuse exactly the five paths"'
mv "$work/rust-research.saved" "$w/server/rust-research.cjs"
touch "$w/server/research-service.cjs"
rr_try research-old-handlers
check "a Core still carrying the research handlers is refused" 'refused "still carries the research handlers"'
rm -f "$w/server/research-service.cjs" "$w/server/rust-research-bridge.cjs"
rr_try research-no-bridge
check "a Core without the bridge is refused" 'refused "admission lease and tool bridge"'
touch "$w/server/rust-research-bridge.cjs"
# The files exist but Core's index.cjs does not wire them (or wires them with an empty secret): refused.
cp "$w/server/index.cjs" "$work/rr-index.saved"
sed '/inferenceAdmission\.handle/d' "$work/rr-index.saved" > "$w/server/index.cjs"
rr_try research-no-lease-mount
check "a Core that does not mount the admission lease route is refused" 'refused "does not mount the admission lease route"'
sed '/researchBridge(req, res)/d' "$work/rr-index.saved" > "$w/server/index.cjs"
rr_try research-no-bridge-mount
check "a Core that does not mount the research bridge is refused" 'refused "does not mount the research bridge"'
# The old bug: the secret read from process.env after clientFromEnv has deleted it.
sed "s/^const FRONT_SECRET = .*/const FRONT_SECRET = 'x';/; s/secret: FRONT_SECRET, json, readJson,\$/secret: String(process.env.NOEVIA_PROJECT_STORE_TOKEN || ''), json, readJson,/" "$work/rr-index.saved" > "$w/server/index.cjs"
rr_try research-late-secret
check "a Core that reads the secret from process.env after clientFromEnv is refused" 'refused "does not capture the front.s secret"'
grep -v '^const FRONT_SECRET' "$work/rr-index.saved" | sed "s/secret: FRONT_SECRET/secret: String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '')/" > "$w/server/index.cjs"
rr_try research-env-secret
check "a Core with no captured secret is refused" 'refused "does not capture the front.s secret"'
# Captured, but after clientFromEnv: already deleted, so empty.
rr_after="const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');"
awk -v l="$rr_after" '/^const FRONT_SECRET/ { next } { print } /clientFromEnv/ { print l }' "$work/rr-index.saved" > "$w/server/index.cjs"
rr_try research-secret-after
check "a Core that captures the secret after clientFromEnv is refused" 'refused "hand its admission lease and research bridge the front.s secret"'
# Captured but only one of the two gets it.
sed "/createResearchBridge/{n;s/secret: FRONT_SECRET/secret: ''/;}" "$work/rr-index.saved" > "$w/server/index.cjs"
rr_try research-bridge-no-secret
check "a Core that gives the bridge no secret is refused" 'refused "hand its admission lease and research bridge the front.s secret"'
sed "/createAdmissionRoutes/{n;s/secret: FRONT_SECRET/secret: ''/;}" "$work/rr-index.saved" > "$w/server/index.cjs"
rr_try research-lease-no-secret
check "a Core that gives the lease no secret is refused" 'refused "hand its admission lease and research bridge the front.s secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
rr_try research-front-only
check "a rust-research front cannot pair with the old Core handlers" 'refused "deep research ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
rr_owner=rust; rr_try research-old-core-rust-rows
check "old pair whose route table gives research to Rust is refused" 'refused "deep research ownership pairing"'
move_try research-old-pair
check "historic deep research old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# The Code and Browser task reads (sbstndalton/noevia#2257): the pair, its rows and what Core must have done.
tr_project_rows() {
  for path in code 'code/{task}' browser 'browser/{task}'; do
    [ "${tr_skip:-}" = "$path" ] && continue
    printf '[[route]]\npath = "/api/projects/{projectId}/%s"\nowner = "%s"\n' "$path" "$tr_owner"
    [ "$tr_owner" = rust ] && printf '%s\n' "${tr_methods:-methods = [\"GET\"]}"
  done
  printf '[[route]]\npath = "/api/code/active"\nowner = "%s"\n' "$tr_owner"
  [ -n "${tr_active_methods:-}" ] && printf '%s\n' "$tr_active_methods"
  return 0
}
tr_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; tr_project_rows)
}
cat > "$w/server/rust-task-reads.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'ALL /api/code/active',
  'GET /api/projects/{projectId}/code',
  'GET /api/projects/{projectId}/code/{task}',
  'GET /api/projects/{projectId}/browser',
  'GET /api/projects/{projectId}/browser/{task}',
]));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/rust-task-facts.cjs"
tr_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const PROJECT_STORE = require('./project-store-client.cjs').clientFromEnv(process.env);
const taskFactsBridge = require('./rust-task-facts.cjs').createTaskFactsBridge({
  secret: FRONT_SECRET, json, readJson,
});
  if (require('./rust-task-reads.cjs').refuseOwned(req, res, {})) return;
  if (await taskFactsBridge(req, res)) return;
JS
}
tr_front() { sed "s/\"start-id\"/\"start-id\", \"rust-task-reads\"/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
tr_owner=rust; tr_core; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
tr_try tasks-core-only
check "a task read refusal needs the native capability" 'refused "task read ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; tr_front
tr_try tasks-front-only
check "a rust-task-reads front cannot pair with an old Core" 'refused "task read ownership pairing"'
tr_core
tr_try tasks-pair
check "the matching task read pair assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# #2264: both moves together, as the real mains have them: the project configuration pairing must not hold the reads back.
printf '%s\n' "  if (require('./rust-project-config.cjs').refuseOwned(req, res, {})) return;" "    known: allToolboxes().map((b) => b.id)," >> "$w/server/index.cjs"
sed -i.bak 's/"rust-task-reads"/"rust-task-reads", "rust-project-config"/' "$rz/bins/noevia-server/src/lib.rs"; rm -f "$rz/bins/noevia-server/src/lib.rs.bak"
pc_config_methods='methods = ["POST"]'; pc_skills_methods='methods = ["GET", "PUT"]'
pc_saved_refuser="$(cat "$w/server/rust-project-config.cjs" 2>/dev/null || true)"
cat > "$w/server/rust-project-config.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{projectId}/config',
  'GET /api/projects/{projectId}/instruction-skills',
  'PUT /api/projects/{projectId}/instruction-skills',
  'GET /api/projects/{projectId}/instruction-skills/manifests',
  'GET /api/projects/{projectId}/instruction-skills/manifests/{skillId}/content',
  'POST /api/projects/{project}/skills/install',
]));
module.exports = { OWNED_ROUTES };
JS
try_routes tasks-and-config-pair < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'
  printf '[[route]]\npath = "/api/projects/{projectId}/config"\nowner = "rust"\n%s\n' "$pc_config_methods"
  printf '[[route]]\npath = "/api/projects/{projectId}/instruction-skills"\nowner = "rust"\n%s\n' "$pc_skills_methods"
  printf '[[route]]\npath = "/api/projects/{projectId}/instruction-skills/manifests"\nowner = "rust"\nmethods = ["GET"]\n'
  printf '[[route]]\npath = "/api/projects/{projectId}/instruction-skills/manifests/{skillId}/content"\nowner = "rust"\nmethods = ["GET"]\n'
  printf '[[route]]\npath = "/api/projects/{project}/skills/install"\nowner = "rust"\nmethods = ["POST"]\n'
  tr_project_rows)
check "the project configuration and task read pairs assemble together" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
if [ -n "$pc_saved_refuser" ]; then printf '%s\n' "$pc_saved_refuser" > "$w/server/rust-project-config.cjs"; else rm -f "$w/server/rust-project-config.cjs"; fi
tr_core; tr_front
tr_methods='methods = ["GET", "POST"]'
tr_try tasks-post-too
check "a task POST given to the front is refused (supervision stays Node's)" 'refused "task read ownership pairing"'
tr_methods=""; tr_skip='browser/{task}'
tr_try tasks-missing-row
check "a pair missing one read is refused" 'refused "incomplete route ownership"'
tr_skip=""; tr_active_methods='methods = ["GET"]'
tr_try tasks-active-get-only
check "an active list owned for GET alone is refused" 'refused "task read ownership pairing"'
tr_active_methods=""; tr_owner=node
tr_try tasks-node-rows
check "a rust-task-reads pair with Node's rows is refused" 'refused "task read ownership pairing"'
tr_owner=rust
cp "$w/server/rust-task-reads.cjs" "$work/rust-task-reads.saved"; printf 'module.exports = {};\n' > "$w/server/rust-task-reads.cjs"
tr_try tasks-unlisted
check "a Core not refusing exactly the five reads is refused" 'refused "Core must refuse exactly the five reads"'
cp "$work/rust-task-reads.saved" "$w/server/rust-task-reads.cjs"
mkdir -p "$w/server/routes"; [ -f "$w/server/routes/code.cjs" ] && cp "$w/server/routes/code.cjs" "$work/tr-code.saved" || : > "$work/tr-code.saved"
printf 'send(200, service.list(ws, project));\n' >> "$w/server/routes/code.cjs"
tr_try tasks-old-handlers
check "a Core still carrying the read handlers is refused" 'refused "still carries the task read handlers"'
if [ -s "$work/tr-code.saved" ]; then cp "$work/tr-code.saved" "$w/server/routes/code.cjs"; else rm -f "$w/server/routes/code.cjs"; fi
rm -f "$w/server/rust-task-facts.cjs"
tr_try tasks-no-facts
check "a Core without the facts bridge is refused" 'refused "does not offer the front its task facts"'
touch "$w/server/rust-task-facts.cjs"
cp "$w/server/index.cjs" "$work/tr-index.saved"
sed '/taskFactsBridge(req, res)/d' "$work/tr-index.saved" > "$w/server/index.cjs"
tr_try tasks-no-mount
check "a Core that does not mount the facts bridge is refused" 'refused "does not mount the task facts bridge"'
sed "s/secret: FRONT_SECRET/secret: ''/" "$work/tr-index.saved" > "$w/server/index.cjs"
tr_try tasks-no-secret
check "a Core that gives the facts bridge no secret is refused" 'refused "front.s captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
tr_owner=node
tr_try tasks-old-pair
check "the old pair with Node's rows stays a valid rollback" '[ $rc -eq 0 ]'
tr_owner=rust
tr_try tasks-old-with-rust-rows
check "an old pair whose table gives the reads to Rust is refused" 'refused "task read ownership pairing"'
rm -f "$w/server/rust-task-reads.cjs" "$w/server/rust-task-facts.cjs"
rm -f "$w/server/rust-research.cjs" "$w/server/inference-admission-lease.cjs" "$w/server/rust-research-bridge.cjs"
# #2282 tool approval public-policy/bridge pairing.
ta_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; printf '[[route]]\npath = "/api/tool-approvals/{approvalId}"\nowner = "%s"\n' "$ta_owner"; [ "$ta_owner" != rust ] || printf '%s\n' "${ta_methods:-methods = [\"POST\"]}")
}
cat > "$w/server/rust-tool-approvals.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['POST /api/tool-approvals/{approvalId}']));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/rust-tool-approval-bridge.cjs"
ta_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const toolApprovalBridge = require('./rust-tool-approval-bridge.cjs').createToolApprovalBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-tool-approvals.cjs').refuseOwned(req, res, {})) return;
if (await toolApprovalBridge(req, res)) return;
JS
}
ta_front() { sed 's/"start-id"/"start-id", "rust-tool-approvals"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
ta_owner=rust; ta_core
ta_try approvals-core-only
check "approval Core requires the native front" 'refused "tool approval ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; ta_front
ta_try approvals-front-only
check "native approval front requires its Core refusal" 'refused "tool approval ownership pairing"'
ta_core
ta_try approvals-pair
check "approval paired public policy and pending state bridge assemble" '[ $rc -eq 0 ]'
ta_methods='methods = ["POST", "GET"]'
ta_try approvals-extra-method
check "approval migration owns POST alone" 'refused "tool approval ownership pairing"'
ta_methods=""; ta_owner=node
ta_try approvals-node-row
check "approval native pair cannot retain a Node-owned row" 'refused "tool approval ownership pairing"'
ta_owner=rust
mkdir -p "$w/server/routes"; touch "$w/server/routes/approvals.cjs"
ta_try approvals-old-handler
check "approval native pair deletes the public Node handler" 'refused "still carries the public handler"'
rm -f "$w/server/routes/approvals.cjs"
cp "$w/server/index.cjs" "$work/ta-index.saved"
sed '/toolApprovalBridge(req, res)/d' "$work/ta-index.saved" > "$w/server/index.cjs"
ta_try approvals-no-mount
check "approval pending bridge must be mounted" 'refused "missing bridge mount"'
sed "s/secret: FRONT_SECRET/secret: ''/" "$work/ta-index.saved" > "$w/server/index.cjs"
ta_try approvals-no-secret
check "approval pending bridge requires captured front secret" 'refused "missing captured front secret"'
cp "$work/ta-index.saved" "$w/server/index.cjs"
rm -f "$w/server/rust-tool-approval-bridge.cjs"
ta_try approvals-no-bridge
check "approval pending state bridge must exist" 'refused "missing pending state bridge"'
touch "$w/server/rust-tool-approval-bridge.cjs"
cp "$w/server/rust-tool-approvals.cjs" "$work/ta-refusal.saved"
printf '%s\n' 'module.exports = {};' > "$w/server/rust-tool-approvals.cjs"
ta_try approvals-no-owned-route
check "approval refusal must list the exact POST" 'refused "Core must refuse exactly the approval POST"'
cp "$work/ta-refusal.saved" "$w/server/rust-tool-approvals.cjs"
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
ta_owner=node
ta_try approvals-old-pair
check "historic approval old/old rollback pair assembles" '[ $rc -eq 0 ]'
ta_owner=rust
ta_try approvals-old-rust-row
check "historic pair cannot assign approvals to Rust" 'refused "tool approval ownership pairing"'
cp "$w/server/rust-tool-approvals.cjs" "$work/ta-refuser.paired"
rm -f "$w/server/rust-tool-approvals.cjs" "$w/server/rust-tool-approval-bridge.cjs"
# Chat port S4: the framing suggestion's owner pair (every method Rust's) and its loopback bridge.
fs_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; printf '[[route]]\npath = "/api/chat-framing/suggest"\nowner = "%s"\n' "$fs_owner"; [ -z "${fs_methods:-}" ] || printf '%s\n' "$fs_methods")
}
cat > "$w/server/rust-chat-framing-suggest.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['POST /api/chat-framing/suggest']));
module.exports = { OWNED_ROUTES };
JS
fs_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const chatFramingSuggestBridge = require('./rust-chat-framing-suggest.cjs').createSuggestBridge({
  secret: FRONT_SECRET, json, readJson, framing: chatFraming,
});
if (require('./rust-chat-framing-suggest.cjs').refuseOwned(req, res, {})) return;
if (await chatFramingSuggestBridge(req, res)) return;
JS
}
fs_front() { sed 's/"start-id"/"start-id", "rust-chat-framing-suggest"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
[ ! -f "$w/server/routes/chat-framing.cjs" ] || cp "$w/server/routes/chat-framing.cjs" "$work/fs-routes.saved"
mkdir -p "$w/server/routes"; printf '%s\n' 'module.exports = {};' > "$w/server/routes/chat-framing.cjs"
fs_owner=rust; fs_methods=""; fs_core
fs_try suggest-core-only
check "framing suggestion Core requires the native front" 'refused "framing suggestion ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; fs_front
fs_try suggest-front-only
check "native framing suggestion front requires its Core refusal" 'refused "framing suggestion ownership pairing"'
fs_core
fs_try suggest-pair
check "framing suggestion pair with its loopback bridge assembles" '[ $rc -eq 0 ]'
fs_methods='methods = ["POST"]'
fs_try suggest-post-only-row
check "framing suggestion: every method must be Rust's, not only POST" 'refused "every method must belong to Rust"'
fs_methods=""; fs_owner=node
fs_try suggest-node-row
check "framing suggestion native pair cannot keep a Node-owned row" 'refused "every method must belong to Rust"'
fs_owner=rust
printf '%s\n' '    const result = await framing.suggest({ message });' > "$w/server/routes/chat-framing.cjs"
fs_try suggest-old-handler
check "framing suggestion native pair drops the public Node suggestion" 'refused "still carries the public suggestion handler"'
printf '%s\n' 'module.exports = {};' '// framing.suggest(' > "$w/server/routes/chat-framing.cjs"
fs_try suggest-commented-handler
check "framing suggestion: a commented-out call is not the handler" '[ $rc -eq 0 ]'
cp "$w/server/index.cjs" "$work/fs-index.saved"
sed '/chatFramingSuggestBridge(req, res)/d' "$work/fs-index.saved" > "$w/server/index.cjs"
fs_try suggest-no-mount
check "framing suggestion bridge must be mounted" 'refused "framing suggestion ownership pairing: missing bridge mount"'
sed "s/secret: FRONT_SECRET/secret: ''/" "$work/fs-index.saved" > "$w/server/index.cjs"
fs_try suggest-no-secret
check "framing suggestion bridge requires the captured front secret" 'refused "framing suggestion ownership pairing: missing captured front secret"'
cp "$work/fs-index.saved" "$w/server/index.cjs"
printf "%s\n" "const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/chat-framing/suggest']));" > "$w/server/rust-chat-framing-suggest.cjs"
fs_try suggest-all-refuser
check "framing suggestion: Core refuses exactly the POST" 'refused "Core must refuse exactly this POST"'
printf '%s\n' "/*" "const OWNED_ROUTES = Object.freeze(new Set(['POST /api/chat-framing/suggest']));" "*/" > "$w/server/rust-chat-framing-suggest.cjs"
fs_try suggest-comment-marker
check "framing suggestion: the refusal must be executable code" 'refused "Core must refuse exactly this POST"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
fs_owner=node
fs_try suggest-old-pair
check "framing suggestion old/old rollback pair assembles" '[ $rc -eq 0 ]'
fs_owner=rust
fs_try suggest-old-rust-row
check "an old pair cannot give the suggestion to Rust" 'refused "framing suggestion ownership pairing"'
if [ -f "$work/fs-routes.saved" ]; then cp "$work/fs-routes.saved" "$w/server/routes/chat-framing.cjs"; else rm -f "$w/server/routes/chat-framing.cjs"; fi
rm -f "$w/server/rust-chat-framing-suggest.cjs"
# #2281 toolbox picker owner pair and the narrow facts bridge.
tp_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    if [ "${tp_skip:-}" != yes ]; then printf '[[route]]\npath = "/api/toolboxes"\nowner = "%s"\n' "$tp_owner"; [ -z "${tp_methods:-}" ] || printf '%s\n' "$tp_methods"; fi)
}
cat > "$w/server/rust-toolbox-picker.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/toolboxes']));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/rust-toolbox-picker-facts.cjs"
tp_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const toolboxPickerFacts = require('./rust-toolbox-picker-facts.cjs').createToolboxPickerFacts({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-toolbox-picker.cjs').refuseOwned(req, res, {})) return;
if (await toolboxPickerFacts(req, res)) return;
JS
}
tp_front() { sed 's/"start-id"/"start-id", "rust-toolbox-picker"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
tp_owner=rust; tp_core
tp_try picker-core-only
check "picker Core refusal cannot pair with an old front" 'refused "toolbox picker ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; tp_front
tp_try picker-front-only
check "picker capability cannot pair with an old Core" 'refused "toolbox picker ownership pairing"'
tp_core; tp_try picker-pair
check "matching toolbox picker pair assembles" '[ $rc -eq 0 ]'
tp_owner=node; tp_try picker-node-rows
check "picker native pair rejects Node rows" 'refused "toolbox picker ownership pairing"'
tp_owner=rust; tp_skip=yes; tp_try picker-missing-row
check "picker native pair rejects missing rows" 'refused "incomplete route ownership"'
unset tp_skip; tp_methods='methods = ["GET"]'; tp_try picker-partial-row
check "picker native pair owns 405s as well as GET" 'refused "toolbox picker ownership pairing"'
unset tp_methods
cp "$w/server/rust-toolbox-picker.cjs" "$work/tp-refuser.saved"
printf 'const OWNED_ROUTES = Object.freeze(new Set([]));\n' > "$w/server/rust-toolbox-picker.cjs"
tp_try picker-refuser
check "picker pair rejects incomplete Core refusal" 'refused "Core must refuse exactly the picker"'
cp "$work/tp-refuser.saved" "$w/server/rust-toolbox-picker.cjs"
touch "$w/server/routes/toolboxes.cjs"; tp_try picker-dead-handler
check "picker pair rejects retained public Node handler" 'refused "Core still carries the public handler"'
rm -f "$w/server/routes/toolboxes.cjs"
mv "$w/server/rust-toolbox-picker-facts.cjs" "$work/tp-facts.saved"; tp_try picker-missing-facts
check "picker pair requires facts bridge" 'refused "missing raw facts bridge"'
mv "$work/tp-facts.saved" "$w/server/rust-toolbox-picker-facts.cjs"
cp "$w/server/index.cjs" "$work/tp-index.saved"
sed '/await toolboxPickerFacts(req, res)/d' "$work/tp-index.saved" > "$w/server/index.cjs"
tp_try picker-no-mount
check "picker pair requires bridge mount" 'refused "missing facts mount"'
sed 's/secret: FRONT_SECRET/secret: null/' "$work/tp-index.saved" > "$w/server/index.cjs"
tp_try picker-no-secret
check "picker pair requires captured bridge secret" 'refused "front captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
tp_try picker-old-rust-rows
check "old picker pair rejects Rust rows" 'refused "toolbox picker ownership pairing"'
tp_owner=node; tp_try picker-old-pair
check "old toolbox picker pair remains a valid rollback" '[ $rc -eq 0 ]'
# Exercise both moves in one candidate and independently during rollback.
cp "$work/ta-refuser.paired" "$w/server/rust-tool-approvals.cjs"
touch "$w/server/rust-tool-approval-bridge.cjs"
ports_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/toolboxes"
owner = "$tp_owner"
[[route]]
path = "/api/tool-approvals/{approvalId}"
owner = "$ta_owner"
methods = ["POST"]
TOML
}
ta_core
# Both bridges use the same captured front secret.
sed -n '/^const toolboxPickerFacts = /,$p' "$work/tp-index.saved" >> "$w/server/index.cjs"
sed 's/"start-id"/"start-id", "rust-tool-approvals", "rust-toolbox-picker"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
ta_owner=rust; tp_owner=rust
ports_try combined-ports
check "approval and toolbox native pairs assemble together" '[ $rc -eq 0 ]'
ta_core; ta_front; tp_owner=node
ports_try approval-native-picker-old
check "approval native pair permits toolbox rollback" '[ $rc -eq 0 ]'
tp_core; tp_front; tp_owner=rust; ta_owner=node
ports_try picker-native-approval-old
check "toolbox native pair permits approval rollback" '[ $rc -eq 0 ]'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
ta_owner=node; tp_owner=node
ports_try combined-old-pair
check "both port pairs permit historic rollback together" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-tool-approvals.cjs" "$w/server/rust-tool-approval-bridge.cjs"
rm -f "$w/server/rust-toolbox-picker.cjs" "$w/server/rust-toolbox-picker-facts.cjs"
# GET inference-budget and GET installed (sbstndalton/noevia#2262): the pair, its rows and what Core must have done.
ms_rows() {
  for path in inference-budget installed; do
    [ "${ms_skip:-}" = "$path" ] && continue
    printf '[[route]]\npath = "/api/models/%s"\nowner = "%s"\n' "$path" "$ms_owner"
    [ "$ms_owner" = rust ] && printf '%s\n' "${ms_methods:-methods = [\"GET\"]}"
  done
  return 0
}
ms_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; ms_rows)
}
printf '%s\n' "const OWNED_PATHS = Object.freeze(['/api/models/inference-budget', '/api/models/installed']);" > "$w/server/rust-model-state-reads.cjs"
touch "$w/server/rust-model-facts.cjs"
ms_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const PROJECT_STORE = require('./project-store-client.cjs').clientFromEnv(process.env);
const modelFactsBridge = require('./rust-model-facts.cjs').createModelFactsBridge({
  secret: FRONT_SECRET, json, readJson,
});
  if (require('./rust-model-state-reads.cjs').refuseOwned(req, res, {})) return;
  if (await modelFactsBridge(req, res)) return;
JS
}
ms_front() { sed "s/\"start-id\"/\"start-id\", \"rust-model-state-reads\"/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
ms_owner=rust; ms_core; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
ms_try model-state-core-only
check "a model state refusal needs the native capability" 'refused "model state read ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; ms_front
ms_try model-state-front-only
check "a rust-model-state-reads front cannot pair with an old Core" 'refused "model state read ownership pairing"'
ms_core
ms_try model-state-pair
check "the matching model state pair assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
ms_methods='methods = ["GET", "PUT"]'
ms_try model-state-put-too
check "the budget PUT given to the front is refused (it stays Node's)" 'refused "model state read ownership pairing"'
ms_methods=""; ms_skip=installed
ms_try model-state-missing-row
check "a model state pair missing one read is refused" 'refused "incomplete route ownership"'
ms_skip=""; ms_owner=node
ms_try model-state-node-rows
check "a rust-model-state-reads pair with Node's rows is refused" 'refused "model state read ownership pairing"'
ms_owner=rust
cp "$w/server/rust-model-state-reads.cjs" "$work/ms-reads.saved"; printf 'module.exports = {};\n' > "$w/server/rust-model-state-reads.cjs"
ms_try model-state-unlisted
check "a Core not refusing exactly the two reads is refused" 'refused "Core must refuse exactly the two reads"'
cp "$work/ms-reads.saved" "$w/server/rust-model-state-reads.cjs"
mkdir -p "$w/server/routes"; [ -f "$w/server/routes/models.cjs" ] && cp "$w/server/routes/models.cjs" "$work/ms-models.saved" || : > "$work/ms-models.saved"
printf 'await modelManager.inferenceEstimates();\n' >> "$w/server/routes/models.cjs"
ms_try model-state-old-handlers
check "a Core still carrying the read handlers is refused" 'refused "still carries the read handlers"'
if [ -s "$work/ms-models.saved" ]; then cp "$work/ms-models.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi
rm -f "$w/server/rust-model-facts.cjs"
ms_try model-state-no-facts
check "a Core without the model facts bridge is refused" 'refused "does not offer the front its model facts"'
touch "$w/server/rust-model-facts.cjs"
cp "$w/server/index.cjs" "$work/ms-index.saved"
sed '/modelFactsBridge(req, res)/d' "$work/ms-index.saved" > "$w/server/index.cjs"
ms_try model-state-no-mount
check "a Core that does not mount the model facts bridge is refused" 'refused "does not mount the model facts bridge"'
sed "s/secret: FRONT_SECRET/secret: ''/" "$work/ms-index.saved" > "$w/server/index.cjs"
ms_try model-state-no-secret
check "a Core that gives the model facts bridge no secret is refused" 'refused "front.s captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
ms_owner=node
ms_try model-state-old-pair
check "the old model state pair with Node's rows stays a valid rollback" '[ $rc -eq 0 ]'
ms_owner=rust
ms_try model-state-old-with-rust-rows
check "an old pair whose table gives the model state reads to Rust is refused" 'refused "model state read ownership pairing"'
rm -f "$w/server/rust-model-state-reads.cjs" "$w/server/rust-model-facts.cjs"
# #2306: GET-only status ownership; POST start stays in the same Node route module.
atr_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    if [ "${atr_skip:-}" != yes ]; then printf '[[route]]\npath = "/api/models/autotune"\nowner = "%s"\n' "$atr_owner"; [ -z "${atr_methods:-}" ] || printf '%s\n' "$atr_methods"; fi)
}
cat > "$w/server/rust-autotune-read.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['GET /api/models/autotune']));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/rust-autotune-read-bridge.cjs"
[ ! -f "$w/server/llamacpp-manager.cjs" ] || cp "$w/server/llamacpp-manager.cjs" "$work/atr-manager.saved"
[ ! -f "$w/server/routes/models.cjs" ] || cp "$w/server/routes/models.cjs" "$work/atr-models.saved"
printf '%s\n' 'statusFacts: autotuner.statusFacts,' > "$w/server/llamacpp-manager.cjs"
printf '%s\n' "if (req.method === 'POST') modelManager.autotune.start(model, options);" > "$w/server/routes/models.cjs"
atr_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const autotuneReadBridge = require('./rust-autotune-read-bridge.cjs').createAutotuneReadBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-autotune-read.cjs').refuseOwned(req, res, {})) return;
if (await autotuneReadBridge(req, res)) return;
JS
}
atr_front() { sed 's/"start-id"/"start-id", "rust-autotune-read"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
atr_owner=rust; atr_methods='methods = ["GET"]'; atr_core
atr_try atr-core-only
check "GET autotune status refusal cannot pair with an old front" 'refused "auto-tune read ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; atr_front
atr_try atr-front-only
check "GET autotune status capability cannot pair with old Core" 'refused "auto-tune read ownership pairing"'
atr_core; atr_try atr-pair
check "matching GET-only autotune status pair assembles" '[ $rc -eq 0 ]'
atr_owner=node; atr_try atr-node-rows
check "native status pair rejects Node GET ownership" 'refused "auto-tune read ownership pairing"'
atr_owner=rust; atr_skip=yes; atr_try atr-missing-row
check "native status pair requires its route row" 'refused "incomplete route ownership"'
unset atr_skip; atr_methods='methods = ["POST"]'; atr_try atr-post-row
check "status capability cannot claim POST start" 'refused "GET only; POST start and other methods stay Node"'
unset atr_methods; atr_try atr-all-row
check "status capability cannot claim the whole autotune path" 'refused "GET only; POST start and other methods stay Node"'
atr_methods='methods = ["GET"]'
cp "$w/server/rust-autotune-read.cjs" "$work/atr-refuser.saved"
printf 'const OWNED_ROUTES = Object.freeze(new Set(["ALL /api/models/autotune"]));\n' > "$w/server/rust-autotune-read.cjs"; atr_try atr-all-refuser
check "native status pair refuses exactly GET, never POST or all verbs" 'refused "Core must refuse exactly GET status"'
cp "$work/atr-refuser.saved" "$w/server/rust-autotune-read.cjs"
[ ! -f "$w/server/llamacpp-full-autotune.cjs" ] || cp "$w/server/llamacpp-full-autotune.cjs" "$work/atr-actor.saved"
printf 'const status = model => ({status:200,body:{}});\n' >> "$w/server/llamacpp-full-autotune.cjs"; atr_try atr-old-formatter
check "native status pair rejects the old response formatter" 'refused "public status formatter"'
if [ -f "$work/atr-actor.saved" ]; then cp "$work/atr-actor.saved" "$w/server/llamacpp-full-autotune.cjs"; else rm -f "$w/server/llamacpp-full-autotune.cjs"; fi
cp "$w/server/routes/models.cjs" "$work/atr-live-models.saved"
printf 'modelManager.autotune.status(model);\n' >> "$w/server/routes/models.cjs"; atr_try atr-old-get
check "native status pair rejects the Node GET handler" 'refused "public GET handler"'
cp "$work/atr-live-models.saved" "$w/server/routes/models.cjs"
printf 'module.exports = {};\n' > "$w/server/routes/models.cjs"; atr_try atr-missing-post
check "native status pair preserves Node POST start" 'refused "POST start must stay Node-owned"'
cp "$work/atr-live-models.saved" "$w/server/routes/models.cjs"
cp "$w/server/llamacpp-manager.cjs" "$work/atr-live-manager.saved"; printf 'module.exports = {};\n' > "$w/server/llamacpp-manager.cjs"; atr_try atr-no-facts
check "native status pair needs the raw state getter" 'refused "raw status facts"'
cp "$work/atr-live-manager.saved" "$w/server/llamacpp-manager.cjs"
mv "$w/server/rust-autotune-read-bridge.cjs" "$work/atr-bridge.saved"; atr_try atr-no-bridge
check "native status pair needs its facts bridge" 'refused "missing facts bridge"'
mv "$work/atr-bridge.saved" "$w/server/rust-autotune-read-bridge.cjs"
cp "$w/server/index.cjs" "$work/atr-index.saved"
sed '/await autotuneReadBridge(req, res)/d' "$work/atr-index.saved" > "$w/server/index.cjs"; atr_try atr-no-mount
check "native status pair needs a bridge mount" 'refused "missing facts bridge mount"'
sed 's/secret: FRONT_SECRET/secret: null/' "$work/atr-index.saved" > "$w/server/index.cjs"; atr_try atr-no-secret
check "native status facts need the captured front secret" 'refused "front captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
atr_try atr-old-rust-rows
check "old status pair rejects a Rust-owned GET row" 'refused "auto-tune read ownership pairing"'
atr_owner=node; unset atr_methods; atr_try atr-old-pair
check "old full-Node autotune pair stays valid for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-autotune-read.cjs" "$w/server/rust-autotune-read-bridge.cjs"
if [ -f "$work/atr-manager.saved" ]; then cp "$work/atr-manager.saved" "$w/server/llamacpp-manager.cjs"; else rm -f "$w/server/llamacpp-manager.cjs"; fi
if [ -f "$work/atr-models.saved" ]; then cp "$work/atr-models.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi
# #1863: only the idle unload GET moves.
iur_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    printf '[[route]]\npath = "/api/models/idle-unload"\nowner = "%s"\n' "$iur_owner"; [ -z "${iur_methods:-}" ] || printf '%s\n' "$iur_methods")
}
printf '%s\n' "const OWNED_ROUTES = Object.freeze(new Set(['GET /api/models/idle-unload']));" > "$w/server/rust-idle-unload-read.cjs"
touch "$w/server/rust-idle-unload-read-facts.cjs"
[ ! -f "$w/server/routes/models.cjs" ] || cp "$w/server/routes/models.cjs" "$work/iur-models.saved"
printf '%s\n' 'idleUnload.save(body, actor);' > "$w/server/routes/models.cjs"
printf '%s\n' 'async function effectiveSeconds() {}' > "$w/server/idle-unload-setting.cjs"
iur_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const idleUnloadFacts = require('./rust-idle-unload-read-facts.cjs').createIdleUnloadFacts({
  secret: FRONT_SECRET, json,
});
if (require('./rust-idle-unload-read.cjs').refuseOwned(req, res, {})) return;
if (await idleUnloadFacts(req, res)) return;
JS
}
iur_owner=rust; iur_methods='methods = ["GET"]'; iur_core
iur_try iur-core-only
check "idle unload GET Core refusal requires native capability" 'refused "idle unload read ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
sed 's/"start-id"/"start-id", "rust-idle-unload-read"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
iur_try iur-front-only
check "native idle unload GET requires its paired Core" 'refused "idle unload read ownership pairing"'
iur_core; iur_try iur-pair
check "matching idle unload GET pair assembles" '[ $rc -eq 0 ]'
iur_methods='methods = ["PUT"]'; iur_try iur-put
check "idle unload GET pair cannot claim the write" 'refused "GET only; PUT and other methods stay Node"'
iur_methods='methods = ["GET"]'
printf '%s\n' 'idleUnload.get();' >> "$w/server/routes/models.cjs"
iur_try iur-retained-get
check "idle unload GET pair rejects a retained Node handler" 'refused "public GET handler"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
iur_owner=node; unset iur_methods; iur_try iur-old-pair
check "old idle unload pair remains available for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-idle-unload-read.cjs" "$w/server/rust-idle-unload-read-facts.cjs" "$w/server/idle-unload-setting.cjs"
if [ -f "$work/iur-models.saved" ]; then cp "$work/iur-models.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi
# #2238: only the model assignments GET moves.
mas_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    printf '[[route]]\npath = "/api/models/assignments"\nowner = "%s"\n' "$mas_owner"; [ -z "${mas_methods:-}" ] || printf '%s\n' "$mas_methods")
}
printf '%s\n' "const OWNED_ROUTES = Object.freeze(new Set(['GET /api/models/assignments']));" > "$w/server/rust-model-assignments.cjs"
touch "$w/server/rust-model-assignments-facts.cjs"
mas_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const modelAssignmentsFacts = require('./rust-model-assignments-facts.cjs').createModelAssignmentsFacts({
  secret: FRONT_SECRET, json,
});
if (require('./rust-model-assignments.cjs').refuseOwned(req, res, {})) return;
if (await modelAssignmentsFacts(req, res)) return;
JS
}
mas_owner=rust; mas_methods='methods = ["GET"]'; mas_core
mas_try mas-core-only
check "model assignments GET Core refusal requires native capability" 'refused "model assignments read ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
sed 's/"start-id"/"start-id", "rust-model-assignments"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
mas_try mas-front-only
check "native model assignments GET requires its paired Core" 'refused "model assignments read ownership pairing"'
mas_core; mas_try mas-pair
check "matching model assignments GET pair assembles" '[ $rc -eq 0 ]'
mas_methods='methods = ["PUT"]'; mas_try mas-put
check "model assignments GET pair cannot claim the write" 'refused "GET only; other methods stay Node"'
mas_methods='methods = ["GET"]'
cp "$w/server/rust-model-assignments.cjs" "$work/mas-refuser.saved"
{ printf '/*\n'; cat "$work/mas-refuser.saved"; printf '*/\n'; } > "$w/server/rust-model-assignments.cjs"
mas_try mas-comment-only
check "model assignments marker inside a comment is refused" 'refused "Core must refuse exactly GET model assignments"'
printf '%s\n' "const OWNED_ROUTES = Object.freeze(new Set(['GET /api/models/assignments', ...extra]));" > "$w/server/rust-model-assignments.cjs"
mas_try mas-dynamic
check "model assignments marker cannot include dynamic methods" 'refused "Core must refuse exactly GET model assignments"'
cp "$work/mas-refuser.saved" "$w/server/rust-model-assignments.cjs"
touch "$w/server/model-assignments.cjs"
mas_try mas-retained-get
check "model assignments GET pair rejects a retained Node formatter" 'refused "public GET formatter"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
mas_owner=node; unset mas_methods; mas_try mas-old-pair
check "old model assignments pair remains available for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-model-assignments.cjs" "$w/server/rust-model-assignments-facts.cjs" "$w/server/model-assignments.cjs"
# Download GET pairs the exact refuser with its bounded facts owner.
mdr_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    if [ "${mdr_owner:-}" ]; then
      printf '[[route]]\npath = "/api/models/downloads"\nowner = "%s"\n%s\n' "$mdr_owner" "${mdr_methods:-}"
    fi)
}
[ ! -f "$w/server/routes/models.cjs" ] || cp "$w/server/routes/models.cjs" "$work/mdr-models.saved"
printf "%s\n" "    if (p === '/api/models/downloads' && req.method !== 'GET') {" > "$w/server/routes/models.cjs"
touch "$w/server/rust-model-downloads-read-facts.cjs"
printf "%s\n" "const OWNED_ROUTES = Object.freeze(new Set(['GET /api/models/downloads']));" > "$w/server/rust-model-downloads-read.cjs"
cp "$work/feature-index.saved" "$w/server/index.cjs"
cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const modelDownloadsFacts = require('./rust-model-downloads-read-facts.cjs').createModelDownloadsFacts({
  secret: FRONT_SECRET, json,
});
if (require('./rust-model-downloads-read.cjs').refuseOwned(req, res, {})) return;
if (await modelDownloadsFacts(req, res)) return;
JS
cp "$w/server/index.cjs" "$work/mdr-index.saved"
mdr_owner=rust; mdr_methods='methods = ["GET"]'; mdr_try mdr-core-only
check "download GET refuser rejects old front" 'refused "model downloads read ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
sed 's/"start-id"/"start-id", "rust-model-downloads-read"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
mdr_try mdr-front-only
check "download GET capability rejects old Core" 'refused "model downloads read ownership pairing"'
cp "$work/mdr-index.saved" "$w/server/index.cjs"
mdr_try mdr-pair
check "matching download GET pair assembles" '[ $rc -eq 0 ]'
mdr_methods='methods = ["GET", "HEAD"]'; mdr_try mdr-wrong-methods
check "download GET cannot claim HEAD" 'refused "other methods stay Node"'
mdr_methods='methods = ["GET"]'
cat > "$w/server/rust-model-downloads-read.cjs" <<'JS'
/*
const OWNED_ROUTES = Object.freeze(new Set(['GET /api/models/downloads']));
*/
JS
mdr_try mdr-comment-marker
check "download GET marker must be executable code" 'refused "Core must refuse exactly this GET"'
printf "%s\n" "const OWNED_ROUTES = Object.freeze(new Set(['GET /api/models/downloads']));" > "$w/server/rust-model-downloads-read.cjs"
printf "%s\n" "    if (p === '/api/models/downloads') {" > "$w/server/routes/models.cjs"
mdr_try mdr-old-branch
check "paired download read rejects legacy GET handler" 'refused "Core must retain only the legacy methods"'
# Since noevia-core 9919523 the non-GET methods may instead be residuals that rust-residual-fallbacks.cjs
# refuses (paired with the front's rust-residual-fallbacks-v1 by the residual fallback pairing).
cat > "$work/mdr-residual.cjs" <<'JS'
'use strict';
const RUST_RESIDUAL_FALLBACKS_OWNED = 'rust-residual-fallbacks-v1';
function owned(method, p) {
  if (p === '/api/models/downloads') return method !== 'GET';
  return p.startsWith('/api/models/synthetic-');
}
function refuseOwned(req, res, { parseRequestUrl, json }) {
  const p = parseRequestUrl(req)?.pathname;
  if (!p || !owned(req.method, p)) return false;
  json(res, 503, { error: 'synthetic residual refusal' });
  return true;
}
module.exports = { RUST_RESIDUAL_FALLBACKS_OWNED, owned, refuseOwned };
JS
sed "s|  if (p === '/api/models/downloads') return method !== 'GET';|  if (p === '/api/models/downloads') return false;|" "$work/mdr-residual.cjs" > "$work/mdr-residual-keeps.cjs"
sed "s|  if (p === '/api/models/downloads') return method !== 'GET';|  if (p === '/api/models/downloads') return true;|" "$work/mdr-residual.cjs" > "$work/mdr-residual-get.cjs"
check "residual download fixtures differ only in what they refuse" \
  '! cmp -s "$work/mdr-residual.cjs" "$work/mdr-residual-keeps.cjs" && ! cmp -s "$work/mdr-residual.cjs" "$work/mdr-residual-get.cjs"'
mdr_mount="if (require('./rust-residual-fallbacks.cjs').refuseOwned(req, res, { parseRequestUrl, json })) return;"
mdr_no_handler="    // /api/models/downloads non-GET residuals are refused at the front ownership boundary."
# mdr_residual <residual module|none> <index.cjs mount line> <routes/models.cjs line>
mdr_residual() {
  if [ "$1" = none ]; then rm -f "$w/server/rust-residual-fallbacks.cjs"; else cp "$1" "$w/server/rust-residual-fallbacks.cjs"; fi
  cp "$work/mdr-index.saved" "$w/server/index.cjs"; printf '%s\n' "$2" >> "$w/server/index.cjs"
  printf '%s\n' "$3" > "$w/server/routes/models.cjs"
}
mdr_legacy='refused "model downloads read ownership pairing: Core must retain only the legacy methods"'
sed 's/"start-id"/"start-id", "rust-model-downloads-read", "rust-residual-fallbacks-v1"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
mdr_residual "$work/mdr-residual.cjs" "$mdr_mount" "$mdr_no_handler"
mdr_try mdr-residual-pair
check "download GET pair with residual non-GET methods (Core 9919523) assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
mdr_residual "$work/mdr-residual.cjs" "// $mdr_mount" "$mdr_no_handler"
mdr_try mdr-residual-unmounted
check "a residual boundary index.cjs only mentions in a comment does not replace the legacy methods" "$mdr_legacy"
mdr_residual none "$mdr_mount" "$mdr_no_handler"
mdr_try mdr-residual-missing
check "a residual boundary index.cjs requires but Core lacks does not replace the legacy methods" "$mdr_legacy"
mdr_residual "$work/mdr-residual-keeps.cjs" "$mdr_mount" "$mdr_no_handler"
mdr_try mdr-residual-keeps-downloads
check "a residual boundary that lets non-GET downloads through does not replace the legacy methods" "$mdr_legacy"
mdr_residual "$work/mdr-residual-get.cjs" "$mdr_mount" "$mdr_no_handler"
mdr_try mdr-residual-refuses-get
check "a residual boundary that also refuses the GET does not replace the legacy methods" "$mdr_legacy"
mdr_residual "$work/mdr-residual.cjs" "$mdr_mount" "    if (p === '/api/models/downloads') {"
mdr_try mdr-residual-node-handler
check "a residual boundary beside a Node downloads handler is refused" "$mdr_legacy"
sed 's/"start-id"/"start-id", "rust-model-downloads-read"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
mdr_residual "$work/mdr-residual.cjs" "$mdr_mount" "$mdr_no_handler"
mdr_try mdr-residual-old-front
check "residual download methods still need the front's residual capability" 'refused "residual fallback pairing: Core and Rust must move together"'
rm -f "$w/server/rust-residual-fallbacks.cjs"
printf "%s\n" "    if (p === '/api/models/downloads') {" > "$w/server/routes/models.cjs"
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
mdr_try mdr-old-rust-row
check "old download pair rejects Rust ownership" 'refused "model downloads read ownership pairing"'
unset mdr_owner mdr_methods; mdr_try mdr-old-pair
check "old download pair stays valid for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-model-downloads-read.cjs" "$w/server/rust-model-downloads-read-facts.cjs"
if [ -f "$work/mdr-models.saved" ]; then cp "$work/mdr-models.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi
# Preset GET and its shared snapshot owner. Exercise the literal used by the real refuser.
pr_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    printf '[[route]]\npath = "/api/models/preset"\nowner = "%s"\n%s\n' "$pr_owner" "${pr_methods:-}")
}
for pr_file in llamacpp-manager.cjs routes/models.cjs; do
  [ ! -f "$w/server/$pr_file" ] || cp "$w/server/$pr_file" "$work/pr-${pr_file##*/}.saved"
done
printf '%s\n' 'presetFacts: model => presets?.get(model) ?? null,' > "$w/server/llamacpp-manager.cjs"
printf '%s\n' 'const result = await modelManager.applyPreset(await readJson(req));' > "$w/server/routes/models.cjs"
touch "$w/server/rust-preset-read-bridge.cjs"
printf "%s\n" "const OWNED_ROUTES = Object.freeze(new Set(['GET /api/models/preset']));" > "$w/server/rust-preset-read.cjs"
cp "$work/feature-index.saved" "$w/server/index.cjs"
cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const presetReadBridge = require('./rust-preset-read-bridge.cjs').createPresetReadBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-preset-read.cjs').refuseOwned(req, res, {})) return;
if (await presetReadBridge(req, res)) return;
JS
cp "$w/server/index.cjs" "$work/pr-index.saved"
pr_owner=rust; pr_methods='methods = ["GET"]'; pr_try pr-core-only
check "preset GET refuser rejects old front" 'refused "preset read ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
sed 's/"start-id"/"start-id", "rust-preset-read"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
pr_try pr-front-only
check "preset GET capability rejects old Core" 'refused "preset read ownership pairing"'
cp "$work/pr-index.saved" "$w/server/index.cjs"
pr_try pr-pair
check "matching preset GET pair assembles" '[ $rc -eq 0 ]'
pr_methods='methods = ["GET", "PUT"]'; pr_try pr-wrong-methods
check "preset GET cannot claim PUT" 'refused "PUT and other methods stay Node"'
pr_methods='methods = ["GET"]'
printf "%s\n" "const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/models/preset']));" > "$w/server/rust-preset-read.cjs"
pr_try pr-all-refuser
check "preset refuser cannot claim other methods" 'refused "Core must refuse exactly this GET"'
cat > "$w/server/rust-preset-read.cjs" <<'JS'
/*
const OWNED_ROUTES = Object.freeze(new Set(['GET /api/models/preset']));
*/
JS
pr_try pr-comment-marker
check "preset marker must be executable code" 'refused "Core must refuse exactly this GET"'
printf "%s\n" "const OWNED_ROUTES = Object.freeze(new Set(['GET /api/models/preset']));" > "$w/server/rust-preset-read.cjs"
printf '%s\n' 'modelManager.getPreset(model);' >> "$w/server/routes/models.cjs"
pr_try pr-old-get
check "paired preset read rejects old public GET" 'refused "still carries the public GET handler"'
printf '%s\n' 'module.exports = {};' > "$w/server/routes/models.cjs"
pr_try pr-no-writer
check "paired preset read requires Node PUT" 'refused "PUT must stay Node-owned"'
printf '%s\n' 'const result = await modelManager.applyPreset(await readJson(req));' > "$w/server/routes/models.cjs"
sed 's/secret: FRONT_SECRET/secret: null/' "$work/pr-index.saved" > "$w/server/index.cjs"
pr_try pr-no-secret
check "preset facts need the captured front secret" 'refused "front captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
pr_try pr-old-rust-row
check "old preset pair rejects Rust ownership" 'refused "preset read ownership pairing"'
pr_owner=node; unset pr_methods; pr_try pr-old-pair
check "old preset pair stays valid for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-preset-read.cjs" "$w/server/rust-preset-read-bridge.cjs"
for pr_file in llamacpp-manager.cjs routes/models.cjs; do
  if [ -f "$work/pr-${pr_file##*/}.saved" ]; then
    cp "$work/pr-${pr_file##*/}.saved" "$w/server/$pr_file"
  else
    rm -f "$w/server/$pr_file"
  fi
done
# #2293: dismissal policy moves independently of the live autotune worker.
ac_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    if [ "${ac_skip:-}" != yes ]; then printf '[[route]]\npath = "/api/models/autotune/clear"\nowner = "%s"\n' "$ac_owner"; [ -z "${ac_methods:-}" ] || printf '%s\n' "$ac_methods"; fi)
}
cat > "$w/server/rust-autotune-clear.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/models/autotune/clear']));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/rust-autotune-clear-bridge.cjs"
[ ! -f "$w/server/llamacpp-manager.cjs" ] || cp "$w/server/llamacpp-manager.cjs" "$work/ac-manager.saved"
printf '%s\n' 'clearFacts: autotuner.clearFacts, compareAndClear: autotuner.compareAndClear,' > "$w/server/llamacpp-manager.cjs"
ac_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const autotuneClearBridge = require('./rust-autotune-clear-bridge.cjs').createAutotuneClearBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-autotune-clear.cjs').refuseOwned(req, res, {})) return;
if (await autotuneClearBridge(req, res)) return;
JS
}
ac_front() { sed 's/"start-id"/"start-id", "rust-autotune-clear"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
ac_owner=rust; ac_core
ac_try ac-core-only
check "autotune dismissal refusal cannot pair with an old front" 'refused "autotune dismissal ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; ac_front
ac_try ac-front-only
check "autotune dismissal capability cannot pair with an old Core" 'refused "autotune dismissal ownership pairing"'
ac_core; ac_try ac-pair
check "matching autotune dismissal pair assembles" '[ $rc -eq 0 ]'
[ ! -f "$w/server/llamacpp-full-autotune.cjs" ] || cp "$w/server/llamacpp-full-autotune.cjs" "$work/ac-actor-facts.saved"
printf 'function clearFacts() { return {}; }\n' >> "$w/server/llamacpp-full-autotune.cjs"
ac_try ac-live-actor-facts
check "native dismissal pair accepts its retained actor facts primitive" '[ $rc -eq 0 ]'
if [ -f "$work/ac-actor-facts.saved" ]; then cp "$work/ac-actor-facts.saved" "$w/server/llamacpp-full-autotune.cjs"; else rm -f "$w/server/llamacpp-full-autotune.cjs"; fi
# Both model namespaces together: the older read pairing must not keep settings policy in Core.
cp "$work/ms-reads.saved" "$w/server/rust-model-state-reads.cjs"; touch "$w/server/rust-model-facts.cjs"
cat >> "$w/server/index.cjs" <<'JS'
const modelFactsBridge = require('./rust-model-facts.cjs').createModelFactsBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-model-state-reads.cjs').refuseOwned(req, res, {})) return;
if (await modelFactsBridge(req, res)) return;
JS
sed 's/"start-id"/"start-id", "rust-autotune-clear", "rust-model-state-reads"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
ms_owner=rust
try_routes ac-with-model-reads < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; ms_rows; printf '[[route]]\npath = "/api/models/autotune/clear"\nowner = "rust"\n')
check "autotune dismissal and existing model read pairs assemble together" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-model-state-reads.cjs" "$w/server/rust-model-facts.cjs"; ac_core; ac_front
ac_owner=node; ac_try ac-node-rows
check "native dismissal pair rejects Node ownership" 'refused "autotune dismissal ownership pairing"'
ac_owner=rust; ac_skip=yes; ac_try ac-missing-row
check "native dismissal pair requires its route row" 'refused "incomplete route ownership"'
unset ac_skip; ac_methods='methods = ["POST"]'; ac_try ac-partial-row
check "native dismissal pair owns other-method refusals as well as POST" 'refused "autotune dismissal ownership pairing"'
unset ac_methods
cp "$w/server/rust-autotune-clear.cjs" "$work/ac-refuser.saved"
printf 'const OWNED_ROUTES = Object.freeze(new Set([]));\n' > "$w/server/rust-autotune-clear.cjs"; ac_try ac-refuser
check "native dismissal pair requires exact Core refusal" 'refused "Core must refuse exactly"'
cp "$work/ac-refuser.saved" "$w/server/rust-autotune-clear.cjs"
[ ! -f "$w/server/routes/models.cjs" ] || cp "$w/server/routes/models.cjs" "$work/ac-models.saved"
printf "if (p === '/api/models/autotune/clear') send();\n" >> "$w/server/routes/models.cjs"; ac_try ac-old-handler
check "native dismissal pair rejects retained public handler" 'refused "Core still carries the public handler"'
if [ -f "$work/ac-models.saved" ]; then cp "$work/ac-models.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi
[ ! -f "$w/server/llamacpp-full-autotune.cjs" ] || cp "$w/server/llamacpp-full-autotune.cjs" "$work/ac-actor.saved"
printf 'function clear() {}\n' >> "$w/server/llamacpp-full-autotune.cjs"; ac_try ac-old-policy
check "native dismissal pair rejects retained Node dismissal policy" 'refused "Core still carries the public dismissal policy"'
if [ -f "$work/ac-actor.saved" ]; then cp "$work/ac-actor.saved" "$w/server/llamacpp-full-autotune.cjs"; else rm -f "$w/server/llamacpp-full-autotune.cjs"; fi
cp "$w/server/llamacpp-manager.cjs" "$work/ac-live-manager.saved"; printf 'module.exports = {};\n' > "$w/server/llamacpp-manager.cjs"; ac_try ac-no-primitives
check "native dismissal pair requires the live single-writer primitives" 'refused "Core does not expose the live actor primitives"'
cp "$work/ac-live-manager.saved" "$w/server/llamacpp-manager.cjs"
mv "$w/server/rust-autotune-clear-bridge.cjs" "$work/ac-bridge.saved"; ac_try ac-no-bridge
check "native dismissal pair requires actor state bridge" 'refused "missing state bridge"'
mv "$work/ac-bridge.saved" "$w/server/rust-autotune-clear-bridge.cjs"
cp "$w/server/index.cjs" "$work/ac-index.saved"
sed '/await autotuneClearBridge(req, res)/d' "$work/ac-index.saved" > "$w/server/index.cjs"; ac_try ac-no-mount
check "native dismissal pair requires bridge mount" 'refused "missing state bridge mount"'
sed 's/secret: FRONT_SECRET/secret: null/' "$work/ac-index.saved" > "$w/server/index.cjs"; ac_try ac-no-secret
check "native dismissal pair requires captured bridge secret" 'refused "front captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
ac_try ac-old-rust-rows
check "old dismissal pair rejects Rust ownership" 'refused "autotune dismissal ownership pairing"'
ac_owner=node; ac_try ac-old-pair
check "old autotune dismissal pair stays valid for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-autotune-clear.cjs" "$w/server/rust-autotune-clear-bridge.cjs"
if [ -f "$work/ac-manager.saved" ]; then cp "$work/ac-manager.saved" "$w/server/llamacpp-manager.cjs"; else rm -f "$w/server/llamacpp-manager.cjs"; fi
# #2304: exact GET folder scan paired with the one shared cache owner.
mm_scan_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    if [ "${mm_scan_skip:-}" != yes ]; then printf '[[route]]\npath = "/api/model-manager/models"\nowner = "%s"\nmethods = [%s]\n' "$mm_scan_owner" "${mm_scan_methods:-\"GET\"}"; fi)
}
cat > "$w/server/rust-model-manager-scan.cjs" <<'JS'
const PATH = '/api/model-manager/models';
const OWNED_ROUTES = Object.freeze(new Set(['GET '+PATH]));
JS
touch "$w/server/rust-model-manager-scan-cache.cjs"
[ ! -f "$w/server/models.cjs" ] || cp "$w/server/models.cjs" "$work/mm-scan-service.saved"
printf '%s\n' 'modelScanSnapshot: () => modelScanCache.snapshot(),' 'publishModelScan: (body,token) => modelScanCache.publish(body,token),' 'requestModelScanRefresh: token => modelScanCache.refresh(token),' > "$w/server/models.cjs"
mm_scan_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const modelManagerScanCache = require('./rust-model-manager-scan-cache.cjs').createModelManagerScanCache({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-model-manager-scan.cjs').refuseOwned(req, res, {})) return;
if (await modelManagerScanCache(req, res)) return;
JS
}
mm_scan_front() { sed 's/"start-id"/"start-id", "rust-model-manager-scan"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
mm_scan_owner=rust; mm_scan_core; mm_scan_try mm-scan-core-only
check "model scan refusal rejects old front" 'refused "model scan read ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; mm_scan_front; mm_scan_try mm-scan-front-only
check "model scan front rejects old Core" 'refused "model scan read ownership pairing"'
mm_scan_core; mm_scan_try mm-scan-pair
check "matching model scan GET pair assembles" '[ $rc -eq 0 ]'
mm_scan_owner=node; mm_scan_try mm-scan-node-row
check "native scan GET rejects Node row" 'refused "model scan read ownership pairing"'
mm_scan_owner=rust; mm_scan_skip=yes; mm_scan_try mm-scan-no-row
check "native scan GET requires exact child row" 'refused "incomplete route ownership"'
unset mm_scan_skip; mm_scan_methods='"GET", "HEAD"'; mm_scan_try mm-scan-head-row
check "native scan GET cannot take HEAD policy" 'refused "only GET belongs"'
unset mm_scan_methods
cp "$w/server/rust-model-manager-scan.cjs" "$work/mm-scan-refuser.saved"
sed "s/'GET '+PATH/'GET \/api\/model-manager\/models'/" "$work/mm-scan-refuser.saved" > "$w/server/rust-model-manager-scan.cjs"; mm_scan_try mm-scan-literal
check "literal model scan GET marker still assembles" '[ $rc -eq 0 ]'
sed "s/'GET '+PATH/'ALL '+PATH/" "$work/mm-scan-refuser.saved" > "$w/server/rust-model-manager-scan.cjs"; mm_scan_try mm-scan-all-refuser
check "native scan Core cannot refuse other methods" 'refused "Core must refuse exactly"'
sed "s@models';@models/delete';@" "$work/mm-scan-refuser.saved" > "$w/server/rust-model-manager-scan.cjs"; mm_scan_try mm-scan-wrong-path
check "native scan Core must refuse the exact path" 'refused "Core must refuse exactly"'
sed "s/'GET '+PATH/'GET '+PATH, 'HEAD '+PATH/" "$work/mm-scan-refuser.saved" > "$w/server/rust-model-manager-scan.cjs"; mm_scan_try mm-scan-extra-method
check "native scan Core cannot also refuse HEAD" 'refused "Core must refuse exactly"'
{
  printf '/*\n'
  cat "$work/mm-scan-refuser.saved"
  printf '*/\n'
} > "$w/server/rust-model-manager-scan.cjs"
mm_scan_try mm-scan-comment-only
check "commented scan declarations cannot establish ownership" 'refused "Core must refuse exactly"'
cp "$work/mm-scan-refuser.saved" "$w/server/rust-model-manager-scan.cjs"
cp "$w/server/models.cjs" "$work/mm-scan-live-service.saved"; printf 'module.exports = {};\n' > "$w/server/models.cjs"; mm_scan_try mm-scan-no-owner
check "native scan needs the existing shared cache owner" 'refused "existing shared cache primitives"'
cp "$work/mm-scan-live-service.saved" "$w/server/models.cjs"
mv "$w/server/rust-model-manager-scan-cache.cjs" "$work/mm-scan-bridge.saved"; mm_scan_try mm-scan-no-bridge
check "native scan needs cache bridge" 'refused "missing cache bridge"'
mv "$work/mm-scan-bridge.saved" "$w/server/rust-model-manager-scan-cache.cjs"
cp "$w/server/index.cjs" "$work/mm-scan-index.saved"
sed '/await modelManagerScanCache(req, res)/d' "$work/mm-scan-index.saved" > "$w/server/index.cjs"; mm_scan_try mm-scan-no-mount
check "native scan needs cache bridge mount" 'refused "missing cache bridge mount"'
sed 's/secret: FRONT_SECRET/secret: null/' "$work/mm-scan-index.saved" > "$w/server/index.cjs"; mm_scan_try mm-scan-no-secret
check "native scan cache bridge needs captured secret" 'refused "front captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
mm_scan_try mm-scan-old-rust-row
check "old scan pair rejects native child row" 'refused "model scan read ownership pairing"'
mm_scan_owner=node; mm_scan_try mm-scan-old-pair
check "old scan pair stays valid for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-model-manager-scan.cjs" "$w/server/rust-model-manager-scan-cache.cjs"
if [ -f "$work/mm-scan-service.saved" ]; then cp "$work/mm-scan-service.saved" "$w/server/models.cjs"; else rm -f "$w/server/models.cjs"; fi
# #2301: resume policy moves independently of the live autotune worker.
atrm_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    if [ "${atrm_skip:-}" != yes ]; then printf '[[route]]\npath = "/api/models/autotune/resume"\nowner = "%s"\n' "$atrm_owner"; [ -z "${atrm_methods:-}" ] || printf '%s\n' "$atrm_methods"; fi)
}
cat > "$w/server/rust-autotune-resume.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/models/autotune/resume']));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/rust-autotune-resume-bridge.cjs"
[ ! -f "$w/server/llamacpp-manager.cjs" ] || cp "$w/server/llamacpp-manager.cjs" "$work/atrm-manager.saved"
printf '%s\n' 'resumeFacts: autotuner.resumeFacts, prepareResume: autotuner.prepareResume, compareAndResume: autotuner.compareAndResume,' > "$w/server/llamacpp-manager.cjs"
atrm_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const autotuneResumeBridge = require('./rust-autotune-resume-bridge.cjs').createAutotuneResumeBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-autotune-resume.cjs').refuseOwned(req, res, {})) return;
if (await autotuneResumeBridge(req, res)) return;
JS
}
atrm_front() { sed 's/"start-id"/"start-id", "rust-autotune-resume"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
atrm_owner=rust; atrm_core
atrm_try atrm-core-only
check "auto-tune resume refusal cannot pair with an old front" 'refused "auto-tune resume ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; atrm_front
atrm_try atrm-front-only
check "auto-tune resume capability cannot pair with an old Core" 'refused "auto-tune resume ownership pairing"'
atrm_core; atrm_try atrm-pair
check "matching auto-tune resume pair assembles" '[ $rc -eq 0 ]'
# Both model namespaces together: the older read pairing must not keep settings policy in Core.
cp "$work/ms-reads.saved" "$w/server/rust-model-state-reads.cjs"; touch "$w/server/rust-model-facts.cjs"
cat >> "$w/server/index.cjs" <<'JS'
const modelFactsBridge = require('./rust-model-facts.cjs').createModelFactsBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-model-state-reads.cjs').refuseOwned(req, res, {})) return;
if (await modelFactsBridge(req, res)) return;
JS
sed 's/"start-id"/"start-id", "rust-autotune-resume", "rust-model-state-reads"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
ms_owner=rust
try_routes atrm-with-model-reads < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; ms_rows; printf '[[route]]\npath = "/api/models/autotune/resume"\nowner = "rust"\n')
check "auto-tune resume and existing model read pairs assemble together" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-model-state-reads.cjs" "$w/server/rust-model-facts.cjs"; atrm_core; atrm_front
atrm_owner=node; atrm_try atrm-node-rows
check "native resume pair rejects Node ownership" 'refused "auto-tune resume ownership pairing"'
atrm_owner=rust; atrm_skip=yes; atrm_try atrm-missing-row
check "native resume pair requires its route row" 'refused "incomplete route ownership"'
unset atrm_skip; atrm_methods='methods = ["POST"]'; atrm_try atrm-partial-row
check "native resume pair owns other-method refusals as well as POST" 'refused "auto-tune resume ownership pairing"'
unset atrm_methods
cp "$w/server/rust-autotune-resume.cjs" "$work/atrm-refuser.saved"
printf 'const OWNED_ROUTES = Object.freeze(new Set([]));\n' > "$w/server/rust-autotune-resume.cjs"; atrm_try atrm-refuser
check "native resume pair requires exact Core refusal" 'refused "Core must refuse exactly"'
cp "$work/atrm-refuser.saved" "$w/server/rust-autotune-resume.cjs"
[ ! -f "$w/server/routes/models.cjs" ] || cp "$w/server/routes/models.cjs" "$work/atrm-models.saved"
printf "if (p === '/api/models/autotune/resume') send();\n" >> "$w/server/routes/models.cjs"; atrm_try atrm-old-handler
check "native resume pair rejects retained public handler" 'refused "Core still carries the public handler"'
if [ -f "$work/atrm-models.saved" ]; then cp "$work/atrm-models.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi
[ ! -f "$w/server/llamacpp-full-autotune.cjs" ] || cp "$w/server/llamacpp-full-autotune.cjs" "$work/atrm-actor.saved"
printf 'async function resume() {}\n' >> "$w/server/llamacpp-full-autotune.cjs"; atrm_try atrm-old-policy
check "native resume pair rejects retained Node resume policy" 'refused "Core still carries the public resume policy"'
if [ -f "$work/atrm-actor.saved" ]; then cp "$work/atrm-actor.saved" "$w/server/llamacpp-full-autotune.cjs"; else rm -f "$w/server/llamacpp-full-autotune.cjs"; fi
cp "$w/server/llamacpp-manager.cjs" "$work/atrm-live-manager.saved"; printf 'module.exports = {};\n' > "$w/server/llamacpp-manager.cjs"; atrm_try atrm-no-primitives
check "native resume pair requires the live single-writer primitives" 'refused "Core does not expose the live actor primitives"'
cp "$work/atrm-live-manager.saved" "$w/server/llamacpp-manager.cjs"
mv "$w/server/rust-autotune-resume-bridge.cjs" "$work/atrm-bridge.saved"; atrm_try atrm-no-bridge
check "native resume pair requires actor state bridge" 'refused "missing state bridge"'
mv "$work/atrm-bridge.saved" "$w/server/rust-autotune-resume-bridge.cjs"
cp "$w/server/index.cjs" "$work/atrm-index.saved"
sed '/await autotuneResumeBridge(req, res)/d' "$work/atrm-index.saved" > "$w/server/index.cjs"; atrm_try atrm-no-mount
check "native resume pair requires bridge mount" 'refused "missing state bridge mount"'
sed 's/secret: FRONT_SECRET/secret: null/' "$work/atrm-index.saved" > "$w/server/index.cjs"; atrm_try atrm-no-secret
check "native resume pair requires captured bridge secret" 'refused "front captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
atrm_try atrm-old-rust-rows
check "old resume pair rejects Rust ownership" 'refused "auto-tune resume ownership pairing"'
atrm_owner=node; atrm_try atrm-old-pair
check "old auto-tune resume pair stays valid for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-autotune-resume.cjs" "$w/server/rust-autotune-resume-bridge.cjs"
if [ -f "$work/atrm-manager.saved" ]; then cp "$work/atrm-manager.saved" "$w/server/llamacpp-manager.cjs"; else rm -f "$w/server/llamacpp-manager.cjs"; fi
# #2292: cancellation policy moves independently of the live calibration worker.
cc_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    if [ "${cc_skip:-}" != yes ]; then printf '[[route]]\npath = "/api/models/calibration/cancel"\nowner = "%s"\n' "$cc_owner"; [ -z "${cc_methods:-}" ] || printf '%s\n' "$cc_methods"; fi)
}
cat > "$w/server/rust-calibration-cancel.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/models/calibration/cancel']));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/rust-calibration-cancel-bridge.cjs"
[ ! -f "$w/server/llamacpp-manager.cjs" ] || cp "$w/server/llamacpp-manager.cjs" "$work/cc-manager.saved"
printf '%s\n' 'cancellationFacts: calibrator.cancellationFacts, compareAndAbort: calibrator.compareAndAbort,' > "$w/server/llamacpp-manager.cjs"
cc_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const calibrationCancelBridge = require('./rust-calibration-cancel-bridge.cjs').createCalibrationCancelBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-calibration-cancel.cjs').refuseOwned(req, res, {})) return;
if (await calibrationCancelBridge(req, res)) return;
JS
}
cc_front() { sed 's/"start-id"/"start-id", "rust-calibration-cancel"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
cc_owner=rust; cc_core
cc_try cc-core-only
check "calibration cancellation refusal cannot pair with an old front" 'refused "calibration cancellation ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cc_front
cc_try cc-front-only
check "calibration cancellation capability cannot pair with an old Core" 'refused "calibration cancellation ownership pairing"'
cc_core; cc_try cc-pair
check "matching calibration cancellation pair assembles" '[ $rc -eq 0 ]'
[ ! -f "$w/server/llamacpp-calibration.cjs" ] || cp "$w/server/llamacpp-calibration.cjs" "$work/cc-actor-facts.saved"
printf 'function cancellationFacts() { return {}; }\n' >> "$w/server/llamacpp-calibration.cjs"
cc_try cc-live-actor-facts
check "native cancellation pair accepts its retained actor facts primitive" '[ $rc -eq 0 ]'
if [ -f "$work/cc-actor-facts.saved" ]; then cp "$work/cc-actor-facts.saved" "$w/server/llamacpp-calibration.cjs"; else rm -f "$w/server/llamacpp-calibration.cjs"; fi
# Both model namespaces together: the older read pairing must not keep settings policy in Core.
cp "$work/ms-reads.saved" "$w/server/rust-model-state-reads.cjs"; touch "$w/server/rust-model-facts.cjs"
cat >> "$w/server/index.cjs" <<'JS'
const modelFactsBridge = require('./rust-model-facts.cjs').createModelFactsBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-model-state-reads.cjs').refuseOwned(req, res, {})) return;
if (await modelFactsBridge(req, res)) return;
JS
sed 's/"start-id"/"start-id", "rust-calibration-cancel", "rust-model-state-reads"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
ms_owner=rust
try_routes cc-with-model-reads < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; ms_rows; printf '[[route]]\npath = "/api/models/calibration/cancel"\nowner = "rust"\n')
check "calibration cancellation and existing model read pairs assemble together" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-model-state-reads.cjs" "$w/server/rust-model-facts.cjs"; cc_core; cc_front
cc_owner=node; cc_try cc-node-rows
check "native cancellation pair rejects Node ownership" 'refused "calibration cancellation ownership pairing"'
cc_owner=rust; cc_skip=yes; cc_try cc-missing-row
check "native cancellation pair requires its route row" 'refused "incomplete route ownership"'
unset cc_skip; cc_methods='methods = ["POST"]'; cc_try cc-partial-row
check "native cancellation pair owns other-method refusals as well as POST" 'refused "calibration cancellation ownership pairing"'
unset cc_methods
cp "$w/server/rust-calibration-cancel.cjs" "$work/cc-refuser.saved"
printf 'const OWNED_ROUTES = Object.freeze(new Set([]));\n' > "$w/server/rust-calibration-cancel.cjs"; cc_try cc-refuser
check "native cancellation pair requires exact Core refusal" 'refused "Core must refuse exactly"'
cp "$work/cc-refuser.saved" "$w/server/rust-calibration-cancel.cjs"
[ ! -f "$w/server/routes/models.cjs" ] || cp "$w/server/routes/models.cjs" "$work/cc-models.saved"
printf "if (p === '/api/models/calibration/cancel') send();\n" >> "$w/server/routes/models.cjs"; cc_try cc-old-handler
check "native cancellation pair rejects retained public handler" 'refused "Core still carries the public handler"'
if [ -f "$work/cc-models.saved" ]; then cp "$work/cc-models.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi
[ ! -f "$w/server/llamacpp-calibration.cjs" ] || cp "$w/server/llamacpp-calibration.cjs" "$work/cc-actor.saved"
printf 'function cancel() {}\n' >> "$w/server/llamacpp-calibration.cjs"; cc_try cc-old-policy
check "native cancellation pair rejects retained Node cancellation policy" 'refused "Core still carries the public cancellation policy"'
if [ -f "$work/cc-actor.saved" ]; then cp "$work/cc-actor.saved" "$w/server/llamacpp-calibration.cjs"; else rm -f "$w/server/llamacpp-calibration.cjs"; fi
cp "$w/server/llamacpp-manager.cjs" "$work/cc-live-manager.saved"; printf 'module.exports = {};\n' > "$w/server/llamacpp-manager.cjs"; cc_try cc-no-primitives
check "native cancellation pair requires the live single-writer primitives" 'refused "Core does not expose the live actor primitives"'
cp "$work/cc-live-manager.saved" "$w/server/llamacpp-manager.cjs"
mv "$w/server/rust-calibration-cancel-bridge.cjs" "$work/cc-bridge.saved"; cc_try cc-no-bridge
check "native cancellation pair requires actor state bridge" 'refused "missing state bridge"'
mv "$work/cc-bridge.saved" "$w/server/rust-calibration-cancel-bridge.cjs"
cp "$w/server/index.cjs" "$work/cc-index.saved"
sed '/await calibrationCancelBridge(req, res)/d' "$work/cc-index.saved" > "$w/server/index.cjs"; cc_try cc-no-mount
check "native cancellation pair requires bridge mount" 'refused "missing state bridge mount"'
sed 's/secret: FRONT_SECRET/secret: null/' "$work/cc-index.saved" > "$w/server/index.cjs"; cc_try cc-no-secret
check "native cancellation pair requires captured bridge secret" 'refused "front captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
cc_try cc-old-rust-rows
check "old cancellation pair rejects Rust ownership" 'refused "calibration cancellation ownership pairing"'
cc_owner=node; cc_try cc-old-pair
check "old calibration cancellation pair stays valid for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-calibration-cancel.cjs" "$w/server/rust-calibration-cancel-bridge.cjs"
if [ -f "$work/cc-manager.saved" ]; then cp "$work/cc-manager.saved" "$w/server/llamacpp-manager.cjs"; else rm -f "$w/server/llamacpp-manager.cjs"; fi
# Row V: the front is the only issuer of the egress proxy's control key and signed grants; Core is a
# fail-closed client (marker 'noevia-code-egress-client/1', FEATURES "rust-code-egress-issuer"). Both
# halves move together; a comment is not a marker; the Node issuer must be gone from a client Core.
ce_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n')
}
ce_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  printf '%s\n' "const CODE_EGRESS_CLIENT_MARKER = 'noevia-code-egress-client/1';" > "$w/server/code-egress-client.cjs"
  printf '%s\n' "const { createEgressClient } = require('./code-egress-client.cjs');" > "$w/server/code-egress.cjs"
  rm -f "$w/server/code-egress-control.cjs"
}
ce_front() { sed 's/"start-id"/"start-id", "rust-code-egress-issuer"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"; rm -f "$w/server/code-egress-client.cjs" "$w/server/code-egress.cjs" "$w/server/code-egress-control.cjs"
printf '%s\n' "function publishWebKey() {}" > "$w/server/code-egress-control.cjs"
printf '%s\n' "const { publishWebKey } = require('./code-egress-control.cjs');" > "$w/server/code-egress.cjs"
ce_try ce-legacy
check "code egress: legacy Core with a legacy front assembles (rollback pair)" '[ $rc -eq 0 ]'
ce_core; ce_try ce-core-only
check "code egress: a client Core cannot pair with a front that has no issuer" 'refused "code egress issuer pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"; ce_front
printf '%s\n' "function publishWebKey() {}" > "$w/server/code-egress-control.cjs"
printf '%s\n' "const { publishWebKey } = require('./code-egress-control.cjs');" > "$w/server/code-egress.cjs"; rm -f "$w/server/code-egress-client.cjs"
ce_try ce-front-only
check "code egress: a front that issues cannot pair with a Core that still publishes the key" 'refused "code egress issuer pairing"'
printf '%s\n' "// const CODE_EGRESS_CLIENT_MARKER = 'noevia-code-egress-client/1';" > "$w/server/code-egress-client.cjs"; ce_try ce-comment-marker
check "code egress: a commented marker is not the marker" 'refused "code egress issuer pairing"'
ce_core; printf '%s\n' "function publishWebKey() {}" > "$w/server/code-egress-control.cjs"; ce_try ce-node-issuer
check "code egress: a client Core that still carries the Node issuer is refused" 'refused "still carries the Node issuer"'
ce_core; printf '%s\n' "const { createEgressClient } = require('./code-egress-client.cjs'); publishWebKey({});" > "$w/server/code-egress.cjs"; ce_try ce-publishes
check "code egress: a client Core whose setup still publishes keys is refused" 'refused "still publishes keys or signs grants"'
ce_core; printf '%s\n' "module.exports = {};" > "$w/server/code-egress.cjs"; ce_try ce-no-client
check "code egress: a client Core whose setup does not use the client is refused" 'refused "does not use the native client"'
ce_core; ce_try ce-pair
check "code egress: the matching client Core and issuer front assemble" '[ $rc -eq 0 ]'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
rm -f "$w/server/code-egress-client.cjs" "$w/server/code-egress.cjs" "$w/server/code-egress-control.cjs"
# #2303: start/status policy moves independently of the live calibration worker.
cr_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    if [ "${cr_skip:-}" != yes ]; then printf '[[route]]\npath = "/api/models/calibration"\nowner = "%s"\n' "$cr_owner"; [ -z "${cr_methods:-}" ] || printf '%s\n' "$cr_methods"; fi)
}
cat > "$w/server/rust-calibration-routes.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/models/calibration']));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/rust-calibration-routes-bridge.cjs"
[ ! -f "$w/server/llamacpp-manager.cjs" ] || cp "$w/server/llamacpp-manager.cjs" "$work/cr-manager.saved"
printf '%s\n' 'stateFacts: calibrator.stateFacts, listingFacts: calibrator.listingFacts, preparationFacts: calibrator.preparationFacts, compareAndLaunch: calibrator.compareAndLaunch,' > "$w/server/llamacpp-manager.cjs"
cr_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const calibrationRoutesBridge = require('./rust-calibration-routes-bridge.cjs').createCalibrationRoutesBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-calibration-routes.cjs').refuseOwned(req, res, {})) return;
if (await calibrationRoutesBridge(req, res)) return;
JS
}
cr_front() { sed 's/"start-id"/"start-id", "rust-calibration-routes"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
[ ! -f "$w/server/llamacpp-calibration.cjs" ] || cp "$w/server/llamacpp-calibration.cjs" "$work/cr-original-actor.saved"
printf 'function statusFacts() {}\nasync function startFacts() {}\n' > "$w/server/llamacpp-calibration.cjs"
cr_owner=rust; cr_core
cr_try cr-core-only
check "calibration start/read refusal cannot pair with an old front" 'refused "calibration start/read ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cr_front
cr_try cr-front-only
check "calibration start/read capability cannot pair with an old Core" 'refused "calibration start/read ownership pairing"'
cr_core; cr_try cr-pair
check "matching calibration start/read pair assembles" '[ $rc -eq 0 ]'
# Both public operations compose with the same retained calibration worker/controller.
cp "$w/server/index.cjs" "$work/cr-pair-index.saved"
cp "$w/server/llamacpp-manager.cjs" "$work/cr-pair-manager.saved"
cat > "$w/server/rust-calibration-cancel.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/models/calibration/cancel']));
JS
touch "$w/server/rust-calibration-cancel-bridge.cjs"
printf '%s\n' 'cancellationFacts: calibrator.cancellationFacts, compareAndAbort: calibrator.compareAndAbort,' >> "$w/server/llamacpp-manager.cjs"
cat >> "$w/server/index.cjs" <<'JS'
const calibrationCancelBridge = require('./rust-calibration-cancel-bridge.cjs').createCalibrationCancelBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-calibration-cancel.cjs').refuseOwned(req, res, {})) return;
if (await calibrationCancelBridge(req, res)) return;
JS
sed 's/"start-id"/"start-id", "rust-calibration-routes", "rust-calibration-cancel"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
try_routes cr-with-cancellation < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n[[route]]\npath = "/api/models/calibration"\nowner = "rust"\n[[route]]\npath = "/api/models/calibration/cancel"\nowner = "rust"\n')
check "calibration start/read and cancellation pair share one worker" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-calibration-cancel.cjs" "$w/server/rust-calibration-cancel-bridge.cjs"
cp "$work/cr-pair-index.saved" "$w/server/index.cjs"; cp "$work/cr-pair-manager.saved" "$w/server/llamacpp-manager.cjs"; cr_front
# Both model namespaces together: the older read pairing must not keep settings policy in Core.
cp "$work/ms-reads.saved" "$w/server/rust-model-state-reads.cjs"; touch "$w/server/rust-model-facts.cjs"
cat >> "$w/server/index.cjs" <<'JS'
const modelFactsBridge = require('./rust-model-facts.cjs').createModelFactsBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-model-state-reads.cjs').refuseOwned(req, res, {})) return;
if (await modelFactsBridge(req, res)) return;
JS
sed 's/"start-id"/"start-id", "rust-calibration-routes", "rust-model-state-reads"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
ms_owner=rust
try_routes cr-with-model-reads < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; ms_rows; printf '[[route]]\npath = "/api/models/calibration"\nowner = "rust"\n')
check "calibration start/read and existing model read pairs assemble together" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-model-state-reads.cjs" "$w/server/rust-model-facts.cjs"; cr_core; cr_front
cr_owner=node; cr_try cr-node-rows
check "native calibration pair rejects Node ownership" 'refused "calibration start/read ownership pairing"'
cr_owner=rust; cr_skip=yes; cr_try cr-missing-row
check "native calibration pair requires its route row" 'refused "incomplete route ownership"'
unset cr_skip; cr_methods='methods = ["POST"]'; cr_try cr-partial-row
check "native calibration pair owns other-method refusals as well as POST" 'refused "calibration start/read ownership pairing"'
unset cr_methods
cp "$w/server/rust-calibration-routes.cjs" "$work/cr-refuser.saved"
printf 'const OWNED_ROUTES = Object.freeze(new Set([]));\n' > "$w/server/rust-calibration-routes.cjs"; cr_try cr-refuser
check "native calibration pair requires exact Core refusal" 'refused "Core must refuse exactly"'
cp "$work/cr-refuser.saved" "$w/server/rust-calibration-routes.cjs"
[ ! -f "$w/server/routes/models.cjs" ] || cp "$w/server/routes/models.cjs" "$work/cr-models.saved"
printf "if (p === '/api/models/calibration') send();\n" >> "$w/server/routes/models.cjs"; cr_try cr-old-handler
check "native calibration pair rejects retained public handler" 'refused "Core still carries the public handler"'
if [ -f "$work/cr-models.saved" ]; then cp "$work/cr-models.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi
[ ! -f "$w/server/llamacpp-calibration.cjs" ] || cp "$w/server/llamacpp-calibration.cjs" "$work/cr-actor.saved"
for cr_legacy in start status; do
  printf 'async function %s() {}\n' "$cr_legacy" >> "$w/server/llamacpp-calibration.cjs"
  cr_try "cr-old-policy-$cr_legacy"
  check "native calibration pair rejects retained Node $cr_legacy policy" 'refused "Core still carries the public start/status policy"'
  if [ -f "$work/cr-actor.saved" ]; then cp "$work/cr-actor.saved" "$w/server/llamacpp-calibration.cjs"; else rm -f "$w/server/llamacpp-calibration.cjs"; fi
done
cp "$w/server/llamacpp-manager.cjs" "$work/cr-live-manager.saved"; printf 'module.exports = {};\n' > "$w/server/llamacpp-manager.cjs"; cr_try cr-no-primitives
check "native calibration pair requires the live single-writer primitives" 'refused "Core does not expose the live actor primitives"'
cp "$work/cr-live-manager.saved" "$w/server/llamacpp-manager.cjs"
mv "$w/server/rust-calibration-routes-bridge.cjs" "$work/cr-bridge.saved"; cr_try cr-no-bridge
check "native calibration pair requires actor state bridge" 'refused "missing state bridge"'
mv "$work/cr-bridge.saved" "$w/server/rust-calibration-routes-bridge.cjs"
cp "$w/server/index.cjs" "$work/cr-index.saved"
sed '/await calibrationRoutesBridge(req, res)/d' "$work/cr-index.saved" > "$w/server/index.cjs"; cr_try cr-no-mount
check "native calibration pair requires bridge mount" 'refused "missing state bridge mount"'
sed 's/secret: FRONT_SECRET/secret: null/' "$work/cr-index.saved" > "$w/server/index.cjs"; cr_try cr-no-secret
check "native calibration pair requires captured bridge secret" 'refused "front captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
cr_try cr-old-rust-rows
check "old calibration pair rejects Rust ownership" 'refused "calibration start/read ownership pairing"'
cr_owner=node; cr_try cr-old-pair
check "old calibration start/read pair stays valid for rollback" '[ $rc -eq 0 ]'
# #2303 (worker): the calibration job's owner pairs by explicit markers, both ways, beside the route pairs.
cw_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    printf '[[route]]\npath = "/api/models/calibration"\nowner = "%s"\n' "${cw_routes_owner:-rust}"
    printf '[[route]]\npath = "/api/models/calibration/cancel"\nowner = "%s"\n' "${cw_routes_owner:-rust}")
}
cp "$w/server/rust-calibration-routes.cjs" "$work/cw-routes.saved"; cp "$w/server/llamacpp-manager.cjs" "$work/cw-manager.saved"
cat > "$w/server/rust-calibration-cancel.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/models/calibration/cancel']));
JS
touch "$w/server/rust-calibration-cancel-bridge.cjs"
# `cw_marker [generation]`: Core's exported marker (generation 2 unless given).
cw_marker() {
  printf '%s\n' "const CALIBRATION_WORKER_OWNER = 'noevia-calibration-worker-rust/${1:-2}';" \
    "const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/models/calibration']));" \
    'module.exports = { CALIBRATION_WORKER_OWNER, OWNED_ROUTES };' > "$w/server/rust-calibration-routes.cjs"
}
cw_unmarked() { cp "$work/cw-routes.saved" "$w/server/rust-calibration-routes.cjs"; }
# Core's live primitives, and its public calibrator built only when a caller asks for it.
cw_primitives() {
  { cat "$work/cw-manager.saved"
    printf '%s\n' 'cancellationFacts: calibrator.cancellationFacts, compareAndAbort: calibrator.compareAndAbort,'
    printf '%s\n' "$1"
  } > "$w/server/llamacpp-manager.cjs"
}
cw_manager() { cw_primitives "  const calibrator=presets&&publicCalibrator?require('./llamacpp-calibration.cjs').createCalibrator({}):null;"; }
cw_ungated() { cw_primitives "  const calibrator=presets?require('./llamacpp-calibration.cjs').createCalibrator({}):null;"; }
cw_core() {
  cr_core
  cat >> "$w/server/index.cjs" <<'JS'
const calibrationCancelBridge = require('./rust-calibration-cancel-bridge.cjs').createCalibrationCancelBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-calibration-cancel.cjs').refuseOwned(req, res, {})) return;
if (await calibrationCancelBridge(req, res)) return;
JS
}
cw_front() { sed "s/\"start-id\"/\"start-id\", \"rust-calibration-routes\", \"rust-calibration-cancel\"${1:+, \"$1\"}/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
mkdir -p "$repo/build"; cp "$here/../../build/web-supervisor.sh" "$repo/build/web-supervisor.sh"
cw_marker; cw_manager; cw_core; cw_front
cw_try cw-core-only
check "calibration worker marker cannot pair with a front that lacks the worker" 'refused "calibration worker pairing"'
cw_unmarked; cw_ungated; cw_front rust-calibration-worker-v2
cw_try cw-front-only
check "native calibration worker cannot pair with a Core that still runs the job" 'refused "calibration worker pairing"'
cw_marker; cw_manager
cw_try cw-pair
check "matching calibration worker pair assembles" '[ $rc -eq 0 ]'
# Generation 2 has every calibration load decided by Core first: generations pair only with themselves, and
# generation 1 (loads without that decision) is refused even matched.
cw_marker 1
cw_try cw-core-1-front-2
check "a generation-1 Core cannot pair with a generation-2 front" 'refused "Core (generation 1) and Rust (generation 2)"'
cw_marker; cw_front rust-calibration-worker
cw_try cw-core-2-front-1
check "a generation-2 Core cannot pair with a generation-1 front" 'refused "Core (generation 2) and Rust (generation 1)"'
cw_marker 1
cw_try cw-gen-1-pair
check "a matched generation-1 pair is refused: its loads skip Core's load decision" 'refused "generation 1 sends calibration loads without Core'"'"'s load decision"'
cw_marker; cw_front rust-calibration-worker-v2
cp "$repo/build/web-supervisor.sh" "$work/cw-supervisor.saved"
sed 's#rust-calibration-worker-v2#rust-calibration-worker#g; s#noevia-calibration-worker-rust/2#noevia-calibration-worker-rust/1#g' "$work/cw-supervisor.saved" > "$repo/build/web-supervisor.sh"
cw_try cw-gen-1-supervisor
check "a supervisor that compares only generation 1 cannot launch a generation-2 pair" 'refused "web supervisor lacks a prelaunch capability comparison"'
cp "$work/cw-supervisor.saved" "$repo/build/web-supervisor.sh"
# Core's source shape is not this script's to judge (Core CI boots index.cjs for that): a marked Core whose
# manager reads differently, or whose index.cjs mentions recover() in a comment, still pairs by its marker.
cp "$w/server/index.cjs" "$work/cw-index.saved"
printf '%s\n' '/* boot */ // modelManager.calibration?.recover()' >> "$w/server/index.cjs"; cw_ungated
cw_try cw-shape-free
check "a marked calibration worker pair is decided by its markers, not Core's source shapes" '[ $rc -eq 0 ]'
cp "$work/cw-index.saved" "$w/server/index.cjs"; cw_manager
cp "$repo/build/web-supervisor.sh" "$work/cw-supervisor.saved"; grep -v 'CALIBRATION_WORKER_OWNER\|rust-calibration-worker' "$work/cw-supervisor.saved" > "$repo/build/web-supervisor.sh"
cw_try cw-no-supervisor
check "native calibration worker needs the supervisor's prelaunch comparison" 'refused "web supervisor lacks a prelaunch capability comparison"'
cp "$work/cw-supervisor.saved" "$repo/build/web-supervisor.sh"
sed 's/^const CALIBRATION_WORKER_OWNER/\/\/ const CALIBRATION_WORKER_OWNER/' "$w/server/rust-calibration-routes.cjs" > "$work/cw-comment.cjs"; cp "$work/cw-comment.cjs" "$w/server/rust-calibration-routes.cjs"
cw_try cw-comment-marker
check "a calibration worker marker in a comment is no marker" 'refused "calibration worker pairing"'
cw_marker
cp "$work/feature-index.saved" "$w/server/index.cjs"; cw_front rust-calibration-worker-v2
sed 's/"rust-calibration-routes", "rust-calibration-cancel", //' "$rz/bins/noevia-server/src/lib.rs" > "$work/cw-lib"; cp "$work/cw-lib" "$rz/bins/noevia-server/src/lib.rs"
cw_routes_owner=node cw_try cw-no-routes
check "native calibration worker needs the native calibration routes" 'refused "needs the native start/read and cancellation routes"'
cw_unmarked; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
cp "$work/cw-manager.saved" "$w/server/llamacpp-manager.cjs"
cw_routes_owner=node cw_try cw-old-old
check "old calibration worker pair stays valid for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-calibration-cancel.cjs" "$w/server/rust-calibration-cancel-bridge.cjs" "$repo/build/web-supervisor.sh"
cw_unmarked; cp "$work/cw-manager.saved" "$w/server/llamacpp-manager.cjs"
rm -f "$w/server/rust-calibration-routes.cjs" "$w/server/rust-calibration-routes-bridge.cjs"
if [ -f "$work/cr-manager.saved" ]; then cp "$work/cr-manager.saved" "$w/server/llamacpp-manager.cjs"; else rm -f "$w/server/llamacpp-manager.cjs"; fi
if [ -f "$work/cr-original-actor.saved" ]; then cp "$work/cr-original-actor.saved" "$w/server/llamacpp-calibration.cjs"; else rm -f "$w/server/llamacpp-calibration.cjs"; fi
# Row T: MCP discovery is native, Core its fail-closed client; the two release together.
md_try() { try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'); }
md_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const discovery = require('./mcp-native-discovery.cjs').createNativeDiscovery({ broker: PROJECT_STORE });
const chatFacts = require('./toolbox-chat-facts.cjs').createChatFactsPublisher({ dataDir: DATA_DIR });
JS
}
md_front() { sed 's/"start-id"/"start-id", "rust-mcp-discovery"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
[ ! -f "$w/server/mcp-wiring.cjs" ] || cp "$w/server/mcp-wiring.cjs" "$work/md-wiring.saved"
printf 'function createMcpWiring() {}\n' > "$w/server/mcp-wiring.cjs"
touch "$w/server/mcp-native-discovery.cjs"
md_core; md_try md-core-only
check "MCP discovery client cannot pair with an old front" 'refused "MCP discovery ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; md_front
md_try md-front-only
check "MCP discovery capability cannot pair with an old Core" 'refused "MCP discovery ownership pairing"'
md_core; md_try md-pair
check "matching MCP discovery pair assembles" '[ $rc -eq 0 ]'
printf 'async function discoverOneServer() {}\n' > "$w/server/mcp-wiring.cjs"; md_try md-core-discovers
check "a Core that still discovers cannot pair with the native actor" 'refused "Core still discovers"'
printf 'function createMcpWiring() {}\n' > "$w/server/mcp-wiring.cjs"
echo "const mcpDiscoveryPublisher = require('./mcp-discovery-snapshot.cjs').createMcpDiscoveryPublisher({});" >> "$w/server/index.cjs"; md_try md-core-publishes
check "a Core that still publishes a discovery catalogue cannot pair" 'refused "still publishes a discovery catalogue"'
md_core; touch "$w/server/rust-toolbox-picker-facts.cjs"; md_try md-bridge
check "the picker facts bridge cannot survive beside the native actor" 'refused "picker facts bridge is gone"'
rm -f "$w/server/rust-toolbox-picker-facts.cjs"
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
md_try md-old-pair
check "an old Core and front still pair for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/mcp-native-discovery.cjs"
if [ -f "$work/md-wiring.saved" ]; then cp "$work/md-wiring.saved" "$w/server/mcp-wiring.cjs"; else rm -f "$w/server/mcp-wiring.cjs"; fi
# #2287: settings policy moves independently of the live tune state writer.
ats_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    if [ "${ats_skip:-}" != yes ]; then printf '[[route]]\npath = "/api/models/autotune/settings"\nowner = "%s"\n' "$ats_owner"; [ -z "${ats_methods:-}" ] || printf '%s\n' "$ats_methods"; fi)
}
cat > "$w/server/rust-autotune-settings.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/models/autotune/settings']));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/rust-autotune-settings-bridge.cjs"
[ ! -f "$w/server/llamacpp-manager.cjs" ] || cp "$w/server/llamacpp-manager.cjs" "$work/ats-manager.saved"
printf '%s\n' 'settingsFacts: autotuner.settingsFacts, commitSettings: autotuner.commitSettings,' > "$w/server/llamacpp-manager.cjs"
ats_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const autotuneSettingsBridge = require('./rust-autotune-settings-bridge.cjs').createAutotuneSettingsBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-autotune-settings.cjs').refuseOwned(req, res, {})) return;
if (await autotuneSettingsBridge(req, res)) return;
JS
}
ats_front() { sed 's/"start-id"/"start-id", "rust-autotune-settings"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
ats_owner=rust; ats_core
ats_try ats-core-only
check "auto-tune settings refusal cannot pair with an old front" 'refused "auto-tune settings ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; ats_front
ats_try ats-front-only
check "auto-tune settings capability cannot pair with an old Core" 'refused "auto-tune settings ownership pairing"'
ats_core; ats_try ats-pair
check "matching auto-tune settings pair assembles" '[ $rc -eq 0 ]'
# Both model namespaces together: the older read pairing must not keep settings policy in Core.
cp "$work/ms-reads.saved" "$w/server/rust-model-state-reads.cjs"; touch "$w/server/rust-model-facts.cjs"
cat >> "$w/server/index.cjs" <<'JS'
const modelFactsBridge = require('./rust-model-facts.cjs').createModelFactsBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-model-state-reads.cjs').refuseOwned(req, res, {})) return;
if (await modelFactsBridge(req, res)) return;
JS
sed 's/"start-id"/"start-id", "rust-autotune-settings", "rust-model-state-reads"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
ms_owner=rust
try_routes ats-with-model-reads < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; ms_rows; printf '[[route]]\npath = "/api/models/autotune/settings"\nowner = "rust"\n')
check "auto-tune settings and existing model read pairs assemble together" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-model-state-reads.cjs" "$w/server/rust-model-facts.cjs"; ats_core; ats_front
ats_owner=node; ats_try ats-node-rows
check "native settings pair rejects Node ownership" 'refused "auto-tune settings ownership pairing"'
ats_owner=rust; ats_skip=yes; ats_try ats-missing-row
check "native settings pair requires its route row" 'refused "incomplete route ownership"'
unset ats_skip; ats_methods='methods = ["POST"]'; ats_try ats-partial-row
check "native settings pair owns other-method refusals as well as POST" 'refused "auto-tune settings ownership pairing"'
unset ats_methods
cp "$w/server/rust-autotune-settings.cjs" "$work/ats-refuser.saved"
printf 'const OWNED_ROUTES = Object.freeze(new Set([]));\n' > "$w/server/rust-autotune-settings.cjs"; ats_try ats-refuser
check "native settings pair requires exact Core refusal" 'refused "Core must refuse exactly"'
cp "$work/ats-refuser.saved" "$w/server/rust-autotune-settings.cjs"
[ ! -f "$w/server/routes/models.cjs" ] || cp "$w/server/routes/models.cjs" "$work/ats-models.saved"
printf "if (p === '/api/models/autotune/settings') send();\n" >> "$w/server/routes/models.cjs"; ats_try ats-old-handler
check "native settings pair rejects retained public handler" 'refused "Core still carries the public handler"'
if [ -f "$work/ats-models.saved" ]; then cp "$work/ats-models.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi
[ ! -f "$w/server/llamacpp-full-autotune.cjs" ] || cp "$w/server/llamacpp-full-autotune.cjs" "$work/ats-actor.saved"
printf 'function setSettings() {}\n' >> "$w/server/llamacpp-full-autotune.cjs"; ats_try ats-old-policy
check "native settings pair rejects retained Node settings policy" 'refused "Core still carries the public settings policy"'
if [ -f "$work/ats-actor.saved" ]; then cp "$work/ats-actor.saved" "$w/server/llamacpp-full-autotune.cjs"; else rm -f "$w/server/llamacpp-full-autotune.cjs"; fi
cp "$w/server/llamacpp-manager.cjs" "$work/ats-live-manager.saved"; printf 'module.exports = {};\n' > "$w/server/llamacpp-manager.cjs"; ats_try ats-no-primitives
check "native settings pair requires the live single-writer primitives" 'refused "Core does not expose the live actor primitives"'
cp "$work/ats-live-manager.saved" "$w/server/llamacpp-manager.cjs"
mv "$w/server/rust-autotune-settings-bridge.cjs" "$work/ats-bridge.saved"; ats_try ats-no-bridge
check "native settings pair requires actor state bridge" 'refused "missing state bridge"'
mv "$work/ats-bridge.saved" "$w/server/rust-autotune-settings-bridge.cjs"
cp "$w/server/index.cjs" "$work/ats-index.saved"
sed '/await autotuneSettingsBridge(req, res)/d' "$work/ats-index.saved" > "$w/server/index.cjs"; ats_try ats-no-mount
check "native settings pair requires bridge mount" 'refused "missing state bridge mount"'
sed 's/secret: FRONT_SECRET/secret: null/' "$work/ats-index.saved" > "$w/server/index.cjs"; ats_try ats-no-secret
check "native settings pair requires captured bridge secret" 'refused "front captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
ats_try ats-old-rust-rows
check "old settings pair rejects Rust ownership" 'refused "auto-tune settings ownership pairing"'
ats_owner=node; ats_try ats-old-pair
check "old auto-tune settings pair stays valid for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-autotune-settings.cjs" "$w/server/rust-autotune-settings-bridge.cjs"
if [ -f "$work/ats-manager.saved" ]; then cp "$work/ats-manager.saved" "$w/server/llamacpp-manager.cjs"; else rm -f "$w/server/llamacpp-manager.cjs"; fi
# #2294: cancellation policy moves independently of the live auto-tune worker.
atc_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    if [ "${atc_skip:-}" != yes ]; then printf '[[route]]\npath = "/api/models/autotune/cancel"\nowner = "%s"\n' "$atc_owner"; [ -z "${atc_methods:-}" ] || printf '%s\n' "$atc_methods"; fi)
}
cat > "$w/server/rust-autotune-cancel.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/models/autotune/cancel']));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/rust-autotune-cancel-bridge.cjs"
[ ! -f "$w/server/llamacpp-manager.cjs" ] || cp "$w/server/llamacpp-manager.cjs" "$work/atc-manager.saved"
printf '%s\n' 'cancellationFacts: autotuner.cancellationFacts, compareAndAbort: autotuner.compareAndAbort,' > "$w/server/llamacpp-manager.cjs"
atc_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const autotuneCancelBridge = require('./rust-autotune-cancel-bridge.cjs').createAutotuneCancelBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-autotune-cancel.cjs').refuseOwned(req, res, {})) return;
if (await autotuneCancelBridge(req, res)) return;
JS
}
atc_front() { sed 's/"start-id"/"start-id", "rust-autotune-cancel"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
atc_owner=rust; atc_core
atc_try atc-core-only
check "auto-tune cancellation refusal cannot pair with an old front" 'refused "auto-tune cancellation ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; atc_front
atc_try atc-front-only
check "auto-tune cancellation capability cannot pair with an old Core" 'refused "auto-tune cancellation ownership pairing"'
atc_core; atc_try atc-pair
check "matching auto-tune cancellation pair assembles" '[ $rc -eq 0 ]'
# Both model namespaces together: the older read pairing must not keep settings policy in Core.
cp "$work/ms-reads.saved" "$w/server/rust-model-state-reads.cjs"; touch "$w/server/rust-model-facts.cjs"
cat >> "$w/server/index.cjs" <<'JS'
const modelFactsBridge = require('./rust-model-facts.cjs').createModelFactsBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-model-state-reads.cjs').refuseOwned(req, res, {})) return;
if (await modelFactsBridge(req, res)) return;
JS
sed 's/"start-id"/"start-id", "rust-autotune-cancel", "rust-model-state-reads"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
ms_owner=rust
try_routes atc-with-model-reads < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; ms_rows; printf '[[route]]\npath = "/api/models/autotune/cancel"\nowner = "rust"\n')
check "auto-tune cancellation and existing model read pairs assemble together" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-model-state-reads.cjs" "$w/server/rust-model-facts.cjs"; atc_core; atc_front
atc_owner=node; atc_try atc-node-rows
check "native cancellation pair rejects Node ownership" 'refused "auto-tune cancellation ownership pairing"'
atc_owner=rust; atc_skip=yes; atc_try atc-missing-row
check "native cancellation pair requires its route row" 'refused "incomplete route ownership"'
unset atc_skip; atc_methods='methods = ["POST"]'; atc_try atc-partial-row
check "native cancellation pair owns other-method refusals as well as POST" 'refused "auto-tune cancellation ownership pairing"'
unset atc_methods
cp "$w/server/rust-autotune-cancel.cjs" "$work/atc-refuser.saved"
printf 'const OWNED_ROUTES = Object.freeze(new Set([]));\n' > "$w/server/rust-autotune-cancel.cjs"; atc_try atc-refuser
check "native cancellation pair requires exact Core refusal" 'refused "Core must refuse exactly"'
cp "$work/atc-refuser.saved" "$w/server/rust-autotune-cancel.cjs"
[ ! -f "$w/server/routes/models.cjs" ] || cp "$w/server/routes/models.cjs" "$work/atc-models.saved"
printf "if (p === '/api/models/autotune/cancel') send();\n" >> "$w/server/routes/models.cjs"; atc_try atc-old-handler
check "native cancellation pair rejects retained public handler" 'refused "Core still carries the public handler"'
if [ -f "$work/atc-models.saved" ]; then cp "$work/atc-models.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi
[ ! -f "$w/server/llamacpp-full-autotune.cjs" ] || cp "$w/server/llamacpp-full-autotune.cjs" "$work/atc-actor.saved"
printf 'function cancel() {}\n' >> "$w/server/llamacpp-full-autotune.cjs"; atc_try atc-old-policy
check "native cancellation pair rejects retained Node cancellation policy" 'refused "Core still carries the public cancellation policy"'
if [ -f "$work/atc-actor.saved" ]; then cp "$work/atc-actor.saved" "$w/server/llamacpp-full-autotune.cjs"; else rm -f "$w/server/llamacpp-full-autotune.cjs"; fi
cp "$w/server/llamacpp-manager.cjs" "$work/atc-live-manager.saved"; printf 'module.exports = {};\n' > "$w/server/llamacpp-manager.cjs"; atc_try atc-no-primitives
check "native cancellation pair requires the live single-writer primitives" 'refused "Core does not expose the live actor primitives"'
cp "$work/atc-live-manager.saved" "$w/server/llamacpp-manager.cjs"
mv "$w/server/rust-autotune-cancel-bridge.cjs" "$work/atc-bridge.saved"; atc_try atc-no-bridge
check "native cancellation pair requires actor state bridge" 'refused "missing state bridge"'
mv "$work/atc-bridge.saved" "$w/server/rust-autotune-cancel-bridge.cjs"
cp "$w/server/index.cjs" "$work/atc-index.saved"
sed '/await autotuneCancelBridge(req, res)/d' "$work/atc-index.saved" > "$w/server/index.cjs"; atc_try atc-no-mount
check "native cancellation pair requires bridge mount" 'refused "missing state bridge mount"'
sed 's/secret: FRONT_SECRET/secret: null/' "$work/atc-index.saved" > "$w/server/index.cjs"; atc_try atc-no-secret
check "native cancellation pair requires captured bridge secret" 'refused "front captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
atc_try atc-old-rust-rows
check "old cancellation pair rejects Rust ownership" 'refused "auto-tune cancellation ownership pairing"'
atc_owner=node; atc_try atc-old-pair
check "old auto-tune cancellation pair stays valid for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-autotune-cancel.cjs" "$w/server/rust-autotune-cancel-bridge.cjs"
if [ -f "$work/atc-manager.saved" ]; then cp "$work/atc-manager.saved" "$w/server/llamacpp-manager.cjs"; else rm -f "$w/server/llamacpp-manager.cjs"; fi
# #2295: discovery policy moves independently of the live autotune worker.
au_scan_try() {
  try_routes "$1" < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n';
    if [ "${au_scan_skip:-}" != yes ]; then printf '[[route]]\npath = "/api/models/autotune/untuned"\nowner = "%s"\n' "$au_scan_owner"; [ -z "${au_scan_methods:-}" ] || printf '%s\n' "$au_scan_methods"; fi)
}
cat > "$w/server/rust-autotune-untuned.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['ALL /api/models/autotune/untuned']));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/rust-autotune-untuned-facts.cjs"
[ ! -f "$w/server/llamacpp-manager.cjs" ] || cp "$w/server/llamacpp-manager.cjs" "$work/aus-manager.saved"
printf '%s\n' 'scanFacts: autotuner.scanFacts,' > "$w/server/llamacpp-manager.cjs"
au_scan_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const autotuneUntunedFacts = require('./rust-autotune-untuned-facts.cjs').createAutotuneUntunedFacts({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-autotune-untuned.cjs').refuseOwned(req, res, {})) return;
if (await autotuneUntunedFacts(req, res)) return;
JS
}
au_scan_front() { sed 's/"start-id"/"start-id", "rust-autotune-untuned"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
# The candidate scanner must have the same native and WASM primitive, not a Node decision copy.
for pair in "server/llamacpp-full-autotune.cjs aus-original-actor" "server/dav-parse-wasm.cjs aus-original-wasm"; do
  set -- $pair; [ ! -f "$w/$1" ] || cp "$w/$1" "$work/$2"
done
[ ! -f "$rz/bins/dav-parse-wasm/src/lib.rs" ] || cp "$rz/bins/dav-parse-wasm/src/lib.rs" "$work/aus-original-rust-wasm"
mkdir -p "$rz/bins/dav-parse-wasm/src"
printf 'async function untunedFacts() {}\nconst scan = r => wasm.autotuneScan(r);\n' > "$w/server/llamacpp-full-autotune.cjs"
printf 'const call = e => e.autotune_scan();\n' > "$w/server/dav-parse-wasm.cjs"
printf 'pub extern "C" fn autotune_scan() -> u32 { 0 }\n' > "$rz/bins/dav-parse-wasm/src/lib.rs"
au_scan_owner=rust; au_scan_core
au_scan_try aus-core-only
check "untuned discovery refusal cannot pair with an old front" 'refused "untuned discovery ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; au_scan_front
au_scan_try aus-front-only
check "untuned discovery capability cannot pair with an old Core" 'refused "untuned discovery ownership pairing"'
au_scan_core; au_scan_try aus-pair
check "matching untuned discovery pair assembles" '[ $rc -eq 0 ]'
# Each shared-policy link must be actual code; comments cannot satisfy it.
for aus_link in actor adapter rust; do
  case "$aus_link" in
    actor) aus_path="$w/server/llamacpp-full-autotune.cjs";;
    adapter) aus_path="$w/server/dav-parse-wasm.cjs";;
    rust) aus_path="$rz/bins/dav-parse-wasm/src/lib.rs";;
  esac
  cp "$aus_path" "$work/aus-policy-link.saved"
  sed 's/^/\/\/ /' "$work/aus-policy-link.saved" > "$aus_path"
  au_scan_try "aus-comment-only-$aus_link"
  check "native discovery pair rejects comment-only shared policy $aus_link" 'refused "shared Rust/WASM policy and raw owner facts required"'
  cp "$work/aus-policy-link.saved" "$aus_path"
done
# Both model namespaces together: the older read pairing must not keep settings policy in Core.
cp "$work/ms-reads.saved" "$w/server/rust-model-state-reads.cjs"; touch "$w/server/rust-model-facts.cjs"
cat >> "$w/server/index.cjs" <<'JS'
const modelFactsBridge = require('./rust-model-facts.cjs').createModelFactsBridge({
  secret: FRONT_SECRET, json, readJson,
});
if (require('./rust-model-state-reads.cjs').refuseOwned(req, res, {})) return;
if (await modelFactsBridge(req, res)) return;
JS
sed 's/"start-id"/"start-id", "rust-autotune-untuned", "rust-model-state-reads"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
ms_owner=rust
try_routes aus-with-model-reads < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n'; ms_rows; printf '[[route]]\npath = "/api/models/autotune/untuned"\nowner = "rust"\n')
check "untuned discovery and existing model read pairs assemble together" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-model-state-reads.cjs" "$w/server/rust-model-facts.cjs"; au_scan_core; au_scan_front
au_scan_owner=node; au_scan_try aus-node-rows
check "native discovery pair rejects Node ownership" 'refused "untuned discovery ownership pairing"'
au_scan_owner=rust; au_scan_skip=yes; au_scan_try aus-missing-row
check "native discovery pair requires its route row" 'refused "incomplete route ownership"'
unset au_scan_skip; au_scan_methods='methods = ["POST"]'; au_scan_try aus-partial-row
check "native discovery pair owns other-method refusals as well as POST" 'refused "untuned discovery ownership pairing"'
unset au_scan_methods
cp "$w/server/rust-autotune-untuned.cjs" "$work/aus-refuser.saved"
printf 'const OWNED_ROUTES = Object.freeze(new Set([]));\n' > "$w/server/rust-autotune-untuned.cjs"; au_scan_try aus-refuser
check "native discovery pair requires exact Core refusal" 'refused "Core must refuse exactly"'
cp "$work/aus-refuser.saved" "$w/server/rust-autotune-untuned.cjs"
[ ! -f "$w/server/routes/models.cjs" ] || cp "$w/server/routes/models.cjs" "$work/aus-models.saved"
printf "if (p === '/api/models/autotune/untuned') send();\n" >> "$w/server/routes/models.cjs"; au_scan_try aus-old-handler
check "native discovery pair rejects retained public handler" 'refused "Core still carries the public handler"'
if [ -f "$work/aus-models.saved" ]; then cp "$work/aus-models.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi
[ ! -f "$w/server/llamacpp-full-autotune.cjs" ] || cp "$w/server/llamacpp-full-autotune.cjs" "$work/aus-actor.saved"
printf 'async function untuned() {}\n' >> "$w/server/llamacpp-full-autotune.cjs"; au_scan_try aus-old-policy
check "native discovery pair rejects retained Node discovery policy" 'refused "Core still carries the public discovery policy"'
if [ -f "$work/aus-actor.saved" ]; then cp "$work/aus-actor.saved" "$w/server/llamacpp-full-autotune.cjs"; else rm -f "$w/server/llamacpp-full-autotune.cjs"; fi
cp "$w/server/llamacpp-manager.cjs" "$work/aus-live-manager.saved"; printf 'module.exports = {};\n' > "$w/server/llamacpp-manager.cjs"; au_scan_try aus-no-primitives
check "native discovery pair requires the live single-writer primitives" 'refused "shared Rust/WASM policy and raw owner facts required"'
cp "$work/aus-live-manager.saved" "$w/server/llamacpp-manager.cjs"
mv "$w/server/rust-autotune-untuned-facts.cjs" "$work/aus-bridge.saved"; au_scan_try aus-no-bridge
check "native discovery pair requires actor state bridge" 'refused "missing state bridge"'
mv "$work/aus-bridge.saved" "$w/server/rust-autotune-untuned-facts.cjs"
cp "$w/server/index.cjs" "$work/aus-index.saved"
sed '/await autotuneUntunedFacts(req, res)/d' "$work/aus-index.saved" > "$w/server/index.cjs"; au_scan_try aus-no-mount
check "native discovery pair requires bridge mount" 'refused "missing state bridge mount"'
sed 's/secret: FRONT_SECRET/secret: null/' "$work/aus-index.saved" > "$w/server/index.cjs"; au_scan_try aus-no-secret
check "native discovery pair requires captured bridge secret" 'refused "front captured secret"'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
au_scan_try aus-old-rust-rows
check "old discovery pair rejects Rust ownership" 'refused "untuned discovery ownership pairing"'
au_scan_owner=node; au_scan_try aus-old-pair
check "old untuned discovery pair stays valid for rollback" '[ $rc -eq 0 ]'
rm -f "$w/server/rust-autotune-untuned.cjs" "$w/server/rust-autotune-untuned-facts.cjs"
if [ -f "$work/aus-manager.saved" ]; then cp "$work/aus-manager.saved" "$w/server/llamacpp-manager.cjs"; else rm -f "$w/server/llamacpp-manager.cjs"; fi
for pair in "server/llamacpp-full-autotune.cjs aus-original-actor" "server/dav-parse-wasm.cjs aus-original-wasm"; do
  set -- $pair; if [ -f "$work/$2" ]; then cp "$work/$2" "$w/$1"; else rm -f "$w/$1"; fi
done
if [ -f "$work/aus-original-rust-wasm" ]; then cp "$work/aus-original-rust-wasm" "$rz/bins/dav-parse-wasm/src/lib.rs"; else rm -f "$rz/bins/dav-parse-wasm/src/lib.rs"; fi
# Account deletion owner release matrix (sbstndalton/noevia#2190, #2191 round 9): DELETE /api/admin/users/{id} only,
# and a Core with no way left to delete an account.
au_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/admin/users/{id}"
owner = "rust"
$au_methods
TOML
}
au_methods='methods = ["DELETE"]'
cp "$w/server/rust-auth.cjs" "$work/au-rust-auth.saved"
cat > "$w/server/rust-admin-users.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'DELETE /api/admin/users/{id}',
]));
module.exports = { OWNED_ROUTES };
JS
printf '%s\n' "function refuseOwned(req, res, pathname, json) { return false; }" "const FRONT_TABLES = { users: { message: 'users is written by the Rust front' } };" > "$w/server/rust-auth.cjs"
printf '%s\n' "module.exports = { createAuth() { return { listUsers() {} }; } };" > "$w/server/auth.cjs"
au_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  printf '%s\n' "  if (require('./rust-admin-users.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
}
au_front() { sed "s/\"start-id\"/\"start-id\", \"rust-admin-users\"/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
au_core; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
au_try admin-users-core-only
check "account deletion Core refusal requires the native capability" 'refused "account deletion ownership pairing"'
au_front
au_try admin-users-pair
check "matching account deletion pair with DELETE only assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
au_methods=""
au_try admin-users-all-methods
check "an all-method account route is refused (Node keeps the other methods)" 'refused "account deletion ownership pairing"'
au_methods='methods = ["DELETE", "PUT"]'
au_try admin-users-extra-method
check "an account route with another method is refused" 'refused "account deletion ownership pairing"'
au_methods='methods = ["DELETE"]'
printf '%s\n' "module.exports = { createAuth() { return {" "    deleteUser(actorId, userId, username) { return false; }," "  }; } };" > "$w/server/auth.cjs"
au_try admin-users-core-can-delete
check "a Core that can still delete an account is refused" 'refused "Core can still delete an account"'
printf '%s\n' "module.exports = { createAuth() { return { listUsers() {} }; } };" > "$w/server/auth.cjs"
printf '%s\n' "function refuseOwned(req, res, pathname, json) { return false; }" "const FRONT_TABLES = {};" > "$w/server/rust-auth.cjs"
au_try admin-users-guard-open
check "a Core whose guard does not refuse users is refused" 'refused "Core can still delete an account"'
printf '%s\n' "function refuseOwned(req, res, pathname, json) { return false; }" "const FRONT_TABLES = { users: { message: 'users is written by the Rust front' } };" > "$w/server/rust-auth.cjs"
mv "$w/server/rust-admin-users.cjs" "$work/rust-admin-users.saved"
printf 'module.exports = {};\n' > "$w/server/rust-admin-users.cjs"
au_try admin-users-unlisted
check "a Core that refuses nothing is refused" 'refused "Core must refuse exactly DELETE"'
mv "$work/rust-admin-users.saved" "$w/server/rust-admin-users.cjs"
cp "$work/feature-index.saved" "$w/server/index.cjs"
au_try admin-users-front-only
check "a rust-admin-users front cannot pair with the old Core handler" 'refused "account deletion ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try admin-users-old-pair
check "historic account deletion old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
rm -f "$w/server/rust-admin-users.cjs" "$w/server/auth.cjs"
cp "$work/au-rust-auth.saved" "$w/server/rust-auth.cjs"
# Document page reader owner release matrix (sbstndalton/noevia#2191 round 4): GET
# /api/projects/{id}/documents/pages only; no other pair needed.
document_pages_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{id}/documents/pages"
owner = "rust"
$document_pages_methods
TOML
}
document_pages_methods='methods = ["GET"]'
cat > "$w/server/rust-project-document-pages.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'GET /api/projects/{id}/documents/pages',
]));
module.exports = { OWNED_ROUTES };
JS
pages_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  [ "${1:-}" = pages ] && printf '%s\n' "  if (require('./rust-project-document-pages.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  return 0
}
pages_front() { sed "s/\"start-id\"/\"start-id\"$1/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
pages_core pages; pages_front ""
document_pages_try document-pages-core-only
check "document page reader Core refusal requires the native capability" 'refused "project document page reader ownership pairing"'
pages_front ', \"rust-project-document-pages\"'
document_pages_try document-pages-pair
check "matching document page reader pair with GET only assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
mv "$w/server/rust-project-document-pages.cjs" "$work/rust-project-document-pages.saved"
document_pages_try document-pages-unlisted
check "a front owning the page reader needs a Core that lists it (OWNED_ROUTES)" 'refused "does not list in server/rust-projects.cjs OWNED_ROUTES"'
mv "$work/rust-project-document-pages.saved" "$w/server/rust-project-document-pages.cjs"
document_pages_methods=""
document_pages_try document-pages-all-methods
check "an all-method document pages route is refused (Node keeps the other methods)" 'refused "project document page reader ownership pairing"'
document_pages_methods='methods = ["GET"]'
pages_core
document_pages_try document-pages-front-only
check "a rust-project-document-pages front cannot pair with the old Core handler" 'refused "project document page reader ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try document-pages-old-pair
check "historic document page reader old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
rm -f "$w/server/rust-project-document-pages.cjs"
# Conversation import owner release matrix (sbstndalton/noevia#2191 round 4): POST
# /api/import/conversations only, on top of the create/delete pair.
conversation_import_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{projectId}"
owner = "rust"
methods = ["DELETE"]
[[route]]
path = "/api/import/conversations"
owner = "rust"
$conversation_import_methods
TOML
}
conversation_import_methods='methods = ["POST"]'
import_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  [ "${2:-}" = nolifecycle ] || printf '%s\n' "  if (require('./rust-project-lifecycle.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  [ "${1:-}" = import ] && printf '%s\n' "  if (require('./rust-conversation-import.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  return 0
}
import_front() { sed "s/\"start-id\"/\"start-id\"$1/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
cat > "$w/server/rust-project-lifecycle.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects',
  'DELETE /api/projects/{projectId}',
]));
module.exports = { OWNED_ROUTES };
JS
cat > "$w/server/rust-conversation-import.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/import/conversations',
]));
module.exports = { OWNED_ROUTES };
JS
import_core import; import_front ', \"rust-project-lifecycle\"'
conversation_import_try conversation-import-core-only
check "conversation import Core refusal requires the native capability" 'refused "conversation import ownership pairing"'
import_front ', \"rust-project-lifecycle\", \"rust-conversation-import\"'
conversation_import_try conversation-import-pair
check "matching conversation import pair with POST only assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
conversation_import_methods=""
conversation_import_try conversation-import-all-methods
check "an all-method import route is refused (Node keeps the 405)" 'refused "conversation import ownership pairing"'
conversation_import_methods='methods = ["POST"]'
import_core
conversation_import_try conversation-import-front-only
check "a rust-conversation-import front cannot pair with the old Core handler" 'refused "conversation import ownership pairing"'
import_core import nolifecycle; import_front ', \"rust-conversation-import\"'
conversation_import_try conversation-import-without-lifecycle
check "a conversation import pair without the create/delete pair is refused" 'refused "needs the project create/delete pair"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try conversation-import-old-pair
check "historic conversation import old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
rm -f "$w/server/rust-conversation-import.cjs" "$w/server/rust-project-lifecycle.cjs"
# Project document upload owner release matrix (sbstndalton/noevia#2191 round 5): POST
# /api/projects/{id}/documents only, with the rust-document-extraction pipeline.
documents_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{id}/documents"
owner = "rust"
$documents_methods
TOML
}
documents_methods='methods = ["POST"]'
documents_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  [ "${1:-}" = documents ] && printf '%s\n' "  if (require('./rust-project-documents.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  return 0
}
documents_front() { sed "s/\"start-id\"/\"start-id\"$1/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
cat > "$w/server/rust-project-documents.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{id}/documents',
]));
module.exports = { OWNED_ROUTES };
JS
documents_core documents; documents_front ', \"rust-document-extraction\"'
documents_try documents-core-only
check "document upload Core refusal requires the native capability" 'refused "project document upload ownership pairing"'
documents_front ', \"rust-document-extraction\", \"rust-project-documents\"'
documents_try documents-pair
check "matching document upload pair with POST only assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
documents_methods=""
documents_try documents-all-methods
check "an all-method document route is refused" 'refused "project document upload ownership pairing"'
documents_methods='methods = ["POST"]'
documents_front ', \"rust-project-documents\"'
documents_try documents-without-pipeline
check "a document upload front without the extraction pipeline is refused" 'refused "needs the rust-document-extraction pipeline"'
documents_core
documents_front ', \"rust-document-extraction\", \"rust-project-documents\"'
documents_try documents-front-only
check "a rust-project-documents front cannot pair with the old Core handler" 'refused "project document upload ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try documents-old-pair
check "historic document upload old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
rm -f "$w/server/rust-project-documents.cjs"
# Source job owner release matrix (sbstndalton/noevia#2191 round 6): POST of the upload and the sync
# (the background start) and GET of the poll; no Node client, no internal store.
sj_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{id}/upload"
owner = "rust"
$sj_methods
[[route]]
path = "/api/projects/{id}/sources/sync"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{id}/source-jobs/{jobId}"
owner = "rust"
methods = ["GET"]
TOML
}
sj_methods='methods = ["POST"]'
sj_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  [ "${1:-}" = jobs ] && printf '%s\n' "  if (require('./rust-source-jobs.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  return 0
}
sj_front() { sed "s/\"start-id\"/\"start-id\"$1/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
cat > "$w/server/rust-source-jobs.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{id}/upload',
  'POST /api/projects/{id}/sources/sync',
  'GET /api/projects/{id}/source-jobs/{jobId}',
]));
module.exports = { OWNED_ROUTES };
JS
# The old generation's client and internal store, set aside for the new pair and put back for the
# old/old rollback case.
# (the source lines only: the other pairings read the same files).
for f in "$w/server/project-store-client.cjs" "$w/server/source-jobs.cjs" "$rz/bins/noevia-server/src/project_store.rs" "$rz/crates/server-projects/src/source_jobs.rs"; do
  if [ -e "$f" ]; then cp "$f" "$f.sj-saved"; fi
done
rm -f "$w/server/source-jobs.cjs"
for f in "$w/server/project-store-client.cjs" "$rz/bins/noevia-server/src/project_store.rs" "$rz/crates/server-projects/src/source_jobs.rs"; do
  if [ -e "$f" ]; then grep -vE 'SOURCE_JOBS_CLIENT_MARKER|sourceJobsFor\(|/v1/source-jobs/|SOURCE_JOBS_STORE_MARKER|use server_projects::source_jobs as jobs;' "$f.sj-saved" > "$f" || true; fi
done
sj_core jobs; sj_front ''
sj_try source-jobs-core-only
check "source job Core refusal requires the native capability" 'refused "source job ownership pairing: Core and Rust must move together"'
sj_front ', \"rust-source-jobs\"'
sj_try source-jobs-pair
check "matching source job pair with exact methods assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# sbstndalton/noevia#2191 round 8: the project source operations ride on that pair, with the host lock,
# Docling extraction, the storage latch file and the file-operation list.
sw_plan='methods = ["POST"]'
sw_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{id}/upload"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{id}/sources/sync"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/projects/{id}/folder-import/plan"
owner = "rust"
$sw_plan
[[route]]
path = "/api/projects/{id}/source-jobs/{jobId}"
owner = "rust"
methods = ["GET"]
TOML
}
sw_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  printf '%s\n' "  if (require('./rust-source-jobs.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  if [ "${1:-}" = work ]; then
    printf '%s\n' "  if (require('./rust-project-source-work.cjs').refuseOwned(req, res, {})) return;" "const storageLatch = require('./storage-latch.cjs').createStorageLatch({ file: require('node:path').join(DATA_DIR, 'storage-latch.db') });" >> "$w/server/index.cjs"
  fi
  return 0
}
cat > "$w/server/rust-source-jobs.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'GET /api/projects/{id}/source-jobs/{jobId}',
]));
module.exports = { OWNED_ROUTES };
JS
cat > "$w/server/rust-project-source-work.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{id}/upload',
  'POST /api/projects/{id}/sources/sync',
  'POST /api/projects/{id}/folder-import/plan',
]));
module.exports = { OWNED_ROUTES };
JS
printf '%s\n' "const FILE = 'source-file-ops.json';" > "$w/server/rust-source-ops.cjs"
printf '%s\n' "db.exec('BEGIN IMMEDIATE');" > "$w/server/storage-latch.cjs"
printf '%s\n' 'pub const FILE: &str = "storage-latch.db";' '    conn.execute_batch("BEGIN IMMEDIATE")?;' > "$rz/crates/server-projects/src/storage_latch.rs"
printf '%s\n' 'pub const FILE: &str = "source-file-ops.json";' > "$rz/crates/server-projects/src/source_ops.rs"
# The host lock the front takes (the capability this one needs) and Core's side of it.
printf '%s\n' "const fileLock = require('./large-document-file-lock.cjs');" > "$w/server/large-document-lock.cjs"
printf '%s\n' "const LOCK_FILE = 'large-document.lock';" "  try { db.exec('BEGIN IMMEDIATE'); return db; } catch (err) { throw err; }" "module.exports = { LOCK_FILE };" > "$w/server/large-document-file-lock.cjs"
printf '%s\n' 'pub const LARGE_LOCK_FILE: &str = "large-document.lock";' '        match conn.execute_batch("BEGIN IMMEDIATE") {' > "$rz/crates/server-projects/src/extract.rs"
sw_front() { sed "s/\"start-id\"/\"start-id\"$1/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
sw_all=', \"rust-source-jobs\", \"rust-document-extraction\", \"rust-large-document-host-lock\"'
sw_core work; sw_front "$sw_all"
sw_try source-work-core-only
check "a source-work Core refuses an old front" 'refused "project source work ownership pairing: Core and Rust must move together"'
sw_core; sw_front "$sw_all, \"rust-project-source-work\""
sw_try source-work-front-only
check "a rust-project-source-work front refuses an old Core" 'refused "project source work ownership pairing: Core and Rust must move together"'
sw_core work; sw_front "$sw_all, \"rust-project-source-work\""
sw_try source-work-pair
check "the matching source operations pair assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
sw_front ", \"rust-source-jobs\", \"rust-large-document-host-lock\", \"rust-project-source-work\""
sw_try source-work-no-extraction
check "source operations without the Docling extraction pipeline are refused" 'refused "project source work ownership pairing: needs the rust-document-extraction capability"'
sw_front "$sw_all, \"rust-project-source-work\""
# Each piece of the worker path is refused on its own, not only the registry: the folder import, the PDF
# reduction and the worker header a route or the index would still answer.
mkdir -p "$w/server/routes"
for worker_file in source-work.cjs folder-import.cjs pdf-reduce.cjs; do
  printf '%s\n' "// stub" > "$w/server/$worker_file"
  sw_try "source-work-worker-path-$worker_file"
  check "a pair whose Core keeps server/$worker_file is refused" 'refused "project source work ownership pairing: Core still carries the worker path"'
  rm -f "$w/server/$worker_file"
done
cp "$w/server/index.cjs" "$work/sw-index-saved"
printf '%s\n' "if (req.headers['x-noevia-source-work']) {}" > "$w/server/routes/projects.cjs"
sw_try source-work-worker-header-route
check "a pair whose Core routes still answer the worker header is refused" 'refused "project source work ownership pairing: Core still carries the worker path"'
rm -f "$w/server/routes/projects.cjs"
printf '%s\n' "if (req.headers['x-noevia-source-work']) {}" >> "$w/server/index.cjs"
sw_try source-work-worker-header-index
check "a pair whose Core index still answers the worker header is refused" 'refused "project source work ownership pairing: Core still carries the worker path"'
cp "$work/sw-index-saved" "$w/server/index.cjs"
cp "$w/server/storage-latch.cjs" "$work/sw-latch-core"; cp "$rz/crates/server-projects/src/storage_latch.rs" "$work/sw-latch-rs"
sed "s/storage-latch.db/other.db/" "$work/sw-latch-rs" > "$rz/crates/server-projects/src/storage_latch.rs"
sw_try source-work-latch-name
check "a front that keeps its latch in another file than Core is refused" 'refused "project source work ownership pairing: Core and Rust must name the same storage latch file"'
cp "$work/sw-latch-rs" "$rz/crates/server-projects/src/storage_latch.rs"
# The latch file named only in a comment of Core's index, or not at all, is not a pairing (and the script says
# so instead of ending without a word).
sed "s|^const storageLatch = .*|// storage-latch.db|" "$work/sw-index-saved" > "$w/server/index.cjs"
sw_try source-work-latch-name-comment
check "a Core that names its latch file only in a comment is refused" 'refused "project source work ownership pairing: Core and Rust must name the same storage latch file"'
grep -v "storage-latch" "$work/sw-index-saved" > "$w/server/index.cjs"
sw_try source-work-latch-name-absent
check "a Core that never names its latch file is refused with a message" 'refused "project source work ownership pairing: Core and Rust must name the same storage latch file"'
cp "$work/sw-index-saved" "$w/server/index.cjs"
# BEGIN IMMEDIATE only in a comment does not make the change atomic.
sed "s|^db.exec('BEGIN IMMEDIATE');|// db.exec('BEGIN IMMEDIATE');|" "$work/sw-latch-core" > "$w/server/storage-latch.cjs"
sw_try source-work-latch-statement-core-comment
check "a Core whose latch transaction is only a comment is refused" 'refused "project source work ownership pairing: Core and Rust must both change the storage latch with BEGIN IMMEDIATE"'
cp "$work/sw-latch-core" "$w/server/storage-latch.cjs"
sed 's|^    conn.execute_batch("BEGIN IMMEDIATE")?;|    // conn.execute_batch("BEGIN IMMEDIATE")?;|' "$work/sw-latch-rs" > "$rz/crates/server-projects/src/storage_latch.rs"
sw_try source-work-latch-statement-rs-comment
check "a front whose latch transaction is only a comment is refused" 'refused "project source work ownership pairing: Core and Rust must both change the storage latch with BEGIN IMMEDIATE"'
cp "$work/sw-latch-rs" "$rz/crates/server-projects/src/storage_latch.rs"
sed "s/BEGIN IMMEDIATE/BEGIN DEFERRED/" "$work/sw-latch-core" > "$w/server/storage-latch.cjs"
sw_try source-work-latch-statement
check "a Core that changes the latch another way is refused" 'refused "project source work ownership pairing: Core and Rust must both change the storage latch with BEGIN IMMEDIATE"'
cp "$work/sw-latch-core" "$w/server/storage-latch.cjs"
printf '%s\n' 'pub const FILE: &str = "other-ops.json";' > "$rz/crates/server-projects/src/source_ops.rs"
sw_try source-work-ops-name
check "a front that lists its operations in another file than Core reads is refused" 'refused "project source work ownership pairing: Core and Rust must name the same file-operation list"'
printf '%s\n' 'pub const FILE: &str = "source-file-ops.json";' > "$rz/crates/server-projects/src/source_ops.rs"
rm -f "$w/server/rust-source-ops.cjs"
sw_try source-work-no-ops-reader
check "a Core without its file-operation reader is refused" 'refused "project source work ownership pairing: Core lacks its readers"'
printf '%s\n' "const FILE = 'source-file-ops.json';" > "$w/server/rust-source-ops.cjs"
sw_plan='methods = ["POST", "GET"]'
sw_try source-work-plan-methods
check "a folder plan route that is not exactly POST is refused" 'refused "project source work ownership pairing: exactly POST of the upload, the sync and the folder import"'
sw_plan='methods = ["POST"]'
sw_try source-work-pair-again
check "the matching source operations pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
rm -f "$w/server/rust-project-source-work.cjs" "$w/server/rust-source-ops.cjs" "$w/server/storage-latch.cjs" "$w/server/large-document-lock.cjs" "$w/server/large-document-file-lock.cjs" "$rz/crates/server-projects/src/storage_latch.rs" "$rz/crates/server-projects/src/source_ops.rs" "$rz/crates/server-projects/src/extract.rs"
cat > "$w/server/rust-source-jobs.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set([
  'POST /api/projects/{id}/upload',
  'POST /api/projects/{id}/sources/sync',
  'GET /api/projects/{id}/source-jobs/{jobId}',
]));
module.exports = { OWNED_ROUTES };
JS
sj_core jobs; sj_front ', \"rust-source-jobs\"'
sj_methods=""
sj_try source-jobs-all-methods
check "an all-method upload route is refused" 'refused "source job ownership pairing: exactly POST"'
sj_methods='methods = ["POST"]'
cp "$w/server/project-store-client.cjs" "$work/sj-client"
printf '%s\n' "const SOURCE_JOBS_CLIENT_MARKER = 'noevia-source-jobs-client/1';" >> "$w/server/project-store-client.cjs"
sj_try source-jobs-with-client
check "a source job pair whose Core keeps the journal client is refused" 'refused "Core still carries a source journal client"'
cp "$work/sj-client" "$w/server/project-store-client.cjs"
cp "$rz/bins/noevia-server/src/project_store.rs" "$work/sj-store"
printf '%s\n' '        .route("/v1/source-jobs/start", source_route(SourceOp::Start))' >> "$rz/bins/noevia-server/src/project_store.rs"
sj_try source-jobs-with-store
check "a source job pair whose front keeps the internal store is refused" 'refused "the front still serves the internal source store"'
cp "$work/sj-store" "$rz/bins/noevia-server/src/project_store.rs"
sj_core
sj_try source-jobs-front-only
check "a rust-source-jobs front cannot pair with the old Core" 'refused "source job ownership pairing: Core and Rust must move together"'
for f in "$w/server/project-store-client.cjs" "$w/server/source-jobs.cjs" "$rz/bins/noevia-server/src/project_store.rs" "$rz/crates/server-projects/src/source_jobs.rs"; do
  if [ -e "$f.sj-saved" ]; then mv "$f.sj-saved" "$f"; fi
done
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try source-jobs-old-pair
check "historic source job old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# sbstndalton/noevia#2191 round 7 (#697): the host-wide large-document lock pairs in both directions.
printf '%s\n' "const fileLock = require('./large-document-file-lock.cjs');" > "$w/server/large-document-lock.cjs"
printf '%s\n' "const LOCK_FILE = 'large-document.lock';" "  try { db.exec('BEGIN IMMEDIATE'); return db; } catch (err) { throw err; }" "module.exports = { LOCK_FILE };" > "$w/server/large-document-file-lock.cjs"
printf '%s\n' 'pub const LARGE_LOCK_FILE: &str = "large-document.lock";' '        match conn.execute_batch("BEGIN IMMEDIATE") {' > "$rz/crates/server-projects/src/extract.rs"
move_try large-lock-core-only
check "a host-lock Core cannot pair with an in-process-lock front" 'refused "large-document lock pairing: Core and Rust must share the host lock"'
sed 's/"start-id"/"start-id", "rust-large-document-host-lock"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
move_try large-lock-pair
check "matching host large-document lock pair assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Both halves must also name the same lock file and take it the same way (review #2191 r6+7).
cp "$w/server/large-document-file-lock.cjs" "$work/file-lock.saved"
cp "$rz/crates/server-projects/src/extract.rs" "$work/extract-lock.saved"
sed "s/large-document.lock/other.lock/" "$work/file-lock.saved" > "$w/server/large-document-file-lock.cjs"
move_try large-lock-core-name
check "a Core that locks another file than the front is refused" 'refused "large-document lock pairing: Core and Rust must name the same lock file (Core .other.lock., Rust .large-document.lock.)"'
cp "$work/file-lock.saved" "$w/server/large-document-file-lock.cjs"
sed "s/large-document.lock/other.lock/" "$work/extract-lock.saved" > "$rz/crates/server-projects/src/extract.rs"
move_try large-lock-rust-name
check "a front that locks another file than Core is refused" 'refused "large-document lock pairing: Core and Rust must name the same lock file (Core .large-document.lock., Rust .other.lock.)"'
cp "$work/extract-lock.saved" "$rz/crates/server-projects/src/extract.rs"
sed "s/BEGIN IMMEDIATE/BEGIN DEFERRED/" "$work/file-lock.saved" > "$w/server/large-document-file-lock.cjs"
move_try large-lock-core-statement
check "a Core that takes the lock another way is refused" 'refused "large-document lock pairing: Core and Rust must both take the lock with BEGIN IMMEDIATE"'
cp "$work/file-lock.saved" "$w/server/large-document-file-lock.cjs"
sed "s/BEGIN IMMEDIATE/BEGIN DEFERRED/" "$work/extract-lock.saved" > "$rz/crates/server-projects/src/extract.rs"
move_try large-lock-rust-statement
check "a front that takes the lock another way is refused" 'refused "large-document lock pairing: Core and Rust must both take the lock with BEGIN IMMEDIATE"'
cp "$work/extract-lock.saved" "$rz/crates/server-projects/src/extract.rs"
move_try large-lock-pair-again
check "the matching host lock pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
rm -f "$w/server/large-document-lock.cjs" "$w/server/large-document-file-lock.cjs" "$rz/crates/server-projects/src/extract.rs"
move_try large-lock-front-only
check "a host-lock front cannot pair with an in-process-lock Core" 'refused "large-document lock pairing: Core and Rust must share the host lock"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
rm -f "$w/server/rust-source-jobs.cjs"
# Public page and plugin directory owner release matrix (sbstndalton/noevia#2190): two independent pairs.
singles_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/about"
owner = "rust"
methods = ["GET", "HEAD"]
[[route]]
path = "/privacy"
owner = "$pages_owner"
$pages_limit
[[route]]
path = "/device"
owner = "rust"
$device_limit
[[route]]
path = "/api/plugins/directory"
owner = "$dir_owner"
$dir_limit
TOML
}
pages_owner=rust; pages_limit='methods = ["GET", "HEAD"]'; device_limit=""; dir_owner=rust; dir_limit=""
printf '%s\n' "  if (require('./rust-public-pages.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
singles_try pages-core-only
check "public page Core refusal requires the native capability" 'refused "public page ownership pairing"'
sed 's/"start-id"/"start-id", "rust-public-pages"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
singles_try pages-pair
check "matching public page pair assembles with the directory old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
pages_limit='methods = ["GET"]'
singles_try pages-get-only
check "a page without HEAD is refused" 'refused "public page ownership pairing"'
pages_limit=""
singles_try pages-all-methods
check "an all-method page is refused (Node keeps the pages' other methods)" 'refused "public page ownership pairing"'
pages_limit='methods = ["GET", "HEAD"]'; device_limit='methods = ["GET"]'
singles_try pages-device-get
check "a GET-only /device is refused (every method is Rust's)" 'refused "public page ownership pairing"'
device_limit=""; pages_owner=node
singles_try pages-incomplete
check "a Node-owned /privacy is refused" 'refused "public page ownership pairing"'
pages_owner=rust
printf '%s\n' "  if (require('./rust-plugin-directory.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
singles_try directory-core-only
check "plugin directory Core refusal requires the native capability" 'refused "plugin directory ownership pairing"'
sed 's/"start-id"/"start-id", "rust-public-pages", "rust-plugin-directory"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
singles_try singles-pair
check "both #2190 pairs native assemble" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
dir_limit='methods = ["GET"]'
singles_try directory-get-only
check "a GET-only plugin directory is refused (Node answered every method)" 'refused "plugin directory ownership pairing"'
dir_limit=""; dir_owner=node
singles_try directory-node-owned
check "a Node-owned plugin directory beside a native pair is refused" 'refused "plugin directory ownership pairing"'
dir_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
singles_try singles-front-only
check "#2190 fronts cannot pair with the old Core handlers" 'refused "ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try singles-old-pair
check "historic #2190 old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Round 2 (#2190): the decision settings pair, every method of both routes.
decision_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/admin/decision-settings"
owner = "rust"
$decision_limit
[[route]]
path = "/api/admin/decision-settings/test"
owner = "$decision_test_owner"
TOML
}
decision_limit=""; decision_test_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-decision-settings.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
decision_try decision-core-only
check "decision settings Core refusal requires the native capability" 'refused "decision settings ownership pairing"'
sed 's/"start-id"/"start-id", "rust-decision-settings"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
decision_try decision-pair
check "matching decision settings pair assembles with the round 1 pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
decision_limit='methods = ["GET", "PUT", "DELETE"]'
decision_try decision-some-methods
check "a method-limited decision settings route is refused (Node answered every method)" 'refused "decision settings ownership pairing"'
decision_limit=""; decision_test_owner=node
decision_try decision-test-node
check "a Node-owned connection test beside a native pair is refused" 'refused "decision settings ownership pairing"'
decision_test_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
decision_try decision-front-only
check "a rust-decision-settings front cannot pair with the old Core handlers" 'refused "decision settings ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try decision-old-pair
check "historic decision settings old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Round 3 (#2190): the storage integration pair, exactly POST of all five routes.
storage_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/integrations/storage/folder"
owner = "rust"
$storage_methods
[[route]]
path = "/api/integrations/storage/test"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/integrations/storage/nextcloud/start"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/integrations/storage/nextcloud/poll"
owner = "$storage_poll_owner"
methods = ["POST"]
[[route]]
path = "/api/integrations/storage/nextcloud/cancel"
owner = "rust"
methods = ["POST"]
TOML
}
storage_methods='methods = ["POST"]'; storage_poll_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-storage-integrations.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
storage_try storage-core-only
check "storage integration Core refusal requires the native capability" 'refused "storage integration ownership pairing"'
sed 's/"start-id"/"start-id", "rust-storage-integrations"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
storage_try storage-pair
check "matching storage integration pair assembles with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
storage_methods=''
storage_try storage-all-methods
check "an all-methods storage folder route is refused (Node keeps the other methods)" 'refused "storage integration ownership pairing"'
storage_methods='methods = ["POST", "PUT"]'
storage_try storage-extra-method
check "a storage route with a method beside POST is refused" 'refused "storage integration ownership pairing"'
storage_methods='methods = ["POST"]'; storage_poll_owner=node
storage_try storage-poll-node
check "a Node-owned Nextcloud poll beside a native pair is refused" 'refused "storage integration ownership pairing"'
storage_poll_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
storage_try storage-front-only
check "a rust-storage-integrations front cannot pair with the old Core handlers" 'refused "storage integration ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try storage-old-pair
check "historic storage integration old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# Round 3 (#2190): the vault-mirror preferences, every method Rust's.
mirror_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/chat-vault-mirror/preferences"
owner = "$mirror_owner"
$mirror_methods
TOML
}
mirror_methods=''; mirror_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-vault-mirror-preferences.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
mirror_try mirror-core-only
check "vault mirror Core refusal requires the native capability" 'refused "vault mirror preference ownership pairing"'
sed 's/"start-id"/"start-id", "rust-vault-mirror-preferences"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
mirror_try mirror-pair
check "matching vault mirror pair assembles with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
mirror_methods='methods = ["GET", "PUT"]'
mirror_try mirror-some-methods
check "a vault mirror route limited to some methods is refused (Core refuses them all)" 'refused "vault mirror preference ownership pairing"'
mirror_methods=''; mirror_owner=node
mirror_try mirror-node-route
check "a Node-owned vault mirror route beside a native pair is refused" 'refused "vault mirror preference ownership pairing"'
mirror_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
mirror_try mirror-front-only
check "a rust-vault-mirror-preferences front cannot pair with the old Core route" 'refused "vault mirror preference ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try mirror-old-pair
check "historic vault mirror old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# The chat journal tail and the mirror and brain schedules (rust-chat-mirror-v1): the front owns them, the core
# keeps the executors; both declare it exactly, neither in a comment, and the Node journal reader is gone.
cm_note="$work/cm.saved"; mkdir -p "$cm_note"
cp "$w/server/chat-change-journal.cjs" "$cm_note/journal.cjs"; cp "$rz/bins/noevia-server/src/main.rs" "$cm_note/main.rs"
cm_restore() {
  cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"; cp "$work/feature-index.saved" "$w/server/index.cjs"
  cp "$cm_note/journal.cjs" "$w/server/chat-change-journal.cjs"; cp "$cm_note/main.rs" "$rz/bins/noevia-server/src/main.rs"
  rm -rf "$w/server/rust-chat-mirror.cjs" "$rz/crates/chat-mirror-sched"
}
cm_core() { # the paired core: the executor module, the require, no Node journal reader
  printf '%s\n' "const RUST_CHAT_MIRROR_OWNED = 'rust-chat-mirror-v1';" "module.exports = { RUST_CHAT_MIRROR_OWNED };" > "$w/server/rust-chat-mirror.cjs"
  cp "$work/feature-index.saved" "$w/server/index.cjs"; printf '%s\n' "const chatMirror = require('./rust-chat-mirror.cjs');" >> "$w/server/index.cjs"
  rm -f "$w/server/chat-change-journal.cjs"
}
cm_front() { # the paired front: capability, module, scheduler marker, the start call (journal op kept)
  sed 's/"start-id"/"start-id", "rust-chat-mirror-v1"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
  printf '%s\n' 'pub mod chat_mirror;' >> "$rz/bins/noevia-server/src/lib.rs"
  mkdir -p "$rz/crates/chat-mirror-sched/src"; echo 'pub const MARKER: &str = "noevia-chat-mirror-scheduler/1";' > "$rz/crates/chat-mirror-sched/src/lib.rs"
  printf '%s\n' 'fn route() { let op = "/v1/changes/read"; }' 'fn start() { ChatMirror::start(); }' > "$rz/bins/noevia-server/src/main.rs"
}
# This guard's Rust detector, read from the assembler under test, on the fixture's lib.rs.
cm_rs_detect() { ( eval "$(sed -n '/^chat_mirror_core_version()/,/^chat_mirror_core_owner=/{ /^chat_mirror_core_owner=/d; p; }' "$here/assemble-release.sh")"; chat_mirror_rs_version "$rz/bins/noevia-server/src/lib.rs" ); }
cm_restore; cm_core; cm_front
check "the direct chat mirror detector reads the paired fixture front" '[ "$(cm_rs_detect)" = v1 ]'
move_try chat-mirror-pair
check "a paired chat mirror Core and front assemble, the move reader and journal consumer being the front's" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
cm_restore; cm_core
move_try chat-mirror-core-only
check "a chat mirror Core beside a front without the capability is refused" 'refused "chat mirror schedule ownership pairing"'
cm_restore; cm_front
move_try chat-mirror-front-only
check "a chat mirror front beside the old Core (a second schedule) is refused" 'refused "chat mirror schedule ownership pairing"'
cm_restore; cm_core; cm_front; cp "$cm_note/journal.cjs" "$w/server/chat-change-journal.cjs"
move_try chat-mirror-two-readers
check "a pair whose Core still carries the Node journal reader is refused" 'refused "still carries the Node journal reader"'
cm_restore; cm_core; cm_front
sed 's/"rust-chat-mirror-v1"/"x"/' "$rz/bins/noevia-server/src/lib.rs" > "$work/cm-lib.tmp"; printf '%s\n' '// "rust-chat-mirror-v1" is the capability' >> "$work/cm-lib.tmp"; cp "$work/cm-lib.tmp" "$rz/bins/noevia-server/src/lib.rs"
move_try chat-mirror-comment-capability
check "a capability named only in a comment is not the capability" 'refused "chat mirror schedule ownership pairing"'
cm_restore; cm_core; cm_front
sed 's/"rust-chat-mirror-v1"/"rust-chat-mirror-v1", "rust-chat-mirror-v1"/' "$rz/bins/noevia-server/src/lib.rs" > "$work/cm-lib.tmp"; cp "$work/cm-lib.tmp" "$rz/bins/noevia-server/src/lib.rs"
move_try chat-mirror-duplicate-capability
check "a duplicated capability entry is refused" 'refused "chat mirror schedule ownership pairing"'
cm_restore; cm_core; cm_front
printf '%s\n' "// const RUST_CHAT_MIRROR_OWNED = 'rust-chat-mirror-v1';" "module.exports = {};" > "$w/server/rust-chat-mirror.cjs"
move_try chat-mirror-unexported-marker
check "a Core module that does not export its marker is refused" 'refused "does not export RUST_CHAT_MIRROR_OWNED"'
cm_restore; cm_core; cm_front
printf '%s\n' 'fn route() { let op = "/v1/changes/read"; }' '// ChatMirror::start(' > "$rz/bins/noevia-server/src/main.rs"
move_try chat-mirror-never-started
check "a front that declares the capability but never starts the schedule is refused" 'refused "does not carry and start the schedule"'
cm_restore; cm_core; cm_front
echo 'pub const MARKER: &str = "something-else/1";' > "$rz/crates/chat-mirror-sched/src/lib.rs"
move_try chat-mirror-wrong-scheduler
check "a front whose scheduler crate lacks its marker is refused" 'refused "does not carry and start the schedule"'
for cm_case in element declaration module startup startup-parent module-declaration escaped raw macro exported-wrong; do
  cm_restore; cm_core; cm_front
  case "$cm_case" in
    element) sed 's/"rust-chat-mirror-v1"/#[cfg(any())] "rust-chat-mirror-v1"/' "$rz/bins/noevia-server/src/lib.rs" > "$work/cm-lib.tmp"; cp "$work/cm-lib.tmp" "$rz/bins/noevia-server/src/lib.rs";;
    declaration) sed '/pub const FEATURES/i\
#[cfg(any())]
' "$rz/bins/noevia-server/src/lib.rs" > "$work/cm-lib.tmp"; cp "$work/cm-lib.tmp" "$rz/bins/noevia-server/src/lib.rs";;
    module) cp "$rz/bins/noevia-server/src/lib.rs" "$work/cm-lib.tmp"; { echo '#[cfg(any())] mod disabled {'; cat "$work/cm-lib.tmp"; echo '}'; } > "$rz/bins/noevia-server/src/lib.rs";;
    module-declaration) sed '/pub mod chat_mirror/i\
#[cfg(any())]
' "$rz/bins/noevia-server/src/lib.rs" > "$work/cm-lib.tmp"; cp "$work/cm-lib.tmp" "$rz/bins/noevia-server/src/lib.rs";;
    startup) printf '%s\n' '#[cfg(any())] fn start() { ChatMirror::start(); }' > "$rz/bins/noevia-server/src/main.rs";;
    startup-parent) printf '%s\n' '#[cfg(any())] mod disabled { fn start() { ChatMirror::start(); } }' > "$rz/bins/noevia-server/src/main.rs";;
    escaped) sed 's/"rust-chat-mirror-v1"/"rust-chat-mirror-v1", "rust-chat-mirror-v\\x31"/' "$rz/bins/noevia-server/src/lib.rs" > "$work/cm-lib.tmp"; cp "$work/cm-lib.tmp" "$rz/bins/noevia-server/src/lib.rs";;
    raw) sed 's/"rust-chat-mirror-v1"/r#"rust-chat-mirror-v1"#/' "$rz/bins/noevia-server/src/lib.rs" > "$work/cm-lib.tmp"; cp "$work/cm-lib.tmp" "$rz/bins/noevia-server/src/lib.rs";;
    macro) sed 's/"rust-chat-mirror-v1"/concat!("rust-chat-mirror-v", "1")/' "$rz/bins/noevia-server/src/lib.rs" > "$work/cm-lib.tmp"; cp "$work/cm-lib.tmp" "$rz/bins/noevia-server/src/lib.rs";;
    exported-wrong) echo "module.exports.RUST_CHAT_MIRROR_OWNED = 'wrong';" >> "$w/server/rust-chat-mirror.cjs";;
  esac
  move_try "chat-mirror-disabled-$cm_case"
  case "$cm_case" in
    # An unprovable FEATURES declaration or element is refused first by the strict readers that run
    # before this guard (maintenance lease, reranker settings). The release must still be refused,
    # and this guard's own detector must refuse the same lib.rs when run directly.
    declaration|module|raw|macro)
      check "chat mirror rejects unprovable $cm_case" '{ refused "chat mirror" || refused "maintenance lease pairing" || refused "reranker settings ownership pairing"; } && [ "$(cm_rs_detect)" = invalid ]';;
    *) check "chat mirror rejects unprovable $cm_case" 'refused "chat mirror"';;
  esac
done
cm_restore
move_try chat-mirror-old-pair
check "historic chat mirror old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# Round 4 (#2190): the storage connection save, exactly GET and PUT of the path Rust's.
conn_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/integrations/storage"
owner = "$conn_owner"
$conn_methods
TOML
}
conn_methods='methods = ["GET", "PUT"]'; conn_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-storage-connection.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
conn_try conn-core-only
check "storage connection Core refusal requires the native capability" 'refused "storage connection ownership pairing"'
sed 's/"start-id"/"start-id", "rust-storage-connection"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
conn_try conn-pair
check "matching storage connection pair assembles with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
conn_methods='methods = ["GET"]'
conn_try conn-get-only
check "a storage connection route without PUT is refused (Core refuses the save)" 'refused "storage connection ownership pairing"'
conn_methods=''
conn_try conn-all-methods
check "a storage connection route Rust's for every method is refused (Node keeps the others)" 'refused "storage connection ownership pairing"'
conn_methods='methods = ["GET", "PUT", "DELETE"]'
conn_try conn-extra-method
check "a storage connection route with an extra method is refused" 'refused "storage connection ownership pairing"'
conn_methods='methods = ["GET", "PUT"]'; conn_owner=node
conn_try conn-node-route
check "a Node-owned storage connection route beside a native pair is refused" 'refused "storage connection ownership pairing"'
conn_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
conn_try conn-front-only
check "a rust-storage-connection front cannot pair with the old Core save" 'refused "storage connection ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try conn-old-pair
check "historic storage connection old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# Round 4 (#2190): the provider probe, exactly POST of the path Rust's.
ptest_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/providers/test"
owner = "$ptest_owner"
$ptest_methods
TOML
}
ptest_methods='methods = ["POST"]'; ptest_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-provider-test.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
ptest_try ptest-core-only
check "provider test Core refusal requires the native capability" 'refused "provider test ownership pairing"'
sed 's/"start-id"/"start-id", "rust-provider-test"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
ptest_try ptest-pair
check "matching provider test pair assembles with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
ptest_methods=''
ptest_try ptest-all-methods
check "a provider test route Rust's for every method is refused (Node keeps PUT/DELETE)" 'refused "provider test ownership pairing"'
ptest_methods='methods = ["POST", "PUT"]'
ptest_try ptest-extra-method
check "a provider test route with an extra method is refused" 'refused "provider test ownership pairing"'
ptest_methods='methods = ["POST"]'; ptest_owner=node
ptest_try ptest-node-route
check "a Node-owned provider test route beside a native pair is refused" 'refused "provider test ownership pairing"'
ptest_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
ptest_try ptest-front-only
check "a rust-provider-test front cannot pair with the old Core probe" 'refused "provider test ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try ptest-old-pair
check "historic provider test old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# Round 5 (#2190): Sign in with ChatGPT's token broker, exactly the broker's methods Rust's.
cgpt_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/providers/chatgpt/device"
owner = "$cgpt_owner"
$cgpt_post
[[route]]
path = "/api/providers/chatgpt/device/cancel"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/providers/chatgpt/device/poll"
owner = "rust"
methods = ["POST"]
$cgpt_models
TOML
}
cgpt_models_rust='[[route]]
path = "/api/providers/chatgpt/models"
owner = "rust"
methods = ["GET"]'
cgpt_post='methods = ["POST"]'; cgpt_owner=rust; cgpt_models="$cgpt_models_rust"
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-chatgpt-oauth.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
cgpt_try cgpt-core-only
check "ChatGPT sign-in Core refusal requires the native capability" 'refused "ChatGPT sign-in ownership pairing"'
sed 's/"start-id"/"start-id", "rust-chatgpt-oauth"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
cgpt_try cgpt-pair
check "matching ChatGPT sign-in pair assembles with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
cgpt_post=''
cgpt_try cgpt-all-methods
check "a ChatGPT device route Rust's for every method is refused" 'refused "ChatGPT sign-in ownership pairing"'
cgpt_post='methods = ["GET"]'
cgpt_try cgpt-wrong-method
check "a ChatGPT device route with the wrong method is refused" 'refused "ChatGPT sign-in ownership pairing"'
cgpt_post='methods = ["POST"]'; cgpt_owner=node
cgpt_try cgpt-node-route
check "a Node-owned ChatGPT device route beside a native pair is refused" 'refused "ChatGPT sign-in ownership pairing"'
cgpt_owner=rust; cgpt_models=''
cgpt_try cgpt-missing-models
check "a native ChatGPT pair without the model list route is refused" 'refused "ChatGPT sign-in ownership pairing"'
cgpt_models="$cgpt_models_rust"
cp "$work/feature-index.saved" "$w/server/index.cjs"
cgpt_try cgpt-front-only
check "a rust-chatgpt-oauth front cannot pair with the old Core sign-in" 'refused "ChatGPT sign-in ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try cgpt-old-pair
check "historic ChatGPT sign-in old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# #2202: the MCP server credentials, exactly the broker's methods Rust's, with the store's /v1/mcp/*
# ops served by the front and asked for by Core.
mcp_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/mcp-keys/servers"
owner = "rust"
methods = ["GET"]
[[route]]
path = "/api/mcp-keys/{*}"
owner = "$mcp_owner"
$mcp_keys_methods
[[route]]
path = "/api/mcp-oauth/servers"
owner = "rust"
methods = ["GET"]
[[route]]
path = "/api/mcp-oauth/{id}"
owner = "rust"
methods = ["DELETE"]
[[route]]
path = "/api/mcp-oauth/{id}/connect"
owner = "rust"
methods = ["POST"]
$mcp_callback
TOML
}
mcp_callback_rust='[[route]]
path = "/api/mcp-oauth/callback"
owner = "rust"
methods = ["GET"]'
mcp_keys_methods='methods = ["DELETE", "PUT"]'; mcp_owner=rust; mcp_callback="$mcp_callback_rust"
cp "$w/server/project-store-client.cjs" "$work/mcp-client.saved"
if [ -f "$rz/bins/noevia-server/src/project_store.rs" ]; then cp "$rz/bins/noevia-server/src/project_store.rs" "$work/mcp-store.saved"; else rm -f "$work/mcp-store.saved"; fi
mcp_files() { # store yes|no|comment, client yes|no|comment ("comment": only a comment mentions it, which serves/asks nothing)
  cp "$work/mcp-client.saved" "$w/server/project-store-client.cjs"
  if [ -f "$work/mcp-store.saved" ]; then cp "$work/mcp-store.saved" "$rz/bins/noevia-server/src/project_store.rs"; else : > "$rz/bins/noevia-server/src/project_store.rs"; fi
  case "$1" in
    yes) printf '%s\n' 'router.route(&format!("/v1/mcp/{op}"), post(mcp_op));' >> "$rz/bins/noevia-server/src/project_store.rs";;
    comment) printf '%s\n' '// router.route(&format!("/v1/mcp/{op}"), post(mcp_op));' '/// the internal store: POST /v1/mcp/session' >> "$rz/bins/noevia-server/src/project_store.rs";;
  esac
  case "$2" in
    yes) printf '%s\n' 'async mcpSession(user, server) { return call("mcp/session"); }' 'async mcpKey(user, server) { return call("mcp/key"); }' 'async mcpReseal() { return call("mcp/reseal"); }' >> "$w/server/project-store-client.cjs";;
    comment) printf '%s\n' '// mcpSession(user, server) mcpKey(user, server) mcpReseal()' '/* async mcpSession(user, server) {}' '   async mcpKey(user, server) {}' '   async mcpReseal() {} */' >> "$w/server/project-store-client.cjs";;
  esac
  return 0
}
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-mcp-credentials.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
mcp_files yes yes
mcp_try mcp-core-only
check "MCP credential Core refusal requires the native capability" 'refused "MCP credential ownership pairing: Core and Rust must move together"'
sed 's/"start-id"/"start-id", "rust-mcp-credentials"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
mcp_try mcp-pair
check "matching MCP credential pair assembles with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
mcp_keys_methods=''
mcp_try mcp-all-methods
check "an MCP key route Rust's for every method is refused (Node keeps the others)" 'refused "MCP credential ownership pairing: exactly"'
mcp_keys_methods='methods = ["PUT"]'
mcp_try mcp-missing-method
check "an MCP key route without DELETE is refused" 'refused "MCP credential ownership pairing: exactly"'
mcp_keys_methods='methods = ["DELETE", "PUT", "GET"]'
mcp_try mcp-extra-method
check "an MCP key route with an extra method is refused" 'refused "MCP credential ownership pairing: exactly"'
mcp_keys_methods='methods = ["DELETE", "PUT"]'; mcp_owner=node
mcp_try mcp-node-route
check "a Node-owned MCP key route beside a native pair is refused" 'refused "MCP credential ownership pairing: exactly"'
mcp_owner=rust; mcp_callback=''
mcp_try mcp-missing-callback
check "a native MCP pair without the sign-in callback route is refused" 'refused "MCP credential ownership pairing: incomplete route ownership"'
mcp_callback="$mcp_callback_rust"
mcp_files no yes
mcp_try mcp-no-store-route
check "a front whose store serves no /v1/mcp/* is refused" 'refused "MCP credential ownership pairing: the front does not serve"'
mcp_files comment yes
mcp_try mcp-store-comment-only
check "a /v1/mcp/ that only a comment names is not a store that serves it" 'refused "MCP credential ownership pairing: the front does not serve"'
mcp_files yes no
mcp_try mcp-no-client-ops
check "a Core whose store client never asks for a session, a key or the re-seal is refused" 'refused "MCP credential ownership pairing: Core.s store client"'
mcp_files yes comment
mcp_try mcp-client-comment-only
check "store-client ops that only comments name (line and block) are not calls" 'refused "MCP credential ownership pairing: Core.s store client"'
cp "$work/mcp-client.saved" "$w/server/project-store-client.cjs"
printf '%s\n' 'async mcpSession(u, s) {}' 'async mcpKey(u, s) {}' '// async mcpReseal() {}  (not yet)' >> "$w/server/project-store-client.cjs"
mcp_try mcp-client-one-op-in-comment
check "one op present only in a comment, the others in code, is still refused" 'refused "MCP credential ownership pairing: Core.s store client does not call mcpReseal"'
mcp_files yes yes
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  // if (require('./rust-mcp-credentials.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
mcp_try mcp-marker-comment-only
check "a Core marker that only a comment names is the old Core, not a pair" 'refused "MCP credential ownership pairing: Core and Rust must move together"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
mcp_try mcp-front-only
check "a rust-mcp-credentials front cannot pair with the old Core (which would write the tables)" 'refused "MCP credential ownership pairing: Core and Rust must move together"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
mcp_files no no
cp "$work/mcp-client.saved" "$w/server/project-store-client.cjs"
move_try mcp-old-pair
check "historic MCP credential old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# #2202 round 2: the admin MCP directory, the permitted-tools view and the connectors list: three Core refusals
# paired with three front capabilities, with exactly the methods the front answers, the discovery snapshot Core
# publishes and the front reads, and a Core whose directory module holds no write of the table.
cp "$w/server/project-store-client.cjs" "$work/mcp2-client.saved"
mcp2_files() { # discovery yes|no|comment (Core publishes it), writes none|code|comment (directory-mcp.cjs), front lib mod yes|no
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  case "$1" in
    yes) printf '%s\n' "const publisher = require('./mcp-discovery-snapshot.cjs').createMcpDiscoveryPublisher({ dataDir });" >> "$w/server/index.cjs";;
    comment) printf '%s\n' "// const publisher = require('./mcp-discovery-snapshot.cjs').createMcpDiscoveryPublisher({ dataDir });" >> "$w/server/index.cjs";;
  esac
  echo "// the catalogue" > "$w/server/mcp-discovery-snapshot.cjs"
  case "$2" in
    none) printf '%s\n' "const rows = db.prepare('SELECT id FROM directory_mcp_servers').all();" > "$w/server/directory-mcp.cjs";;
    code) printf '%s\n' "db.prepare('INSERT INTO directory_mcp_servers(id) VALUES(?)').run(id);" > "$w/server/directory-mcp.cjs";;
    comment) printf '%s\n' "// the front does INSERT INTO directory_mcp_servers and DELETE FROM directory_mcp_servers" "const rows = db.prepare('SELECT id FROM directory_mcp_servers').all();" > "$w/server/directory-mcp.cjs";;
  esac
  printf '%s\n' "const TABLES = ['mcp_oauth_tokens', 'directory_mcp_servers'];" > "$w/server/rust-mcp-credentials.cjs"
  printf '%s\n' '"SELECT id FROM directory_mcp_servers WHERE headers_enc IS NOT NULL"' > "$rz/bins/noevia-server/src/mcp_broker.rs"
  case "$3" in
    yes) sed 's/"start-id"/"start-id", "rust-mcp-directory", "rust-toolboxes-permitted", "rust-connectors"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; printf '%s\n' 'pub mod mcp_discovery;' >> "$rz/bins/noevia-server/src/lib.rs";;
    no) sed 's/"start-id"/"start-id", "rust-mcp-directory", "rust-toolboxes-permitted", "rust-connectors"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs";;
  esac
  return 0
}
mcp2_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
$mcp2_dir
$mcp2_perm
$mcp2_cnx
TOML
}
mcp2_route() { printf '[[route]]\npath = "%s"\nowner = "%s"\n%s\n' "$1" "$2" "$3"; }
mcp2_dir_rust="$(for p in /api/admin/mcp-directory /api/admin/mcp-directory/custom /api/admin/mcp-directory/custom/preview '/api/admin/mcp-directory/{*}' '/api/admin/mcp-directory/{*}/keys' '/api/admin/mcp-directory/{id}/oauth-client'; do mcp2_route "$p" rust ''; done)"
mcp2_perm_rust="$(mcp2_route /api/toolboxes/permitted rust '')"
mcp2_cnx_rust="$(mcp2_route /api/connectors rust 'methods = ["GET"]'; mcp2_route /api/connectors/nextcloud/policy rust 'methods = ["PUT"]')"
mcp2_dir="$mcp2_dir_rust"; mcp2_perm="$mcp2_perm_rust"; mcp2_cnx="$mcp2_cnx_rust"
# The Core half alone, the front half alone.
mcp2_files yes none no
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
printf '%s\n' "  if (require('./rust-mcp-directory.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
mcp2_try mcp2-dir-core-only
check "an MCP directory Core refusal requires the native capability" 'refused "MCP directory ownership pairing: Core and Rust must move together"'
mcp2_files yes none yes
cp "$work/feature-index.saved" "$w/server/index.cjs"
mcp2_try mcp2-front-only
check "rust-mcp-directory, rust-toolboxes-permitted and rust-connectors fronts cannot pair with the old Core" 'refused "ownership pairing: Core and Rust must move together"'
# The matching pairs.
mcp2_files yes none yes
printf '%s\n' "  if (require('./rust-mcp-directory.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-toolboxes-permitted.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-connectors.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
mcp2_try mcp2-pair
check "the matching MCP directory, permitted tools and connectors pairs assemble with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Row T: the same three pairs over the front's own discovery and Core's published toolbox facts (no discovery snapshot).
mcp2_files no none no
sed 's/"start-id"/"start-id", "rust-mcp-directory", "rust-toolboxes-permitted", "rust-connectors", "rust-mcp-discovery"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; printf '%s\n' 'pub mod mcp_discovery;' >> "$rz/bins/noevia-server/src/lib.rs"
rm -f "$w/server/mcp-discovery-snapshot.cjs"; touch "$w/server/toolbox-chat-facts.cjs" "$w/server/mcp-native-discovery.cjs"
printf '%s\n' "  if (require('./rust-mcp-directory.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-toolboxes-permitted.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-connectors.cjs').refuseOwned(req, res, {})) return;" "const discovery = require('./mcp-native-discovery.cjs').createNativeDiscovery({ broker: PROJECT_STORE });" "const chatFacts = require('./toolbox-chat-facts.cjs').createChatFactsPublisher({ dataDir });" >> "$w/server/index.cjs"
mcp2_try mcp2-native-pair
check "the matching MCP directory, permitted tools and connectors pairs assemble over the front's own discovery" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
cp "$rz/bins/noevia-server/src/lib.rs" "$work/md-lib"
for prefix in $'#[cfg(any())]\n' $'#[cfg(any())]\nmod disabled {\n'; do
  python3 - "$work/md-lib" "$rz/bins/noevia-server/src/lib.rs" "$prefix" <<'MDPY'
import sys
s=open(sys.argv[1]).read(); s=s.replace('pub const FEATURES',sys.argv[3]+'pub const FEATURES')
if 'mod disabled' in sys.argv[3]: s+='\n}'
open(sys.argv[2],'w').write(s)
MDPY
  mcp2_try md-disabled-scope
  check "native discovery refuses disabled FEATURES scope" 'refused "MCP discovery ownership pairing"'
done
for element in '#[cfg(any())] "rust-mcp-discovery"' '"rust-mcp-discovery", "rust-mcp-\x64iscovery"' 'b"rust-mcp-discovery"' 'r#"rust-mcp-discovery"#' 'concat!("rust-mcp-discovery")'; do
  python3 - "$work/md-lib" "$rz/bins/noevia-server/src/lib.rs" "$element" <<'MDPY'
import sys
open(sys.argv[2],'w').write(open(sys.argv[1]).read().replace('"rust-mcp-discovery"',sys.argv[3]))
MDPY
  mcp2_try md-invalid-element
  check "native discovery refuses gated duplicate or nonliteral marker" 'refused "MCP discovery ownership pairing"'
done
sed 's/, "rust-mcp-discovery"//' "$work/md-lib" > "$rz/bins/noevia-server/src/lib.rs"
mcp2_try md-core-half
check "native discovery refuses Core-only half" 'refused "MCP discovery ownership pairing"'
cp "$work/md-lib" "$rz/bins/noevia-server/src/lib.rs"
cp "$w/server/index.cjs" "$work/md-index"
grep -v "mcp-native-discovery.cjs" "$work/md-index" > "$w/server/index.cjs"
mcp2_try md-rust-half
check "native discovery refuses Rust-only half" 'refused "MCP discovery ownership pairing"'
cp "$work/md-index" "$w/server/index.cjs"
grep -v "createChatFactsPublisher" "$w/server/index.cjs" > "$w/server/index.cjs.tmp" && mv "$w/server/index.cjs.tmp" "$w/server/index.cjs"; mcp2_try mcp2-native-no-facts
check "a native discovery pair whose Core publishes no toolbox facts is refused" 'refused "must publish the chat process"'
rm -f "$w/server/toolbox-chat-facts.cjs" "$w/server/mcp-native-discovery.cjs"
mcp2_files yes none yes
printf '%s\n' "  if (require('./rust-mcp-directory.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-toolboxes-permitted.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-connectors.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
# Routes: exactly the front's.
mcp2_dir="$(mcp2_route /api/admin/mcp-directory rust 'methods = ["GET"]'; for p in /api/admin/mcp-directory/custom /api/admin/mcp-directory/custom/preview '/api/admin/mcp-directory/{*}' '/api/admin/mcp-directory/{*}/keys' '/api/admin/mcp-directory/{id}/oauth-client'; do mcp2_route "$p" rust ''; done)"
mcp2_try mcp2-dir-get-only
check "a directory route that is Rust's for GET only is refused (core's 405 for the rest is the front's)" 'refused "MCP directory ownership pairing: every method"'
mcp2_dir="$(for p in /api/admin/mcp-directory /api/admin/mcp-directory/custom /api/admin/mcp-directory/custom/preview '/api/admin/mcp-directory/{*}' '/api/admin/mcp-directory/{*}/keys'; do mcp2_route "$p" rust ''; done; mcp2_route '/api/admin/mcp-directory/{id}/oauth-client' node '')"
mcp2_try mcp2-dir-node-route
check "a Node-owned directory route beside a native pair is refused" 'refused "MCP directory ownership pairing: every method"'
mcp2_dir="$(for p in /api/admin/mcp-directory /api/admin/mcp-directory/custom /api/admin/mcp-directory/custom/preview '/api/admin/mcp-directory/{*}' '/api/admin/mcp-directory/{*}/keys'; do mcp2_route "$p" rust ''; done)"
mcp2_try mcp2-dir-missing-route
check "a native directory pair without the app route is refused" 'refused "MCP directory ownership pairing: incomplete route ownership"'
mcp2_dir="$mcp2_dir_rust"
mcp2_perm="$(mcp2_route /api/toolboxes/permitted rust 'methods = ["GET"]')"
mcp2_try mcp2-perm-get-only
check "a permitted-tools route that is Rust's for GET only is refused" 'refused "permitted tools ownership pairing: every method"'
mcp2_perm="$mcp2_perm_rust"
mcp2_cnx="$(mcp2_route /api/connectors rust ''; mcp2_route /api/connectors/nextcloud/policy rust 'methods = ["PUT"]')"
mcp2_try mcp2-cnx-all-methods
check "a connectors list that is Rust's for every method is refused (Node keeps the others)" 'refused "connectors ownership pairing: exactly"'
mcp2_cnx="$(mcp2_route /api/connectors rust 'methods = ["GET"]'; mcp2_route /api/connectors/nextcloud/policy rust 'methods = ["PUT", "POST"]')"
mcp2_try mcp2-cnx-extra-method
check "a Nextcloud policy route with an extra method is refused" 'refused "connectors ownership pairing: exactly"'
mcp2_cnx="$(mcp2_route /api/connectors rust 'methods = ["GET"]')"
mcp2_try mcp2-cnx-missing
check "a connectors pair without the Nextcloud policy route is refused" 'refused "connectors ownership pairing: incomplete route ownership"'
mcp2_cnx="$mcp2_cnx_rust"
# The snapshot Node publishes and the front reads.
mcp2_files no none yes
printf '%s\n' "  if (require('./rust-mcp-directory.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-toolboxes-permitted.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-connectors.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
mcp2_try mcp2-no-publisher
check "a Core that publishes no discovery snapshot cannot pair with the front that reads it" 'refused "ownership pairing: Core does not publish the discovery snapshot"'
mcp2_files comment none yes
printf '%s\n' "  if (require('./rust-mcp-directory.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-toolboxes-permitted.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-connectors.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
mcp2_try mcp2-publisher-comment
check "a publisher that only a comment names publishes nothing" 'refused "ownership pairing: Core does not publish the discovery snapshot"'
mcp2_files yes none no
printf '%s\n' "  if (require('./rust-mcp-directory.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-toolboxes-permitted.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-connectors.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
mcp2_try mcp2-no-reader
check "a front that does not read the discovery snapshot cannot pair with Core's publisher-less views" 'refused "ownership pairing: Core does not publish the discovery snapshot"'
# One writer of the table.
mcp2_files yes code yes
printf '%s\n' "  if (require('./rust-mcp-directory.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-toolboxes-permitted.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-connectors.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
mcp2_try mcp2-second-writer
check "a Core whose directory module still writes directory_mcp_servers beside the front is refused" 'refused "MCP directory ownership pairing: Core still writes directory_mcp_servers"'
mcp2_files yes comment yes
printf '%s\n' "  if (require('./rust-mcp-directory.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-toolboxes-permitted.cjs').refuseOwned(req, res, {})) return;" "  if (require('./rust-connectors.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
mcp2_try mcp2-writer-comment
check "a write of the table that only a comment names is not a writer" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Marker in a comment only: the old Core.
mcp2_files yes none yes
printf '%s\n' "  // if (require('./rust-mcp-directory.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
mcp2_try mcp2-marker-comment
check "a directory marker that only a comment names is the old Core, not a pair" 'refused "MCP directory ownership pairing: Core and Rust must move together"'
# Back to old/old.
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
rm -f "$w/server/mcp-discovery-snapshot.cjs" "$w/server/directory-mcp.cjs" "$w/server/rust-mcp-credentials.cjs" "$rz/bins/noevia-server/src/mcp_broker.rs"
cp "$work/mcp2-client.saved" "$w/server/project-store-client.cjs"
move_try mcp2-old-pair
check "historic MCP directory, permitted tools and connectors old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# Round 5 (#2190): the provider model lists, the route Rust's for every method.
pmod_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/providers/{providerId}/models{*?}"
owner = "$pmod_owner"
$pmod_methods
TOML
}
pmod_methods=''; pmod_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-provider-models.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
pmod_try pmod-core-only
check "provider model list Core refusal requires the native capability" 'refused "provider model list ownership pairing"'
sed 's/"start-id"/"start-id", "rust-provider-models"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
pmod_try pmod-pair
check "matching provider model list pair assembles with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
pmod_methods='methods = ["GET"]'
pmod_try pmod-get-only
check "a provider model list route Rust's for GET only is refused (Node would keep the 405s)" 'refused "provider model list ownership pairing"'
pmod_methods=''; pmod_owner=node
pmod_try pmod-node-route
check "a Node-owned provider model list route beside a native pair is refused" 'refused "provider model list ownership pairing"'
pmod_owner=rust
cp "$work/feature-index.saved" "$w/server/index.cjs"
pmod_try pmod-front-only
check "a rust-provider-models front cannot pair with the old Core list" 'refused "provider model list ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try pmod-old-pair
check "historic provider model list old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Round 6 (#2190): the provider registry. The routes: the list (GET, POST), one row (PUT, DELETE), the
# ChatGPT disconnect (GET stays the status read, DELETE joins it) and the probe's id reading (POST
# plus PUT and DELETE); with the pair the probe's route needs exactly those three.
prov_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/providers"
owner = "$prov_owner"
$prov_list
[[route]]
path = "/api/providers/{id}"
owner = "rust"
methods = ["PUT", "DELETE"]
[[route]]
path = "/api/providers/chatgpt"
owner = "rust"
methods = ["GET", "DELETE"]
$prov_test
TOML
}
prov_test_rust='[[route]]
path = "/api/providers/test"
owner = "rust"
methods = ["POST", "PUT", "DELETE"]'
prov_list='methods = ["GET", "POST"]'; prov_owner=rust; prov_test="$prov_test_rust"
# The key re-seal (round 6 review) moves with the registry: Core's store client asks for it, the front's
# store serves it. The fixture files are put back at the end of the block.
cp "$w/server/project-store-client.cjs" "$work/reseal-client.saved"
if [ -f "$rz/bins/noevia-server/src/project_store.rs" ]; then cp "$rz/bins/noevia-server/src/project_store.rs" "$work/reseal-store.saved"; else rm -f "$work/reseal-store.saved"; fi
reseal_files() {
  # The fixture's own client and store files, with the re-seal's call and route appended (yes) or not (no).
  cp "$work/reseal-client.saved" "$w/server/project-store-client.cjs"
  if [ -f "$work/reseal-store.saved" ]; then cp "$work/reseal-store.saved" "$rz/bins/noevia-server/src/project_store.rs"; else : > "$rz/bins/noevia-server/src/project_store.rs"; fi
  if [ "$1" = yes ]; then
    printf '%s\n' '// providersReseal(scope) is called by the rotation' >> "$w/server/project-store-client.cjs"
    printf '%s\n' '.route("/v1/providers/reseal", post(providers_reseal))' >> "$rz/bins/noevia-server/src/project_store.rs"
  fi
}
reseal_index() { # registry yes|no, reseal yes|no
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  [ "$1" = yes ] && printf '%s\n' "  if (require('./rust-providers.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  [ "$2" = yes ] && printf '%s\n' "  const providersReseal = require('./rust-providers-reseal.cjs');" >> "$w/server/index.cjs"
  return 0
}
reseal_lib() { # registry yes|no, reseal yes|no
  features='"start-id"'
  [ "$1" = yes ] && features="$features, \"rust-providers\""
  [ "$2" = yes ] && features="$features, \"rust-providers-reseal\""
  sed "s/\"start-id\"/$features/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
}
reseal_files yes
reseal_index yes no
prov_try prov-core-only
check "provider registry Core refusal requires the native capability" 'refused "provider registry ownership pairing"'
reseal_index yes yes; reseal_lib yes yes
prov_try prov-pair
check "matching provider registry and key re-seal pair assembles with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
reseal_index yes no; reseal_lib yes no
prov_try prov-pair-no-reseal
check "a native registry pair without the key re-seal on either side is refused (the rotation would be a second writer)" 'refused "provider key reseal ownership pairing"'
reseal_index yes yes; reseal_lib yes no
prov_try prov-reseal-core-only
check "a Core that rotates through the front's store cannot pair with a front without the op" 'refused "provider key reseal ownership pairing"'
reseal_index yes no; reseal_lib yes yes
prov_try prov-reseal-front-only
check "a front with the key re-seal cannot pair with a Core that still rewrites the provider files" 'refused "provider key reseal ownership pairing"'
reseal_index no yes; reseal_lib no yes
prov_try prov-reseal-no-registry
check "the key re-seal without the provider registry is refused" 'refused "provider key reseal ownership pairing"'
reseal_index yes yes; reseal_lib yes yes
reseal_files no
prov_try prov-reseal-no-ops
check "a native pair whose store serves no /v1/providers/reseal and whose client never asks is refused" 'refused "provider key reseal ownership pairing"'
reseal_files no; printf '%s\n' '// providersReseal(scope) is called by the rotation' >> "$w/server/project-store-client.cjs"
prov_try prov-reseal-no-route
check "a front whose store has no /v1/providers/reseal route is refused" 'refused "provider key reseal ownership pairing: the front does not serve"'
reseal_files yes
cp "$work/reseal-client.saved" "$w/server/project-store-client.cjs"
prov_try prov-reseal-no-client
check "a Core whose store client never calls the re-seal is refused" 'refused "provider key reseal ownership pairing: Core.s store client"'
reseal_files yes
reseal_index yes yes; reseal_lib yes yes
prov_list='methods = ["GET"]'
prov_try prov-get-only
check "a provider list route without POST is refused (Core refuses the connect)" 'refused "provider registry ownership pairing"'
prov_list=''
prov_try prov-all-methods
check "a provider list route Rust's for every method is refused (Node keeps the others)" 'refused "provider registry ownership pairing"'
prov_list='methods = ["GET", "POST", "PUT"]'
prov_try prov-extra-method
check "a provider list route with an extra method is refused" 'refused "provider registry ownership pairing"'
prov_list='methods = ["GET", "POST"]'; prov_owner=node
prov_try prov-node-route
check "a Node-owned provider list route beside a native pair is refused" 'refused "provider registry ownership pairing"'
prov_owner=rust; prov_test='[[route]]
path = "/api/providers/test"
owner = "rust"
methods = ["POST"]'
prov_try prov-probe-post-only
check "a native registry pair whose probe route lacks PUT and DELETE is refused" 'refused "provider registry ownership pairing\|provider test ownership pairing"'
prov_test="$prov_test_rust"
cp "$work/feature-index.saved" "$w/server/index.cjs"
prov_try prov-front-only
check "a rust-providers front cannot pair with the old Core registry" 'refused "provider registry ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try prov-old-pair
check "historic provider registry old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
cp "$work/reseal-client.saved" "$w/server/project-store-client.cjs"
if [ -f "$work/reseal-store.saved" ]; then cp "$work/reseal-store.saved" "$rz/bins/noevia-server/src/project_store.rs"; else rm -f "$rz/bins/noevia-server/src/project_store.rs"; fi
# The close-out GETs (#2190 health and auto-roles, #2191 workspace): each its own pair of Core refusal and
# front capability, and exactly the GET of the path Rust's. Checked one at a time with the others old/old.
close_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "$close_path"
owner = "$close_owner"
$close_methods
TOML
}
# The chat search and download refusers, as the real ones declare them (checked only once index.cjs requires them).
printf "%s\n" "const OWNED_ROUTES = Object.freeze(new Set(['GET /api/chats/search']));" > "$w/server/rust-chat-search.cjs"
printf "%s\n" "const OWNED_ROUTES = Object.freeze(new Set(['GET /api/chats/{chatId}/export']));" > "$w/server/rust-chat-export.cjs"
for close_entry in "rust-health.cjs|rust-health|/api/health|health check" "rust-auto-roles.cjs|rust-auto-roles|/api/auto-roles|auto-roles read" "rust-workspace.cjs|rust-workspace|/api/workspace|workspace list" "rust-chat-search.cjs|rust-chat-search|/api/chats/search|chat search" "rust-chat-export.cjs|rust-chat-export|/api/chats/{chatId}/export|chat download"; do
  IFS='|' read -r close_marker close_cap close_path close_label <<<"$close_entry"
  close_methods='methods = ["GET"]'; close_owner=rust
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  printf '%s\n' "  if (require('./$close_marker').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  close_try "close-$close_cap-core-only"
  check "$close_label: Core refusal requires the native capability" 'refused "$close_label ownership pairing"'
  sed "s/\"start-id\"/\"start-id\", \"$close_cap\"/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
  close_try "close-$close_cap-pair"
  check "$close_label: matching pair assembles with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
  close_methods='methods = ["GET", "PUT"]'
  close_try "close-$close_cap-extra-method"
  check "$close_label: a route with a method besides GET is refused" 'refused "$close_label ownership pairing"'
  close_methods='methods = ["PUT"]'
  close_try "close-$close_cap-put-only"
  check "$close_label: a PUT-only route is refused" 'refused "$close_label ownership pairing"'
  close_methods=''
  close_try "close-$close_cap-all-methods"
  check "$close_label: a route Rust's for every method is refused (Node keeps the others)" 'refused "$close_label ownership pairing"'
  close_methods='methods = ["GET"]'; close_owner=node
  close_try "close-$close_cap-node-route"
  check "$close_label: a Node-owned route beside a native pair is refused" 'refused "$close_label ownership pairing"'
  close_owner=rust
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  close_try "close-$close_cap-front-only"
  check "$close_label: a front with the capability cannot pair with the old Core" 'refused "$close_label ownership pairing"'
  cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
  move_try "close-$close_cap-old-pair"
  check "$close_label: the historic old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
done
# F1 writer pairing, retaining the read pair and its exact GET|PUT contract.
roles_core_good() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  printf '%s\n' "require('./rust-auto-roles.cjs');" "require('./rust-auto-roles-write.cjs');" "PROJECT_STORE.autoRolesReady();" "autoRolesWriteBridge(req, res);" >> "$w/server/index.cjs"
  printf '%s\n' "module.exports = { RUST_AUTO_ROLES_WRITE_OWNED: 'rust-auto-roles-write' };" > "$w/server/rust-auto-roles-write.cjs"
}
roles_rs_good() { sed 's/"start-id"/"start-id", "rust-auto-roles", "rust-auto-roles-write"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
roles_core_good
close_path=/api/auto-roles; close_owner=rust; close_methods='methods = ["GET", "PUT"]'
close_try roles-write-core-only
check "auto-roles write: Core refuses an older front" 'refused "auto-roles write ownership pairing"'
roles_rs_good
close_try roles-write-paired
check "auto-roles write: coherent GET and PUT pair assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
close_methods='methods = ["GET"]'
close_try roles-write-missing-put
check "auto-roles write: a capability without PUT is refused" 'refused "auto-roles read ownership pairing"'
cp "$work/feature-index.saved" "$w/server/index.cjs"
rm -f "$w/server/rust-auto-roles-write.cjs"
close_try roles-write-front-only
check "auto-roles write: a native front refuses the old writer" 'refused "auto-roles write ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
close_try roles-write-old-old
check "auto-roles write: historic old/old still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
close_methods='methods = ["GET", "PUT"]'
for malformed in absent unknown duplicate comment template invalid; do
  for front in old new; do
    roles_core_good
    case "$malformed" in
      absent) printf "%s\n" "module.exports = {};" > "$w/server/rust-auto-roles-write.cjs" ;;
      unknown) printf "%s\n" "module.exports = { RUST_AUTO_ROLES_WRITE_OWNED: 'rust-auto-roles-write-v2' };" > "$w/server/rust-auto-roles-write.cjs" ;;
      duplicate) printf "%s\n" "const duplicate = 'rust-auto-roles-write';" >> "$w/server/rust-auto-roles-write.cjs" ;;
      comment) printf "%s\n" "/* module.exports = { RUST_AUTO_ROLES_WRITE_OWNED: 'rust-auto-roles-write' }; */" > "$w/server/rust-auto-roles-write.cjs" ;;
      template) printf '%s\n' 'const text = `not an export; "rust-auto-roles-write"`;' > "$w/server/rust-auto-roles-write.cjs" ;;
      invalid) printf "%s\n" "module.exports = {" > "$w/server/rust-auto-roles-write.cjs" ;;
    esac
    if [ "$front" = new ]; then roles_rs_good; else cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"; fi
    close_try "roles-core-$malformed-$front"
    check "auto-roles write: $malformed Core marker refuses with $front front" 'refused "auto-roles write ownership pairing"'
  done
done
for malformed in unknown duplicate outside comment raw bytes raw-bytes concat attribute escaped-duplicate escaped; do
  for core in old new; do
    roles_core_good; roles_rs_good
    if [ "$core" = old ]; then rm -f "$w/server/rust-auto-roles-write.cjs"; cp "$work/feature-index.saved" "$w/server/index.cjs"; fi
    case "$malformed" in
      unknown) sed 's/"rust-auto-roles-write"/"rust-auto-roles-write-v2"/' "$rz/bins/noevia-server/src/lib.rs" > "$work/roles-lib" ;;
      duplicate) sed 's/"rust-auto-roles-write"/"rust-auto-roles-write", "rust-auto-roles-write"/' "$rz/bins/noevia-server/src/lib.rs" > "$work/roles-lib" ;;
      outside) cat "$rz/bins/noevia-server/src/lib.rs" > "$work/roles-lib"; printf '%s\n' 'const OTHER: &str = "rust-auto-roles-write";' >> "$work/roles-lib" ;;
      comment) cat "$rz/bins/noevia-server/src/lib.rs" > "$work/roles-lib"; printf '%s\n' '/* "rust-auto-roles-write" */' >> "$work/roles-lib" ;;
      raw) sed 's/"rust-auto-roles-write"/r#"rust-auto-roles-write"#/' "$rz/bins/noevia-server/src/lib.rs" > "$work/roles-lib" ;;
      bytes) sed 's/"rust-auto-roles-write"/b"rust-auto-roles-write"/' "$rz/bins/noevia-server/src/lib.rs" > "$work/roles-lib" ;;
      raw-bytes) sed 's/"rust-auto-roles-write"/br#"rust-auto-roles-write"#/' "$rz/bins/noevia-server/src/lib.rs" > "$work/roles-lib" ;;
      concat) sed 's/"rust-auto-roles-write"/concat!("rust-auto-roles-write", "-v2")/' "$rz/bins/noevia-server/src/lib.rs" > "$work/roles-lib" ;;
      attribute) sed 's/"rust-auto-roles-write"/#[cfg(feature = "rust-auto-roles-write")] "unrelated"/' "$rz/bins/noevia-server/src/lib.rs" > "$work/roles-lib" ;;
      escaped-duplicate) sed 's/"rust-auto-roles-write"/"rust-auto-roles-write", "\\x72ust-auto-roles-write"/' "$rz/bins/noevia-server/src/lib.rs" > "$work/roles-lib" ;;
      escaped) sed 's/"rust-auto-roles-write"/"\\x72ust-auto-roles-write"/' "$rz/bins/noevia-server/src/lib.rs" > "$work/roles-lib" ;;
    esac
    cp "$work/roles-lib" "$rz/bins/noevia-server/src/lib.rs"
    close_try "roles-rust-$malformed-$core"
    if [ "$core" = new ] && [[ "$malformed" =~ ^(outside|comment|escaped)$ ]]; then
      check "auto-roles write: tokenizer accepts $malformed with the matching Core" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
    else
      check "auto-roles write: $malformed Rust marker refuses with $core Core" 'refused "auto-roles write ownership pairing"'
    fi
  done
done
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
rm -f "$w/server/rust-auto-roles-write.cjs"
# The chat pairs' Core side: exactly the GET refused, in code, and the old handler gone from routes/chat-lists.cjs.
[ ! -f "$w/server/routes/chat-lists.cjs" ] || cp "$w/server/routes/chat-lists.cjs" "$work/chat-lists.saved"
mkdir -p "$w/server/routes"
for cl_entry in "rust-chat-search.cjs|rust-chat-search|/api/chats/search|chat search|GET /api/chats/search|if (p === '/api/chats/search' && req.method === 'GET') {" "rust-chat-export.cjs|rust-chat-export|/api/chats/{chatId}/export|chat download|GET /api/chats/{chatId}/export|const text = chatMarkdown(chat, store.readHistory(spaceId));"; do
  IFS='|' read -r close_marker close_cap close_path close_label cl_owned cl_handler <<<"$cl_entry"
  close_methods='methods = ["GET"]'; close_owner=rust
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  printf '%s\n' "  if (require('./$close_marker').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
  sed "s/\"start-id\"/\"start-id\", \"$close_cap\"/" "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
  printf '%s\n' "module.exports = {};" > "$w/server/routes/chat-lists.cjs"
  close_try "cl-$close_cap-pair"
  check "$close_label: the pair assembles once Node's handler is gone" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
  printf '%s\n' "    $cl_handler" >> "$w/server/routes/chat-lists.cjs"
  close_try "cl-$close_cap-old-handler"
  check "$close_label: a paired Core that still carries the handler is refused" 'refused "Core still carries the public"'
  printf '%s\n' "module.exports = {};" "// $cl_handler" > "$w/server/routes/chat-lists.cjs"
  close_try "cl-$close_cap-commented-handler"
  check "$close_label: a commented-out handler is not the handler" '[ $rc -eq 0 ]'
  printf "%s\n" "const OWNED_ROUTES = Object.freeze(new Set(['ALL ${close_path}']));" > "$w/server/$close_marker"
  close_try "cl-$close_cap-all-refuser"
  check "$close_label: a refuser of every method is refused" 'refused "Core must refuse exactly this GET"'
  printf '%s\n' "/*" "const OWNED_ROUTES = Object.freeze(new Set(['${cl_owned}']));" "*/" > "$w/server/$close_marker"
  close_try "cl-$close_cap-comment-marker"
  check "$close_label: the refusal must be executable code" 'refused "Core must refuse exactly this GET"'
  printf "%s\n" "const OWNED_ROUTES = Object.freeze(new Set(['${cl_owned}']));" > "$w/server/$close_marker"
done
cp "$work/feature-index.saved" "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
if [ -f "$work/chat-lists.saved" ]; then cp "$work/chat-lists.saved" "$w/server/routes/chat-lists.cjs"; else rm -f "$w/server/routes/chat-lists.cjs"; fi
rm -f "$w/server/rust-chat-search.cjs" "$w/server/rust-chat-export.cjs"
# Round 7 (#2190): Google Drive's token authority, exactly the connector writes' methods Rust's.
gdrv_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/connectors/gdrive/connect"
owner = "$gdrv_owner"
$gdrv_post
[[route]]
path = "/api/connectors/gdrive/disconnect"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/connectors/gdrive/policy"
owner = "rust"
methods = ["PUT"]
$gdrv_copy
TOML
}
gdrv_copy_rust='[[route]]
path = "/api/connectors/gdrive/backup-copy"
owner = "rust"
methods = ["PUT"]'
gdrv_post='methods = ["POST"]'; gdrv_owner=rust; gdrv_copy="$gdrv_copy_rust"
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-google-drive.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
gdrv_try gdrv-core-only
check "Google Drive Core refusal requires the native capability" 'refused "Google Drive ownership pairing"'
sed 's/"start-id"/"start-id", "rust-google-drive"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
gdrv_try gdrv-pair
check "matching Google Drive pair assembles with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
gdrv_post=''
gdrv_try gdrv-all-methods
check "a Google Drive connector route Rust's for every method is refused (Node keeps the 404s)" 'refused "Google Drive ownership pairing"'
gdrv_post='methods = ["PUT"]'
gdrv_try gdrv-wrong-method
check "a Google Drive connector route with the wrong method is refused" 'refused "Google Drive ownership pairing"'
gdrv_post='methods = ["POST"]'; gdrv_owner=node
gdrv_try gdrv-node-route
check "a Node-owned Google Drive connector route beside a native pair is refused" 'refused "Google Drive ownership pairing"'
gdrv_owner=rust; gdrv_copy=''
gdrv_try gdrv-missing-copy
check "a native Google Drive pair without the backup-copy route is refused" 'refused "Google Drive ownership pairing"'
gdrv_copy="$gdrv_copy_rust"
cp "$work/feature-index.saved" "$w/server/index.cjs"
gdrv_try gdrv-front-only
check "a rust-google-drive front cannot pair with the old Core connectors" 'refused "Google Drive ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try gdrv-old-pair
check "historic Google Drive old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# Round 7 (#2190): the off-site backup, all eight paths Rust's for every method.
offs_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/admin/offsite-backup"
owner = "$offs_owner"
$offs_methods
[[route]]
path = "/api/admin/offsite-backup/copy"
owner = "rust"
[[route]]
path = "/api/admin/offsite-backup/google/connect"
owner = "rust"
[[route]]
path = "/api/admin/offsite-backup/google/disconnect"
owner = "rust"
$offs_newstore
[[route]]
path = "/api/admin/offsite-backup/recovery-key"
owner = "rust"
[[route]]
path = "/api/admin/offsite-backup/run"
owner = "rust"
$offs_verify
TOML
}
offs_verify_rust='[[route]]
path = "/api/admin/offsite-backup/verify"
owner = "rust"'
offs_newstore_rust='[[route]]
path = "/api/admin/offsite-backup/new-store"
owner = "rust"'
offs_methods=''; offs_owner=rust; offs_verify="$offs_verify_rust"; offs_newstore="$offs_newstore_rust"
# Core's own list of the paths it refuses (server/rust-offsite-backup.cjs), with the new-store action (yes) or without it.
offs_core_file() {
  if [ "$1" = yes ]; then
    printf '%s\n' "const OWNED_PATHS = ['/api/admin/offsite-backup', '/api/admin/offsite-backup/new-store'];" > "$w/server/rust-offsite-backup.cjs"
  else
    printf '%s\n' "const OWNED_PATHS = ['/api/admin/offsite-backup'];" > "$w/server/rust-offsite-backup.cjs"
  fi
}
offs_core_file yes
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-offsite-backup.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
offs_try offs-core-only
check "off-site backup Core refusal requires the native capability" 'refused "off-site backup ownership pairing"'
sed 's/"start-id"/"start-id", "rust-offsite-backup"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
offs_try offs-pair
check "matching off-site backup pair assembles with the earlier pairs old/old" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
offs_methods='methods = ["GET"]'
offs_try offs-get-only
check "an off-site backup path Rust's for GET only is refused (Node would keep the 405s)" 'refused "off-site backup ownership pairing"'
offs_methods=''; offs_owner=node
offs_try offs-node-route
check "a Node-owned off-site backup path beside a native pair is refused" 'refused "off-site backup ownership pairing"'
offs_owner=rust; offs_verify=''
offs_try offs-missing-verify
check "a native off-site backup pair without the restore-test route is refused" 'refused "off-site backup ownership pairing"'
offs_verify="$offs_verify_rust"; offs_newstore=''
offs_try offs-missing-newstore
check "a native off-site backup pair without the new-store route is refused" 'refused "off-site backup ownership pairing: incomplete route ownership"'
offs_newstore="$offs_newstore_rust"
offs_core_file no
offs_try offs-core-without-newstore
check "a Core that does not refuse the new-store path cannot pair with a front that answers it" 'refused "off-site backup ownership pairing: Core does not refuse the new-store path"'
offs_core_file yes
cp "$work/feature-index.saved" "$w/server/index.cjs"
offs_try offs-front-only
check "a rust-offsite-backup front cannot pair with the old Core backup" 'refused "off-site backup ownership pairing"'
rm -f "$w/server/rust-offsite-backup.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try offs-old-pair
check "historic off-site backup old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
# Model sizing owner release matrix (sbstndalton/noevia#2189): two routes, GET only.
sizing_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/models/estimate"
owner = "rust"
methods = ["GET"]
[[route]]
path = "$sizing_last"
owner = "rust"
$sizing_limit
TOML
}
sizing_last="/api/models/preset/suggest"; sizing_limit='methods = ["GET"]'
printf '%s\n' "  if (require('./rust-model-sizing.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
sizing_try sizing-core-only
check "model sizing Core refusal requires the native capability" 'refused "model sizing ownership pairing"'
sed 's/"start-id"/"start-id", "rust-model-sizing"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
sizing_try sizing-pair
check "matching model sizing pair with both GET-only routes assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
sizing_limit=""
sizing_try sizing-all-methods
check "an all-method model sizing route is refused (Node keeps the other methods)" 'refused "model sizing ownership pairing"'
sizing_limit='methods = ["GET", "POST"]'
sizing_try sizing-get-post
check "a model sizing route with more than GET is refused" 'refused "model sizing ownership pairing"'
sizing_limit='methods = ["GET"]'; sizing_last="/api/models/preset/suggestx"
sizing_try sizing-incomplete
check "an incomplete model sizing route set is refused" 'refused "model sizing ownership pairing"'
sizing_last="/api/models/preset/suggest"
# An M1 and M2-A Core beside an M1-only front: the #2187 pair holds, the #2189 one does not.
printf '%s\n' "  if (require('./rust-models.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
sed 's/"start-id"/"start-id", "rust-model-reads"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
both_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/models/capabilities"
owner = "rust"
methods = ["GET"]
[[route]]
path = "/api/models/hardware"
owner = "rust"
methods = ["GET"]
[[route]]
path = "/api/models/estimate"
owner = "rust"
methods = ["GET"]
[[route]]
path = "/api/models/preset/suggest"
owner = "rust"
methods = ["GET"]
TOML
}
both_try sizing-m1-front
check "an M2-A Core cannot pair with an M1-only front" 'refused "model sizing ownership pairing: Core and Rust must move together"'
sed 's/"start-id"/"start-id", "rust-model-reads", "rust-model-sizing"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
both_try sizing-m1-m2a-pair
check "the M1 and M2-A Core with a front that has both assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
cp "$work/feature-index.saved" "$w/server/index.cjs"
sed 's/"start-id"/"start-id", "rust-model-sizing"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
sizing_try sizing-front-only
check "a rust-model-sizing front cannot pair with the old Core handlers" 'refused "model sizing ownership pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try sizing-old-pair
check "historic model sizing old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# Model maintenance owner release matrix (sbstndalton/noevia#2210): three routes, one method each; the recheck
# stays Node's.
maint_try() {
  try_routes "$1" <<TOML
[[route]]
path = "/api/chats/{conversationId}/move"
owner = "rust"
methods = ["POST"]
[[route]]
path = "/api/models/presets/reload"
owner = "rust"
$maint_reload
[[route]]
path = "/api/models/evidence"
owner = "rust"
$maint_evidence
$maint_import
$maint_recheck
TOML
}
maint_reload='methods = ["POST"]'; maint_evidence='methods = ["GET"]'
maint_import='[[route]]
path = "/api/models/evidence/import"
owner = "rust"
methods = ["POST"]'
maint_recheck=''
cp "$work/feature-index.saved" "$w/server/index.cjs"
printf '%s\n' "  if (require('./rust-model-maintenance.cjs').refuseOwned(req, res, {})) return;" >> "$w/server/index.cjs"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
maint_try maint-core-only
check "model maintenance Core refusal requires the native capability" 'refused "model maintenance ownership pairing: Core and Rust must move together"'
sed 's/"start-id"/"start-id", "rust-model-maintenance"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
maint_try maint-pair
check "matching model maintenance pair with the three one-method routes assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
maint_reload=''
maint_try maint-reload-all-methods
check "an all-method preset reload is refused (Node keeps the other methods)" 'refused "model maintenance ownership pairing"'
maint_reload='methods = ["POST", "PUT"]'
maint_try maint-reload-put
check "a preset reload with more than POST is refused" 'refused "model maintenance ownership pairing"'
maint_reload='methods = ["POST"]'; maint_evidence='methods = ["GET", "POST"]'
maint_try maint-evidence-post
check "an evidence read with more than GET is refused" 'refused "model maintenance ownership pairing"'
maint_evidence='methods = ["GET"]'; maint_import=''
maint_try maint-incomplete
check "an incomplete model maintenance route set is refused" 'refused "model maintenance ownership pairing: incomplete route ownership"'
maint_import='[[route]]
path = "/api/models/evidence/import"
owner = "rust"
methods = ["POST"]'
maint_recheck='[[route]]
path = "/api/models/evidence/recheck"
owner = "rust"
methods = ["POST"]'
maint_try maint-recheck-rust
check "a Rust-owned recheck (it loads a model after Node's admission check) is refused" 'refused "model maintenance ownership pairing: the recheck stays Node"'
maint_recheck=''
cp "$work/feature-index.saved" "$w/server/index.cjs"
maint_try maint-front-only
check "a rust-model-maintenance front cannot pair with the old Core handlers" 'refused "model maintenance ownership pairing: Core and Rust must move together"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
move_try maint-old-pair
check "historic model maintenance old/old rollback pair still assembles" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'

# Diary worker capability pair beside the unchanged route fixture.
cp "$w/server/index.cjs" "$work/db-index.saved"
cp "$rz/bins/noevia-server/src/lib.rs" "$work/db-lib.saved"
[ ! -f "$w/server/rust-diary.cjs" ] || cp "$w/server/rust-diary.cjs" "$work/db-module.saved"
mkdir -p "$repo/build"; cp "$here/../../build/web-supervisor.sh" "$repo/build/web-supervisor.sh"
db_try() { move_try "$1"; }
printf "%s\n" "const DIARY_BACKUP_WORKER_OWNER = 'noevia-diary-backup-worker-rust/1';" "module.exports = { DIARY_BACKUP_WORKER_OWNER };" > "$w/server/rust-diary.cjs"
db_try diary-core-only
check "diary worker new Core old front refused" 'refused "diary backup worker pairing"'
sed 's/"start-id"/"start-id", "rust-diary-backup-worker"/' "$work/db-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
db_try diary-pair
check "diary worker matched pair assembles" '[ $rc -eq 0 ]'
printf "%s\n" "require('./diary-backup-worker.cjs').startDiaryBackupWorker({});" >> "$w/server/index.cjs"
db_try diary-double
check "diary worker retained Node startup refused" 'refused "Core still starts the worker"'
cp "$work/db-index.saved" "$w/server/index.cjs"
printf 'module.exports = {};\n' > "$w/server/rust-diary.cjs"
db_try diary-front-only
check "diary worker new front old Core refused" 'refused "diary backup worker pairing"'
cp "$work/db-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
if [ -f "$work/db-module.saved" ]; then cp "$work/db-module.saved" "$w/server/rust-diary.cjs"; else rm -f "$w/server/rust-diary.cjs"; fi

# Watchdog ownership matrix, using the same explicit capability parser as route moves.
mkdir -p "$repo/build"
cp "$here/../../build/web-supervisor.sh" "$repo/build/web-supervisor.sh"
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
cat > "$w/server/rust-budget-watch.cjs" <<'JS'
const BUDGET_WATCH_OWNER = 'noevia-budget-watch-rust/3';
module.exports = { BUDGET_WATCH_OWNER };
JS
try_routes bw-core-only < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n')
check "budget watch: new Core and old front refused" 'refused "budget watch pairing"'
sed 's/"start-id"/"start-id", "rust-budget-watch-v3"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
try_routes bw-pair < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n')
[ "$rc" -eq 0 ] || cat "$work/err" >&2
check "budget watch: new paired owners assemble" '[ $rc -eq 0 ]'
sed 's/"start-id"/"start-id", "rust-budget-watch-v2"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
move_try bw-v2-front-v3-core
check "budget watch: v2 front and v3 Core refused" 'refused "budget watch pairing"'
sed -i.bak 's@noevia-budget-watch-rust/3@noevia-budget-watch-rust/2@' "$w/server/rust-budget-watch.cjs"
move_try bw-v2-pair
check "budget watch: matched native v2 pair assembles for rollback" '[ $rc -eq 0 ]'
sed 's/"start-id"/"start-id", "rust-budget-watch-v3"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
move_try bw-v3-front-v2-core
check "budget watch: v3 front and v2 Core refused" 'refused "budget watch pairing"'
sed -i.bak 's@noevia-budget-watch-rust/2@noevia-budget-watch-rust/3@' "$w/server/rust-budget-watch.cjs"
sed 's/"start-id"/"start-id", "rust-budget-watch"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
move_try bw-v1-front-v3-core
check "budget watch: v1 front and v3 Core refused" 'refused "budget watch pairing"'
sed -i.bak 's@noevia-budget-watch-rust/3@noevia-budget-watch-rust/1@' "$w/server/rust-budget-watch.cjs"
move_try bw-v1-pair
check "budget watch: matched native v1 pair assembles for rollback" '[ $rc -eq 0 ]'
sed 's/"start-id"/"start-id", "rust-budget-watch-v3"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
move_try bw-v3-front-v1-core
check "budget watch: v3 front and v1 Core refused" 'refused "budget watch pairing"'
rm "$w/server/rust-budget-watch.cjs"
try_routes bw-front-only < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n')
check "budget watch: old Core and new front refused" 'refused "budget watch pairing"'
cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
try_routes bw-old-pair < <(printf '[[route]]\npath = "/api/chats/{conversationId}/move"\nowner = "rust"\nmethods = ["POST"]\n')
check "budget watch: old paired owners assemble for rollback" '[ $rc -eq 0 ]'

# #2286 recheck moves independently, after the native evidence-store group.
cat > "$w/server/rust-model-evidence-recheck.cjs" <<'JS'
const OWNED_ROUTES = Object.freeze(new Set(['POST /api/models/evidence/recheck']));
module.exports = { OWNED_ROUTES };
JS
touch "$w/server/inference-admission-lease.cjs"
mkdir -p "$w/server/routes"
cp "$w/server/routes/models.cjs" "$work/er-model-routes.saved" 2>/dev/null || true
printf '%s\n' '// Other model routes, no public image probe.' > "$w/server/routes/models.cjs"
er_core() {
  cp "$work/feature-index.saved" "$w/server/index.cjs"
  cat >> "$w/server/index.cjs" <<'JS'
if (require('./rust-model-maintenance.cjs').refuseOwned(req, res, {})) return;
if (require('./rust-model-evidence-recheck.cjs').refuseOwned(req, res, {})) return;
const FRONT_SECRET = String(process.env.NOEVIA_PROJECT_STORE_TOKEN || '');
const inferenceAdmission = require('./inference-admission-lease.cjs').createAdmissionRoutes({
  secret: FRONT_SECRET,
});
if (await inferenceAdmission.handle(req, res)) return;
JS
}
er_front() { sed 's/"start-id"/"start-id", "rust-model-maintenance", "rust-model-evidence-recheck"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"; }
maint_recheck='[[route]]
path = "/api/models/evidence/recheck"
owner = "rust"
methods = ["POST"]'
er_core
sed 's/"start-id"/"start-id", "rust-model-maintenance"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
maint_try recheck-core-only
check "native recheck Core requires the front capability" 'refused "model maintenance ownership pairing: the recheck stays Node"'
er_front
sed '/rust-model-evidence-recheck.cjs/d' "$w/server/index.cjs" > "$work/er-core-old"; cp "$work/er-core-old" "$w/server/index.cjs"
maint_try recheck-front-only
check "native recheck front requires the Core refusal" 'refused "evidence recheck ownership pairing"'
er_core
maint_try recheck-pair
check "native recheck plus native evidence store assemble" '[ $rc -eq 0 ]'
maint_recheck='[[route]]
path = "/api/models/evidence/recheck"
owner = "rust"
methods = ["POST", "GET"]'
maint_try recheck-extra-method
check "native recheck owns POST alone" 'refused "evidence recheck ownership pairing"'
maint_recheck='[[route]]
path = "/api/models/evidence/recheck"
owner = "node"'
maint_try recheck-node-row
check "native recheck cannot retain a Node-owned row" 'refused "evidence recheck ownership pairing"'
maint_recheck='[[route]]
path = "/api/models/evidence/recheck"
owner = "rust"
methods = ["POST"]'
printf '%s\n' 'createVisionProbe()(base, headers, model);' >> "$w/server/routes/models.cjs"
maint_try recheck-old-probe
check "native recheck deletes the public Node image probe" 'refused "public Node probe still present"'
printf '%s\n' '// Other model routes.' > "$w/server/routes/models.cjs"
cp "$w/server/index.cjs" "$work/er-index.saved"
sed '/inferenceAdmission.handle(req, res)/d' "$work/er-index.saved" > "$w/server/index.cjs"
maint_try recheck-no-admission-mount
check "native recheck requires mounted live admission" 'refused "inference admission must be mounted"'
sed "s/secret: FRONT_SECRET/secret: ''/" "$work/er-index.saved" > "$w/server/index.cjs"
maint_try recheck-no-admission-secret
check "native recheck requires the captured admission secret" 'refused "captured inference admission secret required"'
cp "$work/er-index.saved" "$w/server/index.cjs"
rm -f "$w/server/inference-admission-lease.cjs"
maint_try recheck-no-admission
check "native recheck requires live admission implementation" 'refused "live inference admission required"'
touch "$w/server/inference-admission-lease.cjs"
sed '/rust-model-evidence-recheck.cjs/d' "$work/er-index.saved" > "$w/server/index.cjs"
sed 's/"start-id"/"start-id", "rust-model-maintenance"/' "$work/feature-lib.saved" > "$rz/bins/noevia-server/src/lib.rs"
maint_recheck='[[route]]
path = "/api/models/evidence/recheck"
owner = "node"'
maint_try recheck-old-pair
check "historic recheck old/old remains compatible with native evidence storage" '[ $rc -eq 0 ]'
cp "$work/feature-index.saved" "$w/server/index.cjs"; cp "$work/feature-lib.saved" "$rz/bins/noevia-server/src/lib.rs"
rm -f "$w/server/rust-model-evidence-recheck.cjs" "$w/server/inference-admission-lease.cjs"
if [ -f "$work/er-model-routes.saved" ]; then cp "$work/er-model-routes.saved" "$w/server/routes/models.cjs"; else rm -f "$w/server/routes/models.cjs"; fi

# Restore unrelated final archive-failure fixture, retaining all evidence in this test log.
rm -f "$w/server/project-store-client.cjs" "$w/server/chat.cjs" "$w/server/chat-change-journal.cjs" "$w/server/routes/chat-lists.cjs"
rm -f "$rz/crates/server-projects/src/chat_move.rs" "$rz/crates/server-projects/src/journal.rs" "$rz/bins/noevia-server/src/lib.rs" "$rz/bins/noevia-server/src/main.rs"
g rm -q apps/web/server/rust-auth.cjs apps/web/server/rust-projects.cjs && g commit -qm core-plain-2096

# A failing final tar must not leave out.partial (or a final tarball) behind. The shim writes a
# truncated archive first, like a full disk would.
real_tar="$(command -v tar)"
cat > "$work/bin/tar" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = -czf ]; then echo truncated > "\$2"; exit 1; fi
exec "$real_tar" "\$@"
SHIM
chmod +x "$work/bin/tar"
printf 'NOEVIA_WEB_REF=self\nNOEVIA_CORE_REF=self\n' > "$repo/release/versions.lock"
g commit -qam selfagain; ssha="$(g rev-parse --short HEAD)"; fout="$work/failout"; mkdir -p "$fout"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ssha" "$fout" >/dev/null 2>"$work/err"; rc=$?
check "failing final tar exits non-zero" '[ $rc -ne 0 ]'
check "failing final tar leaves no .partial and no tarball" '[ -z "$(ls -A "$fout")" ]'

check "native media ownership adversarial pairings" 'node "$here/test-media-pairing.cjs"'
check "inference machines pairing adversarial cases" 'bash "$here/test-machines-pairing.sh"'

echo "passed $passes, failed $fails"
[ "$fails" -eq 0 ]
