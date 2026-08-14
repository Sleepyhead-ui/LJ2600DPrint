#!/bin/sh

# Read-only capability probe. Every machine-readable line starts with LJPG_.

clean_value() {
    printf '%s' "$1" | tr '\r\n\t=' '    ' | sed 's/^ *//;s/ *$//'
}

emit() {
    key=$1
    shift
    printf 'LJPG_%s=%s\n' "$key" "$(clean_value "$*")"
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

command_path() {
    command -v "$1" 2>/dev/null || printf 'missing'
}

read_first() {
    for candidate in "$@"; do
        if [ -r "$candidate" ]; then
            head -n 1 "$candidate" 2>/dev/null
            return
        fi
    done
    printf 'unknown'
}

port_state() {
    port=$1
    if netstat -lnt 2>/dev/null | grep -q ":$port "; then
        printf 'listening'
    else
        printf 'free'
    fi
}

ARCH=$(uname -m 2>/dev/null || printf 'unknown')
KERNEL=$(uname -r 2>/dev/null || printf 'unknown')
SYSTEM=$(read_first /etc/issue /etc/banner /proc/version)
BUSYBOX=$(busybox 2>&1 | head -n 1)

PRINTER_DEVICE=missing
if [ -c /dev/lp0 ]; then
    PRINTER_DEVICE=character-device
elif [ -e /dev/lp0 ]; then
    PRINTER_DEVICE=present-not-character-device
fi

USB_MANUFACTURER=$(read_first \
    /sys/class/usb/lp0/device/../manufacturer \
    /sys/class/usbmisc/lp0/device/../manufacturer)
USB_PRODUCT=$(read_first \
    /sys/class/usb/lp0/device/../product \
    /sys/class/usbmisc/lp0/device/../product)
USB_VID=$(read_first \
    /sys/class/usb/lp0/device/../idVendor \
    /sys/class/usbmisc/lp0/device/../idVendor)
USB_PID=$(read_first \
    /sys/class/usb/lp0/device/../idProduct \
    /sys/class/usbmisc/lp0/device/../idProduct)

USBLP=unknown
if [ -d /sys/module/usblp ]; then
    USBLP=loaded
elif grep -q '[[:space:]]usblp$' /proc/modules 2>/dev/null; then
    USBLP=loaded
elif [ "$PRINTER_DEVICE" = character-device ]; then
    USBLP=device-available
else
    USBLP=not-detected
fi

MEM_KB=$(awk '/^MemAvailable:/ { print $2; found=1 } END { if (!found) print "unknown" }' /proc/meminfo 2>/dev/null)
PERSIST_PATH=none
PERSIST_FREE_KB=unknown
for candidate in /osgi /data /mnt/data /overlay; do
    if [ -d "$candidate" ] && [ -w "$candidate" ]; then
        PERSIST_PATH=$candidate
        PERSIST_FREE_KB=$(df -k "$candidate" 2>/dev/null | awk 'NR == 2 { print $4 }')
        [ -n "$PERSIST_FREE_KB" ] || PERSIST_FREE_KB=unknown
        break
    fi
done

STARTUP=none
AUTO_INSTALL=no
if [ -f /fhconf/process_start_list ]; then
    STARTUP=fiberhome-process-start-list
    if [ -w /fhconf/process_start_list ]; then
        AUTO_INSTALL=yes
    fi
elif [ -d /etc/init.d ] && [ -w /etc/init.d ]; then
    STARTUP=init-d-manual-adaptation
elif has_command crond && { [ -w /etc/crontabs ] || [ -w /var/spool/cron/crontabs ]; }; then
    STARTUP=cron-manual-adaptation
fi

CORE=yes
for command_name in tcpsvd lpd softlimit; do
    if ! has_command "$command_name"; then
        CORE=no
    fi
done

WEB=yes
for command_name in httpd sha256sum base64 tar; do
    if ! has_command "$command_name"; then
        WEB=no
    fi
done

GRADE=D
REASON='USB printer character device was not detected'
if [ "$PRINTER_DEVICE" = character-device ]; then
    GRADE=C
    REASON='USB printer is visible; only temporary raw forwarding is confirmed'
    if [ "$CORE" = yes ] && [ "$PERSIST_PATH" != none ]; then
        GRADE=B
        REASON='LPD and persistent storage are available; startup needs adaptation'
        if [ "$AUTO_INSTALL" = yes ]; then
            GRADE=A
            REASON='USB, LPD, persistent storage, and supported FiberHome startup are available'
        fi
    fi
fi

emit PROBE_VERSION 1
emit SYSTEM "$SYSTEM"
emit ARCH "$ARCH"
emit KERNEL "$KERNEL"
emit BUSYBOX "$BUSYBOX"
emit PRINTER_DEVICE "$PRINTER_DEVICE"
emit USBLP "$USBLP"
emit USB_MANUFACTURER "$USB_MANUFACTURER"
emit USB_PRODUCT "$USB_PRODUCT"
emit USB_VID "$USB_VID"
emit USB_PID "$USB_PID"
emit CMD_TCPSVD "$(command_path tcpsvd)"
emit CMD_LPD "$(command_path lpd)"
emit CMD_SOFTLIMIT "$(command_path softlimit)"
emit CMD_HTTPD "$(command_path httpd)"
emit CMD_WGET "$(command_path wget)"
emit CMD_TAR "$(command_path tar)"
emit CMD_SHA256SUM "$(command_path sha256sum)"
emit CMD_BASE64 "$(command_path base64)"
emit MEM_AVAILABLE_KB "$MEM_KB"
emit PERSIST_PATH "$PERSIST_PATH"
emit PERSIST_FREE_KB "$PERSIST_FREE_KB"
emit STARTUP "$STARTUP"
emit AUTO_INSTALL "$AUTO_INSTALL"
emit PORT_515 "$(port_state 515)"
emit PORT_631 "$(port_state 631)"
emit PORT_8631 "$(port_state 8631)"
emit PRINT_SERVICE_INSTALLED "$([ -d /osgi/lj2600d-print ] && printf yes || printf no)"
emit PRINT_SERVICE_MANAGED "$([ -f /osgi/lj2600d-print/.gateway-setup-managed ] && printf yes || printf no)"
emit WEB_SERVICE_INSTALLED "$([ -d /osgi/lj2600d-web ] && printf yes || printf no)"
emit CORE_READY "$CORE"
emit WEB_READY "$WEB"
emit GRADE "$GRADE"
emit REASON "$REASON"
emit LANGUAGE_COMPATIBILITY 'requires a real print test'
