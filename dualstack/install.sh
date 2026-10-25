#!/bin/sh
# Upgrade existing u60proxy only; pass generated dual-stack mode11.json as argument.
set -eu
SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CFG=${1:-/tmp/mode11-dualstack.json}
BASE=/data/proxy-mode
CTL=/data/u60proxy/bin/u60proxy
[ "$(id -u)" = 0 ] || { echo 'Run as root'; exit 1; }
[ -x "$CTL" ] && [ -x "$BASE/bin/sing-box" ] && [ -x "$BASE/scripts/traffic.sh" ] || { echo 'Existing U60 proxy installation required'; exit 1; }
[ -f "$CFG" ] || { echo "Upload generated dual-stack mode11.json to $CFG first"; exit 1; }
for tool in ip ip6tables jsonfilter; do command -v "$tool" >/dev/null || exit 1; done
for file in vless-ipv6.sh traffic-wrapper.sh rollback.sh; do sh -n "$SRC/$file"; done
"$BASE/bin/sing-box" check -c "$CFG"
[ "$(jsonfilter -i "$CFG" -e '@.outbounds[0].type')" = vless ] || exit 1
jsonfilter -i "$CFG" -e '@.inbounds[*].tag' | grep -Fxq vless6-redirect-in || { echo 'This is not the generated dual-stack JSON'; exit 1; }
jsonfilter -i "$CFG" -e '@.inbounds[*].address[*]' | grep -Fxq 'fd75:60:0:168::1/126' || { echo 'IPv6 TUN address absent'; exit 1; }
[ "$(jsonfilter -i "$CFG" -e '@.dns.strategy')" != ipv4_only ] || exit 1
# Do not share table/mark with yesterday's SSH/TUN experiment.
if [ ! -f "$BASE/scripts/vless-ipv6.sh" ]; then
 [ -z "$(ip -6 route show table 168 2>/dev/null)" ] || { echo 'IPv6 route table 168 is already in use'; exit 1; }
 if ip -6 rule show | grep -Eq 'fwmark 0x68|lookup 168([[:space:]]|$)'; then echo 'IPv6 mark 0x68 or table 168 rule is already in use'; exit 1; fi
fi
OLD_MODE=$(cat "$BASE/runtime/current_mode")
case "$OLD_MODE" in ''|*[!0-9]*) exit 1;; esac
umask 077
B="/data/u60-vless6-backup-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$B/files"
: > "$B/missing"
for p in /data/proxy-mode/configs/mode11.json /data/proxy-mode/scripts/traffic.sh /data/proxy-mode/scripts/traffic-vless6-base.sh /data/proxy-mode/scripts/vless-ipv6.sh /data/proxy-mode/runtime/ipv6_guard /data/u60proxy/state/current_mode; do
 if [ -f "$p" ]; then mkdir -p "$B/files$(dirname "$p")"; cp -p "$p" "$B/files$p"; else echo "$p" >> "$B/missing"; fi
done
cp "$SRC/rollback.sh" "$B/rollback.sh"
echo "$OLD_MODE" > "$B/mode"
trap 'trap - EXIT; sh "$B/rollback.sh" "$B" || true' EXIT
if ! grep -q '^# U60_VLESS_DUALSTACK_WRAPPER_V1$' "$BASE/scripts/traffic.sh"; then
 cp -p "$BASE/scripts/traffic.sh" "$BASE/scripts/traffic-vless6-base.sh"
fi
[ -x "$BASE/scripts/traffic-vless6-base.sh" ] || exit 1
cp "$SRC/vless-ipv6.sh" "$BASE/scripts/vless-ipv6.sh.new"
chmod 755 "$BASE/scripts/vless-ipv6.sh.new"
mv "$BASE/scripts/vless-ipv6.sh.new" "$BASE/scripts/vless-ipv6.sh"
cp "$SRC/traffic-wrapper.sh" "$BASE/scripts/traffic.sh.new"
chmod 755 "$BASE/scripts/traffic.sh.new"
mv "$BASE/scripts/traffic.sh.new" "$BASE/scripts/traffic.sh"
cp "$CFG" "$BASE/configs/mode11.json.new"
chmod 600 "$BASE/configs/mode11.json.new"
mv "$BASE/configs/mode11.json.new" "$BASE/configs/mode11.json"
echo strict > "$BASE/runtime/ipv6_guard"
"$CTL" mode set 11
"$BASE/scripts/vless-ipv6.sh" status
[ "$(cat "$BASE/runtime/vless_ipv6_applied")" = on ] || exit 1
echo "$B" > /data/u60-vless6-last-backup
trap - EXIT
echo 'VLESS Mode 11 dual-stack adapter installed. Keep TCP/DNS/UDP/IPv6 Guard ON for the selected devices.'
echo 'Reconnect client Wi-Fi to clear old connections, then verify Azure IPv4 and IPv6 exits.'
echo "Rollback: sh $B/rollback.sh $B"
