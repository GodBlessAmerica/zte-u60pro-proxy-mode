#!/bin/sh
set -eu

BASE=/data/proxy-mode

if [ -x "$BASE/scripts/stop.sh" ]; then
    "$BASE/scripts/stop.sh" || true
fi

cat <<'EOF'
Proxy process stopped.

For safety this script does not automatically delete /data/proxy-mode because it may contain private mode configs and logs.
To remove everything manually after backing up what you need:
  rm -rf /data/proxy-mode

This project does not modify firmware partitions or the stock ZTE web root.
EOF
