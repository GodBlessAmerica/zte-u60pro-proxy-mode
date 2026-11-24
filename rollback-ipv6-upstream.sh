#!/bin/sh
set -eu
umask 077
BASE=/data/proxy-mode
CONTROL=/data/u60proxy
[ "$(id -u)" = 0 ] || exit 1
backup="$(cat "$CONTROL/runtime/ipv6-upstream-backup")"
case "$backup" in "$CONTROL"/backups/ipv6-upstream-*) ;; *) echo 'Invalid backup path' >&2; exit 1;; esac
for f in bin/proxy-mode scripts/start.sh; do
    [ -s "$backup/$f" ] || { echo 'Incomplete backup' >&2; exit 1; }
    sh -n "$backup/$f"
done
for f in bin/proxy-mode scripts/start.sh scripts/ipv6-upstream.sh; do
    if [ -f "$backup/$f" ]; then
        cp -p "$backup/$f" "$BASE/$f.rollback.$$"
        mv -f "$BASE/$f.rollback.$$" "$BASE/$f"
    elif [ "$f" = scripts/ipv6-upstream.sh ]; then
        rm -f "$BASE/$f"
    fi
done
echo 'Original scripts restored. Active proxy was not restarted.'
echo 'Select the previous IPv4 mode in the existing web UI if needed.'
