#!/bin/sh
set -eu
if [ -x /data/u60proxy/bin/u60rollback ]; then
  exec /data/u60proxy/bin/u60rollback latest
fi
echo "u60rollback not found; use the backup directory created by install.sh" >&2
exit 1
