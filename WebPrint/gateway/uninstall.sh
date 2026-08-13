#!/bin/sh

BASE=/osgi/lj2600d-web
PRINT_BASE=/osgi/lj2600d-print
WATCH="$PRINT_BASE/watch.sh"
BACKUP="$BASE/watch.sh.before-web"

for pid in $(ps | grep '[w]atch-web.sh' | awk '{print $1}'); do kill "$pid" 2>/dev/null || true; done
for pid in $(ps | grep '[h]ttpd -p 192.168.1.1:8631' | awk '{print $1}'); do kill "$pid" 2>/dev/null || true; done
sleep 1
for pid in $(ps | grep '[w]atch-web.sh' | awk '{print $1}'); do kill -9 "$pid" 2>/dev/null || true; done
for pid in $(ps | grep '[h]ttpd -p 192.168.1.1:8631' | awk '{print $1}'); do kill -9 "$pid" 2>/dev/null || true; done

if [ -f "$BACKUP" ]; then
    cp "$BACKUP" "$WATCH"
    chmod 755 "$WATCH"
fi
rm -f /var/tmp/lj2600d-web-watch.pid /var/tmp/lj2600d-web-print.lock
sync
echo 'LJ2600D Web Print disabled. Files remain in /osgi/lj2600d-web for inspection.'
