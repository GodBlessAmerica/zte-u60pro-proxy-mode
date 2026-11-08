#!/bin/sh
# Start the web control plane only unless the user has configured a validated
# real profile. Never start placeholder JSON or silently enable client proxying.
BASE=/data/proxy-mode
[ -x /data/start-u60proxy-v2.sh ] && sh /data/start-u60proxy-v2.sh
if [ ! -s "$BASE/runtime/active.json" ]; then exit 0; fi
[ -x "$BASE/bin/sing-box" ] || exit 0
"$BASE/bin/sing-box" check -c "$BASE/runtime/active.json" >/dev/null 2>&1 || exit 0
[ -x "$BASE/bin/proxy-mode" ] && "$BASE/bin/proxy-mode" start >/dev/null 2>&1 || true
