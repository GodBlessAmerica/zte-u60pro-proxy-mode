#!/bin/sh
set -eu
BASE=/data/proxy-mode
CONTROL=/data/u60proxy
B="$(cat "$CONTROL/runtime/udp-capability-backup" 2>/dev/null || true)"
[ -n "$B" ] && [ -d "$B" ] || { echo "backup missing" >&2; exit 1; }
for f in u60proxy proxy-mode traffic.sh; do [ -s "$B/$f" ] || { echo "missing backup: $f" >&2; exit 1; }; done
cp -p "$B/u60proxy" "$CONTROL/bin/u60proxy"
cp -p "$B/proxy-mode" "$BASE/bin/proxy-mode"
cp -p "$B/traffic.sh" "$BASE/scripts/traffic.sh"
"$CONTROL/bin/u60proxy" apply || true
for p in $(ps w | grep '/data/u60proxy/bin/u60proxy serve' | grep -v grep | awk '{print $1}'); do kill "$p" 2>/dev/null || true; done
echo "Restored from $B"
