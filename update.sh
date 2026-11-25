#!/bin/sh
set -eu
umask 077
URL=https://github.com/GodBlessAmerica/zte-u60pro-proxy-mode/releases/download/v2.1.4
D="$(mktemp -d /tmp/u60pro-upgrade-XXXXXX)"
[ "$(id -u)" = 0 ] && [ "$(uname -m)" = aarch64 ] || { echo 'Root ARM64 required'; exit 1; }
[ -x /data/u60proxy/bin/u60proxy ] && [ -x /data/proxy-mode/bin/sing-box ] || { echo 'Existing installation required; use clean installer instead'; exit 1; }
fetch(){ if command -v curl >/dev/null 2>&1; then curl -fL --retry 2 --connect-timeout 20 -o "$2" "$1"; else wget -T 60 -O "$2" "$1"; fi; }
fetch "$URL/u60pro-upgrade.tar.gz" "$D/u60pro-upgrade.tar.gz"
fetch "$URL/SHA256SUMS-upgrade" "$D/SHA256SUMS-upgrade"
(cd "$D" && sha256sum -c SHA256SUMS-upgrade)
tar -xzf "$D/u60pro-upgrade.tar.gz" -C "$D"
sh "$D/u60pro-upgrade/install-v2.1.4.sh"
echo "Package retained: $D"
