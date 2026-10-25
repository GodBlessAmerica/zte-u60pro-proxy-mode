#!/bin/sh
set -eu
URL=https://github.com/GodBlessAmerica/zte-u60pro-proxy-mode/releases/download/v2.3.0-vless-dualstack
WORK=$(mktemp -d /tmp/u60-vless6-download.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
fetch(){
 if command -v curl >/dev/null 2>&1; then curl --http1.1 -fL --connect-timeout 20 --max-time 180 --retry 2 "$1" -o "$2"
 else wget -O "$2" "$1"; fi
}
cd "$WORK"
fetch "$URL/u60-vless-dualstack.tar.gz" u60-vless-dualstack.tar.gz
fetch "$URL/SHA256SUMS" SHA256SUMS
sha256sum -c SHA256SUMS
tar -xzf u60-vless-dualstack.tar.gz
sh u60-vless-dualstack/install-online.sh
