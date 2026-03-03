#!/bin/bash
set -e

cd /opt/services/tichu-online

git pull origin main

docker compose build --no-cache server
docker compose up -d

docker image prune -f
