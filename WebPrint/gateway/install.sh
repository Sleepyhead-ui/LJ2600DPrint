#!/bin/sh

set -eu
BASE=/osgi/lj2600d-web
PRINT_BASE=/osgi/lj2600d-print
WATCH="$PRINT_BASE/watch.sh"
BACKUP="$BASE/watch.sh.before-web"
PIN=${1:-}

case "$PIN" in
    [0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
    *) echo 'Usage: install.sh <4-12 digit PIN>' >&2; exit 2 ;;
esac

[ -x /usr/sbin/httpd ] || { echo 'BusyBox httpd is unavailable.' >&2; exit 1; }
[ -f "$WATCH" ] || { echo 'The LJ2600D print watchdog is not installed.' >&2; exit 1; }

chmod 755 "$BASE/watch-web.sh" "$BASE/install.sh" "$BASE/uninstall.sh"
chmod 755 "$BASE/www/cgi-bin/status.cgi" "$BASE/www/cgi-bin/print.cgi"
printf 'PIN_HASH=%s\n' "$(printf '%s' "$PIN" | sha256sum | awk '{print $1}')" > "$BASE/print.conf"
chmod 600 "$BASE/print.conf"

if [ ! -f "$BACKUP" ]; then
    cp "$WATCH" "$BACKUP"
fi

if ! grep -q 'lj2600d-web/watch-web.sh' "$WATCH"; then
    tmp="$BASE/watch.sh.new"
    sed '/^while true; do/i\
nohup /osgi/lj2600d-web/watch-web.sh >/var/tmp/lj2600d-web.launch.log 2>&1 &' "$WATCH" > "$tmp"
    chmod 755 "$tmp"
    mv "$tmp" "$WATCH"
fi

sync
for pid in $(ps | grep '[w]atch-web.sh' | awk '{print $1}'); do kill "$pid" 2>/dev/null || true; done
for pid in $(ps | grep '[h]ttpd -p 192.168.1.1:8631' | awk '{print $1}'); do kill "$pid" 2>/dev/null || true; done
sleep 1
rm -f /var/tmp/lj2600d-web-watch.pid
nohup "$BASE/watch-web.sh" >/var/tmp/lj2600d-web.launch.log 2>&1 &
echo 'LJ2600D Web Print installed on http://192.168.1.1:8631/'
