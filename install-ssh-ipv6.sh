#!/bin/sh
# Upgrade an existing U60 installation. Keep this script running over USB ADB.
set -eu
SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OLD=/data/proxy-mode
CTL=/data/u60proxy
[ "$(uname -m)" = aarch64 ] || { echo 'Requires aarch64 U60 Pro'; exit 1; }
[ -d /sys/class/net/br-lan ] && [ -x "$OLD/bin/sing-box" ] && [ -x "$OLD/bin/proxy-mode" ] || { echo 'Existing U60 proxy installation required'; exit 1; }
[ -x "$SRC/bin/u60proxy" ] || { echo 'Use the complete release package, not source ZIP'; exit 1; }
MODE=$(cat "$OLD/runtime/current_mode")
case "$MODE" in ''|*[!0-9]*) echo 'Invalid current mode'; exit 1;; esac
for f in "$SRC"/scripts/*.sh "$SRC/bin/proxy-mode" "$SRC/rollback-ssh-ipv6.sh"; do sh -n "$f"; done
"$OLD/bin/sing-box" check -c "$OLD/configs/mode$MODE.json"
BACKUP="/data/u60proxy-ssh6-backup-$(date +%Y%m%d-%H%M%S)-$$"
umask 077
mkdir -p "$BACKUP/files"
: > "$BACKUP/missing"
for p in /data/u60proxy/bin/u60proxy /data/start-u60proxy-v2.sh /data/proxy-mode/bin/proxy-mode /data/proxy-mode/scripts/traffic.sh /data/proxy-mode/scripts/stop.sh /data/proxy-mode/scripts/ssh-ipv6.sh /data/proxy-mode/runtime/active.json /data/proxy-mode/runtime/ssh_ipv6; do
 if [ -f "$p" ]; then mkdir -p "$BACKUP/files$(dirname "$p")"; cp -p "$p" "$BACKUP/files$p"; else echo "$p" >> "$BACKUP/missing"; fi
done
cp -Rp "$OLD/configs" "$BACKUP/configs"
cp "$SRC/rollback-ssh-ipv6.sh" "$BACKUP/rollback.sh"
echo "$MODE" > "$BACKUP/mode"
# Stop only the project's old web supervisor, never vendor services.
for d in /proc/[0-9]*; do
 [ -r "$d/cmdline" ] || continue
 cmd=$(tr '\000' ' ' < "$d/cmdline" 2>/dev/null || true)
 case "$cmd" in 'sh /data/start-u60proxy-v2.sh '*|'/bin/sh /data/start-u60proxy-v2.sh '*) kill "${d##*/}" 2>/dev/null || true;; esac
done
killall u60proxy 2>/dev/null || true
rm -f "$CTL/runtime/web-supervisor.pid" "$CTL/runtime/web.pid"
recover() { trap - EXIT; sh "$BACKUP/rollback.sh" "$BACKUP" || true; }
trap recover EXIT
# Remove yesterday's policy routes using its own cleanup before replacing files.
if [ -x "$OLD/scripts/ipv6-tun.sh" ]; then "$OLD/scripts/ipv6-tun.sh" disable; fi
echo strict > "$OLD/runtime/ipv6_guard"
for f in traffic.sh stop.sh ssh-ipv6.sh; do cp "$SRC/scripts/$f" "$OLD/scripts/$f"; chmod 755 "$OLD/scripts/$f"; done
cp "$SRC/bin/proxy-mode" "$OLD/bin/proxy-mode"
chmod 755 "$OLD/bin/proxy-mode"
cp "$SRC/bin/u60proxy" "$CTL/bin/u60proxy.new"
chmod 755 "$CTL/bin/u60proxy.new"
mv "$CTL/bin/u60proxy.new" "$CTL/bin/u60proxy"
cp "$SRC/start-u60proxy-v2.sh" /data/start-u60proxy-v2.sh
chmod 755 /data/start-u60proxy-v2.sh
"$OLD/bin/proxy-mode" restart "$MODE"
"$CTL/bin/u60proxy" apply
sh /data/start-u60proxy-v2.sh
echo "$BACKUP" > /data/u60proxy-ssh6-last-backup
trap - EXIT
echo 'Installed u60proxy 2.2.0 SSH IPv6 TCP'
echo 'Web: http://10.66.0.1:8081/'
echo 'SSH mode: TCP + DNS + IPv6 Guard ON; UDP OFF recommended.'
echo "Rollback: sh $BACKUP/rollback.sh $BACKUP"
"$OLD/bin/proxy-mode" status
