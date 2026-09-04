#!/bin/sh
set -eu

BASE_URL="https://raw.githubusercontent.com/GodBlessAmerica/zte-u60pro-proxy-mode/main"
TMP="/tmp/zte-u60pro-proxy-mode-main"

fail() { echo "[FAIL] $*" >&2; exit 1; }
fetch() {
    src="$1"
    dst="$2"
    mkdir -p "$(dirname "$dst")"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$src" -o "$dst" || fail "download failed: $src"
    elif command -v wget >/dev/null 2>&1; then
        # raw.githubusercontent.com is used deliberately: no github.com -> codeload redirect.
        wget -O "$dst" "$src" || fail "download failed: $src"
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
