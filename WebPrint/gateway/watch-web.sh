#!/bin/sh

BASE=/osgi/lj2600d-web
PIDFILE=/var/tmp/lj2600d-web-watch.pid
LOG=/var/tmp/lj2600d-web.log

if [ -s "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT
trap 'rm -f "$PIDFILE"; exit 0' INT TERM

while true; do
    if ! netstat -lnt 2>/dev/null | grep -q ':8631 '; then
        /usr/sbin/httpd -p 192.168.1.1:8631 -h "$BASE/www" -c "$BASE/httpd.conf"
        echo "$(date) web service start requested" >> "$LOG"
    fi
    sleep 30
done
