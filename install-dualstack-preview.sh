#!/bin/sh
# Run on U60 Pro only after uploading repository files AND CI-built ARM64 binary.
# Does not modify stock ZTE services or private configs.
set -eu
SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OLD=/data/proxy-mode
CTL=/data/u60proxy/bin/u60proxy
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/data/u60proxy-dualstack-backup-$STAMP"
[ -x "$OLD/bin/proxy-mode" ] || { echo "Existing proxy-mode missing"; exit 1; }
[ -f "$SRC/bin/u60proxy" ] || { echo "Place GitHub Actions ARM64 binary at $SRC/bin/u60proxy"; exit 1; }
[ -f "$SRC/scripts/ipv6-tun.sh" ] || { echo "Missing source scripts"; exit 1; }
[ -d /sys/class/net/br-lan ] || { echo "Not on U60 Pro"; exit 1; }
mkdir -p "$BACKUP" "$OLD/scripts" "$OLD/bin"
for path in /data/proxy-mode/bin/proxy-mode /data/proxy-mode/scripts/stop.sh /data/proxy-mode/scripts/ipv6-tun.sh /data/u60proxy/bin/u60proxy; do
  [ -f "$path" ] || continue
  cp -p "$path" "$BACKUP/$(basename "$(dirname "$path")")-$(basename "$path")"
done
for path in "$SRC/bin/proxy-mode" "$SRC/scripts/stop.sh" "$SRC/scripts/ipv6-tun.sh"; do
  sh -n "$path"
done
# Only replace control binary if its build has been supplied by GitHub Actions.
cp "$SRC/bin/proxy-mode" "$OLD/bin/proxy-mode"
cp "$SRC/scripts/stop.sh" "$OLD/scripts/stop.sh"
cp "$SRC/scripts/ipv6-tun.sh" "$OLD/scripts/ipv6-tun.sh"
cp "$SRC/bin/u60proxy" "$CTL"
chmod 755 "$OLD/bin/proxy-mode" "$OLD/scripts/stop.sh" "$OLD/scripts/ipv6-tun.sh" "$CTL"
echo "$BACKUP" > /data/u60proxy-dualstack-last-backup
echo "Installed. Backups: $BACKUP"
echo "IPv6 proxy is OFF by default. Add fd75:60:0:167::1/126 to the TUN address list before enabling."
echo "Switch current Mode through 8081 after verifying sing-box configs."
