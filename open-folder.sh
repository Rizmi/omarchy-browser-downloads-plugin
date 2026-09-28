#!/usr/bin/env bash
# Managed by io.github.rizmi.browser-downloads
set -euo pipefail

TARGET="${1:-$HOME/Downloads}"
CMD="${2:-nautilus}"

SELECT_FILE=""
if [ -f "$TARGET" ]; then
  SELECT_FILE="$TARGET"
  DIR="$(dirname "$TARGET")"
elif [ -d "$TARGET" ]; then
  DIR="$TARGET"
else
  DIR="$HOME/Downloads"
fi

if [ -n "$CMD" ]; then
  if [ "$CMD" = "nautilus" ]; then
    if [ -n "$SELECT_FILE" ]; then
      exec setsid uwsm-app -- nautilus --select "$SELECT_FILE" 2>/dev/null || exec setsid nautilus --select "$SELECT_FILE" 2>/dev/null || exec nautilus "$DIR" 2>/dev/null || exec xdg-open "$DIR"
    else
      exec setsid uwsm-app -- nautilus --new-window "$DIR" 2>/dev/null || exec setsid nautilus "$DIR" 2>/dev/null || exec xdg-open "$DIR"
    fi
  fi

  # Custom binary (e.g. strata, dolphin, thunar)
  if command -v "$CMD" >/dev/null 2>&1; then
    exec setsid uwsm-app -- "$CMD" "$DIR" 2>/dev/null || exec setsid "$CMD" "$DIR" 2>/dev/null || exec "$CMD" "$DIR"
  fi
fi

# Fallback
exec setsid uwsm-app -- xdg-open "$DIR" 2>/dev/null || exec xdg-open "$DIR"
