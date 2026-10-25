#!/bin/sh
# Uses only the already-installed sing-box and curl; no download or persistent config edits.
set -eu
BASE=/data/proxy-mode
BIN=$BASE/bin/sing-box
CFG=$BASE/runtime/active.json
[ "$(cat "$BASE/runtime/current_mode")" = 11 ] || { echo 'Select Mode 11 first'; exit 1; }
WORK=$(mktemp -d /tmp/u60-vless6-check.XXXXXX)
PID=''
trap '[ -z "$PID" ] || kill "$PID" 2>/dev/null; rm -rf "$WORK"' EXIT
OUT=$(jsonfilter -i "$CFG" -e '@.outbounds')
FINAL=$(jsonfilter -i "$CFG" -e '@.route.final')
cat > "$WORK/config.json" <<EOF
{"log":{"level":"warn"},"inbounds":[{"type":"mixed","tag":"test","listen":"127.0.0.1","listen_port":17891}],"outbounds":$OUT,"route":{"final":"$FINAL"}}
EOF
"$BIN" check -c "$WORK/config.json"
"$BIN" run -c "$WORK/config.json" > "$WORK/log" 2>&1 &
PID=$!
sleep 2
kill -0 "$PID" 2>/dev/null || { tail -n 15 "$WORK/log"; exit 1; }
echo 'Proxy IPv4 exit (expected Azure IPv4):'
curl --http1.1 --noproxy '' --proxy socks5h://127.0.0.1:17891 --connect-timeout 10 --max-time 25 -fsS https://api.ipify.org || true
echo
echo 'Proxy IPv6 exit (expected Azure IPv6, never local carrier IPv6):'
curl --http1.1 --noproxy '' --proxy socks5h://127.0.0.1:17891 --connect-timeout 10 --max-time 25 -fsS https://api6.ipify.org || true
echo
echo 'IPv6 adapter and routing status:'
sh /data/proxy-mode/scripts/vless-ipv6.sh status
echo 'IPv6 TCP counters:'
ip6tables -t nat -nvL U60PM_VLESS6_TCP
echo 'IPv6 UDP counters:'
ip6tables -t mangle -nvL U60PM_VLESS6_UDP
echo 'Recent local test errors:'
tail -n 10 "$WORK/log"
echo 'The SOCKS tests verify remote TCP egress. Verify client TCP/UDP forwarding separately over Wi-Fi.'
