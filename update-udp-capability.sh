#!/bin/sh
set -eu
# Safe bootstrap for supported ZTE U60 Pro (ARM64) devices with existing v2 control plane.
TAG=v2.1.3-udp-capability
REPO=https://github.com/GodBlessAmerica/zte-u60pro-proxy-mode
URL="$REPO/releases/download/$TAG"
NAME=u60proxy-udp-capability.tar.gz
DEST=/tmp/u60proxy-udp-update-$$
fail(){ echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail "Run as root"
case "$(uname -m)" in aarch64|arm64) ;; *) fail "Unsupported CPU architecture (ARM64 required)";; esac
[ -x /data/u60proxy/bin/u60proxy ] || fail "Existing u60proxy v2 installation is required"
[ -x /data/proxy-mode/bin/sing-box ] || fail "Existing sing-box installation is required"
command -v wget >/dev/null 2>&1 || fail "wget required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum required"
mkdir -p "$DEST"
echo "Downloading $TAG into $DEST"
wget -O "$DEST/$NAME" "$URL/$NAME" || fail "Package download failed"
wget -O "$DEST/SHA256SUMS" "$URL/SHA256SUMS" || fail "Checksum download failed"
(cd "$DEST" && sha256sum -c SHA256SUMS) || fail "SHA256 mismatch; refusing install"
tar -xzf "$DEST/$NAME" -C "$DEST" || fail "Invalid archive"
sh "$DEST/u60proxy-udp-capability/install-udp-capability.sh"
echo "Downloaded package retained at $DEST for rollback"
