#!/bin/sh
# U60 VLESS Mode 11 IPv6 adapter. TCP REDIRECT; UDP policy-routed to sing-box TUN.
set -eu
BASE=/data/proxy-mode
RT=$BASE/runtime
LAN=br-lan
TUN=u60udp0
N=U60PM_VLESS6_TCP
M=U60PM_VLESS6_UDP
I=U60PM_VLESS6_IN
F=U60PM_VLESS6_FWD
TABLE=168
MARK=0x68/0xff
mkdir -p "$RT"
drop_jump() {
 table=$1; parent=$2; shift 2
 while ip6tables -t "$table" -C "$parent" "$@" 2>/dev/null; do
   ip6tables -t "$table" -D "$parent" "$@" || break
 done
}
clear() {
 if command -v ip6tables >/dev/null 2>&1; then
   drop_jump nat PREROUTING -i "$LAN" -j "$N"
   drop_jump mangle PREROUTING -i "$LAN" -j "$M"
   drop_jump filter INPUT -i "$LAN" -j "$I"
   drop_jump filter FORWARD -i "$LAN" -j "$F"
   drop_jump filter FORWARD -i "$TUN" -o "$LAN" -j "$F"
   for spec in "nat $N" "mangle $M" "filter $I" "filter $F"; do
     set -- $spec
     ip6tables -t "$1" -F "$2" 2>/dev/null || true
     ip6tables -t "$1" -X "$2" 2>/dev/null || true
   done
 fi
 while ip -6 rule del fwmark "$MARK" table "$TABLE" 2>/dev/null; do :; done
 ip -6 route flush table "$TABLE" 2>/dev/null || true
 echo off > "$RT/vless_ipv6_applied"
}
apply() {
 clear
 [ "$(cat "$RT/current_mode" 2>/dev/null || echo none)" = 11 ] || return 0
 [ "$(cat "$RT/traffic_mode" 2>/dev/null || echo off)" != off ] || return 0
 jsonfilter -i "$RT/active.json" -e '@.inbounds[*].tag' | grep -Fxq vless6-redirect-in || return 0
 [ "$(jsonfilter -i "$RT/active.json" -e '@.outbounds[0].type')" = vless ] || return 0
 [ "$(cat "$RT/ipv6_guard" 2>/dev/null || echo off)" = strict ] || { echo 'VLESS IPv6 requires global IPv6 Guard strict' >&2; return 1; }
 ip -6 addr show dev "$TUN" | grep -Fq 'fd75:60:0:168::1/126' || { echo 'VLESS IPv6 TUN address missing; install generated dual-stack mode11.json' >&2; return 1; }
 for list in proxy_devices udp_devices ipv6_devices; do [ -f "$RT/$list" ] || return 1; done
 # Keep original guard chains attached. Any failure here removes only this adapter.
 trap 'clear' EXIT
 ip6tables -t nat -N "$N"
 ip6tables -t mangle -N "$M"
 ip6tables -N "$I"
 ip6tables -N "$F"
 for prefix in ::1/128 fe80::/10 ff00::/8 fc00::/7; do
   ip6tables -t nat -A "$N" -d "$prefix" -j RETURN
   ip6tables -t mangle -A "$M" -d "$prefix" -j RETURN
 done
 dump=$(ip -6 addr show) || return 1
 addrs=$(printf '%s\n' "$dump" | awk '$1=="inet6" {split($2,a,"/"); print a[1]}')
 for addr in $addrs; do
   ip6tables -t nat -A "$N" -d "$addr/128" -j RETURN
   ip6tables -t mangle -A "$M" -d "$addr/128" -j RETURN
 done
 ip6tables -t nat -A "$N" -p tcp --dport 53 -j RETURN
 ip6tables -t mangle -A "$M" -p udp --dport 53 -j RETURN
 # The terminal blackhole survives loss of the TUN default route.
 ip -6 route replace blackhole default metric 32767 table "$TABLE"
 ip -6 route replace default dev "$TUN" metric 10 table "$TABLE"
 ip -6 rule add fwmark "$MARK" table "$TABLE"
 if [ "$(cat "$RT/traffic_mode")" = all ]; then
   ip6tables -t nat -A "$N" -p tcp -j REDIRECT --to-ports 7894
   ip6tables -A "$I" -p tcp --dport 7894 -j ACCEPT
   ip6tables -t mangle -A "$M" -p udp -j MARK --set-xmark "$MARK"
 else
   while IFS= read -r item; do
     case "$item" in mac:*) ;; *) continue;; esac
     grep -Fxq "$item" "$RT/ipv6_devices" || continue
     mac=${item#mac:}
     ip6tables -t nat -A "$N" -m mac --mac-source "$mac" -p tcp -j REDIRECT --to-ports 7894
     ip6tables -A "$I" -m mac --mac-source "$mac" -p tcp --dport 7894 -j ACCEPT
     if grep -Fxq "$item" "$RT/udp_devices"; then
       ip6tables -t mangle -A "$M" -m mac --mac-source "$mac" -p udp -j MARK --set-xmark "$MARK"
     fi
   done < "$RT/proxy_devices"
 fi
 ip6tables -A "$I" -p tcp --dport 7894 -j REJECT --reject-with tcp-reset
 ip6tables -A "$F" -i "$LAN" -o "$TUN" -p udp -m mark --mark "$MARK" -j ACCEPT
 ip6tables -A "$F" -i "$TUN" -o "$LAN" -j ACCEPT
 ip6tables -I INPUT 1 -i "$LAN" -j "$I"
 ip6tables -I FORWARD 1 -i "$LAN" -j "$F"
 ip6tables -I FORWARD 1 -i "$TUN" -o "$LAN" -j "$F"
 ip6tables -t nat -I PREROUTING 1 -i "$LAN" -j "$N"
 ip6tables -t mangle -I PREROUTING 1 -i "$LAN" -j "$M"
 echo on > "$RT/vless_ipv6_applied"
 trap - EXIT
}
status() {
 echo "vless_ipv6_applied=$(cat "$RT/vless_ipv6_applied" 2>/dev/null || echo off)"
 ip -6 rule show | grep 'fwmark 0x68.*lookup 168' || true
 ip -6 route show table "$TABLE" 2>/dev/null || true
 ip6tables -t nat -S "$N" 2>/dev/null || true
 ip6tables -t mangle -S "$M" 2>/dev/null || true
}
case "${1:-status}" in apply) apply;; clear) clear;; status) status;; *) exit 2;; esac
