#!/bin/sh

set -eu
BASE=/osgi/lj2600d-print
BOOT=/fhconf/lj2600d-start.sh
INSTALL_CONF=/osgi/install.conf
LOCAL_BUNDLES=/osgi/local_bundles
BUNDLE_NAME=io.github.sleepyhead.lj2600d.bootstrap_1.0.1.jar
BUNDLE_LEGACY_NAME=io.github.sleepyhead.lj2600d.bootstrap_1.0.0.jar
BUNDLE_TARGET="$LOCAL_BUNDLES/$BUNDLE_NAME"
BUNDLE_SYMBOLIC_NAME=io.github.sleepyhead.lj2600d.bootstrap

touch /osgi/.lj2600d-bootstrap-disabled
if [ -f "$BASE/setup-backup/install.conf.before-install" ]; then
    sed "/\"SymbolicName\":\"$BUNDLE_SYMBOLIC_NAME\"/d" "$INSTALL_CONF" > "$BASE/setup-backup/install.conf.uninstall"
    grep "\"SymbolicName\":\"$BUNDLE_SYMBOLIC_NAME\"" \
        "$BASE/setup-backup/install.conf.before-install" >> "$BASE/setup-backup/install.conf.uninstall" || true
    chmod 644 "$BASE/setup-backup/install.conf.uninstall"
    mv "$BASE/setup-backup/install.conf.uninstall" "$INSTALL_CONF"
fi
if [ -f "$BASE/setup-backup/bootstrap.jar.before-install" ]; then
    cp "$BASE/setup-backup/bootstrap.jar.before-install" "$BUNDLE_TARGET"
elif [ -f "$BASE/setup-backup/bootstrap.jar.was-absent" ]; then
    rm -f "$BUNDLE_TARGET"
fi
rm -f "$LOCAL_BUNDLES/$BUNDLE_LEGACY_NAME"
if [ -f "$BASE/setup-backup/lj2600d-start.sh.before-install" ]; then
    cp "$BASE/setup-backup/lj2600d-start.sh.before-install" "$BOOT"
elif [ -f "$BASE/setup-backup/lj2600d-start.sh.was-absent" ]; then
    rm -f "$BOOT"
fi
if [ -w /fhconf/process_start_list ]; then
    sed '/^lj2600d_lpd,/d; \
         /\/osgi\/lj2600d-print\/watch\.sh/d; \
         /\/fhconf\/lj2600d-start\.sh/d' /fhconf/process_start_list \
        > "$BASE/setup-backup/process_start_list.uninstall"
    cat "$BASE/setup-backup/process_start_list.uninstall" > /fhconf/process_start_list
    rm -f "$BASE/setup-backup/process_start_list.uninstall"
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
