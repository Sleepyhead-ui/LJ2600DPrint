#!/bin/sh

set -eu
BASE=/osgi/lj2600d-print
BOOT=/fhconf/lj2600d-start.sh
INSTALL_CONF=/osgi/install.conf
LOCAL_BUNDLES=/osgi/local_bundles
BUNDLE_NAME=io.github.sleepyhead.lj2600d.bootstrap_1.0.1.jar
BUNDLE_LEGACY_NAME=io.github.sleepyhead.lj2600d.bootstrap_1.0.0.jar
BUNDLE_SOURCE="$BASE/osgi/$BUNDLE_NAME"
BUNDLE_TARGET="$LOCAL_BUNDLES/$BUNDLE_NAME"
BUNDLE_SYMBOLIC_NAME=io.github.sleepyhead.lj2600d.bootstrap
BUNDLE_ENTRY='{"Location":"/osgi/local_bundles/io.github.sleepyhead.lj2600d.bootstrap_1.0.1.jar","SymbolicName":"io.github.sleepyhead.lj2600d.bootstrap","Version":"1.0.1","ControlAutoStart":true,"IsBuiltIn":false}'
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
[ -f "$INSTALL_CONF" ] && [ -d "$LOCAL_BUNDLES" ] || {
    echo 'The FiberHome OSGi lifecycle configuration was not found.' >&2; exit 1; }
[ -f "$BUNDLE_SOURCE" ] || { echo 'The OSGi bootstrap bundle is missing.' >&2; exit 1; }

mkdir -p "$BASE/setup-backup"
if [ ! -f "$BASE/setup-backup/install.conf.before-install" ]; then
    cp "$INSTALL_CONF" "$BASE/setup-backup/install.conf.before-install"
fi
if [ -e "$BUNDLE_TARGET" ] && [ ! -f "$BASE/setup-backup/bootstrap.jar.before-install" ]; then
    cp "$BUNDLE_TARGET" "$BASE/setup-backup/bootstrap.jar.before-install"
elif [ ! -e "$BUNDLE_TARGET" ]; then
    : > "$BASE/setup-backup/bootstrap.jar.was-absent"
fi
if [ -e "$BOOT" ] && [ ! -f "$BASE/setup-backup/lj2600d-start.sh.before-install" ]; then
    cp "$BOOT" "$BASE/setup-backup/lj2600d-start.sh.before-install"
elif [ ! -e "$BOOT" ]; then
    : > "$BASE/setup-backup/lj2600d-start.sh.was-absent"
fi
chmod 755 "$BASE/boot.sh" "$BASE/watch.sh" "$BASE/install.sh" "$BASE/uninstall.sh"
printf 'LISTEN_ADDRESS=%s\n' "$LISTEN_ADDRESS" > "$BASE/service.conf"
chmod 600 "$BASE/service.conf"

cp "$BASE/boot.sh" "$BOOT"
chmod 755 "$BOOT"
: > "$BASE/osgi-bootstrap.log"
chmod 666 "$BASE/osgi-bootstrap.log"
cp "$BUNDLE_SOURCE" "$BUNDLE_TARGET"
chmod 644 "$BUNDLE_TARGET"
rm -f "$LOCAL_BUNDLES/$BUNDLE_LEGACY_NAME"

# FiberHome keeps an installed bundle in /osgi/felix-cache even when its
# install.conf location changes. Refresh only this bundle's cached revision so
# an upgrade takes effect at the next Felix start without clearing vendor data.
for info in /osgi/felix-cache/bundle*/bundle.info; do
    [ -f "$info" ] || continue
    if grep -q 'io.github.sleepyhead.lj2600d.bootstrap_' "$info"; then
        cache_dir=${info%/bundle.info}
        if [ -f "$cache_dir/version0.0/bundle.jar" ]; then
            cp "$BUNDLE_SOURCE" "$cache_dir/version0.0/bundle.jar"
            chmod 644 "$cache_dir/version0.0/bundle.jar"
        fi
        for metadata in "$info" "$cache_dir/version0.0/revision.location"; do
            [ -f "$metadata" ] || continue
            sed "s#$BUNDLE_LEGACY_NAME#$BUNDLE_NAME#g" "$metadata" \
                > "$BASE/setup-backup/felix-cache.metadata"
            cat "$BASE/setup-backup/felix-cache.metadata" > "$metadata"
        done
        rm -f "$BASE/setup-backup/felix-cache.metadata"
    fi
done
sed "/\"SymbolicName\":\"$BUNDLE_SYMBOLIC_NAME\"/d" "$INSTALL_CONF" > "$BASE/setup-backup/install.conf.new"
printf '%s\n' "$BUNDLE_ENTRY" >> "$BASE/setup-backup/install.conf.new"
chmod 644 "$BASE/setup-backup/install.conf.new"
mv "$BASE/setup-backup/install.conf.new" "$INSTALL_CONF"
rm -f /osgi/.lj2600d-bootstrap-disabled
printf '%s\n' 'managed by LJ2600DPrint GatewaySetup' > "$BASE/.gateway-setup-managed"

# Remove entries made by the earlier, ineffective /fhconf startup method.
if [ -w /fhconf/process_start_list ]; then
    sed '/^lj2600d_lpd,/d; \
         /\/osgi\/lj2600d-print\/watch\.sh/d; \
         /\/fhconf\/lj2600d-start\.sh/d' /fhconf/process_start_list \
        > "$BASE/setup-backup/process_start_list.migrate"
    cat "$BASE/setup-backup/process_start_list.migrate" > /fhconf/process_start_list
    rm -f "$BASE/setup-backup/process_start_list.migrate"
fi
sync

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
nohup "$BOOT" >/var/tmp/lj2600d-watch.launch.log 2>&1 &
sleep 3
if ! netstat -lnt 2>/dev/null | grep -q ':515 '; then
    echo 'LPD did not start on TCP port 515.' >&2
    exit 1
fi
echo 'LJ2600D LPD service installed.'
