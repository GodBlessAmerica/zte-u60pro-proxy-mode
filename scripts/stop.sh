#!/bin/sh
set -eu

BASE=/data/proxy-mode
PID="$BASE/runtime/sing-box.pid"

if [ ! -f "$PID" ]; then
    echo "sing-box not running"
    exit 0
fi

P="$(cat "$PID" 2>/dev/null || true)"
if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then
    kill "$P" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
        kill -0 "$P" 2>/dev/null || break
        sleep 1
    done
    kill -9 "$P" 2>/dev/null || true
fi
rm -f "$PID"
echo "sing-box stopped"
