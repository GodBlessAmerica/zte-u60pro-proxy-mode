#!/bin/sh
set -eu

BASE=/data/proxy-mode
RUNTIME="$BASE/runtime"
LAN=br-lan
PORT=7894
MARK=0x66
MASK=0xff
TABLE=166
CHAIN=U60PM_UDP_TPROXY
INPUT_CHAIN=U60PM_UDP_INPUT
PROXY_LIST="$RUNTIME/proxy_devices"
DIRECT_LIST="$RUNTIME/direct_devices"
TRAFFIC_MODE="$RUNTIME/traffic_mode"
STATE_FILE="$RUNTIME/full_proxy_udp"

mkdir -p "$RUNTIME"
[ -f "$STATE_FILE" ] || echo off > "$STATE_FILE"

have_tproxy() {
    test_chain=U60PM_TP_TEST
    iptables -t mangle -N "$test_chain" 2>/dev/null || true
    iptables -t mangle -F "$test_chain" 2>/dev/null || true
    if iptables -t mangle -A "$test_chain" -p udp -j TPROXY --on-port "$PORT" --tproxy-mark "$MARK/$MASK" 2>/dev/null; then
        iptables -t mangle -F "$test_chain" 2>/dev/null || true
        iptables -t mangle -X "$test_chain" 2>/dev/null || true
        return 0
    fi
    iptables -t mangle -F "$test_chain" 2>/dev/null || true
    iptables -t mangle -X "$test_chain" 2>/dev/null || true
    return 1
}

remove_jump() {
    while iptables -t mangle -C PREROUTING -i "$LAN" -j "$CHAIN" 2>/dev/null; do
        iptables -t mangle -D PREROUTING -i "$LAN" -j "$CHAIN" 2>/dev/null || break
    done
    while iptables -C INPUT -i "$LAN" -j "$INPUT_CHAIN" 2>/dev/null; do
        iptables -D INPUT -i "$LAN" -j "$INPUT_CHAIN" 2>/dev/null || break
    done
}

clear_rules() {
    remove_jump
    iptables -t mangle -F "$CHAIN" 2>/dev/null || true
    iptables -t mangle -X "$CHAIN" 2>/dev/null || true
    iptables -F "$INPUT_CHAIN" 2>/dev/null || true
    iptables -X "$INPUT_CHAIN" 2>/dev/null || true
    while ip rule del fwmark "$MARK/$MASK" table "$TABLE" 2>/dev/null; do :; done
    ip route flush table "$TABLE" 2>/dev/null || true
}

base_chain() {
    iptables -t mangle -N "$CHAIN" 2>/dev/null || true
    iptables -t mangle -F "$CHAIN"
    iptables -t mangle -A "$CHAIN" -d 0.0.0.0/8 -j RETURN
    iptables -t mangle -A "$CHAIN" -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A "$CHAIN" -d 100.64.0.0/10 -j RETURN
    iptables -t mangle -A "$CHAIN" -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A "$CHAIN" -d 169.254.0.0/16 -j RETURN
    iptables -t mangle -A "$CHAIN" -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A "$CHAIN" -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A "$CHAIN" -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A "$CHAIN" -d 240.0.0.0/4 -j RETURN
    iptables -t mangle -A "$CHAIN" -p udp --dport 53 -j RETURN
    iptables -t mangle -A "$CHAIN" -p udp --dport 67:68 -j RETURN
    iptables -t mangle -A "$CHAIN" -p udp --dport 123 -j RETURN
}

append_selector() {
    action="$1" selector="$2"
    kind="${selector%%:*}"
    value="${selector#*:}"
    case "$kind:$action" in
        mac:return) iptables -t mangle -A "$CHAIN" -m mac --mac-source "$value" -j RETURN ;;
        ip:return) iptables -t mangle -A "$CHAIN" -s "$value/32" -j RETURN ;;
        mac:proxy) iptables -t mangle -A "$CHAIN" -m mac --mac-source "$value" -p udp -j TPROXY --on-port "$PORT" --tproxy-mark "$MARK/$MASK" ;;
        ip:proxy) iptables -t mangle -A "$CHAIN" -s "$value/32" -p udp -j TPROXY --on-port "$PORT" --tproxy-mark "$MARK/$MASK" ;;
    esac
}

setup_policy_route() {
    ip rule add fwmark "$MARK/$MASK" table "$TABLE" 2>/dev/null || true
    ip route replace local 0.0.0.0/0 dev lo table "$TABLE"
}

setup_input() {
    iptables -N "$INPUT_CHAIN" 2>/dev/null || true
    iptables -F "$INPUT_CHAIN"
    iptables -A "$INPUT_CHAIN" -p udp --dport "$PORT" -j ACCEPT
    iptables -I INPUT 1 -i "$LAN" -j "$INPUT_CHAIN"
}

apply_rules() {
    have_tproxy || { echo "TPROXY target unavailable" >&2; exit 1; }
    clear_rules
    setup_policy_route
    base_chain
    mode="$(cat "$TRAFFIC_MODE" 2>/dev/null || echo off)"
    case "$mode" in
        selective)
            while IFS= read -r selector; do
                [ -n "$selector" ] || continue
                append_selector proxy "$selector"
            done < "$PROXY_LIST"
            ;;
        all)
            while IFS= read -r selector; do
                [ -n "$selector" ] || continue
                append_selector return "$selector"
            done < "$DIRECT_LIST"
            iptables -t mangle -A "$CHAIN" -p udp -j TPROXY --on-port "$PORT" --tproxy-mark "$MARK/$MASK"
            ;;
        off)
            echo "traffic mode is off; UDP full proxy not attached" >&2
            clear_rules
            exit 1
            ;;
        *)
            echo "unsupported traffic mode: $mode" >&2
            clear_rules
            exit 1
            ;;
    esac
    iptables -t mangle -I PREROUTING 1 -i "$LAN" -j "$CHAIN"
    setup_input
    echo on > "$STATE_FILE"
}

status() {
    state="$(cat "$STATE_FILE" 2>/dev/null || echo off)"
    listener=no
    netstat -lnup 2>/dev/null | grep -q ":$PORT " && listener=yes || true
    chain=no
    iptables -t mangle -C PREROUTING -i "$LAN" -j "$CHAIN" 2>/dev/null && chain=yes || true
    rule=no
    ip rule show 2>/dev/null | grep -q "fwmark 0x66.*lookup $TABLE\|fwmark 0x66.*lookup 166" && rule=yes || true
    echo "full_proxy_udp=$state"
    echo "udp_tproxy_port=$PORT"
    echo "udp_tproxy_listener=$listener"
    echo "udp_tproxy_chain=$chain"
    echo "udp_policy_rule=$rule"
}

preflight() {
    echo "=== UDP TPROXY preflight ==="
    echo "lan=$LAN"
    echo "port=$PORT"
    if have_tproxy; then echo "tproxy_target=ok"; else echo "tproxy_target=missing"; exit 1; fi
    if command -v ip >/dev/null 2>&1; then echo "ip_tool=ok"; else echo "ip_tool=missing"; exit 1; fi
    if [ -f "$PROXY_LIST" ]; then echo "proxy_list=ok"; else echo "proxy_list=missing"; fi
    echo "preflight=ok"
}

case "${1:-status}" in
    preflight) preflight ;;
    apply|on) apply_rules; status ;;
    off|clear|disable) clear_rules; echo off > "$STATE_FILE"; status ;;
    status) status ;;
    *) echo "usage: udp-tproxy.sh preflight|apply|off|status" >&2; exit 2 ;;
esac
