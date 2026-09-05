#!/bin/sh
set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE=/data/u60proxy
OLD=/data/proxy-mode
STARTER=/data/start-u60proxy-v2.sh
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="/data/u60proxy-backup-$TS"

step(){ echo "$1"; }

step "[1/10] preflight"
[ -d "$OLD" ] || { echo "missing $OLD" >&2; exit 1; }
[ -x "$OLD/bin/proxy-mode" ] || { echo "missing proxy-mode core" >&2; exit 1; }
[ -x "$SRC/bin/u60proxy" ] || { echo "missing package binary" >&2; exit 1; }

step "[2/10] backup -> $BACKUP"
mkdir -p "$BACKUP"
[ -d "$BASE" ] && cp -a "$BASE" "$BACKUP/u60proxy" || true
mkdir -p "$BACKUP/proxy-mode-scripts"
[ -f "$OLD/scripts/traffic.sh" ] && cp "$OLD/scripts/traffic.sh" "$BACKUP/proxy-mode-scripts/traffic.sh" || true
[ -f "$OLD/scripts/udp-tun.sh" ] && cp "$OLD/scripts/udp-tun.sh" "$BACKUP/proxy-mode-scripts/udp-tun.sh" || true
[ -f /etc/rc.local ] && cp /etc/rc.local "$BACKUP/rc.local" || true
[ -f "$STARTER" ] && cp "$STARTER" "$BACKUP/start-u60proxy-v2.sh" || true
echo "$BACKUP" > /data/u60proxy-install-backup-latest

step "[3/10] install control plane"
mkdir -p "$BASE/bin" "$BASE/state" "$BASE/runtime"
cp "$SRC/bin/u60proxy" "$BASE/bin/u60proxy"
cp "$SRC/bin/u60doctor" "$BASE/bin/u60doctor"
cp "$SRC/bin/u60backup" "$BASE/bin/u60backup"
cp "$SRC/bin/u60rollback" "$BASE/bin/u60rollback"
chmod 755 "$BASE/bin/u60proxy" "$BASE/bin/u60doctor" "$BASE/bin/u60backup" "$BASE/bin/u60rollback"

# Preserve/seed current mode from the validated proxy core.
if [ ! -s "$BASE/state/current_mode" ]; then
    M="$(cat "$OLD/runtime/current_mode" 2>/dev/null || echo 11)"
    case "$M" in ''|*[!0-9]*) M=11;; esac
    echo "$M" > "$BASE/state/current_mode"
fi

step "[4/10] install per-device dataplane"
cp "$SRC/scripts/traffic.sh" "$OLD/scripts/traffic.sh"
cp "$SRC/scripts/udp-tun.sh" "$OLD/scripts/udp-tun.sh"
chmod 755 "$OLD/scripts/traffic.sh" "$OLD/scripts/udp-tun.sh"

step "[5/10] disable old experimental control services"
for svc in u60proxy u60proxy-v2; do
    if [ -x "/etc/init.d/$svc" ]; then
        "/etc/init.d/$svc" disable >/dev/null 2>&1 || true
        "/etc/init.d/$svc" stop >/dev/null 2>&1 || true
    fi
done

step "[6/10] stop old control-plane processes only"
# Vendor uhttpd 80/443 is intentionally untouched.
for p in $(ps w 2>/dev/null | grep '/data/proxy-mode/bin/u60-web' | grep -v grep | awk '{print $1}'); do
    kill "$p" 2>/dev/null || true
done
if [ -s "$BASE/runtime/web-supervisor.pid" ]; then
    p="$(cat "$BASE/runtime/web-supervisor.pid" 2>/dev/null || true)"
    [ -n "$p" ] && kill "$p" 2>/dev/null || true
fi
for p in $(ps w 2>/dev/null | grep '/data/u60proxy/bin/u60proxy serve' | grep -v grep | awk '{print $1}'); do
    kill "$p" 2>/dev/null || true
done
rm -f "$BASE/runtime/web-supervisor.pid"

step "[7/10] install reliable rc.local startup"
cp "$SRC/start-u60proxy-v2.sh" "$STARTER"
chmod 755 "$STARTER"

if [ -f /etc/rc.local ]; then
    sed -i 's|^[[:space:]]*sh /data/start-u60-web.sh[[:space:]]*$|# u60proxy-v2 disabled old u60-web|' /etc/rc.local
    grep -v '^sh /data/start-u60proxy-v2.sh$' /etc/rc.local > /tmp/rc.local.u60proxy.clean
    awk '
    {
        print
        if ($0 == "sh /data/start-proxy-mode.sh")
            print "sh /data/start-u60proxy-v2.sh"
    }
    ' /tmp/rc.local.u60proxy.clean > /tmp/rc.local.u60proxy.new
    cat /tmp/rc.local.u60proxy.new > /etc/rc.local
    rm -f /tmp/rc.local.u60proxy.clean /tmp/rc.local.u60proxy.new
fi

step "[8/10] migrate device policy"
"$BASE/bin/u60proxy" migrate >/dev/null 2>&1 || true
"$BASE/bin/u60proxy" scan >/dev/null 2>&1 || true

step "[9/10] apply policy and start web"
"$BASE/bin/u60proxy" apply >/dev/null 2>&1 || true
sh "$STARTER"
sleep 3

step "[10/10] doctor"
"$BASE/bin/u60doctor" || true

echo
echo "u60proxy 2.1.1 installed"
echo "Backup: $BACKUP"
echo "Web: http://10.66.0.1:8081"
echo "CLI: /data/u60proxy/bin/u60proxy"
echo "Doctor: /data/u60proxy/bin/u60proxy doctor"
echo "Rollback: /data/u60proxy/bin/u60proxy rollback latest"
echo "Wi-Fi relay: NOT INCLUDED in this release"
