#!/bin/sh

BASE=/osgi/lj2600d-print
LOG=/var/tmp/lj2600d-boot.log

echo "$(date) waiting for persistent app storage" >> "$LOG"
while [ ! -x "$BASE/watch.sh" ]; do
    sleep 2
done

echo "$(date) starting print watchdog" >> "$LOG"
exec "$BASE/watch.sh" >> "$LOG" 2>&1
