#!/bin/sh
set -eu
BASE=/data/proxy-mode
RUNTIME="$BASE/runtime"
LAN=br-lan
PORT=7893
DNS4_PORT=5353
DNS6_PORT=5354
NAT_CHAIN=U60PM_REDIRECT
DNS4_CHAIN=U60PM_DNS4
DNS6_CHAIN=U60PM_DNS6
GUARD4_CHAIN=U60PM_GUARD4
GUARD6_CHAIN=U60PM_GUARD6
INPUT4_CHAIN=U60PM_INPUT4
INPUT6_CHAIN=U60PM_INPUT6
MODE_FILE="$RUNTIME/traffic_mode"
PROXY_LIST="$RUNTIME/proxy_devices"
DNS_LIST="$RUNTIME/dns_devices"
UDP_LIST="$RUNTIME/udp_devices"
IPV6_LIST="$RUNTIME/ipv6_devices"
DIRECT_LIST="$RUNTIME/direct_devices"
mkdir -p "$RUNTIME"
for f in "$PROXY_LIST" "$DNS_LIST" "$UDP_LIST" "$IPV6_LIST" "$DIRECT_LIST"; do [ -f "$f" ] || : > "$f"; done
[ -f "$MODE_FILE" ] || echo selective > "$MODE_FILE"
have_ip6tables(){ command -v ip6tables >/dev/null 2>&1; }
clear_rules(){
 iptables -t nat -D PREROUTING -i "$LAN" -j "$DNS4_CHAIN" 2>/dev/null || true
 iptables -t nat -D PREROUTING -i "$LAN" -j "$NAT_CHAIN" 2>/dev/null || true
 iptables -t nat -F "$DNS4_CHAIN" 2>/dev/null || true; iptables -t nat -X "$DNS4_CHAIN" 2>/dev/null || true
 iptables -t nat -F "$NAT_CHAIN" 2>/dev/null || true; iptables -t nat -X "$NAT_CHAIN" 2>/dev/null || true
 iptables -D FORWARD -i "$LAN" -j "$GUARD4_CHAIN" 2>/dev/null || true; iptables -F "$GUARD4_CHAIN" 2>/dev/null || true; iptables -X "$GUARD4_CHAIN" 2>/dev/null || true
 iptables -D INPUT -i "$LAN" -j "$INPUT4_CHAIN" 2>/dev/null || true; iptables -F "$INPUT4_CHAIN" 2>/dev/null || true; iptables -X "$INPUT4_CHAIN" 2>/dev/null || true
 if have_ip6tables; then
   ip6tables -t nat -D PREROUTING -i "$LAN" -j "$DNS6_CHAIN" 2>/dev/null || true; ip6tables -t nat -F "$DNS6_CHAIN" 2>/dev/null || true; ip6tables -t nat -X "$DNS6_CHAIN" 2>/dev/null || true
   ip6tables -D FORWARD -i "$LAN" -j "$GUARD6_CHAIN" 2>/dev/null || true; ip6tables -F "$GUARD6_CHAIN" 2>/dev/null || true; ip6tables -X "$GUARD6_CHAIN" 2>/dev/null || true
   ip6tables -D INPUT -i "$LAN" -j "$INPUT6_CHAIN" 2>/dev/null || true; ip6tables -F "$INPUT6_CHAIN" 2>/dev/null || true; ip6tables -X "$INPUT6_CHAIN" 2>/dev/null || true
 fi
}
base(){
 iptables -t nat -N "$NAT_CHAIN" 2>/dev/null || true; iptables -t nat -F "$NAT_CHAIN"
 for n in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8; do iptables -t nat -A "$NAT_CHAIN" -d "$n" -j RETURN; done
 iptables -t nat -N "$DNS4_CHAIN" 2>/dev/null || true; iptables -t nat -F "$DNS4_CHAIN"
 iptables -N "$GUARD4_CHAIN" 2>/dev/null || true; iptables -F "$GUARD4_CHAIN"
 for n in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8; do iptables -A "$GUARD4_CHAIN" -d "$n" -j RETURN; done
 iptables -N "$INPUT4_CHAIN" 2>/dev/null || true; iptables -F "$INPUT4_CHAIN"; iptables -A "$INPUT4_CHAIN" -p udp --dport "$DNS4_PORT" -j ACCEPT; iptables -A "$INPUT4_CHAIN" -p tcp --dport "$DNS4_PORT" -j ACCEPT
 if have_ip6tables; then
   ip6tables -t nat -N "$DNS6_CHAIN" 2>/dev/null || true; ip6tables -t nat -F "$DNS6_CHAIN"
   ip6tables -N "$GUARD6_CHAIN" 2>/dev/null || true; ip6tables -F "$GUARD6_CHAIN"; ip6tables -A "$GUARD6_CHAIN" -d fe80::/10 -j RETURN; ip6tables -A "$GUARD6_CHAIN" -d ff00::/8 -j RETURN
   ip6tables -N "$INPUT6_CHAIN" 2>/dev/null || true; ip6tables -F "$INPUT6_CHAIN"; ip6tables -A "$INPUT6_CHAIN" -p udp --dport "$DNS6_PORT" -j ACCEPT; ip6tables -A "$INPUT6_CHAIN" -p tcp --dport "$DNS6_PORT" -j ACCEPT
 fi
}
sel_rule(){ chain="$1" table="$2" selector="$3" proto="$4" target="$5"; kind="${selector%%:*}"; value="${selector#*:}"; if [ "$kind" = mac ]; then $table -A "$chain" -m mac --mac-source "$value" $proto $target; else $table -A "$chain" -s "$value/32" $proto $target; fi; }
apply_rules(){
 mode="$(cat "$MODE_FILE" 2>/dev/null || echo selective)"; clear_rules; [ "$mode" = off ] && return 0; base
 if [ "$mode" = all ]; then
   iptables -t nat -A "$DNS4_CHAIN" -p udp --dport 53 -j REDIRECT --to-ports "$DNS4_PORT"; iptables -t nat -A "$DNS4_CHAIN" -p tcp --dport 53 -j REDIRECT --to-ports "$DNS4_PORT"
   have_ip6tables && { ip6tables -t nat -A "$DNS6_CHAIN" -p udp --dport 53 -j REDIRECT --to-ports "$DNS6_PORT"; ip6tables -t nat -A "$DNS6_CHAIN" -p tcp --dport 53 -j REDIRECT --to-ports "$DNS6_PORT"; }
   iptables -t nat -A "$NAT_CHAIN" -p tcp -j REDIRECT --to-ports "$PORT"; iptables -A "$GUARD4_CHAIN" -p tcp -j RETURN; iptables -A "$GUARD4_CHAIN" -j REJECT; have_ip6tables && ip6tables -A "$GUARD6_CHAIN" -j REJECT
 else
   while IFS= read -r s; do [ -n "$s" ] || continue; sel_rule "$NAT_CHAIN" "iptables -t nat" "$s" "-p tcp" "-j REDIRECT --to-ports $PORT"; done < "$PROXY_LIST"
   while IFS= read -r s; do [ -n "$s" ] || continue; sel_rule "$DNS4_CHAIN" "iptables -t nat" "$s" "-p udp --dport 53" "-j REDIRECT --to-ports $DNS4_PORT"; sel_rule "$DNS4_CHAIN" "iptables -t nat" "$s" "-p tcp --dport 53" "-j REDIRECT --to-ports $DNS4_PORT"; if have_ip6tables && [ "${s%%:*}" = mac ]; then v="${s#*:}"; ip6tables -t nat -A "$DNS6_CHAIN" -m mac --mac-source "$v" -p udp --dport 53 -j REDIRECT --to-ports "$DNS6_PORT"; ip6tables -t nat -A "$DNS6_CHAIN" -m mac --mac-source "$v" -p tcp --dport 53 -j REDIRECT --to-ports "$DNS6_PORT"; fi; done < "$DNS_LIST"
   while IFS= read -r s; do [ -n "$s" ] || continue; sel_rule "$GUARD4_CHAIN" iptables "$s" "-p udp" "-j RETURN"; done < "$UDP_LIST"
   while IFS= read -r s; do [ -n "$s" ] || continue; sel_rule "$GUARD4_CHAIN" iptables "$s" "-p tcp" "-j RETURN"; sel_rule "$GUARD4_CHAIN" iptables "$s" "" "-j REJECT"; done < "$PROXY_LIST"
   if have_ip6tables; then while IFS= read -r s; do [ -n "$s" ] || continue; [ "${s%%:*}" = mac ] || continue; ip6tables -A "$GUARD6_CHAIN" -m mac --mac-source "${s#*:}" -j REJECT; done < "$IPV6_LIST"; fi
 fi
 iptables -t nat -I PREROUTING 1 -i "$LAN" -j "$NAT_CHAIN"; iptables -t nat -I PREROUTING 1 -i "$LAN" -j "$DNS4_CHAIN"; iptables -I FORWARD 1 -i "$LAN" -j "$GUARD4_CHAIN"; iptables -I INPUT 1 -i "$LAN" -j "$INPUT4_CHAIN"
 if have_ip6tables; then ip6tables -t nat -I PREROUTING 1 -i "$LAN" -j "$DNS6_CHAIN"; ip6tables -I FORWARD 1 -i "$LAN" -j "$GUARD6_CHAIN"; ip6tables -I INPUT 1 -i "$LAN" -j "$INPUT6_CHAIN"; fi
}
status(){ echo "traffic_mode=$(cat "$MODE_FILE" 2>/dev/null || echo off)"; for f in proxy_devices dns_devices udp_devices ipv6_devices; do printf '%s=' "$f"; tr '\n' ' ' < "$RUNTIME/$f" 2>/dev/null | sed 's/[[:space:]]*$//'; echo; done; }
case "${1:-status}" in apply|selective) echo selective > "$MODE_FILE"; apply_rules;; off|clear) echo off > "$MODE_FILE"; clear_rules;; on) echo all > "$MODE_FILE"; apply_rules;; status) status;; *) echo "usage: traffic.sh apply|selective|on|off|clear|status" >&2; exit 2;; esac
