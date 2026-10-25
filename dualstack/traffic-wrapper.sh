#!/bin/sh
# U60_VLESS_DUALSTACK_WRAPPER_V1
set -eu
BASE=/data/proxy-mode/scripts
"$BASE/traffic-vless6-base.sh" "$@"
case "${1:-status}" in
 apply|selective|on) "$BASE/vless-ipv6.sh" apply;;
 off|clear) "$BASE/vless-ipv6.sh" clear;;
 status) "$BASE/vless-ipv6.sh" status;;
esac
