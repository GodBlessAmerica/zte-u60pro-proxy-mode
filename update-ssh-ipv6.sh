#!/bin/sh
set -eu
URL=https://github.com/GodBlessAmerica/zte-u60pro-proxy-mode/releases/download/v2.2.0-ssh-ipv6
WORK=$(mktemp -d /tmp/u60-ssh6.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
fetch() {
 if command -v curl >/dev/null 2>&1; then curl -fL --connect-timeout 20 --max-time 180 "$1" -o "$2"
 else wget -O "$2" "$1"; fi
}
cd "$WORK"
fetch "$URL/u60proxy-2.2.0-ssh-ipv6.tar.gz" package.tar.gz
fetch "$URL/SHA256SUMS" SHA256SUMS
mv package.tar.gz u60proxy-2.2.0-ssh-ipv6.tar.gz
sha256sum -c SHA256SUMS
tar -xzf u60proxy-2.2.0-ssh-ipv6.tar.gz
sh u60proxy-2.2.0-ssh-ipv6/install-ssh-ipv6.sh
