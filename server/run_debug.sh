#!/bin/bash
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
echo "Local server starting at ws://$IP:8080"
node server.js
