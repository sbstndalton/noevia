# Cowork UI — build frontend, then serve dist + proxy server.
# Staged 2026-09-03; first build/deploy is gated per MIGRATION.md Step F.
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-fund --no-audit
COPY . .
RUN npm run build

FROM node:22-alpine
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY server/package.json server/package-lock.json* ./server/
# Project-RAG deps (better-sqlite3 is a native module — must build on linux/arm64,
# hence the fresh install here rather than copying any host node_modules; the
# server/.dockerignore keeps the macOS copy out).
RUN cd server && npm ci --no-fund --no-audit 2>/dev/null || npm install --no-fund --no-audit
COPY server ./server
ENV UI_PORT=8021
EXPOSE 8021
CMD ["node", "server/index.cjs"]
