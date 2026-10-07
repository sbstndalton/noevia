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
