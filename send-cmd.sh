#!/usr/bin/env bash
# Managed by io.github.rizmi.browser-downloads
set -euo pipefail

ACTION="${1:-}"
DL_ID="${2:-}"

if [ -z "$ACTION" ] || [ -z "$DL_ID" ]; then
  exit 0
fi

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
SOCK_PATH="$RUNTIME_DIR/browser-downloads.sock"

if [ ! -S "$SOCK_PATH" ]; then
  exit 0
fi

python3 -c "
import socket, sys, json
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sys.argv[1])
    s.sendall(json.dumps({'action': sys.argv[2], 'id': int(sys.argv[3])}).encode('utf-8'))
    s.close()
except Exception:
    pass
" "$SOCK_PATH" "$ACTION" "$DL_ID" 2>/dev/null || true
