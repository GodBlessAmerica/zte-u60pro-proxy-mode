#!/bin/sh
set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DST=/data/proxy-mode

[ "$(id -u)" = "0" ] || { echo "run as root" >&2; exit 1; }
[ -w /data ] || { echo "/data is not writable" >&2; exit 1; }

mkdir -p "$DST/bin" "$DST/configs" "$DST/logs" "$DST/runtime" "$DST/web" "$DST/scripts"
cp "$SRC/bin/proxy-mode" "$DST/bin/proxy-mode"
cp "$SRC/scripts/preflight.sh" "$DST/scripts/preflight.sh"
cp "$SRC/scripts/start.sh" "$DST/scripts/start.sh"
cp "$SRC/scripts/stop.sh" "$DST/scripts/stop.sh"
cp "$SRC/web/index.html" "$DST/web/index.html"
cp "$SRC/web/app.js" "$DST/web/app.js"
cp "$SRC/web/style.css" "$DST/web/style.css"
chmod 755 "$DST/bin/proxy-mode" "$DST/scripts"/*.sh

if [ ! -f "$DST/configs/mode-example.json" ]; then
    cp "$SRC/configs/mode-example.json" "$DST/configs/mode-example.json"
fi

cat <<'EOF'
Installed project files under /data/proxy-mode.

Next steps:
  1) place an aarch64 sing-box binary at /data/proxy-mode/bin/sing-box
  2) chmod 755 /data/proxy-mode/bin/sing-box
  3) create /data/proxy-mode/configs/modeN.json
  4) run /data/proxy-mode/bin/proxy-mode preflight
  5) run /data/proxy-mode/bin/proxy-mode use N
  6) run /data/proxy-mode/bin/proxy-mode start

This installer does not change iptables, rc.local, the stock ZTE web UI, or firmware partitions.
EOF
