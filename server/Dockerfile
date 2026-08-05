# Build context is the repo root (see docker-compose.yml) so the image can pick
# up dist/play alongside server/.
#
# The web client is NOT compiled here. CI builds flutter_app for the web and
# deploy.sh stages the result at dist/play; compiling it on the VPS would hold a
# full core for minutes while the active blue/green slot is still serving games.
#
# Keeping the bundle inside the image is what makes a slot swap atomic — a host
# bind mount would let the static files and the running slot drift apart.

FROM node:20-alpine

WORKDIR /app

COPY server/package*.json ./
RUN npm ci --omit=dev

COPY server/ .

# Served by webApp.js at /play/ — same origin as the WebSocket, which matters
# because the server emits no CORS headers. The directory may be empty: a
# server-only hotfix can deploy without waiting on a web build, and webApp.js
# falls through to the marketing page when index.html isn't there.
COPY dist/play ./public/play

EXPOSE 3000

CMD ["node", "server.js"]
