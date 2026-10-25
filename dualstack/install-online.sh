#!/bin/sh
set -eu
SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
[ "$(id -u)" = 0 ] || { echo 'Run in U60 root shell'; exit 1; }
CFG=/data/proxy-mode/configs/mode11.json
[ -f "$CFG" ] || { echo 'Existing VLESS Mode 11 config is required'; exit 1; }
[ -x "$SRC/bin/u60-vless6-config" ] || { echo 'Use the release package with ARM64 config tool'; exit 1; }
WORK=$(mktemp -d /tmp/u60-vless6-config.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
"$SRC/bin/u60-vless6-config" "$CFG" "$WORK/mode11.json"
sh "$SRC/install.sh" "$WORK/mode11.json"
mkdir -p /data/u60-vless-dualstack
cp "$SRC/check.sh" /data/u60-vless-dualstack/check.sh
cp "$SRC/rollback.sh" /data/u60-vless-dualstack/rollback.sh
chmod 755 /data/u60-vless-dualstack/check.sh /data/u60-vless-dualstack/rollback.sh
echo 'Online update complete. Node credentials preserved locally; no ADB or config upload used.'
