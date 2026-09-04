#!/bin/sh
set -eu

BASE=/data/proxy-mode
BIN="$BASE/bin/sing-box"
CONF="$BASE/runtime/active.json"
PID="$BASE/runtime/sing-box.pid"
LOG="$BASE/logs/sing-box.log"
TRAFFIC="$BASE/scripts/traffic.sh"

[ -x "$BIN" ] || { echo "sing-box binary missing: $BIN" >&2; exit 1; }
[ -f "$CONF" ] || { echo "active config missing: $CONF" >&2; exit 1; }
mkdir -p "$BASE/runtime" "$BASE/logs"

if [ -f "$PID" ] && kill -0 "$(cat "$PID" 2>/dev/null)" 2>/dev/null; then
    [ -x "$TRAFFIC" ] && "$TRAFFIC" apply || true
    echo "sing-box already running"
    exit 0
fi

"$BIN" check -c "$CONF"
nohup "$BIN" run -c "$CONF" >>"$LOG" 2>&1 </dev/null &
echo $! > "$PID"
sleep 1

if kill -0 "$(cat "$PID")" 2>/dev/null; then
    [ -x "$TRAFFIC" ] && "$TRAFFIC" apply || true
    echo "sing-box started: pid $(cat "$PID")"
else
    [ -x "$TRAFFIC" ] && "$TRAFFIC" clear || true
    echo "sing-box failed to start; see $LOG" >&2
    rm -f "$PID"
    exit 1
fi
