#!/bin/sh
# IPv6 TCP REDIRECT -> sing-box -> native SSH outbound. No TUN or WAN bypass.
set -eu
BASE=/data/proxy-mode
RT=$BASE/runtime
CHAIN=U60PM_SSH6
INPUT=U60PM_SSH6_IN
cleanup() {
 command -v ip6tables >/dev/null 2>&1 || return 0
 while ip6tables -t nat -C PREROUTING -i br-lan -j "$CHAIN" 2>/dev/null; do ip6tables -t nat -D PREROUTING -i br-lan -j "$CHAIN" || break; done
 while ip6tables -C INPUT -i br-lan -j "$INPUT" 2>/dev/null; do ip6tables -D INPUT -i br-lan -j "$INPUT" || break; done
 ip6tables -t nat -F "$CHAIN" 2>/dev/null || true
 ip6tables -t nat -X "$CHAIN" 2>/dev/null || true
 ip6tables -F "$INPUT" 2>/dev/null || true
 ip6tables -X "$INPUT" 2>/dev/null || true
}
apply() {
 cleanup
 [ "$(cat "$RT/ssh_ipv6" 2>/dev/null || echo off)" = on ] || return 0
 [ "$(cat "$RT/traffic_mode" 2>/dev/null || echo off)" != off ] || return 0
 [ "$(cat "$RT/ipv6_guard" 2>/dev/null || echo strict)" = strict ] || { echo 'SSH IPv6 requires IPv6 Guard strict' >&2; return 1; }
 command -v ip6tables >/dev/null 2>&1 || { echo 'IPv6 REDIRECT unavailable; keep IPv6 Guard enabled' >&2; return 1; }
 trap 'cleanup' EXIT
 ip6tables -t nat -N "$CHAIN"
 ip6tables -N "$INPUT"
 for n in ::1/128 fe80::/10 ff00::/8 fc00::/7; do ip6tables -t nat -A "$CHAIN" -d "$n" -j RETURN; done
 # Router-local services must not be proxied, including global LAN addresses.
 # Vendor firmware lacks xt_addrtype. Enumerate local addresses instead.
 local_addr_dump=$(ip -6 addr show) || return 1
 local_addrs=$(printf '%s\n' "$local_addr_dump" | awk '$1 == "inet6" { split($2, a, "/"); print a[1] }')
 for local_addr in $local_addrs; do
   ip6tables -t nat -A "$CHAIN" -d "$local_addr/128" -j RETURN
 done
 # Per-device DNS is handled by the existing DNS6 chain.
 ip6tables -t nat -A "$CHAIN" -p tcp --dport 53 -j RETURN
 if [ "$(cat "$RT/traffic_mode")" = all ]; then
   ip6tables -t nat -A "$CHAIN" -p tcp -j REDIRECT --to-ports 7894
   ip6tables -A "$INPUT" -p tcp --dport 7894 -j ACCEPT
 else
   while IFS= read -r item; do
     case "$item" in mac:*) ;; *) continue;; esac
     grep -Fxq "$item" "$RT/ipv6_devices" || continue
     mac=${item#mac:}
     ip6tables -t nat -A "$CHAIN" -m mac --mac-source "$mac" -p tcp -j REDIRECT --to-ports 7894
     ip6tables -A "$INPUT" -m mac --mac-source "$mac" -p tcp --dport 7894 -j ACCEPT
   done < "$RT/proxy_devices"
 fi
 ip6tables -A "$INPUT" -p tcp --dport 7894 -j REJECT
 ip6tables -I INPUT 1 -i br-lan -j "$INPUT"
 ip6tables -t nat -I PREROUTING 1 -i br-lan -j "$CHAIN"
 trap - EXIT
}
case "${1:-status}" in
 apply) apply;;
 clear) cleanup;;
 status)
   echo "ssh_ipv6_config=$(cat "$RT/ssh_ipv6" 2>/dev/null || echo off)"
   ip6tables -t nat -S "$CHAIN" 2>/dev/null || true
   ;;
 *) exit 2;;
esac
