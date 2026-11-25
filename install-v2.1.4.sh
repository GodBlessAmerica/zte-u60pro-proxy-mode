#!/bin/sh
# Unified upgrade for an existing compatible U60 Pro installation.
set -eu
umask 077
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CORE=/data/proxy-mode
UI=/data/u60proxy
B="$UI/backups/v2.1.4-$(date +%Y%m%d-%H%M%S)-$$"
die(){ echo "$*" >&2; exit 1; }
[ "$(id -u)" = 0 ] && [ "$(uname -m)" = aarch64 ] || die 'Root ARM64 required'
for c in ip iptables ip6tables jsonfilter; do command -v "$c" >/dev/null || die "Missing $c"; done
[ -d /sys/class/net/br-lan ] && [ -d /sys/class/net/rmnet_data0 ] || die 'Unsupported network layout'
iptables -V | grep -qi legacy || die 'iptables-legacy required'
[ -x "$CORE/bin/sing-box" ] && [ -x "$CORE/bin/proxy-mode" ] && [ -x "$UI/bin/u60proxy" ] || die 'Existing installation required'
[ -d "$UI/state" ] && [ -d "$CORE/configs" ] && [ -d "$CORE/runtime" ] || die 'Missing existing state'
[ -x /data/start-u60proxy-v2.sh ] || die 'Existing web supervisor required'
for f in bin/proxy-mode scripts/start.sh scripts/stop.sh scripts/traffic.sh scripts/udp-tun.sh scripts/guard-control.sh scripts/ipv6-upstream.sh; do
    sh -n "$ROOT/$f" || die "Invalid $f"
done
[ -s "$ROOT/bin/u60proxy" ] || die 'Missing controller'
sh -n "$ROOT/rollback-v2.1.4.sh"
mkdir -p "$B" "$UI/runtime"
# Store original files and an explicit list of replaced paths; private profiles stay in place.
: > "$B/manifest"
for f in scripts/ipv6-upstream.sh scripts/start.sh scripts/stop.sh scripts/traffic.sh scripts/udp-tun.sh scripts/guard-control.sh bin/proxy-mode; do
    p="$CORE/$f"
    mkdir -p "$B/core/$(dirname "$f")"
    if [ -e "$p" ]; then cp -p "$p" "$B/core/$f"; fi
    printf 'core/%s\n' "$f" >> "$B/manifest"
done
for f in bin/u60proxy bin/rollback-v2.1.4 VERSION; do
    mkdir -p "$B/ui/$(dirname "$f")"
    if [ -e "$UI/$f" ]; then cp -p "$UI/$f" "$B/ui/$f"; fi
    printf 'ui/%s\n' "$f" >> "$B/manifest"
done
printf '%s\n' "$B" > "$UI/runtime/v2.1.4-backup"
replace(){ cp "$1" "$2.new.$$"; chmod "$3" "$2.new.$$"; mv -f "$2.new.$$" "$2"; }
# Restore originals if a replacement fails; no proxy restart during upgrade.
trap 'rc=$?; if [ "$rc" != 0 ]; then sh "$ROOT/rollback-v2.1.4.sh" || true; fi' EXIT
for f in scripts/ipv6-upstream.sh scripts/start.sh scripts/stop.sh scripts/traffic.sh scripts/udp-tun.sh scripts/guard-control.sh bin/proxy-mode; do
    replace "$ROOT/$f" "$CORE/$f" 755
done
replace "$ROOT/bin/u60proxy" "$UI/bin/u60proxy" 755
replace "$ROOT/rollback-v2.1.4.sh" "$UI/bin/rollback-v2.1.4" 700
replace "$ROOT/VERSION" "$UI/VERSION" 644
for p in $(ps w | awk '$0 ~ /\/data\/u60proxy\/bin\/u60proxy serve/ && $0 !~ /awk/ {print $1}'); do kill "$p" 2>/dev/null || true; done
echo "Installed v2.1.4 candidate; running sing-box and firewall left unchanged."
echo "New dataplane scripts take effect on next explicit mode switch or policy apply."
echo "Backup: $B"
echo "Rollback: $UI/bin/rollback-v2.1.4"
