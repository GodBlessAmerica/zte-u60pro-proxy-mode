#!/bin/sh
set -eu
# Run from the extracted release directory, locally on the U60 Pro.
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE=/data/proxy-mode
CONTROL=/data/u60proxy
BACKUP="$CONTROL/backups/udp-capability-$(date +%Y%m%d-%H%M%S)"
[ "$(id -u)" = 0 ] || { echo "root required" >&2; exit 1; }
for f in "$ROOT/bin/u60proxy" "$ROOT/bin/proxy-mode" "$ROOT/scripts/traffic.sh"; do
    [ -s "$f" ] || { echo "missing $f" >&2; exit 1; }
done
[ -x "$BASE/bin/sing-box" ] || { echo "sing-box missing" >&2; exit 1; }
[ -f "$BASE/runtime/active.json" ] || { echo "active.json missing" >&2; exit 1; }
mkdir -p "$BACKUP" "$CONTROL/bin"
cp -p "$CONTROL/bin/u60proxy" "$BACKUP/u60proxy"
cp -p "$BASE/bin/proxy-mode" "$BACKUP/proxy-mode"
cp -p "$BASE/scripts/traffic.sh" "$BACKUP/traffic.sh"
echo "$BACKUP" > "$CONTROL/runtime/udp-capability-backup"
echo "Backup: $BACKUP"
# Replace running executables atomically: copying directly onto a running
# Go binary may fail with "Text file busy" on the vendor OpenWrt firmware.
for pair in \
    "$ROOT/bin/u60proxy:$CONTROL/bin/u60proxy" \
    "$ROOT/bin/proxy-mode:$BASE/bin/proxy-mode" \
    "$ROOT/scripts/traffic.sh:$BASE/scripts/traffic.sh"; do
    src="${pair%%:*}"
    dst="${pair#*:}"
    tmp="${dst}.udp-update.$"
    cp "$src" "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$dst"
done
# Apply safely: traffic.sh creates an independent UDP fail-closed chain before
# any change to the TUN; saved mode configs, credentials and device policy remain.
"$CONTROL/bin/u60proxy" apply
# Restart only the web child (supervisor automatically respawns it).
for p in $(ps w | grep '/data/u60proxy/bin/u60proxy serve' | grep -v grep | awk '{print $1}'); do
    kill "$p" 2>/dev/null || true
done
echo "Installed. Check: $BASE/bin/proxy-mode status"
echo "Rollback: sh $ROOT/rollback-udp-capability.sh"
