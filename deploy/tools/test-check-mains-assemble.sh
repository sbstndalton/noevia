#!/usr/bin/env bash
# Tests deploy/tools/check-mains-assemble.sh with no network: curl is a PATH shim serving synthetic codeload
# tarballs, and the assembler is a stub that checks what it is handed.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/check-mains-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; fi; }
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

rs=1111111111111111111111111111111111111111; old=2222222222222222222222222222222222222222
core=3333333333333333333333333333333333333333; web=4444444444444444444444444444444444444444
svc=5555555555555555555555555555555555555555
mkdir -p "$work/serve" "$work/bin" "$work/src"
mk() { # <name> <ref> : a codeload-shaped tarball
  mkdir -p "$work/src/$1-$2"; echo "synthetic $1" > "$work/src/$1-$2/README.md"
  tar -czf "$work/serve/$1-$2.tgz" -C "$work/src" "$1-$2"
}
mk noevia-rs "$rs"; mk noevia-core "$core"; mk noevia-web "$web"
mkdir -p "$work/src/noevia-services-$svc/diary" "$work/src/noevia-services-$svc/ocr"
for s in diary ocr; do
  printf 'FROM scratch\nARG NOEVIA_RS_REF=%s\nARG NOEVIA_RS_SHA256=%064d\nRUN echo keep\n' "$old" 0 > "$work/src/noevia-services-$svc/$s/Dockerfile"
done
tar -czf "$work/serve/noevia-services-$svc.tgz" -C "$work/src" "noevia-services-$svc"
# The services tree as the lock's rs would leave it: nothing lags.
mkdir -p "$work/src/noevia-services-$old/diary"
printf 'FROM scratch\nARG NOEVIA_RS_REF=%s\nARG NOEVIA_RS_SHA256=%064d\n' "$rs" 1 > "$work/src/noevia-services-$old/diary/Dockerfile"
tar -czf "$work/serve/noevia-services-$old.tgz" -C "$work/src" "noevia-services-$old"

cat > "$work/bin/curl" <<SHIM
#!/usr/bin/env bash
dest=""; url=""
while [ \$# -gt 0 ]; do case "\$1" in -o) dest="\$2"; shift 2 ;; http*) url="\$1"; shift ;; *) shift ;; esac; done
repo="\${url#*sbstndalton/}"; repo="\${repo%%/*}"; ref="\${url##*/}"
[ -f "$work/serve/\$repo-\$ref.tgz" ] || { echo "no such tarball: \$url" >&2; exit 22; }
cp "$work/serve/\$repo-\$ref.tgz" "\$dest"
SHIM
chmod +x "$work/bin/curl"
# The stub assembler: --lock <file> <sha> <out>, CI=true; it downloads the four tarballs through the shim the script
# put first on PATH, verifies each against the lock, and prints the Services Dockerfile pins it received.
cat > "$work/assemble-stub.sh" <<'STUB'
#!/usr/bin/env bash
set -eu
[ "${CI:-}" = true ] || { echo "stub: CI is not true" >&2; exit 2; }
[ "$1" = --lock ] || { echo "stub: no --lock" >&2; exit 2; }
lock="$2"; sha="$3"; out="$4"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "stub: bad sha" >&2; exit 2; }
val() { sed -n "s/^$1=//p" "$lock"; }
d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
for pair in rs:noevia-rs web:noevia-web core:noevia-core services:noevia-services; do
  k="$(printf '%s' "${pair%%:*}" | tr a-z A-Z)"; ref="$(val NOEVIA_${k}_REF)"; sum="$(val NOEVIA_${k}_SHA256)"
  curl -fsSL -o "$d/f" "https://codeload.github.com/sbstndalton/${pair#*:}/tar.gz/$ref"
  got="$( (sha256sum "$d/f" 2>/dev/null || shasum -a 256 "$d/f") | cut -d' ' -f1)"
  [ "$got" = "$sum" ] || { echo "stub: ${pair#*:} checksum mismatch" >&2; exit 3; }
  [ "${pair%%:*}" != services ] || { mkdir -p "$d/s"; tar -xzf "$d/f" -C "$d/s"; cat "$d"/s/*/diary/Dockerfile > "$out/services-diary-dockerfile"; cat "$d"/s/*/ocr/Dockerfile > "$out/services-ocr-dockerfile" 2>/dev/null || :; }
done
echo "stub: all four tarballs verified"
[ "${STUB_FAIL:-}" != 1 ] || { echo "assemble-release: Code executor pairing: the Rust front ... but Core ..." >&2; exit 1; }
STUB
chmod +x "$work/assemble-stub.sh"
run() { PATH="$work/bin:$PATH" ASSEMBLE_RELEASE="$work/assemble-stub.sh" bash "$here/check-mains-assemble.sh" "$@" >"$work/log" 2>&1; rc=$?; }

mkdir -p "$work/o1"
run --rs "$rs" --core "$core" --web "$web" --services "$svc" "$work/o1"
check "a lagging Services pin: the assembler is handed tarballs matching the lock and rc 0" '[ $rc -eq 0 ] && grep -q "stub: all four tarballs verified" "$work/log"'
check "a lagging Services pin is named in a notice" 'grep -q "::notice::the Services pin lags noevia-rs main" "$work/log" && grep -q "of ocr diary pin" "$work/log"'
check "the lagging Dockerfiles carry the rs ref and the rs tarball checksum, and nothing else changed" \
  'grep -qx "ARG NOEVIA_RS_REF=$rs" "$work/o1/services-diary-dockerfile" && grep -qx "ARG NOEVIA_RS_SHA256=$(sha256_of "$work/serve/noevia-rs-$rs.tgz")" "$work/o1/services-diary-dockerfile" && grep -qx "RUN echo keep" "$work/o1/services-ocr-dockerfile" && ! grep -q "$old" "$work/o1/services-ocr-dockerfile"'
check "the run states the four refs it assembled" 'grep -q "check-mains-assemble: rs $rs core $core web $web services $svc" "$work/log"'
mkdir -p "$work/o2"
run --rs "$rs" --core "$core" --web "$web" --services "$old" "$work/o2"
check "a Services pin that already follows rs is left alone (no notice)" '[ $rc -eq 0 ] && ! grep -q "::notice::" "$work/log"'
mkdir -p "$work/o3"
STUB_FAIL=1 run --rs "$rs" --core "$core" --web "$web" --services "$svc" "$work/o3"
check "a refusal by the assembler fails the run and its message reaches the log" '[ $rc -ne 0 ] && grep -q "assemble-release: Code executor pairing: the Rust front" "$work/log" && ! grep -q "assembled (every pairing guard passed)" "$work/log"'
run --rs notasha --core "$core" --web "$web" --services "$svc" "$work/o3"
check "a ref that is not a 40-hex sha is refused" '[ $rc -ne 0 ] && grep -q "not a 40-hex sha" "$work/log"'
run --rs "$core" --core "$core" --web "$web" --services "$svc" "$work/o3"
check "a ref no tarball exists for fails the run with a download error" '[ $rc -ne 0 ] && grep -q "could not download noevia-rs" "$work/log"'
echo "passed $passes, failed $fails"
[ "$fails" -eq 0 ]
