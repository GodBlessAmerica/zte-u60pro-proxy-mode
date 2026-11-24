#!/bin/sh
# Read-only IPv6 upstream diagnostics. No firewall or network changes.
set -u
section() { printf '\n===== %s =====\n' "$1"; }
section "IPv6 upstream addresses"
ip -6 addr show scope global
section "IPv6 routes"
ip -6 route show table all
section "IPv6 policy routing"
ip -6 rule show
section "IPv6 route lookup (no packets sent)"
ip -6 route get 2606:4700:4700::1111 2>&1 || :
section "IPv6 interface controls"
for d in /proc/sys/net/ipv6/conf/*; do
    [ -d "$d" ] || continue
    printf '%s ' "${d##*/}"
    for k in disable_ipv6 accept_ra forwarding; do
        printf '%s=%s ' "$k" "$(cat "$d/$k" 2>/dev/null || echo unavailable)"
    done
    printf '\n'
done
section "IPv6 output and forwarding firewall"
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -S OUTPUT
    ip6tables -S FORWARD
    ip6tables -S U60PM_GUARD6 2>/dev/null || :
    ip6tables -t mangle -S OUTPUT 2>/dev/null || :
else
    echo "ip6tables unavailable"
fi
section "Proxy runtime metadata"
for f in ipv6_guard traffic_mode full_proxy_udp; do
    printf '%s=' "$f"
    cat "/data/proxy-mode/runtime/$f" 2>/dev/null || echo unavailable
done
/data/proxy-mode/bin/sing-box version 2>/dev/null | head -n 2
