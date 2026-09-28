#!/usr/bin/env python3
"""
Browser Download CLI Monitor
Reads live streaming download data from /tmp/browser-downloads.json (or /tmp/zen-downloads.json)
"""

import sys
import os
import time
import json
import argparse

STREAM_FILES = ["/tmp/browser-downloads.json", "/tmp/zen-downloads.json"]

def format_bytes(b):
    if b is None or b <= 0:
        return "0 B"
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if b < 1024.0:
            return f"{b:.1f} {unit}"
        b /= 1024.0
    return f"{b:.1f} PB"

def format_speed(bps):
    if not bps or bps <= 0:
        return "0 B/s"
    return f"{format_bytes(bps)}/s"

def format_eta(seconds):
    if seconds is None or seconds < 0:
        return "--"
    if seconds < 60:
        return f"{seconds}s"
    m, s = divmod(seconds, 60)
    if m < 60:
        return f"{m}m {s}s"
    h, m = divmod(m, 60)
    return f"{h}h {m}m"

def render_progress_bar(percent, width=28):
    if percent is None:
        return "[" + "?" * width + "]"
    pct = min(100, max(0, percent))
    filled = int(width * (pct / 100))
    bar = "=" * filled
    if filled < width:
        bar += ">"
        bar += " " * (width - filled - 1)
    return f"[{bar}]"

def read_data():
    for path in STREAM_FILES:
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                continue
    return None

def display_dashboard(data):
    if not data or not data.get("downloads"):
        print("\033[2J\033[H", end="")
        print("\033[1;36m=== Browser Download Monitor ===\033[0m")
        print("\033[90mNo active downloads.\033[0m")
        return

    downloads = data.get("downloads", [])
    print("\033[2J\033[H", end="")
    print(f"\033[1;36m=== Browser Download Monitor ({len(downloads)} tracking) ===\033[0m\n")

    for dl in downloads:
        fname = dl.get("filename", "Unknown")
        pct = dl.get("percent")
        pct_str = f"{pct:.1f}%" if pct is not None else "--"
        downloaded_bytes = dl.get("downloaded_bytes", 0)
        total_bytes = dl.get("total_bytes")
        bytes_left = dl.get("bytes_left")

        downloaded_str = format_bytes(downloaded_bytes)
        total_str = format_bytes(total_bytes) if (total_bytes and total_bytes > 0) else "Unknown size"
        left_str = f" • \033[1;33m{format_bytes(bytes_left)} left\033[0m" if bytes_left is not None else ""

        speed = format_speed(dl.get("speed_bps", 0))
        eta = format_eta(dl.get("eta_seconds"))
        state = dl.get("state", "in_progress")
        paused = " \033[1;31m[PAUSED]\033[0m" if dl.get("paused") else ""

        if state == "complete":
            bar = "[" + "=" * 24 + "]"
            color = "\033[1;32m"
            status_line = f"{color}✔ COMPLETED\033[0m  |  Total: {downloaded_str}"
        elif state == "interrupted":
            bar = render_progress_bar(pct, width=24)
            color = "\033[1;31m"
            status_line = f"{color}✖ INTERRUPTED\033[0m"
        else:
            bar = render_progress_bar(pct, width=24)
            color = "\033[34m"
            status_line = f"\033[1;33m{pct_str:>6}\033[0m  |  \033[36m{speed:<11}\033[0m  |  ETA: \033[35m{eta}\033[0m"

        print(f"\033[1;37m{fname}\033[0m{paused}")
        print(f" {color}{bar}\033[0m {status_line}")
        if state != "complete":
            print(f" \033[90mProgress: {downloaded_str} of {total_str}{left_str}\033[0m")
        print()

def waybar_output(data):
    if not data or not data.get("downloads"):
        print(json.dumps({"text": "", "tooltip": "No downloads"}))
        return

    dls = [d for d in data.get("downloads", []) if d.get("state") == "in_progress"]
    if not dls:
        print(json.dumps({"text": "", "tooltip": "No active downloads"}))
        return

    first = dls[0]
    pct = f"{first.get('percent', 0):.0f}%" if first.get("percent") is not None else ".."
    speed = format_speed(first.get("speed_bps", 0))
    count = f" (+{len(dls)-1})" if len(dls) > 1 else ""

    text = f" {pct} @ {speed}{count}"
    tooltip = "\n".join([
        f"{d.get('filename')}: {d.get('percent', 0)}% of {format_bytes(d.get('total_bytes'))} - {format_speed(d.get('speed_bps', 0))} - {format_eta(d.get('eta_seconds'))} left"
        for d in dls
    ])
    print(json.dumps({"text": text, "tooltip": tooltip, "class": "downloading"}))

def main():
    parser = argparse.ArgumentParser(description="Monitor browser downloads outside the browser.")
    parser.add_argument("-w", "--watch", action="store_true", help="Continuously watch downloads in terminal")
    parser.add_argument("-j", "--json", action="store_true", help="Print raw JSON state")
    parser.add_argument("--waybar", action="store_true", help="Format output for Waybar / status bar JSON")
    args = parser.parse_args()

    if args.json:
        data = read_data()
        print(json.dumps(data, indent=2) if data else "{}")
        return

    if args.waybar:
        data = read_data()
        waybar_output(data)
        return

    if args.watch:
        try:
            while True:
                data = read_data()
                display_dashboard(data)
                time.sleep(0.25)
        except KeyboardInterrupt:
            print("\nExiting monitor.")
    else:
        data = read_data()
        display_dashboard(data)

if __name__ == "__main__":
    main()
