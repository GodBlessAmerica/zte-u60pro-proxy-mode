#!/bin/sh
set -eu

fail() { echo "[FAIL] $*" >&2; exit 1; }
ok() { echo "[ OK ] $*"; }
warn() { echo "[WARN] $*" >&2; }

[ "$(uname -m 2>/dev/null || true)" = "aarch64" ] || fail "unsupported architecture: $(uname -m 2>/dev/null || echo unknown)"
[ -w /data ] || fail "/data is not writable"
[ -c /dev/net/tun ] || fail "/dev/net/tun is unavailable"
command -v ip >/dev/null 2>&1 || fail "ip command missing"
command -v iptables >/dev/null 2>&1 || fail "iptables command missing"
command -v grep >/dev/null 2>&1 || fail "grep command missing"

if iptables -V 2>/dev/null | grep -qi legacy; then
    ok "iptables-legacy detected"
else
    warn "iptables backend is not reported as legacy"
fi

ip link show br-lan >/dev/null 2>&1 || fail "br-lan not found"
ip link show rmnet_data0 >/dev/null 2>&1 || fail "rmnet_data0 not found"
ip route | grep -q '^default .*rmnet_data0' || warn "default IPv4 route is not currently via rmnet_data0"

if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)" = "1" ]; then
    ok "IPv4 forwarding enabled"
else
    warn "IPv4 forwarding is disabled"
fi

ok "preflight passed"
