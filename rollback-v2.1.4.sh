#!/bin/sh
set -eu
umask 077
UI=/data/u60proxy
CORE=/data/proxy-mode
[ "$(id -u)" = 0 ] || exit 1
B="$(cat "$UI/runtime/v2.1.4-backup")"
case "$B" in "$UI"/backups/v2.1.4-*) ;; *) exit 1;; esac
[ -s "$B/manifest" ] || exit 1
while IFS= read -r f; do
    case "$f" in
        core/scripts/ipv6-upstream.sh|core/scripts/start.sh|core/scripts/stop.sh|core/scripts/traffic.sh|core/scripts/udp-tun.sh|core/scripts/guard-control.sh|core/bin/proxy-mode) dst="$CORE/${f#core/}";;
        ui/bin/u60proxy|ui/bin/rollback-v2.1.4|ui/VERSION) dst="$UI/${f#ui/}";;
        *) echo 'Invalid manifest entry' >&2; exit 1;;
    esac
    if [ -f "$B/$f" ]; then cp -p "$B/$f" "$dst.restore.$$"; mv -f "$dst.restore.$$" "$dst"; else rm -f "$dst"; fi
done < "$B/manifest"
for p in $(ps w | awk '$0 ~ /\/data\/u60proxy\/bin\/u60proxy serve/ && $0 !~ /awk/ {print $1}'); do kill "$p" 2>/dev/null || true; done
echo 'Original files restored; current firewall and proxy untouched. Reapply previous mode if needed.'
