#!/bin/sh
# Opt-in fail-closed IPv6 transparent TCP/UDP proxy via sing-box TUN.
# This script NEVER enables carrier IPv6 bypass.
set -eu
BASE=/data/proxy-mode
RT="$BASE/runtime"
LAN=br-lan
TUN=u60udp0
CHAIN=U60PM_V6_TUN
TABLE=167
MARK=0x67
MASK=0xff
STATE="$RT/ipv6_proxy"
GUARD="$RT/ipv6_guard"
DEVICES="$RT/ipv6_devices"
PROXY_DEVICES="$RT/proxy_devices"
mkdir -p "$RT"
[ -f "$STATE" ] || echo off > "$STATE"
has(){ command -v "$1" >/dev/null 2>&1; }
remove_jump(){
  while ip6tables -t mangle -C PREROUTING -i "$LAN" -j "$CHAIN" 2>/dev/null; do
    ip6tables -t mangle -D PREROUTING -i "$LAN" -j "$CHAIN" || break
  done
}
remove_forward(){
  while ip6tables -C FORWARD -i "$LAN" -o "$TUN" -m mark --mark "$MARK/$MASK" -j ACCEPT 2>/dev/null; do
    ip6tables -D FORWARD -i "$LAN" -o "$TUN" -m mark --mark "$MARK/$MASK" -j ACCEPT || break
  done
  while ip6tables -C FORWARD -i "$TUN" -o "$LAN" -j ACCEPT 2>/dev/null; do
    ip6tables -D FORWARD -i "$TUN" -o "$LAN" -j ACCEPT || break
  done
}
clear(){
  has ip6tables || return 0
  remove_jump
  remove_forward
  ip6tables -t mangle -F "$CHAIN" 2>/dev/null || true
  ip6tables -t mangle -X "$CHAIN" 2>/dev/null || true
  while ip -6 rule del fwmark "$MARK/$MASK" table "$TABLE" 2>/dev/null; do :; done
  ip -6 route flush table "$TABLE" 2>/dev/null || true
}
fail(){ echo "IPv6 proxy not activated: $*" >&2; return 1; }
apply(){
  [ "$(cat "$STATE")" = on ] || { clear; return 0; }
  has ip6tables || fail "ip6tables missing"
  [ "$(cat "$GUARD" 2>/dev/null || echo off)" = strict ] || fail "IPv6 Guard must be strict"
  [ -d "/sys/class/net/$TUN" ] || fail "TUN $TUN missing"
  ip -6 addr show dev "$TUN" | grep -q 'inet6 fd75:60:0:167::1/126' || fail "TUN IPv6 address missing"
  [ -f "$PROXY_DEVICES" ] || fail "proxy device policy missing"
  [ -f "$DEVICES" ] || fail "IPv6 Guard device policy missing"
  # Configure blackhole fallback before any marked packets are introduced.
  clear
  ip -6 route replace blackhole default table "$TABLE" metric 32767
  ip -6 rule add fwmark "$MARK/$MASK" table "$TABLE"
  ip -6 route replace default dev "$TUN" table "$TABLE" metric 10
  ip6tables -t mangle -N "$CHAIN" 2>/dev/null || true
  ip6tables -t mangle -F "$CHAIN"
  for prefix in ::1/128 fe80::/10 ff00::/8 fc00::/7; do
    ip6tables -t mangle -A "$CHAIN" -d "$prefix" -j RETURN
  done
  # DNS redirection already happens in the project's dedicated DNS chain.
  ip6tables -t mangle -A "$CHAIN" -p udp --dport 53 -j RETURN
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    # Only devices with BOTH IPv6 Guard and TCP proxy enabled participate.
    grep -Fxq "$item" "$PROXY_DEVICES" || continue
    case "$item" in
      mac:*) mac="${item#mac:}"; ip6tables -t mangle -A "$CHAIN" -m mac --mac-source "$mac" -p tcp -j MARK --set-xmark "$MARK/$MASK"; ip6tables -t mangle -A "$CHAIN" -m mac --mac-source "$mac" -p udp -j MARK --set-xmark "$MARK/$MASK";;
      *) echo "Ignoring non-MAC IPv6 selector: $item" >&2;;
    esac
  done < "$DEVICES"
  ip6tables -I FORWARD 1 -i "$LAN" -o "$TUN" -m mark --mark "$MARK/$MASK" -j ACCEPT
  ip6tables -I FORWARD 1 -i "$TUN" -o "$LAN" -j ACCEPT
  ip6tables -t mangle -I PREROUTING 1 -i "$LAN" -j "$CHAIN"
}
status(){
  echo "ipv6_proxy_requested=$(cat "$STATE")"
  echo "ipv6_guard=$(cat "$GUARD" 2>/dev/null || echo unknown)"
  echo "ipv6_tun_address=$(ip -6 addr show dev "$TUN" 2>/dev/null | grep -o 'fd75:60:0:167::1/126' | head -n 1 || true)"
  echo "ipv6_rule=$(ip -6 rule show | grep 'fwmark 0x67.*lookup 167' || true)"
  echo "ipv6_tun_route=$(ip -6 route show table "$TABLE" 2>/dev/null || true)"
  if has ip6tables; then
    ip6tables -t mangle -S "$CHAIN" 2>/dev/null || true
  fi
}
case "${1:-status}" in
  status) status;;
  apply) apply;;
  enable)
    [ "$(cat "$GUARD" 2>/dev/null || echo off)" = strict ] || fail "enable IPv6 Guard first"
    echo on > "$STATE"
    if ! apply; then
      echo off > "$STATE"
      clear
      exit 1
    fi
    status;;
  disable|off) echo off > "$STATE"; clear; status;;
  *) echo "usage: $0 status|apply|enable|disable" >&2; exit 2;;
esac
