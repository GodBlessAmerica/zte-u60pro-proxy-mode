#!/bin/sh
set -eu

BASE=/data/proxy-mode
SCRIPT="$BASE/scripts/log-guard.sh"
PID="$BASE/runtime/log-guard.pid"
LOG="$BASE/logs/log-guard-daemon.log"

mkdir -p "$BASE/runtime" "$BASE/logs"

if [ -f "$PID" ]; then
    old="$(cat "$PID" 2>/dev/null || true)"
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
        exit 0
    fi
    rm -f "$PID"
fi

[ -x "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }

nohup "$SCRIPT" daemon >>"$LOG" 2>&1 </dev/null &
echo $! > "$PID"
sleep 1
kill -0 "$(cat "$PID")" 2>/dev/null
