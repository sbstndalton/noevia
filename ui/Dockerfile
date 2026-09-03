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
COPY server ./server
ENV UI_PORT=8021
EXPOSE 8021
CMD ["node", "server/index.cjs"]
