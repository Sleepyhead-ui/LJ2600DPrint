#!/bin/sh

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'X-Content-Type-Options: nosniff\r\n'
printf '\r\n'

if [ -c /dev/lp0 ]; then
    printer=true
else
    printer=false
fi

if [ -d /var/tmp/lj2600d-web-print.lock ]; then
    ready=false
else
    ready=true
fi

printf '{"ok":true,"printer":%s,"ready":%s,"version":"0.1.0"}\n' "$printer" "$ready"
