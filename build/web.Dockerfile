# The web image, built from an ASSEMBLED release tree (#922, #952; deploy/tools/assemble-release.sh).
# Since the repo split cutover this is the only web image recipe: apps/web/Dockerfile is gone, and
# the last CI run proving both built the same image is linked from the cutover PR. Build context =
# the extracted tarball root (noevia/, web/, core/, release-refs), e.g.
#   docker build -f noevia/build/web.Dockerfile --build-arg COWORK_VERSION=<sha> <tree>
# Releases use deploy/tools/build-web-release.sh, which wraps exactly this.
FROM node:22-alpine AS build
WORKDIR /app
# COWORK_VERSION stays the noevia (integration repo) sha; it must match the assembled tree's
# release-refs NOEVIA_SHA. Optional here: the tree already names its sha.
ARG COWORK_VERSION
ARG REQUIRE_RELEASE_VERSION=0
COPY release-refs ./
RUN set -e; . ./release-refs; \
    if [ "$REQUIRE_RELEASE_VERSION" = 1 ] && { [ -z "$COWORK_VERSION" ] || [ "$COWORK_VERSION" = dev ]; }; then \
      echo "COWORK_VERSION build-arg is required for a release build" >&2; exit 1; fi; \
    if [ -n "$COWORK_VERSION" ] && [ "$COWORK_VERSION" != dev ] && [ "$COWORK_VERSION" != "$NOEVIA_SHA" ]; then \
      echo "COWORK_VERSION=$COWORK_VERSION but the assembled tree is noevia $NOEVIA_SHA" >&2; exit 1; fi
COPY web/package.json web/package-lock.json ./
# Prefer IPv4 for registry lookups: hosts with a broken IPv6 route otherwise time out.
RUN NODE_OPTIONS=--dns-result-order=ipv4first npm ci --no-fund --no-audit
# Lay web/ and core/ out as the monorepo's apps/web was, so the same test gate and build command run.
COPY web/ ./
COPY core/server ./server
COPY core/tests/server ./tests/server
COPY core/tests/fixtures ./tests/fixtures
RUN set -e; set -a; . ./release-refs; set +a; export STAMP_VERSION="$NOEVIA_SHA"; \
    node --test tests/client/*.test.cjs tests/server/*.test.cjs && npm run build && \
    node -e 'const fs=require("fs");const f="dist/version.json";const v=JSON.parse(fs.readFileSync(f,"utf8"));if(v.version!==process.env.STAMP_VERSION){console.error("version.json not stamped with "+process.env.STAMP_VERSION);process.exit(1)}fs.writeFileSync(f,JSON.stringify({version:v.version,web:process.env.NOEVIA_WEB_SHA,core:process.env.NOEVIA_CORE_SHA})+"\n")'

# Runtime (glibc for sqlite-vec / better-sqlite3).
FROM node:22-bookworm
WORKDIR /app
COPY --from=build /app/dist ./dist
# /api/ready reads dist/version.json; package.json (web's) is the fallback (#337).
COPY web/package.json ./
COPY core/server/package.json core/server/package-lock.json* ./server/
RUN cd server && NODE_OPTIONS=--dns-result-order=ipv4first npm ci --no-fund --no-audit
COPY core/server ./server
# core owns contracts/; server/ requires it as ../contracts.
COPY core/contracts ./contracts
ENV UI_PORT=8021
EXPOSE 8021
HEALTHCHECK --interval=30s --timeout=6s --start-period=30s --retries=3 CMD node -e "fetch('http://127.0.0.1:'+(process.env.UI_PORT||8021)+'/api/setup/status',{signal:AbortSignal.timeout(5000)}).then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "server/index.cjs"]
