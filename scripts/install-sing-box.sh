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
if command -v wget >/dev/null 2>&1; then
    echo "Downloading sing-box v$VERSION..."
    wget -O "$PKG" "$URL" || fail "download failed; copy $ARCHIVE to $PKG and rerun with U60_SINGBOX_IPK=/path/to/file"
elif command -v curl >/dev/null 2>&1; then
    echo "Downloading sing-box v$VERSION..."
    curl -fL "$URL" -o "$PKG" || fail "download failed"
else
    fail "wget/curl missing"
fi

actual="$(sha256sum "$PKG" | awk '{print $1}')"
[ "$actual" = "$SHA256" ] || fail "SHA256 mismatch: $actual"
ok "package SHA256 verified"

(
    cd "$TMP/pkg"
    tar -xf "$PKG"
)

DATA=""
for f in "$TMP/pkg"/data.tar.gz "$TMP/pkg"/data.tar.xz "$TMP/pkg"/data.tar; do
    [ -f "$f" ] && DATA="$f" && break
done

if [ -z "$DATA" ] && [ -f "$TMP/pkg/data.tar.zst" ]; then
    if tar --help 2>&1 | grep -qi zstd; then
        DATA="$TMP/pkg/data.tar.zst"
    elif command -v zstd >/dev/null 2>&1; then
        zstd -dc "$TMP/pkg/data.tar.zst" > "$TMP/pkg/data.tar"
        DATA="$TMP/pkg/data.tar"
    else
        fail "package uses data.tar.zst but this device cannot decompress zstd"
    fi
fi
[ -n "$DATA" ] || fail "data archive not found in IPK"

tar -xf "$DATA" -C "$TMP/root"
[ -f "$TMP/root/usr/bin/sing-box" ] || fail "usr/bin/sing-box not found in package"
cp "$TMP/root/usr/bin/sing-box" "$BASE/bin/sing-box.new"
chmod 755 "$BASE/bin/sing-box.new"
"$BASE/bin/sing-box.new" version >/dev/null 2>&1 || fail "extracted binary cannot run on this device"
mv "$BASE/bin/sing-box.new" "$BASE/bin/sing-box"

ok "installed $($BASE/bin/sing-box version 2>/dev/null | head -1)"
rm -rf "$TMP"
