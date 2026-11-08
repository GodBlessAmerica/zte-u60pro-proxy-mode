#!/bin/sh
set -eu
# U60 Pro / MU5250 fresh installation only; BusyBox compatible.
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CORE=/data/proxy-mode
UI=/data/u60proxy
HOOK=/data/start-u60proxy-full.sh
LOG=/data/u60proxy-full-install.log
die(){ echo "[FAIL] $*" >&2; exit 1; }
info(){ echo "[INFO] $*"; }
[ "$(id -u)" = 0 ] || die "Root SSH required"
[ "$(uname -m)" = aarch64 ] || die "ZTE U60 Pro ARM64/aarch64 only"
[ -w /data ] || die "/data must be writable"
[ -c /dev/net/tun ] || die "/dev/net/tun missing"
for app in ip iptables ip6tables awk sed grep cp mv chmod tar sha256sum; do
  command -v "$app" >/dev/null 2>&1 || die "missing command: $app"
done
ip link show br-lan >/dev/null 2>&1 || die "br-lan missing"
ip link show rmnet_data0 >/dev/null 2>&1 || die "rmnet_data0 missing"
ip addr show br-lan | grep -q '10\.66\.0\.1/' || die "LAN is not 10.66.0.1; unsupported vendor layout"
iptables -V | grep -qi legacy || die "requires tested iptables-legacy backend"
# Do not overwrite other projects or existing installations.
for p in "$CORE" "$UI" "$HOOK"; do
 [ ! -e "$p" ] || die "Existing installation/path found: $p ; use upgrade, not fresh installer"
done
[ -f /etc/rc.local ] || die "/etc/rc.local missing"
for f in "$ROOT/bin/u60proxy" "$ROOT/bin/sing-box" "$ROOT/bin/proxy-mode" "$ROOT/scripts/udp-tun.sh" "$ROOT/scripts/traffic.sh" "$ROOT/start-u60proxy-v2.sh" "$ROOT/start-u60proxy-full.sh" "$ROOT/templates/mode11-full-proxy.example.json"; do
 [ -s "$f" ] || die "package file missing: $f"
done
"$ROOT/bin/sing-box" version >/dev/null || die "packaged sing-box binary incompatible"
# The clean install has no secrets, no active config, and no default proxy clients.
info "Installing base and web control plane (no traffic policy enabled until configured)"
mkdir -p "$CORE/bin" "$CORE/scripts" "$CORE/configs" "$CORE/runtime" "$CORE/logs" "$UI/bin" "$UI/runtime" "$UI/state"
cp "$ROOT/bin/sing-box" "$CORE/bin/sing-box"
cp "$ROOT/bin/proxy-mode" "$CORE/bin/proxy-mode"
cp "$ROOT/bin/u60proxy" "$UI/bin/u60proxy"
for f in "$ROOT"/scripts/*.sh; do cp "$f" "$CORE/scripts/"; done
for f in u60doctor u60backup u60rollback; do cp "$ROOT/bin/$f" "$UI/bin/$f"; done
cp "$ROOT/templates/mode11-full-proxy.example.json" "$CORE/configs/mode11.example.json"
cp "$ROOT/start-u60proxy-v2.sh" /data/start-u60proxy-v2.sh
cp "$ROOT/start-u60proxy-full.sh" "$HOOK"
chmod 755 "$CORE/bin/"* "$CORE/scripts/"*.sh "$UI/bin/"* /data/start-u60proxy-v2.sh "$HOOK"
# Never install a fake live config containing placeholder credentials.
echo off > "$CORE/runtime/traffic_mode"
echo 11 > "$UI/state/current_mode"
echo 11 > "$CORE/runtime/current_mode"
for f in proxy_devices dns_devices udp_devices ipv6_devices direct_devices; do : > "$CORE/runtime/$f"; done
echo strict > "$CORE/runtime/udp_quic_guard"
echo strict > "$CORE/runtime/ipv6_guard"
echo off > "$CORE/runtime/full_proxy_udp_tun"
# Hook before the final rc.local exit, only if we can do so reliably.
if grep -q '^exit 0[[:space:]]*$' /etc/rc.local; then
  sed '/^exit 0[[:space:]]*$/i\sh /data/start-u60proxy-full.sh' /etc/rc.local > /etc/rc.local.u60full.new
else
  cp /etc/rc.local /etc/rc.local.u60full.new
  printf '\nsh /data/start-u60proxy-full.sh\n' >> /etc/rc.local.u60full.new
fi
cp /etc/rc.local "$UI/runtime/rc.local.before-full"
cp /etc/rc.local.u60full.new /etc/rc.local
rm -f /etc/rc.local.u60full.new
# Starting web only. No sing-box proxy or firewall mutation without configured credentials.
sh /data/start-u60proxy-v2.sh
info "U60 Pro full baseline installed"
info "Web control (trusted LAN ONLY): http://10.66.0.1:8081"
info "Config template: $CORE/configs/mode11.example.json"
info "Copy template to mode11.json, fill credentials privately, run sing-box check and enable only after validation"
info "For diagnostics: $CORE/bin/proxy-mode preflight"
