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
# #2153: a core that builds brains only for origin "history" entries needs a front that journals it.
printf '%s\n' "const JOURNAL_READER_MARKER = 'noevia-chat-change-journal-reader/1';" "function isHistorySave(e) { return !!e && e.op === 'write' && e.origin === 'history'; }" > "$w/server/chat-change-journal.cjs"
g add -A && g commit -qm core-journal-origin; ph10o="$(g rev-parse --short HEAD)"
PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$ph10o" "$out" >/dev/null 2>"$work/err"; rc=$?
check "#2153: ...but a core that needs the journal origin is refused beside a front that journals none" \
  '[ $rc -ne 0 ] && grep -q "journals no origin" "$work/err" && [ ! -f "$out/noevia-release-$ph10o.tar.gz" ]'
mkdir -p "$work/remote/noevia-rs-y/crates/server-projects/src"
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
  g add -A && g commit -qm "$1"; tsha="$(g rev-parse --short HEAD)"
  PATH="$work/bin:$PATH" bash "$repo/deploy/tools/assemble-release.sh" "$tsha" "$out" >/dev/null 2>"$work/err"; rc=$?
}
refused() { [ $rc -ne 0 ] && grep -q "$1" "$work/err" && [ ! -f "$out/noevia-release-$tsha.tar.gz" ]; }

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

# Research journals are a separate kind-scoped internal capability. Every selected pair
# must have the live client export and all compiled store operations, including report-first.
cp "$w/server/project-store-client.cjs" "$work/research-client.previous"
cp "$rz/bins/noevia-server/src/lib.rs" "$work/research-features.previous"
cat > "$w/server/project-store-client.cjs" <<'JS'
const CHAT_MOVE_CLIENT_MARKER = 'noevia-chat-move-client/1';
const RESEARCH_JOBS_CLIENT_MARKER = 'noevia-research-jobs-client/1';
function researchJobsFor(user) { return { user }; }
module.exports = { CHAT_MOVE_CLIENT_MARKER, RESEARCH_JOBS_CLIENT_MARKER, researchJobsFor };
JS
research_try() { move_try "$1"; }
research_try research-new-core-old-rust
check "research new core with old Rust is refused" 'refused "research job store pairing"'
mkdir -p "$rz/crates/server-projects/src"
echo 'pub const RESEARCH_JOBS_STORE_MARKER: &str = "noevia-research-jobs-store/1";' > "$rz/crates/server-projects/src/research_jobs.rs"
echo 'pub mod research_jobs;' > "$rz/crates/server-projects/src/lib.rs"
printf '%s\n' 'pub const FEATURES: &[&str] = &["start-id", server_projects::research_jobs::RESEARCH_JOBS_STORE_MARKER];' > "$rz/bins/noevia-server/src/lib.rs"
{
  echo 'use server_projects::research_jobs as jobs;'
  for op in recover start abandon event cancel finish report prepare artifact clear read list; do
    op_title="$(printf '%s' "$op" | cut -c1 | tr '[:lower:]' '[:upper:]')${op#?}"
    if [ "$op" = recover ] || [ "$op" = report ]; then
      # rustfmt emits this trailing comma when the live route spans multiple lines.
      printf '.route(\n  "%s",\n  research_route(ResearchOp::%s),\n)\n' "/v1/research-jobs/$op" "${op_title}"
    else
      printf '.route("%s", research_route(ResearchOp::%s))\n' "/v1/research-jobs/$op" "${op_title}"
    fi
  done
} > "$rz/bins/noevia-server/src/project_store.rs"
research_try research-matched
check "matching research client and compiled Rust store assemble" '[ $rc -eq 0 ] && [ -f "$out/noevia-release-$tsha.tar.gz" ]'
cp "$w/server/project-store-client.cjs" "$work/research-client.saved"
printf '%s\n' 'function researchJobsFor(user) { return { user }; }' 'module.exports = { researchJobsFor };' > "$w/server/project-store-client.cjs"
research_try research-stripped-core-marker
check "ported research core with stripped marker is refused" 'refused "research job store pairing"'
cp "$work/research-client.saved" "$w/server/project-store-client.cjs"
grep -v '^module.exports' "$w/server/project-store-client.cjs" > "$work/research-unexported"
cp "$work/research-unexported" "$w/server/project-store-client.cjs"
research_try research-unexported-client
check "unexported research client marker is refused" 'refused "research job store pairing"'
cp "$work/research-client.saved" "$w/server/project-store-client.cjs"
cp "$rz/crates/server-projects/src/research_jobs.rs" "$work/research-store.saved"
printf '%s\n' '/* pub const RESEARCH_JOBS_STORE_MARKER: &str = "noevia-research-jobs-store/1"; */' > "$rz/crates/server-projects/src/research_jobs.rs"
research_try research-comment-only-marker
check "comment-only research store marker is refused" 'refused "research job store pairing"'
cp "$work/research-store.saved" "$rz/crates/server-projects/src/research_jobs.rs"
printf '%s\n' 'pub const FEATURES: &[&str] = &["start-id"];' > "$rz/bins/noevia-server/src/lib.rs"
research_try research-uncompiled
check "uncompiled research store marker is refused" 'refused "research job store pairing"'
printf '%s\n' 'pub const FEATURES: &[&str] = &["start-id", server_projects::research_jobs::RESEARCH_JOBS_STORE_MARKER];' > "$rz/bins/noevia-server/src/lib.rs"
grep -v '/v1/research-jobs/report' "$rz/bins/noevia-server/src/project_store.rs" > "$work/research-missing-route"
cp "$work/research-missing-route" "$rz/bins/noevia-server/src/project_store.rs"
research_try research-missing-report-route
check "missing live research report route is refused" 'refused "research job store pairing"'
echo '// .route("/v1/research-jobs/report", research_route(ResearchOp::Report))' >> "$rz/bins/noevia-server/src/project_store.rs"
research_try research-comment-only-route
check "comment-only research report route is refused" 'refused "research job store pairing"'
cp "$work/research-client.previous" "$w/server/project-store-client.cjs"
cp "$work/research-features.previous" "$rz/bins/noevia-server/src/lib.rs"
rm -f "$rz/crates/server-projects/src/research_jobs.rs" "$rz/crates/server-projects/src/lib.rs" "$rz/bins/noevia-server/src/project_store.rs"

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

echo "passed $passes, failed $fails"
[ "$fails" -eq 0 ]
