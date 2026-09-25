# Cowork UI — build frontend, then serve dist + proxy server.
# Staged 2026-09-03; first build/deploy is gated per MIGRATION.md Step F.
FROM node:22-alpine AS build
WORKDIR /app
# COWORK_VERSION is the release tag Compose already builds with
# (compose.yaml `web.build.args`, set from the COWORK_VERSION env var the
# deploy runbook exports — docs/deployment.md). STAMP_VERSION is what
# scripts/stamp-icons.cjs and the __NOEVIA_BUILD__ vite define actually read;
# it defaults to package.json's version there, which never changes between
# releases and would leave the stale-shell guard and favicon cache-busting
# permanently inert in this build (issue #311). "dev" is compose's own
# default for local/no-arg builds, so it is treated the same as unset.
ARG COWORK_VERSION
ENV STAMP_VERSION=$COWORK_VERSION
COPY package.json package-lock.json ./
# Prefer IPv4 for registry lookups: hosts with a broken IPv6 route otherwise time out.
RUN NODE_OPTIONS=--dns-result-order=ipv4first npm ci --no-fund --no-audit
COPY . .
RUN node --test tests/*.test.cjs && npm run build

# Runtime must be glibc (Debian), not Alpine/musl: sqlite-vec's prebuilt vec0.so
# is glibc-linked and cannot load on musl (SQLite retries with a .so suffix -> the
# misleading "vec0.so.so: No such file or directory" error). better-sqlite3 also
# ships glibc prebuilds; on the full Debian image nothing needs compiling and the
# build tools remain available as a source-build fallback.
FROM node:22-bookworm
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY server/package.json server/package-lock.json* ./server/
# Project-RAG deps (both native modules — installed fresh so the platform-matching
# prebuilt binaries land here; server/.dockerignore keeps the macOS copy out).
RUN cd server && NODE_OPTIONS=--dns-result-order=ipv4first npm ci --no-fund --no-audit
COPY server ./server
ENV UI_PORT=8021
EXPOSE 8021
HEALTHCHECK --interval=30s --timeout=6s --start-period=30s --retries=3 CMD node -e "fetch('http://127.0.0.1:'+(process.env.UI_PORT||8021)+'/api/setup/status',{signal:AbortSignal.timeout(5000)}).then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "server/index.cjs"]
