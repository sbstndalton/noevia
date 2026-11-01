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
  printf '[[route]]\npath = "/api/diary/local-exchange"\nowner = "%s"\n\n' "${dr_local:-node}"
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
check "the local exchange moving to Rust is refused (Node still answers it)" 'refused "Diary route ownership pairing"'
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
rm -f "$w/server/rust-tool-approvals.cjs" "$w/server/rust-tool-approval-bridge.cjs"
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
for close_entry in "rust-health.cjs|rust-health|/api/health|health check" "rust-auto-roles.cjs|rust-auto-roles|/api/auto-roles|auto-roles read" "rust-workspace.cjs|rust-workspace|/api/workspace|workspace list"; do
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
sizing_limit='methods = ["GET"]'; sizing_last="/api/models/preset"
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
