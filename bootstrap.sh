#!/bin/sh
set -eu

BASE_URL="https://raw.githubusercontent.com/GodBlessAmerica/zte-u60pro-proxy-mode/main"
TMP="/tmp/zte-u60pro-proxy-mode-main"

fail() { echo "[FAIL] $*" >&2; exit 1; }
fetch() {
    src="$1"
    dst="$2"
    mkdir -p "$(dirname "$dst")"

    if command -v wget >/dev/null 2>&1; then
        # Vendor wget can hang on IPv6/redirect paths. Force IPv4 and bound retries/timeouts.
        wget -4 -T 15 -t 2 -O "$dst" "$src" || fail "download failed: $src"
    elif command -v curl >/dev/null 2>&1; then
        curl -4 --connect-timeout 15 --max-time 30 --retry 1 -fsSL "$src" -o "$dst" || fail "download failed: $src"
    else
        fail "curl/wget missing"
    fi
}

rm -rf "$TMP"
mkdir -p "$TMP/bin" "$TMP/scripts" "$TMP/api" "$TMP/web" "$TMP/configs"

for f in \
    install.sh \
    bin/proxy-mode \
    scripts/preflight.sh \
    scripts/start.sh \
    scripts/stop.sh \
    scripts/install-sing-box.sh \
    api/proxy-api \
    web/index.html \
    web/app.js \
    web/style.css \
    configs/mode-example.json
do
    echo "[*] $f"
    fetch "$BASE_URL/$f" "$TMP/$f"
done

chmod 755 "$TMP/install.sh" "$TMP/bin/proxy-mode" "$TMP/scripts"/*.sh "$TMP/api/proxy-api"
cd "$TMP"
exec sh ./install.sh
