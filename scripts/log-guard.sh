#!/bin/sh
set -eu

LOGDIR=/data/proxy-mode/logs
MAX_BYTES=${MAX_BYTES:-5242880}
KEEP_BYTES=${KEEP_BYTES:-1048576}
INTERVAL=${INTERVAL:-300}

mkdir -p "$LOGDIR"

trim_file() {
    file="$1"
    [ -f "$file" ] || return 0
    size="$(wc -c < "$file" 2>/dev/null || echo 0)"
    case "$size" in ''|*[!0-9]*) size=0 ;; esac
    [ "$size" -gt "$MAX_BYTES" ] || return 0

    tmp="$file.trim.$$"
    if tail -c "$KEEP_BYTES" "$file" > "$tmp" 2>/dev/null; then
        cat "$tmp" > "$file"
        rm -f "$tmp"
        printf '%s trimmed %s to last %s bytes\n' "$(date)" "$file" "$KEEP_BYTES" >> "$LOGDIR/log-guard.log"
    else
        rm -f "$tmp"
        : > "$file"
        printf '%s truncated %s\n' "$(date)" "$file" >> "$LOGDIR/log-guard.log"
    fi
}

run_once() {
    trim_file "$LOGDIR/sing-box.log"
    trim_file "$LOGDIR/startup.log"
    trim_file "$LOGDIR/u60-web.log"
    trim_file "$LOGDIR/log-guard.log"
}

case "${1:-daemon}" in
    once)
        run_once
        ;;
    daemon)
        while :; do
            run_once
            sleep "$INTERVAL"
        done
        ;;
    *)
        echo "usage: log-guard.sh [once|daemon]" >&2
        exit 2
        ;;
esac
