#!/bin/sh
# Read-only readiness check. No firewall changes, no credentials in output.
set -eu
CFG="$1"
command -v jsonfilter >/dev/null || { echo "jsonfilter required" >&2; exit 1; }
[ -r "$CFG" ] || { echo "Config unavailable" >&2; exit 1; }
tag="$(jsonfilter -i "$CFG" -e '@.route.final' 2>/dev/null || true)"
[ -n "$tag" ] || exit 0
# Iterate outbound indexes without depending on mode numbers.
i=0
while [ "$i" -lt 128 ]; do
    t="$(jsonfilter -i "$CFG" -e "@.outbounds[$i].tag" 2>/dev/null || true)"
    [ -n "$t" ] || exit 0
    if [ "$t" = "$tag" ]; then
        [ "$(jsonfilter -i "$CFG" -e "@.outbounds[$i].type")" = vless ] || exit 0
        server="$(jsonfilter -i "$CFG" -e "@.outbounds[$i].server" 2>/dev/null || true)"
        case "$server" in *:*) ;; *) exit 0;; esac
        case "$server" in *[!0-9a-fA-F:]*) echo 'Invalid IPv6 literal' >&2; exit 1;; esac
        command -v ip6tables >/dev/null || { echo 'IPv6 guard unavailable' >&2; exit 1; }
        [ "$(jsonfilter -i "$CFG" -e '@.dns.strategy')" = ipv4_only ] || {
            echo 'IPv6 upstream profile requires dns.strategy=ipv4_only' >&2; exit 1;
        }
        for src in $(ip -6 addr show scope global | awk '/inet6 [23]/{if ($0 !~ /tentative|dadfailed|deprecated/){split($2,a,"/");print a[1]}}'); do
            if ip -6 route get "$server" from "$src" 2>/dev/null | grep -Eq ' dev (rmnet[^ ]*|wwan[^ ]*)[[:space:]]'; then
                echo 'IPv6 upstream route available'
                exit 0
            fi
        done
        echo 'IPv6 upstream route unavailable; check cellular IPv6/APN' >&2
        exit 1
    fi
    i=$((i+1))
done
echo 'Unable to identify final outbound' >&2
exit 1
