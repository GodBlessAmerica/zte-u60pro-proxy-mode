#!/bin/sh
set -eu

BASE=/data/proxy-mode
RUNTIME="$BASE/runtime"
LAN=br-lan
PORT=7893
CHAIN=U60PM_REDIRECT
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

clear_rules() {
    iptables -t nat -D PREROUTING -i "$LAN" -j "$CHAIN" 2>/dev/null || true
    iptables -t nat -F "$CHAIN" 2>/dev/null || true
    iptables -t nat -X "$CHAIN" 2>/dev/null || true
}

base_chain() {
    iptables -t nat -N "$CHAIN" 2>/dev/null || true
    iptables -t nat -F "$CHAIN"
    iptables -t nat -A "$CHAIN" -d 10.0.0.0/8 -j RETURN
    iptables -t nat -A "$CHAIN" -d 172.16.0.0/12 -j RETURN
    iptables -t nat -A "$CHAIN" -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A "$CHAIN" -d 127.0.0.0/8 -j RETURN
}

apply_rules() {
    mode="$(cat "$MODE_FILE" 2>/dev/null || echo off)"
    clear_rules
    [ "$mode" = off ] && return 0

    base_chain
    case "$mode" in
        all)
            while IFS= read -r ip; do
                [ -n "$ip" ] || continue
                iptables -t nat -A "$CHAIN" -s "$ip/32" -j RETURN
            done < "$DIRECT_LIST"
            iptables -t nat -A "$CHAIN" -p tcp -j REDIRECT --to-ports "$PORT"
            ;;
        selective)
            while IFS= read -r ip; do
                [ -n "$ip" ] || continue
                iptables -t nat -A "$CHAIN" -s "$ip/32" -p tcp -j REDIRECT --to-ports "$PORT"
            done < "$PROXY_LIST"
            ;;
        *)
            echo off > "$MODE_FILE"
            clear_rules
            return 1
            ;;
    esac
    iptables -t nat -I PREROUTING 1 -i "$LAN" -j "$CHAIN"
}

status() {
    mode="$(cat "$MODE_FILE" 2>/dev/null || echo off)"
    echo "traffic_mode=$mode"
    echo "proxy_devices=$(tr '\n' ' ' < "$PROXY_LIST" | sed 's/[[:space:]]*$//')"
    echo "direct_devices=$(tr '\n' ' ' < "$DIRECT_LIST" | sed 's/[[:space:]]*$//')"
}

cmd="${1:-status}"
case "$cmd" in
    on)
        echo all > "$MODE_FILE"
        apply_rules
        echo "traffic proxy enabled for all LAN clients"
        ;;
    off)
        echo off > "$MODE_FILE"
        clear_rules
        echo "traffic proxy disabled"
        ;;
    selective)
        echo selective > "$MODE_FILE"
        apply_rules
        echo "traffic proxy set to selective mode"
        ;;
    device)
        [ $# -eq 3 ] || { echo "usage: traffic.sh device <ip> proxy|direct" >&2; exit 2; }
        ip="$2"; action="$3"
        valid_ipv4 "$ip" || { echo "invalid IPv4 address: $ip" >&2; exit 2; }
        mode="$(cat "$MODE_FILE" 2>/dev/null || echo off)"
        case "$action" in
            proxy)
                remove_line "$DIRECT_LIST" "$ip"
                add_line "$PROXY_LIST" "$ip"
                if [ "$mode" = off ]; then echo selective > "$MODE_FILE"; fi
                ;;
            direct)
                remove_line "$PROXY_LIST" "$ip"
                add_line "$DIRECT_LIST" "$ip"
                ;;
            *) echo "action must be proxy or direct" >&2; exit 2 ;;
        esac
        apply_rules
        echo "$ip => $action"
        ;;
    status) status ;;
    apply) apply_rules ;;
    clear) clear_rules ;;
    *) echo "usage: traffic.sh on|off|selective|device <ip> proxy|direct|status|apply|clear" >&2; exit 2 ;;
esac
