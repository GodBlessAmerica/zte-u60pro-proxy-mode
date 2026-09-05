#!/bin/sh

BIN=/data/u60proxy/bin/u60proxy
RUNTIME=/data/u60proxy/runtime
LOG="$RUNTIME/web-startup.log"
PID="$RUNTIME/web-supervisor.pid"
mkdir -p "$RUNTIME"

if [ -s "$PID" ]; then
    p="$(cat "$PID" 2>/dev/null)"
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null && exit 0
fi

(
    echo $$ > "$PID"
    trap 'rm -f "$PID"' EXIT INT TERM

    i=0
    while [ "$i" -lt 60 ]; do
        ip addr show br-lan 2>/dev/null | grep -q '10\.66\.0\.1/' && break
        sleep 1
        i=$((i + 1))
    done

    sleep 2
    "$BIN" scan >> "$LOG" 2>&1 || true

    while true; do
        echo "===== $(date) u60proxy web start =====" >> "$LOG"
        "$BIN" serve >> "$LOG" 2>&1 || true
        echo "===== $(date) u60proxy web exited; retry in 3s =====" >> "$LOG"
        sleep 3
    done
) </dev/null >/dev/null 2>&1 &

exit 0
