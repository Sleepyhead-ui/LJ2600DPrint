#!/bin/sh

BASE=/osgi/lj2600d-web
CONFIG="$BASE/print.conf"
LOCK=/var/tmp/lj2600d-web-print.lock
MAX_BYTES=33554432

respond() {
    code="$1"
    status="$2"
    body="$3"
    printf 'Status: %s %s\r\n' "$code" "$status"
    printf 'Content-Type: application/json\r\n'
    printf 'Cache-Control: no-store\r\n'
    printf 'X-Content-Type-Options: nosniff\r\n'
    printf '\r\n'
    printf '%s\n' "$body"
    exit 0
}

[ "$REQUEST_METHOD" = POST ] || respond 405 'Method Not Allowed' '{"ok":false,"message":"只允许 POST 请求"}'
[ -f "$CONFIG" ] || respond 503 'Service Unavailable' '{"ok":false,"message":"打印服务尚未配置"}'

case "$HTTP_ORIGIN" in
    ""|"http://192.168.1.1:8631") ;;
    *) respond 403 Forbidden '{"ok":false,"message":"请求来源不受信任"}' ;;
esac

PIN_HASH=$(sed -n 's/^PIN_HASH=//p' "$CONFIG" | head -1)
[ -n "$PIN_HASH" ] || respond 503 'Service Unavailable' '{"ok":false,"message":"打印 PIN 尚未配置"}'
IFS=' ' read -r AUTH_LABEL SUPPLIED_PIN
[ "$AUTH_LABEL" = PIN ] || respond 401 Unauthorized '{"ok":false,"message":"打印 PIN 不正确"}'
case "$SUPPLIED_PIN" in
    [0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
    *) respond 401 Unauthorized '{"ok":false,"message":"打印 PIN 不正确"}' ;;
esac
SUPPLIED_HASH=$(printf '%s' "$SUPPLIED_PIN" | sha256sum | awk '{print $1}')
[ "$SUPPLIED_HASH" = "$PIN_HASH" ] || respond 401 Unauthorized '{"ok":false,"message":"打印 PIN 不正确"}'

case "$CONTENT_LENGTH" in
    ''|*[!0-9]*) respond 411 'Length Required' '{"ok":false,"message":"缺少任务大小"}' ;;
esac
[ "$CONTENT_LENGTH" -gt 5 ] || respond 400 'Bad Request' '{"ok":false,"message":"打印任务为空"}'
[ "$CONTENT_LENGTH" -le "$MAX_BYTES" ] || respond 413 'Payload Too Large' '{"ok":false,"message":"打印任务超过 32 MB"}'
[ -c /dev/lp0 ] || respond 503 'Service Unavailable' '{"ok":false,"message":"没有检测到 USB 打印机"}'

if ! mkdir "$LOCK" 2>/dev/null; then
    respond 409 Conflict '{"ok":false,"message":"另一项打印任务正在发送"}'
fi
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT INT TERM

dd bs=1 count=20 of="$LOCK/header" 2>/dev/null
HEADER=$(cat "$LOCK/header")
case "$HEADER" in
    "$(printf '\033')%-12345X@PJL "*) ;;
    *) respond 400 'Bad Request' '{"ok":false,"message":"无法识别打印数据"}' ;;
esac

cat "$LOCK/header" > /dev/lp0 || respond 500 'Internal Server Error' '{"ok":false,"message":"无法写入打印机"}'
cat >> /dev/lp0 || respond 500 'Internal Server Error' '{"ok":false,"message":"打印数据写入失败"}'

respond 200 OK "{\"ok\":true,\"bytes\":$CONTENT_LENGTH}"
