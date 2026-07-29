#!/usr/bin/env bash
# Run the game server locally with profile-photo storage working.
#
# Why this exists: server.js reads MinIO settings from the environment and
# nothing else — there is no dotenv, so `node server.js` on its own starts with
# storage DISABLED. That is not a soft failure: buying the profile-photo item is
# refused outright (we won't take gold for an entitlement that can't be used),
# so the whole feature is untestable without these variables.
#
# Production serves images through nginx at /media/profile-photos/. There is no
# nginx here, so MINIO_PUBLIC_BASE points straight at MinIO instead, and the
# bucket allows anonymous GET (see setup below). The phone has to reach it too,
# hence the LAN address rather than localhost.
#
#   ./run-local.sh            # start MinIO if needed, then the server
#   ./run-local.sh --no-minio # assume MinIO is already running
set -euo pipefail

cd "$(dirname "$0")"

# Free the port before starting. SIGTERM is deliberately NOT used: it triggers
# the production drain, which holds the port until every room empties — so a
# restart while you are sitting in a test room hangs forever and the new
# process dies on EADDRINUSE. Locally there is nothing to drain to.
if command -v lsof >/dev/null 2>&1; then
  OLD_PIDS=$(lsof -tiTCP:"${PORT:-8080}" -sTCP:LISTEN 2>/dev/null || true)
  if [ -n "$OLD_PIDS" ]; then
    echo "[local] stopping previous server ($OLD_PIDS)"
    # shellcheck disable=SC2086
    kill -9 $OLD_PIDS 2>/dev/null || true
    sleep 1
  fi
fi

MINIO_BIN="${MINIO_BIN:-$HOME/.local/bin/minio}"
MINIO_DATA="${MINIO_DATA:-$HOME/.tichu-minio/data}"
MINIO_LOG="${MINIO_LOG:-$HOME/.tichu-minio/minio.log}"
BUCKET="${MINIO_BUCKET:-tichu-profile-photos}"
# Local-only development credentials. Nothing here reaches production.
KEY="${MINIO_ACCESS_KEY:-tichudev}"
SECRET="${MINIO_SECRET_KEY:-tichudev123}"

# The device on your desk fetches images by URL, so it needs an address that
# resolves off-machine. Falls back to localhost for simulator-only work.
LAN_IP="${LAN_IP:-$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo 127.0.0.1)}"

start_minio() {
  if curl -fsS -o /dev/null "http://127.0.0.1:9000/minio/health/live" 2>/dev/null; then
    echo "[local] MinIO already up"
    return
  fi
  if [ ! -x "$MINIO_BIN" ]; then
    echo "[local] MinIO binary not found at $MINIO_BIN" >&2
    echo "[local]   curl -fsSL -o \"$MINIO_BIN\" https://dl.min.io/server/minio/release/darwin-arm64/minio && chmod +x \"$MINIO_BIN\"" >&2
    exit 1
  fi
  mkdir -p "$MINIO_DATA" "$(dirname "$MINIO_LOG")"
  echo "[local] starting MinIO (data=$MINIO_DATA, log=$MINIO_LOG)"
  MINIO_ROOT_USER="$KEY" MINIO_ROOT_PASSWORD="$SECRET" \
    nohup "$MINIO_BIN" server "$MINIO_DATA" --address ":9000" --console-address ":9090" \
    >> "$MINIO_LOG" 2>&1 &
  for _ in $(seq 1 30); do
    curl -fsS -o /dev/null "http://127.0.0.1:9000/minio/health/live" 2>/dev/null && break
    sleep 0.5
  done
}

ensure_bucket() {
  MINIO_BUCKET="$BUCKET" MINIO_ACCESS_KEY="$KEY" MINIO_SECRET_KEY="$SECRET" node -e '
    const Minio = require("minio");
    const c = new Minio.Client({ endPoint: "127.0.0.1", port: 9000, useSSL: false,
      accessKey: process.env.MINIO_ACCESS_KEY, secretKey: process.env.MINIO_SECRET_KEY });
    const b = process.env.MINIO_BUCKET;
    (async () => {
      if (!await c.bucketExists(b)) { await c.makeBucket(b); console.log("[local] bucket created:", b); }
      // Anonymous GET on objects only. The app fetches avatars with a plain
      // request and holds no credentials; listing stays closed.
      await c.setBucketPolicy(b, JSON.stringify({
        Version: "2012-10-17",
        Statement: [{ Effect: "Allow", Principal: { AWS: ["*"] },
          Action: ["s3:GetObject"], Resource: [`arn:aws:s3:::${b}/*`] }],
      }));
    })().catch((e) => { console.error("[local] bucket setup failed:", e.message); process.exit(1); });
  '
}

if [ "${1:-}" != "--no-minio" ]; then
  start_minio
  ensure_bucket
fi

# Optional: image-moderation credentials. Kept outside the repo so a service
# account key can never be committed by accident; skip the file and uploads
# simply go unscreened, which is what a local box wants by default.
VISION_ENV="${VISION_ENV:-$HOME/.tichu-vision.env}"
if [ -f "$VISION_ENV" ]; then
  # shellcheck disable=SC1090
  set -a; . "$VISION_ENV"; set +a
  echo "[local] image moderation ON (from $VISION_ENV)"
else
  echo "[local] image moderation off (no $VISION_ENV)"
fi

echo "[local] server on http://$LAN_IP:8080  (photos via http://$LAN_IP:9000/$BUCKET)"
exec env \
  PORT="${PORT:-8080}" \
  INSTANCE_NAME="${INSTANCE_NAME:-local}" \
  MINIO_ENDPOINT=127.0.0.1 \
  MINIO_PORT=9000 \
  MINIO_USE_SSL=false \
  MINIO_BUCKET="$BUCKET" \
  MINIO_ACCESS_KEY="$KEY" \
  MINIO_SECRET_KEY="$SECRET" \
  MINIO_PUBLIC_BASE="http://$LAN_IP:9000/$BUCKET" \
  VISION_ENABLED="${VISION_ENABLED:-}" \
  VISION_SA_EMAIL="${VISION_SA_EMAIL:-}" \
  VISION_SA_PRIVATE_KEY="${VISION_SA_PRIVATE_KEY:-}" \
  node server.js
