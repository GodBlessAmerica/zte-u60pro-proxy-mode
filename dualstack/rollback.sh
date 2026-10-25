#!/bin/sh
set -eu
B=${1:-$(cat /data/u60-vless6-last-backup)}
case "$B" in /data/u60-vless6-backup-*) ;; *) echo 'Invalid backup directory'; exit 1;; esac
[ -f "$B/mode" ] && [ -d "$B/files/data" ] || exit 1
if [ -x /data/proxy-mode/scripts/vless-ipv6.sh ]; then /data/proxy-mode/scripts/vless-ipv6.sh clear; fi
cp -Rp "$B/files/data/." /data/
while IFS= read -r p; do
 case "$p" in /data/proxy-mode/scripts/vless-ipv6.sh|/data/proxy-mode/scripts/traffic-vless6-base.sh|/data/proxy-mode/configs/mode11.json) rm -f "$p";; esac
done < "$B/missing"
/data/u60proxy/bin/u60proxy mode set "$(cat "$B/mode")"
echo 'Previous U60 configuration and traffic adapter restored.'
