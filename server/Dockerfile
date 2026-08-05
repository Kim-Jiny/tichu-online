# Build context is the repo root (see docker-compose.yml) because the image
# bundles both the server and the web client. Keeping the built web assets
# inside the image is what lets a blue/green swap stay atomic — a host bind
# mount would let the static files and the running slot drift apart.

FROM node:20-alpine AS web
WORKDIR /web
COPY web/package*.json ./
# Not --omit=dev: the build runs tsc and vite, both devDependencies.
RUN npm ci
COPY web/ ./
RUN npm run build

FROM node:20-alpine

WORKDIR /app

COPY server/package*.json ./
RUN npm ci --omit=dev

COPY server/ .

# Served by webApp.js at /play/ — same origin as the WebSocket, which matters
# because the server emits no CORS headers.
COPY --from=web /web/dist ./public/play

EXPOSE 3000

CMD ["node", "server.js"]
