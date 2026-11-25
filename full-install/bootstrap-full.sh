#!/bin/sh
set -eu
# Run on rooted compatible ZTE U60 Pro only.
BASE=https://github.com/GodBlessAmerica/zte-u60pro-proxy-mode/releases/download/v2.1.4
D=/tmp/u60pro-full-$$
[ "$(id -u)" = 0 ] || { echo "Run as root" >&2; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "Requires ARM64 U60 Pro" >&2; exit 1; }
[ ! -e /data/proxy-mode ] && [ ! -e /data/u60proxy ] || { echo "Existing installation detected. Use updater instead." >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || exit 1
umask 077
mkdir -p "$D"
wget -4 -T 60 -O "$D/u60pro-full.tar.gz" "$BASE/u60pro-full.tar.gz" || exit 1
wget -4 -T 60 -O "$D/SHA256SUMS-full" "$BASE/SHA256SUMS-full" || exit 1
(cd "$D" && sha256sum -c SHA256SUMS-full) || { echo "Checksum verification failed" >&2; exit 1; }
tar -xzf "$D/u60pro-full.tar.gz" -C "$D"
sh "$D/u60pro-full/install.sh"
echo "Extracted installation retained under $D"
