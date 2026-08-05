#!/bin/bash
# Blue/green deploy script for tichu-online on the Contabo VPS.
#
# Reads the currently active slot from $ACTIVE_FILE, brings up the
# inactive slot with the latest code, swaps nginx upstream to the new
# slot once /health goes green, then graceful-stops the old slot
# (SIGTERM grace of DRAIN_TIMEOUT_SEC lets in-progress games reach a round
# boundary and migrate via /internal/adopt-rooms).
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
WEB_BUNDLE_DIR="$BASE_DIR/web-bundle"   # uploaded by CI before this runs

log() { echo "[deploy] $*"; }

# The next deploy reads $PROXY_CONF to decide which slot is live, so the file
# must never claim a swap that nginx isn't actually serving. Between writing
# the new conf and confirming the reload we keep a backup here; if the script
# exits non-zero in that window — failed reload, SSH drop, CI kill — put the
# old conf back and reload, so file and reality stay in agreement.
# Cleared once the swap is confirmed, so a later failure (during the drain)
# does not roll back a swap that already happened.
CONF_BACKUP=""
restore_conf_on_fail() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$CONF_BACKUP" ] && [ -f "$CONF_BACKUP" ]; then
    log "upstream swap unconfirmed (exit $rc) — restoring previous $PROXY_CONF"
    cp "$CONF_BACKUP" "$PROXY_CONF" || true
    docker exec nginx nginx -s reload || true
  fi
  if [ "$rc" -eq 0 ] && [ -n "$CONF_BACKUP" ] && [ -f "$CONF_BACKUP" ]; then
    rm -f "$CONF_BACKUP" || true
  fi
}
# A signal is not a failed command: $? at that moment is whatever ran last,
# often 0, so the exit-status test above would skip the restore precisely when
# we need it (Ctrl-C or a CI kill between the conf swap and the reload). Signals
# get their own handler that restores unconditionally, then leaves via the
# conventional 128+signal code with the EXIT trap disarmed so it can't run twice.
restore_conf_on_signal() {
  sig="$1"
  if [ -n "$CONF_BACKUP" ] && [ -f "$CONF_BACKUP" ]; then
    log "interrupted by $sig before the upstream swap was confirmed — restoring $PROXY_CONF"
    cp "$CONF_BACKUP" "$PROXY_CONF" || true
    docker exec nginx nginx -s reload || true
    rm -f "$CONF_BACKUP" || true
  fi
  CONF_BACKUP=""
  trap - EXIT
  case "$sig" in
    INT) exit 130 ;;
    TERM) exit 143 ;;
    *) exit 1 ;;
  esac
}
trap restore_conf_on_fail EXIT
trap 'restore_conf_on_signal INT' INT
trap 'restore_conf_on_signal TERM' TERM

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

# ----- 1b. Stage the web client bundle -----
# CI builds flutter_app for the web and uploads it here, rather than the VPS
# compiling it: the build would otherwise burn a full core for minutes while the
# *active* slot is still serving games, which is exactly the headroom
# BOT_WORKERS=2 and cpus=3.5 exist to protect.
#
# A missing bundle is not fatal. The image just ships without /play and
# server/webApp.js falls through to the marketing page, so a server-only
# hotfix can deploy without waiting on a web build.
rm -rf "$APP_DIR/dist/play"
mkdir -p "$APP_DIR/dist"
if [ -d "$WEB_BUNDLE_DIR" ] && [ -f "$WEB_BUNDLE_DIR/index.html" ]; then
  log "staging web bundle from $WEB_BUNDLE_DIR"
  cp -r "$WEB_BUNDLE_DIR" "$APP_DIR/dist/play"
else
  log "WARN: no web bundle at $WEB_BUNDLE_DIR — image will ship without /play"
  mkdir -p "$APP_DIR/dist/play"
fi

if [ ! -f "$APP_DIR/.env" ]; then
  log "WARN: $APP_DIR/.env missing — DB_PASSWORD / INTERNAL_MIGRATE_TOKEN may be empty"
fi

# ----- 2. Decide slot direction -----
# The nginx upstream is what actually receives traffic, so trust it ahead of
# the bookkeeping file. If a run ever dies between the upstream swap and the
# file write, the file names the slot that is no longer live — and believing
# it would make this run rebuild the container currently serving players.
ACTIVE=""
if [ -f "$PROXY_CONF" ]; then
  # -E: alternation in a BRE is a GNU extension, and this has to be readable
  # on any sed the box ships with.
  ACTIVE=$(sed -nE 's/.*server tichu-online-(blue|green):3000;.*/\1/p' "$PROXY_CONF" | head -1)
fi
if [ -n "$ACTIVE" ]; then
  FILE_ACTIVE=$(cat "$ACTIVE_FILE" 2>/dev/null || echo "")
  if [ -n "$FILE_ACTIVE" ] && [ "$FILE_ACTIVE" != "$ACTIVE" ]; then
    log "WARN: $ACTIVE_FILE says '$FILE_ACTIVE' but nginx routes to '$ACTIVE' — trusting nginx (previous deploy likely died mid-run)"
  fi
else
  ACTIVE=$(cat "$ACTIVE_FILE" 2>/dev/null || echo "blue")
  log "could not read upstream from $PROXY_CONF; falling back to $ACTIVE_FILE ($ACTIVE)"
fi
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
CONF_BACKUP="$PROXY_CONF.pre-$INACTIVE.$$"
cp "$PROXY_CONF" "$CONF_BACKUP"
sed "s|{{ACTIVE}}|$INACTIVE|g" "$TEMPLATE" > "$PROXY_CONF.new"
mv "$PROXY_CONF.new" "$PROXY_CONF"
# From here until the reload is confirmed, the file is ahead of what nginx is
# serving. Any failure exits non-zero and the EXIT trap puts the old conf back.
if ! docker exec nginx nginx -t; then
  log "ABORT: nginx config test failed"
  exit 1
fi
if ! docker exec nginx nginx -s reload; then
  log "ABORT: nginx reload failed"
  exit 1
fi
# Reload confirmed — the file now matches reality. Clear the guard BEFORE
# deleting the backup: if we died between the two, a stray backup file is
# harmless, whereas a still-armed guard would roll back a swap that worked.
CONFIRMED_BACKUP="$CONF_BACKUP"
CONF_BACKUP=""
rm -f "$CONFIRMED_BACKUP"
# Record the swap HERE, not after the drain. Traffic has already moved; if the
# script dies during the drain below (SSH drop, CI kill, reboot) the file must
# already name the live slot, or the next deploy rebuilds the container that is
# serving players.
echo "$INACTIVE" > "$ACTIVE_FILE"
log "nginx reloaded — new connections route to $INACTIVE (active_slot updated)"

# ----- 6. Drain the outgoing slot (graceful stop, DRAIN_TIMEOUT_SEC grace) -----
log "stopping tichu-online-$ACTIVE with up to ${DRAIN_TIMEOUT_SEC}s drain grace"
docker compose --profile "$ACTIVE" stop -t "$DRAIN_TIMEOUT_SEC" "server-$ACTIVE" || true
docker compose --profile "$ACTIVE" rm -f "server-$ACTIVE" || true

# ----- 7. Done (active_slot was already persisted at the swap) -----
log "done. active=$INACTIVE"
