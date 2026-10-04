#!/usr/bin/env bash
# Managed by io.github.rizmi.browser-downloads
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
HOST_DIR="$HOME/.mozilla/native-messaging-hosts"

mkdir -p "$BIN_DIR" "$HOST_DIR"

echo "Registering Downlink native messaging host..."

# 1. Install streamer binary
TARGET_BIN="$BIN_DIR/browser_download_streamer.py"
[ -L "$TARGET_BIN" ] && rm -f "$TARGET_BIN"
TMP_BIN=$(mktemp -p "$BIN_DIR" .streamer.tmp.XXXXXX)
cp "$SCRIPT_DIR/native-host/browser_download_streamer.py" "$TMP_BIN"
chmod 0755 "$TMP_BIN"
mv -f "$TMP_BIN" "$TARGET_BIN"

# 2. Register native messaging manifest
MANIFEST_CONTENT=$(cat <<EOF
{
  "name": "browser_download_streamer",
  "description": "Streams browser download status to local system",
  "path": "$TARGET_BIN",
  "type": "stdio",
  "allowed_extensions": [
    "browser-download-streamer@rizmi.dev"
  ]
}
EOF
)

TARGET_DIRS=(
  "$HOST_DIR"
  "$HOME/.config/zen/native-messaging-hosts"
  "$HOME/.var/app/app.zen_browser.zen/.mozilla/native-messaging-hosts"
  "$HOME/.var/app/org.mozilla.firefox/.mozilla/native-messaging-hosts"
)

for dir in "${TARGET_DIRS[@]}"; do
  if [ -d "$(dirname "$dir")" ] || [ "$dir" = "$HOST_DIR" ]; then
    mkdir -p "$dir"
    target="$dir/browser_download_streamer.json"
    [ -L "$target" ] && rm -f "$target"
    tmp=$(mktemp -p "$dir" .manifest.tmp.XXXXXX)
    printf "%s\n" "$MANIFEST_CONTENT" > "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$target"
    echo "  Installed to $target"
  fi
done

echo "Native messaging host registered successfully!"
