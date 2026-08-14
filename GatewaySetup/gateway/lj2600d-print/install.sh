#!/bin/sh

set -eu
BASE=/osgi/lj2600d-print
START_LIST=/fhconf/process_start_list
ENTRY='lj2600d_lpd,ready:[false],cmd:[/osgi/lj2600d-print/watch.sh &];'
LISTEN_ADDRESS=${1:-}

if [ -z "$LISTEN_ADDRESS" ] && [ -r "$BASE/service.conf" ]; then
    . "$BASE/service.conf"
fi
LISTEN_ADDRESS=${LISTEN_ADDRESS:-192.168.1.1}

case "$LISTEN_ADDRESS" in
    *[!0-9.]*) echo 'Usage: install.sh <LAN IPv4 address>' >&2; exit 2 ;;
esac

[ -c /dev/lp0 ] || { echo '/dev/lp0 is not a USB printer character device.' >&2; exit 1; }
for command_name in tcpsvd lpd softlimit netstat; do
    command -v "$command_name" >/dev/null 2>&1 || { echo "$command_name is unavailable." >&2; exit 1; }
done
[ -f "$START_LIST" ] && [ -w "$START_LIST" ] || {
    echo 'Supported FiberHome startup configuration was not found.' >&2
    exit 1
}

mkdir -p "$BASE/setup-backup"
if [ ! -f "$BASE/setup-backup/process_start_list.before-install" ]; then
    cp "$START_LIST" "$BASE/setup-backup/process_start_list.before-install"
fi
chmod 755 "$BASE/watch.sh" "$BASE/install.sh" "$BASE/uninstall.sh"
printf 'LISTEN_ADDRESS=%s\n' "$LISTEN_ADDRESS" > "$BASE/service.conf"
chmod 600 "$BASE/service.conf"

if ! grep -Fq '/osgi/lj2600d-print/watch.sh' "$START_LIST"; then
    printf '%s\n' "$ENTRY" >> "$START_LIST"
fi
printf '%s\n' 'managed by LJ2600DPrint GatewaySetup' > "$BASE/.gateway-setup-managed"
sync

nohup "$BASE/watch.sh" >/var/tmp/lj2600d-watch.launch.log 2>&1 &
sleep 3
if ! netstat -lnt 2>/dev/null | grep -q ':515 '; then
    echo 'LPD did not start on TCP port 515.' >&2
    exit 1
fi
echo 'LJ2600D LPD service installed.'
