#!/bin/bash
# Blue/green deploy script for tichu-online on the Contabo VPS.
#
# Reads the currently active slot from $ACTIVE_FILE, brings up the
# inactive slot with the latest code, swaps nginx upstream to the new
# slot once /health goes green, then graceful-stops the old slot
# (10-minute SIGTERM grace lets in-progress games finish or migrate
# via /internal/adopt-rooms).
#
# First-time bootstrap is documented in server/deploy/README.md.
#
# Usage (from anywhere on the VPS):
#   bash /opt/services/tichu-online/app/server/deploy/deploy.sh

set -e

BASE_DIR=/opt/services/tichu-online
APP_DIR="$BASE_DIR/app"
ACTIVE_FILE="$BASE_DIR/active_slot"
LOCKFILE="$BASE_DIR/.deploy.lock"
PROXY_CONF=/opt/services/proxy/conf/tichu.conf
TEMPLATE="$APP_DIR/server/deploy/tichu.conf.template"
REPO_URL="https://github.com/Kim-Jiny/tichu-online.git"
BRANCH="main"
HEALTH_TIMEOUT_SEC=60
DRAIN_TIMEOUT_SEC=900   # docker stop -t (matches stop_grace_period in compose)

log() { echo "[deploy] $*"; }

# Concurrent-deploy guard. The drain step blocks for up to
# DRAIN_TIMEOUT_SEC; if a second invocation fires while the first is
# still in that window it would (a) read a stale active_slot and (b)
# rebuild whichever container is currently serving traffic, blowing up
# the in-progress drain. flock + non-blocking serialises invocations.
mkdir -p "$BASE_DIR"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
  log "another deploy is already running (lock=$LOCKFILE). aborting."
  log "if you're sure the previous run died, remove $LOCKFILE manually."
  exit 1
fi

# ----- 1. Pull latest code -----
mkdir -p "$APP_DIR"
if [ ! -d "$APP_DIR/.git" ]; then
  log "fresh clone"
  git clone -b "$BRANCH" "$REPO_URL" "$APP_DIR"
else
  log "updating $APP_DIR"
  cd "$APP_DIR"
  git fetch origin
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
fi

cd "$APP_DIR"

if [ ! -f "$APP_DIR/.env" ]; then
  log "WARN: $APP_DIR/.env missing — DB_PASSWORD / INTERNAL_MIGRATE_TOKEN may be empty"
fi

# ----- 2. Decide slot direction -----
ACTIVE=$(cat "$ACTIVE_FILE" 2>/dev/null || echo "blue")
if [ "$ACTIVE" = "blue" ]; then INACTIVE="green"; else INACTIVE="blue"; fi
log "active=$ACTIVE → switching to $INACTIVE"

# ----- 3. Bring up the inactive slot with the new image -----
log "building + starting tichu-online-$INACTIVE"
docker compose --profile "$INACTIVE" up -d --build "server-$INACTIVE"

# ----- 4. Wait for /health on the new slot -----
# Probe from inside the target container itself — node:20-alpine ships
# with BusyBox wget, while the official nginx:latest image does not.
log "waiting for /health on tichu-online-$INACTIVE (max ${HEALTH_TIMEOUT_SEC}s)"
HEALTHY=0
for i in $(seq 1 $HEALTH_TIMEOUT_SEC); do
  if docker exec "tichu-online-$INACTIVE" wget -q -O- "http://localhost:3000/health" 2>/dev/null | grep -q OK; then
    log "health OK after ${i}s"
    HEALTHY=1
    break
  fi
  sleep 1
done
if [ "$HEALTHY" != "1" ]; then
  log "ABORT: health check failed; rolling back"
  docker compose --profile "$INACTIVE" stop "server-$INACTIVE" || true
  docker compose --profile "$INACTIVE" rm -f "server-$INACTIVE" || true
  exit 1
fi

# ----- 5. Swap nginx upstream -----
log "rewriting $PROXY_CONF (upstream → tichu-online-$INACTIVE)"
sed "s|{{ACTIVE}}|$INACTIVE|g" "$TEMPLATE" > "$PROXY_CONF.new"
mv "$PROXY_CONF.new" "$PROXY_CONF"
docker exec nginx nginx -t
docker exec nginx nginx -s reload
log "nginx reloaded — new connections route to $INACTIVE"

# ----- 6. Drain the outgoing slot (graceful stop, 10-minute grace) -----
log "stopping tichu-online-$ACTIVE with up to ${DRAIN_TIMEOUT_SEC}s drain grace"
docker compose --profile "$ACTIVE" stop -t "$DRAIN_TIMEOUT_SEC" "server-$ACTIVE" || true
docker compose --profile "$ACTIVE" rm -f "server-$ACTIVE" || true

# ----- 7. Persist the new active slot -----
echo "$INACTIVE" > "$ACTIVE_FILE"
log "done. active=$INACTIVE"
