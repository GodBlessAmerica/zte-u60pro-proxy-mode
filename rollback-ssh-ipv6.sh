#!/bin/sh
set -eu
B=${1:-$(cat /data/u60proxy-ssh6-last-backup)}
case "$B" in /data/u60proxy-ssh6-backup-*) ;; *) echo 'Invalid backup path'; exit 1;; esac
[ -d "$B/files/data" ] || exit 1
killall u60proxy 2>/dev/null || true
if [ -x /data/proxy-mode/scripts/ssh-ipv6.sh ]; then /data/proxy-mode/scripts/ssh-ipv6.sh clear; fi
cp -Rp "$B/files/data/." /data/
while IFS= read -r p; do
 case "$p" in /data/proxy-mode/scripts/ssh-ipv6.sh|/data/proxy-mode/runtime/ssh_ipv6) rm -f "$p";; esac
done < "$B/missing"
rm -f /data/u60proxy/runtime/web-supervisor.pid /data/u60proxy/runtime/web.pid
/data/proxy-mode/bin/proxy-mode restart "$(cat "$B/mode")"
sh /data/start-u60proxy-v2.sh
echo 'Restored previous program and active mode; private configs preserved.'
