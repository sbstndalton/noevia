# Cowork UI — build frontend, then serve dist + proxy server.
# Staged 2026-09-03; first build/deploy is gated per MIGRATION.md Step F.
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-fund --no-audit
COPY . .
RUN npm run build

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
RUN cd server && npm ci --no-fund --no-audit 2>/dev/null || npm install --no-fund --no-audit
COPY server ./server
ENV UI_PORT=8021
EXPOSE 8021
CMD ["node", "server/index.cjs"]
