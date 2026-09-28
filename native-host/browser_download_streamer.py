#!/usr/bin/env python3
# Managed by io.github.rizmi.browser-downloads
"""
Native Messaging Host for Browser Download Streamer
Receives real-time download status from Firefox/Zen/Gecko browsers
and listens on a local UNIX socket to forward control commands (cancel, pause, resume).
"""

import sys
import json
import struct
import os
import tempfile
import socket
import threading

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
TARGET_FILES = [
    os.path.join(RUNTIME_DIR, "browser-downloads.json"),
    "/tmp/browser-downloads.json",
    "/tmp/zen-downloads.json"
]
SOCK_PATH = os.path.join(RUNTIME_DIR, "browser-downloads.sock")

stdout_lock = threading.Lock()

def atomic_write_json(target_path, data):
    """Safely and atomically write JSON data without following symlinks."""
    target_dir = os.path.dirname(target_path)
    if not os.path.exists(target_dir):
        return

    # Never follow an existing symlink at target path
    if os.path.islink(target_path):
        try:
            os.unlink(target_path)
        except OSError:
            return

    tmp_name = None
    try:
        with tempfile.NamedTemporaryFile("w", dir=target_dir, prefix=".dl-", suffix=".tmp", delete=False, encoding="utf-8") as tf:
            tmp_name = tf.name
            json.dump(data, tf, indent=2)
            tf.flush()
            os.fsync(tf.fileno())

        os.replace(tmp_name, target_path)
    except Exception:
        if tmp_name and os.path.exists(tmp_name):
            try:
                os.unlink(tmp_name)
            except OSError:
                pass

def send_message_to_browser(obj):
    """Send a message or command to the browser via standard output."""
    with stdout_lock:
        try:
            encoded_payload = json.dumps(obj).encode("utf-8")
            sys.stdout.buffer.write(struct.pack("@I", len(encoded_payload)))
            sys.stdout.buffer.write(encoded_payload)
            sys.stdout.buffer.flush()
        except Exception:
            pass

def socket_listener():
    """Listens on a private UNIX domain socket for desktop control commands."""
    if os.path.exists(SOCK_PATH):
        try:
            os.unlink(SOCK_PATH)
        except OSError:
            pass

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        server.bind(SOCK_PATH)
        os.chmod(SOCK_PATH, 0o600)
        server.listen(5)
    except Exception:
        return

    while True:
        try:
            conn, _ = server.accept()
            with conn:
                raw_data = conn.recv(1024)
                if raw_data:
                    cmd = json.loads(raw_data.decode("utf-8"))
                    send_message_to_browser(cmd)
        except Exception:
            break

def read_message():
    """Read a message from standard input (Native Messaging 4-byte prefix)."""
    raw_length = sys.stdin.buffer.read(4)
    if not raw_length or len(raw_length) < 4:
        return None
    msg_length = struct.unpack("@I", raw_length)[0]
    raw_data = sys.stdin.buffer.read(msg_length)
    if not raw_data:
        return None
    return json.loads(raw_data.decode("utf-8"))

def main():
    # Start UNIX socket listener for desktop controls
    t = threading.Thread(target=socket_listener, daemon=True)
    t.start()

    try:
        while True:
            msg = read_message()
            if msg is None:
                break

            for target in TARGET_FILES:
                atomic_write_json(target, msg)

            send_message_to_browser({"status": "ok", "timestamp": msg.get("timestamp")})
    finally:
        if os.path.exists(SOCK_PATH):
            try:
                os.unlink(SOCK_PATH)
            except OSError:
                pass

if __name__ == "__main__":
    main()
