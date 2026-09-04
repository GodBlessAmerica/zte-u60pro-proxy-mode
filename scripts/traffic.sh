#!/bin/sh
set -eu

BASE=/data/proxy-mode
RUNTIME="$BASE/runtime"
LAN=br-lan
PORT=7893
NAT_CHAIN=U60PM_REDIRECT
GUARD4_CHAIN=U60PM_GUARD4
GUARD6_CHAIN=U60PM_GUARD6
MODE_FILE="$RUNTIME/traffic_mode"
PROXY_LIST="$RUNTIME/proxy_devices"
DIRECT_LIST="$RUNTIME/direct_devices"

mkdir -p "$RUNTIME"
[ -f "$MODE_FILE" ] || echo off > "$MODE_FILE"
[ -f "$PROXY_LIST" ] || : > "$PROXY_LIST"
[ -f "$DIRECT_LIST" ] || : > "$DIRECT_LIST"

valid_ipv4() {
    echo "$1" | awk -F. 'NF==4 {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i<0 || $i>255) exit 1; exit 0} {exit 1}'
}

valid_mac() {
    echo "$1" | grep -Eiq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'
}

normalize_selector() {
    value="$1"
    if valid_ipv4 "$value"; then
        printf 'ip:%s\n' "$value"
    elif valid_mac "$value"; then
        printf 'mac:%s\n' "$(echo "$value" | tr 'A-F' 'a-f')"
    else
        return 1
    fi
}

remove_line() {
    file="$1" value="$2"
    tmp="$file.tmp"
    grep -vxF "$value" "$file" 2>/dev/null > "$tmp" || true
    mv "$tmp" "$file"
}

add_line() {
    file="$1" value="$2"
    grep -qxF "$value" "$file" 2>/dev/null || echo "$value" >> "$file"
}

have_ip6tables() {
    command -v ip6tables >/dev/null 2>&1
}

clear_rules() {
    iptables -t nat -D PREROUTING -i "$LAN" -j "$NAT_CHAIN" 2>/dev/null || true
    iptables -t nat -F "$NAT_CHAIN" 2>/dev/null || true
    iptables -t nat -X "$NAT_CHAIN" 2>/dev/null || true

    iptables -D FORWARD -i "$LAN" -j "$GUARD4_CHAIN" 2>/dev/null || true
    iptables -F "$GUARD4_CHAIN" 2>/dev/null || true
    iptables -X "$GUARD4_CHAIN" 2>/dev/null || true

    if have_ip6tables; then
        ip6tables -D FORWARD -i "$LAN" -j "$GUARD6_CHAIN" 2>/dev/null || true
        ip6tables -F "$GUARD6_CHAIN" 2>/dev/null || true
        ip6tables -X "$GUARD6_CHAIN" 2>/dev/null || true
    fi
}

base_nat_chain() {
    iptables -t nat -N "$NAT_CHAIN" 2>/dev/null || true
    iptables -t nat -F "$NAT_CHAIN"
    iptables -t nat -A "$NAT_CHAIN" -d 10.0.0.0/8 -j RETURN
    iptables -t nat -A "$NAT_CHAIN" -d 172.16.0.0/12 -j RETURN
    iptables -t nat -A "$NAT_CHAIN" -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A "$NAT_CHAIN" -d 127.0.0.0/8 -j RETURN
}

base_guard4_chain() {
    iptables -N "$GUARD4_CHAIN" 2>/dev/null || true
    iptables -F "$GUARD4_CHAIN"
    # Keep LAN/private traffic untouched. Only Internet-bound traffic is guarded.
    iptables -A "$GUARD4_CHAIN" -d 10.0.0.0/8 -j RETURN
    iptables -A "$GUARD4_CHAIN" -d 172.16.0.0/12 -j RETURN
    iptables -A "$GUARD4_CHAIN" -d 192.168.0.0/16 -j RETURN
    iptables -A "$GUARD4_CHAIN" -d 127.0.0.0/8 -j RETURN
}

base_guard6_chain() {
    have_ip6tables || return 0
    ip6tables -N "$GUARD6_CHAIN" 2>/dev/null || true
    ip6tables -F "$GUARD6_CHAIN"
    # Link-local/local IPv6 is not forwarded to WAN; allow it for LAN operation.
    ip6tables -A "$GUARD6_CHAIN" -d fe80::/10 -j RETURN
    ip6tables -A "$GUARD6_CHAIN" -d ff00::/8 -j RETURN
}

append_nat_rule() {
    list_action="$1" selector="$2"
    kind="${selector%%:*}"
    value="${selector#*:}"
    case "$kind:$list_action" in
        ip:return) iptables -t nat -A "$NAT_CHAIN" -s "$value/32" -j RETURN ;;
        mac:return) iptables -t nat -A "$NAT_CHAIN" -m mac --mac-source "$value" -j RETURN ;;
        ip:proxy) iptables -t nat -A "$NAT_CHAIN" -s "$value/32" -p tcp -j REDIRECT --to-ports "$PORT" ;;
        mac:proxy) iptables -t nat -A "$NAT_CHAIN" -m mac --mac-source "$value" -p tcp -j REDIRECT --to-ports "$PORT" ;;
    esac
}

append_guard4_rule() {
    list_action="$1" selector="$2"
    kind="${selector%%:*}"
    value="${selector#*:}"
    case "$kind:$list_action" in
        ip:return) iptables -A "$GUARD4_CHAIN" -s "$value/32" -j RETURN ;;
        mac:return) iptables -A "$GUARD4_CHAIN" -m mac --mac-source "$value" -j RETURN ;;
        ip:proxy)
            iptables -A "$GUARD4_CHAIN" -s "$value/32" -p tcp -j RETURN
            iptables -A "$GUARD4_CHAIN" -s "$value/32" -j REJECT
            ;;
        mac:proxy)
            iptables -A "$GUARD4_CHAIN" -m mac --mac-source "$value" -p tcp -j RETURN
            iptables -A "$GUARD4_CHAIN" -m mac --mac-source "$value" -j REJECT
            ;;
    esac
}

append_guard6_rule() {
    have_ip6tables || return 0
    list_action="$1" selector="$2"
    kind="${selector%%:*}"
    value="${selector#*:}"
    case "$kind:$list_action" in
        ip:return)
            # IPv4 selectors cannot reliably identify a client's IPv6 traffic.
            # MAC selectors are recommended when IPv6 leak protection is required.
            ;;
        mac:return) ip6tables -A "$GUARD6_CHAIN" -m mac --mac-source "$value" -j RETURN ;;
        ip:proxy)
            # No safe IPv4->IPv6 identity mapping here; leave unmatched.
            ;;
        mac:proxy) ip6tables -A "$GUARD6_CHAIN" -m mac --mac-source "$value" -j REJECT ;;
    esac
}

apply_rules() {
    mode="$(cat "$MODE_FILE" 2>/dev/null || echo off)"
    clear_rules
    [ "$mode" = off ] && return 0

    base_nat_chain
    base_guard4_chain
    base_guard6_chain

    case "$mode" in
        all)
            while IFS= read -r selector; do
                [ -n "$selector" ] || continue
                append_nat_rule return "$selector"
                append_guard4_rule return "$selector"
                append_guard6_rule return "$selector"
            done < "$DIRECT_LIST"

            iptables -t nat -A "$NAT_CHAIN" -p tcp -j REDIRECT --to-ports "$PORT"
            # TCP is handled by sing-box. Block every other Internet-bound IPv4 protocol
            # so QUIC/UDP/ICMP cannot bypass the proxy.
            iptables -A "$GUARD4_CHAIN" -p tcp -j RETURN
            iptables -A "$GUARD4_CHAIN" -j REJECT

            # Current REDIRECT path is IPv4/TCP only. Block forwarded global IPv6
            # to prevent IPv6 bypass for proxied clients.
            if have_ip6tables; then
                ip6tables -A "$GUARD6_CHAIN" -j REJECT
            fi
            ;;
        selective)
            while IFS= read -r selector; do
                [ -n "$selector" ] || continue
                append_nat_rule proxy "$selector"
                append_guard4_rule proxy "$selector"
                append_guard6_rule proxy "$selector"
            done < "$PROXY_LIST"
            ;;
        *)
            echo off > "$MODE_FILE"
            clear_rules
            return 1
            ;;
    esac

    iptables -t nat -I PREROUTING 1 -i "$LAN" -j "$NAT_CHAIN"
    iptables -I FORWARD 1 -i "$LAN" -j "$GUARD4_CHAIN"
    if have_ip6tables; then
        ip6tables -I FORWARD 1 -i "$LAN" -j "$GUARD6_CHAIN"
    fi
}

status() {
    mode="$(cat "$MODE_FILE" 2>/dev/null || echo off)"
    echo "traffic_mode=$mode"
    echo "proxy_devices=$(tr '\n' ' ' < "$PROXY_LIST" | sed 's/[[:space:]]*$//')"
    echo "direct_devices=$(tr '\n' ' ' < "$DIRECT_LIST" | sed 's/[[:space:]]*$//')"
    if [ "$mode" = off ]; then
        echo "ipv4_leak_guard=off"
        echo "ipv6_leak_guard=off"
    else
        echo "ipv4_leak_guard=strict"
        if have_ip6tables; then
            echo "ipv6_leak_guard=strict"
        else
            echo "ipv6_leak_guard=unavailable"
        fi
    fi
}

cmd="${1:-status}"
case "$cmd" in
    on)
        echo all > "$MODE_FILE"
        apply_rules
        echo "traffic proxy enabled for all LAN clients (strict leak guard)"
        ;;
    off)
        echo off > "$MODE_FILE"
        clear_rules
        echo "traffic proxy disabled"
        ;;
    selective)
        echo selective > "$MODE_FILE"
        apply_rules
        echo "traffic proxy set to selective mode (strict leak guard)"
        ;;
    device)
        [ $# -eq 3 ] || { echo "usage: traffic.sh device <ip|mac> proxy|direct" >&2; exit 2; }
        selector="$(normalize_selector "$2")" || { echo "invalid device selector: $2" >&2; exit 2; }
        action="$3"
        mode="$(cat "$MODE_FILE" 2>/dev/null || echo off)"
        case "$action" in
            proxy)
                remove_line "$DIRECT_LIST" "$selector"
                add_line "$PROXY_LIST" "$selector"
                [ "$mode" != off ] || echo selective > "$MODE_FILE"
                ;;
            direct)
                remove_line "$PROXY_LIST" "$selector"
                add_line "$DIRECT_LIST" "$selector"
                ;;
            *) echo "action must be proxy or direct" >&2; exit 2 ;;
        esac
        apply_rules
        echo "$selector => $action"
        ;;
    status) status ;;
    apply) apply_rules ;;
    clear) clear_rules ;;
    *) echo "usage: traffic.sh on|off|selective|device <ip|mac> proxy|direct|status|apply|clear" >&2; exit 2 ;;
esac
