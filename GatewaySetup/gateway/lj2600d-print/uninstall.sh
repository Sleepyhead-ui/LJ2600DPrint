#!/bin/sh

set -eu
BASE=/osgi/lj2600d-print
START_LIST=/fhconf/process_start_list
BACKUP="$BASE/setup-backup/process_start_list.before-install"
BOOT=/fhconf/lj2600d-start.sh

if [ -f "$BACKUP" ] && [ -w "$START_LIST" ]; then
    cp "$BACKUP" "$START_LIST"
fi
if [ -f "$BASE/setup-backup/lj2600d-start.sh.before-install" ]; then
    cp "$BASE/setup-backup/lj2600d-start.sh.before-install" "$BOOT"
elif [ -f "$BASE/setup-backup/lj2600d-start.sh.was-absent" ]; then
    rm -f "$BOOT"
fi

for pidfile in /var/tmp/lj2600d-watch.pid /var/tmp/lj2600d-lpd.pid; do
    if [ -s "$pidfile" ]; then
        pid=$(cat "$pidfile")
        kill "$pid" 2>/dev/null || true
    fi
done
for pid in $(ps | grep '[o]sgi/lj2600d-print/watch.sh' | awk '{print $1}'); do
    kill "$pid" 2>/dev/null || true
done
for pid in $(ps | grep '[t]cpsvd -E .* 515 ' | awk '{print $1}'); do
    kill "$pid" 2>/dev/null || true
done
sleep 1
for pid in $(ps | grep '[o]sgi/lj2600d-print/watch.sh' | awk '{print $1}'); do
    kill -9 "$pid" 2>/dev/null || true
done
for pid in $(ps | grep '[t]cpsvd -E .* 515 ' | awk '{print $1}'); do
    kill -9 "$pid" 2>/dev/null || true
done
rm -f /var/tmp/lj2600d-watch.pid /var/tmp/lj2600d-lpd.pid
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
