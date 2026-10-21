#!/bin/sh
# Existing rc.local entry remains valid. No persistent log or polling supervisor.
BIN=/data/u60proxy/bin/u60proxy
RT=/data/u60proxy/runtime
mkdir -p "$RT"
if [ -s "$RT/web.pid" ]; then
 p=$(cat "$RT/web.pid")
 case "$p" in ''|*[!0-9]*) ;; *)
  if [ -r "/proc/$p/cmdline" ] && tr '\000' ' ' < "/proc/$p/cmdline" | grep -q '^/data/u60proxy/bin/u60proxy serve'; then exit 0; fi;;
 esac
fi
(
 i=0
 while [ "$i" -lt 60 ]; do
  ip addr show br-lan 2>/dev/null | grep -q '10\.66\.0\.1/' && break
  sleep 1
  i=$((i+1))
 done
 exec "$BIN" serve
) </dev/null >/dev/null 2>&1 &
echo $! > "$RT/web.pid"
