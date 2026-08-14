#!/bin/sh

set -eu
BASE=/osgi/lj2600d-print
START_LIST=/fhconf/process_start_list
BACKUP="$BASE/setup-backup/process_start_list.before-install"

if [ -f "$BACKUP" ] && [ -w "$START_LIST" ]; then
    cp "$BACKUP" "$START_LIST"
fi

for pidfile in /var/tmp/lj2600d-watch.pid /var/tmp/lj2600d-lpd.pid; do
    if [ -s "$pidfile" ]; then
        pid=$(cat "$pidfile")
        kill "$pid" 2>/dev/null || true
        rm -f "$pidfile"
    fi
done
rm -f "$BASE/.gateway-setup-managed"
sync

if [ -d /osgi/lj2600d-print.previous ]; then
    rm -rf /osgi/lj2600d-print.gateway-setup-disabled
    mv "$BASE" /osgi/lj2600d-print.gateway-setup-disabled
    mv /osgi/lj2600d-print.previous "$BASE"
    if [ -x "$BASE/watch.sh" ]; then
        nohup "$BASE/watch.sh" >/var/tmp/lj2600d-watch.launch.log 2>&1 &
    fi
    echo 'GatewaySetup changes were reverted and the previous print service was restored.'
else
    echo 'GatewaySetup changes were reverted. Installed files were retained for inspection.'
fi
