#!/bin/sh
# Upgrade only the shell integration on an existing v2.1.3 installation.
set -eu
umask 077
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE=/data/proxy-mode
CONTROL=/data/u60proxy
BACKUP="$CONTROL/backups/ipv6-upstream-$(date +%Y%m%d-%H%M%S)-$$"
die(){ echo "$*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die 'Root required'
[ "$(uname -m)" = aarch64 ] || die 'ARM64 required'
for app in ip ip6tables jsonfilter; do command -v "$app" >/dev/null || die "Missing $app"; done
[ -d /sys/class/net/br-lan ] || die 'Missing LAN'
[ -d /sys/class/net/rmnet_data0 ] || die 'Missing cellular interface'
[ -x "$CONTROL/bin/u60proxy" ] || die 'Existing v2.1.3 installation required'
# Exit 0 or 1 is allowed because current profile need not support UDP.
# Verify the installed CLI advertises the mode-independent command.
probe_rc=0
probe="$("$CONTROL/bin/u60proxy" udp-capable 2>&1)" || probe_rc=$?
case "$probe" in *"u60proxy v2"*|*"Usage:"*) die 'Install the v2.1.3 UDP-capability release first';; esac
case "$probe_rc" in 0|1) ;; *) die 'UDP capability command failed';; esac
[ "$probe_rc" = 0 ] || case "$probe" in error:*) ;; *) die 'Cannot verify UDP capability command';; esac
[ -x "$BASE/bin/sing-box" ] || die 'Missing sing-box'
for f in bin/proxy-mode scripts/start.sh scripts/stop.sh scripts/traffic.sh scripts/udp-tun.sh; do
    [ -x "$BASE/$f" ] || die "Missing installed $f"
done
for f in bin/proxy-mode scripts/start.sh scripts/ipv6-upstream.sh rollback-ipv6-upstream.sh; do
    sh -n "$ROOT/$f" || die "Invalid shell file $f"
done
mkdir -p "$BACKUP/bin" "$BACKUP/scripts" "$CONTROL/runtime"
for f in bin/proxy-mode scripts/start.sh scripts/ipv6-upstream.sh; do
    if [ -e "$BASE/$f" ]; then cp -p "$BASE/$f" "$BACKUP/$f"; fi
done
printf '%s\n' "$BACKUP" > "$CONTROL/runtime/ipv6-upstream-backup"
# Install helper first; existing running proxy and all private profiles untouched.
for f in scripts/ipv6-upstream.sh scripts/start.sh bin/proxy-mode; do
    tmp="$BASE/$f.new.$$"
    cp "$ROOT/$f" "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$BASE/$f"
done
mkdir -p "$CONTROL/bin"
cp "$ROOT/rollback-ipv6-upstream.sh" "$CONTROL/bin/rollback-ipv6-upstream"
chmod 700 "$CONTROL/bin/rollback-ipv6-upstream"
echo 'IPv6 upstream integration installed; active proxy not restarted.'
echo "Backup: $BACKUP"
echo "Template: $ROOT/configs/mode13-ipv6-upstream.example.json"
echo 'Use a new unused mode number and fill node credentials locally.'
