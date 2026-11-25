#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || exit 1
BASE=/data/u60proxy
BIN="$BASE/bin/u60proxy"
backup="$(cat "$BASE/runtime/ui-backup")"
case "$backup" in "$BASE"/backups/ui-*) ;; *) exit 1;; esac
[ -s "$backup/u60proxy" ] || exit 1
cp -p "$backup/u60proxy" "$BIN.rollback.$$"
mv -f "$BIN.rollback.$$" "$BIN"
for p in $(ps w | awk '$0 ~ /\/data\/u60proxy\/bin\/u60proxy serve/ && $0 !~ /awk/ {print $1}'); do
    kill "$p" 2>/dev/null || true
done
echo 'Original web controller restored; profiles and proxy unchanged.'
