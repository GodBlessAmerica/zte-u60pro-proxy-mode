#!/bin/sh
set -eu

VERSION="1.14.0"
ARCHIVE="sing-box_${VERSION}_openwrt_aarch64_cortex-a53.ipk"
URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/${ARCHIVE}"
SHA256="c344b12633c5acbdd10749a4390dd87980524ed021da07bf784ec0924145be6c"
BASE=/data/proxy-mode
TMP=/tmp/u60-sing-box-install

fail() { echo "[FAIL] $*" >&2; exit 1; }
ok() { echo "[ OK ] $*"; }

[ "$(uname -m 2>/dev/null || true)" = "aarch64" ] || fail "this installer requires aarch64"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum missing"
command -v tar >/dev/null 2>&1 || fail "tar missing"
mkdir -p "$BASE/bin"
rm -rf "$TMP"
mkdir -p "$TMP/pkg" "$TMP/root"

PKG="$TMP/$ARCHIVE"
if [ -n "${U60_SINGBOX_IPK:-}" ]; then
    [ -f "$U60_SINGBOX_IPK" ] || fail "local package not found: $U60_SINGBOX_IPK"
    echo "Using local package: $U60_SINGBOX_IPK"
    cp "$U60_SINGBOX_IPK" "$PKG"
else
    echo "Downloading sing-box v$VERSION..."
    if command -v wget >/dev/null 2>&1; then
        wget -4 -T 30 -O "$PKG" "$URL" || fail "download failed; copy $ARCHIVE to the router and run: U60_SINGBOX_IPK=/path/to/$ARCHIVE $0"
    elif command -v curl >/dev/null 2>&1; then
        curl -4 --connect-timeout 20 --max-time 120 -fL "$URL" -o "$PKG" || fail "download failed"
    else
        fail "wget/curl missing"
    fi
fi

actual="$(sha256sum "$PKG" | awk '{print $1}')"
[ "$actual" = "$SHA256" ] || fail "SHA256 mismatch: $actual"
ok "package SHA256 verified"

# OpenWrt .ipk files are ar archives. Some vendor systems do not expose /usr/bin/ar,
# so support both a standalone ar binary and the BusyBox ar applet.
if command -v ar >/dev/null 2>&1; then
    (
        cd "$TMP/pkg"
        ar x "$PKG"
    ) || fail "failed to unpack IPK with ar"
elif command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx ar; then
    (
        cd "$TMP/pkg"
        busybox ar x "$PKG"
    ) || fail "failed to unpack IPK with busybox ar"
else
    fail "IPK is an ar archive but this device has no ar applet; run: command -v ar; busybox --list | grep '^ar$'"
fi

DATA=""
for f in "$TMP/pkg"/data.tar.gz "$TMP/pkg"/data.tar.xz "$TMP/pkg"/data.tar "$TMP/pkg"/data.tar.zst; do
    [ -f "$f" ] && DATA="$f" && break
done
[ -n "$DATA" ] || fail "data archive not found in IPK"

case "$DATA" in
    *.zst)
        if tar --help 2>&1 | grep -qi zstd; then
            tar -xf "$DATA" -C "$TMP/root"
        elif command -v zstd >/dev/null 2>&1; then
            zstd -dc "$DATA" | tar -xf - -C "$TMP/root"
        else
            fail "package uses data.tar.zst but this device cannot decompress zstd"
        fi
        ;;
    *)
        tar -xf "$DATA" -C "$TMP/root"
        ;;
esac

[ -f "$TMP/root/usr/bin/sing-box" ] || fail "usr/bin/sing-box not found in package"
cp "$TMP/root/usr/bin/sing-box" "$BASE/bin/sing-box.new"
chmod 755 "$BASE/bin/sing-box.new"
"$BASE/bin/sing-box.new" version >/dev/null 2>&1 || fail "extracted binary cannot run on this device"
mv "$BASE/bin/sing-box.new" "$BASE/bin/sing-box"

ok "installed $($BASE/bin/sing-box version 2>/dev/null | head -1)"
rm -rf "$TMP"
