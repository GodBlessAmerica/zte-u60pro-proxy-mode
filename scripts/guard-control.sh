#!/bin/sh
set -eu

BASE=/data/proxy-mode
RUNTIME="$BASE/runtime"
LAN=br-lan
UDP_FILE="$RUNTIME/udp_quic_guard"
IPV6_FILE="$RUNTIME/ipv6_guard"
GUARD4=U60PM_GUARD4
GUARD6=U60PM_GUARD6

mkdir -p "$RUNTIME"
[ -f "$UDP_FILE" ] || echo strict > "$UDP_FILE"
[ -f "$IPV6_FILE" ] || echo strict > "$IPV6_FILE"

read_flag() {
    file="$1"
    v="$(cat "$file" 2>/dev/null || echo strict)"
    case "$v" in strict|off) echo "$v" ;; *) echo strict ;; esac
}

remove_jump4() {
    while iptables -C FORWARD -i "$LAN" -j "$GUARD4" 2>/dev/null; do
        iptables -D FORWARD -i "$LAN" -j "$GUARD4" 2>/dev/null || break
    done
}

remove_jump6() {
    command -v ip6tables >/dev/null 2>&1 || return 0
    while ip6tables -C FORWARD -i "$LAN" -j "$GUARD6" 2>/dev/null; do
        ip6tables -D FORWARD -i "$LAN" -j "$GUARD6" 2>/dev/null || break
    done
}

apply() {
    udp="$(read_flag "$UDP_FILE")"
    v6="$(read_flag "$IPV6_FILE")"

    # traffic.sh creates the guard chains. This script only controls whether
    # those isolated chains are attached to FORWARD.
    if iptables -L "$GUARD4" >/dev/null 2>&1; then
        if [ "$udp" = strict ]; then
            iptables -C FORWARD -i "$LAN" -j "$GUARD4" 2>/dev/null || \
                iptables -I FORWARD 1 -i "$LAN" -j "$GUARD4"
        else
            remove_jump4
        fi
    fi

    if command -v ip6tables >/dev/null 2>&1 && ip6tables -L "$GUARD6" >/dev/null 2>&1; then
        if [ "$v6" = strict ]; then
            ip6tables -C FORWARD -i "$LAN" -j "$GUARD6" 2>/dev/null || \
                ip6tables -I FORWARD 1 -i "$LAN" -j "$GUARD6"
        else
            remove_jump6
        fi
    fi
}

status() {
    echo "udp_quic_guard=$(read_flag "$UDP_FILE")"
    if command -v ip6tables >/dev/null 2>&1; then
        echo "ipv6_guard=$(read_flag "$IPV6_FILE")"
    else
        echo "ipv6_guard=unavailable"
    fi
}

case "${1:-status}" in
    status) status ;;
    apply) apply ;;
    udp)
        [ $# -eq 2 ] || { echo "usage: guard-control.sh udp strict|off" >&2; exit 2; }
        case "$2" in strict|off) echo "$2" > "$UDP_FILE" ;; *) exit 2 ;; esac
        apply
        status
        ;;
    ipv6)
        [ $# -eq 2 ] || { echo "usage: guard-control.sh ipv6 strict|off" >&2; exit 2; }
        case "$2" in strict|off) echo "$2" > "$IPV6_FILE" ;; *) exit 2 ;; esac
        apply
        status
        ;;
    *)
        echo "usage: guard-control.sh status|apply|udp strict|off|ipv6 strict|off" >&2
        exit 2
        ;;
esac
