#!/bin/sh

BASE=/osgi/lj2600d-print
SPOOL=/var/tmp/lj2600d-lpd-spool
WATCH_PID=/var/tmp/lj2600d-watch.pid
LPD_PID=/var/tmp/lj2600d-lpd.pid
LOG=/var/tmp/lj2600d-lpd.log
LISTEN_ADDRESS=192.168.1.1

if [ -r "$BASE/service.conf" ]; then
    . "$BASE/service.conf"
fi

if [ -s "$WATCH_PID" ] && kill -0 "$(cat "$WATCH_PID")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$WATCH_PID"
trap 'rm -f "$WATCH_PID"' EXIT
trap 'rm -f "$WATCH_PID"; exit 0' INT TERM

start_web_service() {
    if [ -x /osgi/lj2600d-web/watch-web.sh ]; then
        nohup /osgi/lj2600d-web/watch-web.sh >/var/tmp/lj2600d-web.launch.log 2>&1 &
    fi
}

start_web_service
while true; do
    if [ -c /dev/lp0 ]; then
        mkdir -p "$SPOOL"
        ln -sf /dev/lp0 "$SPOOL/LJ2600D"
        ln -sf /dev/lp0 "$SPOOL/lp"
        if ! netstat -lnt 2>/dev/null | grep -q ':515 '; then
            nohup tcpsvd -E "$LISTEN_ADDRESS" 515 softlimit -m 16777216 lpd "$SPOOL" >>"$LOG" 2>&1 &
            echo $! > "$LPD_PID"
            sleep 2
        fi
    fi
    sleep 20
done
