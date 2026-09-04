#!/bin/sh
set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DST=/data/proxy-mode
WEBROOT=/data/www/proxy-mode
CGIROOT=/data/www/cgi-bin

[ "$(id -u)" = "0" ] || { echo "run as root" >&2; exit 1; }
[ -w /data ] || { echo "/data is not writable" >&2; exit 1; }

mkdir -p "$DST/bin" "$DST/configs" "$DST/logs" "$DST/runtime" "$DST/scripts"
mkdir -p "$WEBROOT" "$CGIROOT"

cp "$SRC/bin/proxy-mode" "$DST/bin/proxy-mode"
cp "$SRC/scripts/preflight.sh" "$DST/scripts/preflight.sh"
cp "$SRC/scripts/start.sh" "$DST/scripts/start.sh"
cp "$SRC/scripts/stop.sh" "$DST/scripts/stop.sh"
cp "$SRC/scripts/traffic.sh" "$DST/scripts/traffic.sh"
cp "$SRC/scripts/install-sing-box.sh" "$DST/scripts/install-sing-box.sh"
chmod 755 "$DST/bin/proxy-mode" "$DST/scripts"/*.sh

cp "$SRC/web/index.html" "$WEBROOT/index.html"
cp "$SRC/web/app.js" "$WEBROOT/app.js"
cp "$SRC/web/style.css" "$WEBROOT/style.css"
cp "$SRC/api/proxy-api" "$CGIROOT/proxy-api"
chmod 755 "$CGIROOT/proxy-api"

if [ ! -f "$DST/configs/mode-example.json" ]; then
    cp "$SRC/configs/mode-example.json" "$DST/configs/mode-example.json"
fi

if [ ! -s "$DST/runtime/web.token" ]; then
    if command -v hexdump >/dev/null 2>&1; then
        head -c 24 /dev/urandom | hexdump -ve '1/1 "%02x"' > "$DST/runtime/web.token"
    else
        date +%s | sha256sum | awk '{print $1}' > "$DST/runtime/web.token"
    fi
    chmod 600 "$DST/runtime/web.token"
fi

cat <<EOF
Installed project files under $DST.
Dashboard files: $WEBROOT
CGI API: $CGIROOT/proxy-api

Web control token:
$(cat "$DST/runtime/web.token")

Keep this token private. Do not paste it into issue reports or public logs.

Next steps:
  1) install or place sing-box at /data/proxy-mode/bin/sing-box
  2) create /data/proxy-mode/configs/modeN.json
  3) /data/proxy-mode/bin/proxy-mode preflight
  4) /data/proxy-mode/bin/proxy-mode use N
  5) /data/proxy-mode/bin/proxy-mode start
  6) /data/proxy-mode/bin/proxy-mode traffic on|off|selective

If the isolated OpenUI uhttpd is already running on :8080, open:
  http://10.66.0.1:8080/proxy-mode/

This installer never changes rc.local, the stock ZTE web UI, or firmware partitions. Transparent proxy rules are isolated in the U60PM_REDIRECT chain and can be removed with 'proxy-mode traffic off' or 'proxy-mode stop'.
EOF
