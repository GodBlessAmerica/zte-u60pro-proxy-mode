#!/bin/sh
set -eu

BASE=/data/proxy-mode
RUNTIME="$BASE/runtime"
LAN=br-lan
TUN=u60udp0
MARK=0x67
MASK=0xff
TABLE=167
CHAIN=U60PM_UDP_TUN
PROXY_LIST="$RUNTIME/proxy_devices"
DIRECT_LIST="$RUNTIME/direct_devices"
TRAFFIC_MODE="$RUNTIME/traffic_mode"
STATE_FILE="$RUNTIME/full_proxy_udp_tun"

mkdir -p "$RUNTIME"
[ -f "$STATE_FILE" ] || echo off > "$STATE_FILE"

remove_jump() {
    while iptables -t mangle -C PREROUTING -i "$LAN" -j "$CHAIN" 2>/dev/null; do
        iptables -t mangle -D PREROUTING -i "$LAN" -j "$CHAIN" 2>/dev/null || break
    done
}

remove_forward_rules() {
    while iptables -C FORWARD -i "$TUN" -o "$LAN" -j ACCEPT 2>/dev/null; do
        iptables -D FORWARD -i "$TUN" -o "$LAN" -j ACCEPT 2>/dev/null || break
    done
    while iptables -C FORWARD -i "$LAN" -o "$TUN" -p udp -m mark --mark "$MARK/$MASK" -j ACCEPT 2>/dev/null; do
        iptables -D FORWARD -i "$LAN" -o "$TUN" -p udp -m mark --mark "$MARK/$MASK" -j ACCEPT 2>/dev/null || break
    done
}

clear_rules() {
    remove_jump
    remove_forward_rules
    iptables -t mangle -F "$CHAIN" 2>/dev/null || true
    iptables -t mangle -X "$CHAIN" 2>/dev/null || true
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
}

append_selector() {
    action="$1" selector="$2"
    kind="${selector%%:*}"
    value="${selector#*:}"
    case "$kind:$action" in
        mac:return) iptables -t mangle -A "$CHAIN" -m mac --mac-source "$value" -j RETURN ;;
        ip:return) iptables -t mangle -A "$CHAIN" -s "$value/32" -j RETURN ;;
        mac:proxy) iptables -t mangle -A "$CHAIN" -m mac --mac-source "$value" -p udp -j MARK --set-xmark "$MARK/$MASK" ;;
        ip:proxy) iptables -t mangle -A "$CHAIN" -s "$value/32" -p udp -j MARK --set-xmark "$MARK/$MASK" ;;
    esac
}

apply_rules() {
    [ -d "/sys/class/net/$TUN" ] || { echo "$TUN is not ready" >&2; exit 1; }
    clear_rules
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
            iptables -t mangle -A "$CHAIN" -p udp -j MARK --set-xmark "$MARK/$MASK"
            ;;
        off)
            echo "traffic mode is off; UDP TUN not attached" >&2
            clear_rules
            echo off > "$STATE_FILE"
            exit 1
            ;;
        *)
            echo "unsupported traffic mode: $mode" >&2
            clear_rules
            echo off > "$STATE_FILE"
            exit 1
            ;;
    esac

    iptables -t mangle -I PREROUTING 1 -i "$LAN" -j "$CHAIN"
    ip rule add fwmark "$MARK/$MASK" table "$TABLE" 2>/dev/null || true
    ip route replace default dev "$TUN" metric 10 table "$TABLE"
    ip route replace blackhole default metric 32767 table "$TABLE"

    iptables -I FORWARD 1 -i "$LAN" -o "$TUN" -p udp -m mark --mark "$MARK/$MASK" -j ACCEPT
    iptables -I FORWARD 1 -i "$TUN" -o "$LAN" -j ACCEPT

    echo on > "$STATE_FILE"
}

status() {
    tun=no
    [ -d "/sys/class/net/$TUN" ] && tun=yes
    chain=no
    iptables -t mangle -C PREROUTING -i "$LAN" -j "$CHAIN" 2>/dev/null && chain=yes || true
    rule=no
    ip rule show 2>/dev/null | grep -q "fwmark 0x67.*lookup 167" && rule=yes || true
    route=no
    ip route show table "$TABLE" 2>/dev/null | grep -q "default dev $TUN" && route=yes || true
    blackhole=no
    ip route show table "$TABLE" 2>/dev/null | grep -q "blackhole default" && blackhole=yes || true

    # Live state wins over any stale runtime marker. This prevents the retired
    # udp-tproxy helper from making the UI report OFF while the TUN path is up.
    state=off
    if [ "$tun" = yes ] && [ "$chain" = yes ] && [ "$rule" = yes ] && [ "$route" = yes ] && [ "$blackhole" = yes ]; then
        state=on
    fi

    echo "$state" > "$STATE_FILE"
    echo "full_proxy_udp=$state"
    echo "udp_tun_interface=$TUN"
    echo "udp_tun_ready=$tun"
    echo "udp_tun_chain=$chain"
    echo "udp_policy_rule=$rule"
    echo "udp_tun_route=$route"
    echo "udp_fail_closed=$blackhole"
}

case "${1:-status}" in
    apply|on) apply_rules; status ;;
    off|clear|disable) clear_rules; echo off > "$STATE_FILE"; status ;;
    status) status ;;
    *) echo "usage: udp-tun.sh apply|off|status" >&2; exit 2 ;;
esac
