#!/bin/sh
# Install only the rebuilt web controller, without restarting sing-box.
set -eu
umask 077
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE=/data/u60proxy
BIN="$BASE/bin/u60proxy"
[ "$(id -u)" = 0 ] && [ "$(uname -m)" = aarch64 ] || { echo 'Root ARM64 required'; exit 1; }
[ -x "$BIN" ] && [ -x /data/proxy-mode/scripts/ipv6-upstream.sh ] || { echo 'Existing IPv6 preview required'; exit 1; }
[ -s "$ROOT/bin/u60proxy" ] || exit 1
backup="$BASE/backups/ui-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$backup"
cp -p "$BIN" "$backup/u60proxy"
printf '%s\n' "$backup" > "$BASE/runtime/ui-backup"
cp "$ROOT/bin/u60proxy" "$BIN.new.$$"
chmod 755 "$BIN.new.$$"
mv -f "$BIN.new.$$" "$BIN"
for p in $(ps w | awk '$0 ~ /\/data\/u60proxy\/bin\/u60proxy serve/ && $0 !~ /awk/ {print $1}'); do
    kill "$p" 2>/dev/null || true
done
echo "Web controller upgraded; existing supervisor should restart web only."
echo "Backup: $backup"
echo "Refresh http://10.66.0.1:8081"
