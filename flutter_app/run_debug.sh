#!/bin/bash
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
echo "Debug server IP: $IP"
flutter run --dart-define=DEBUG_SERVER_IP="$IP" "$@"
