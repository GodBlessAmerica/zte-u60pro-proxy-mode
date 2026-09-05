#!/bin/sh
set -eu

BASE=/data/proxy-mode
PID="$BASE/runtime/sing-box.pid"
TRAFFIC="$BASE/scripts/traffic.sh"
UDP_TUN="$BASE/scripts/udp-tun.sh"
LEGACY_TPROXY="$BASE/scripts/udp-tproxy.sh"

# Remove mode-specific UDP policy routing before traffic chains or the TUN vanish.
[ -x "$UDP_TUN" ] && "$UDP_TUN" off >/dev/null 2>&1 || true
[ -x "$LEGACY_TPROXY" ] && "$LEGACY_TPROXY" off >/dev/null 2>&1 || true
[ -x "$TRAFFIC" ] && "$TRAFFIC" clear || true

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
