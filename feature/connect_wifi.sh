#!/bin/bash

# Connect Smart Speaker to a WiFi network provided by the user.
# Usage:
#   sudo ./connect_wifi.sh "<ssid>" "<password>"

set -u
set -o pipefail

export LC_ALL=C

readonly IFACE="${WIFI_IFACE:-wlan0}"
readonly AP_CON_NAME="${AP_CON_NAME:-SmartSpeaker-Setup}"
readonly CLIENT_CON_NAME="${CLIENT_CON_NAME:-SmartSpeaker-Client}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATUS_FILE="/run/smart-speaker-wifi-status"

readonly SSID="${1:-}"
readonly PASSWORD="${2:-}"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

write_status() {
    local state="$1"
    local tmp_file

    tmp_file="$(mktemp /run/smart-speaker-wifi-status.XXXXXX)" || return 1

    printf '%s\n%s\n' "$state" "$SSID" > "$tmp_file"
    chmod 600 "$tmp_file"
    mv -f "$tmp_file" "$STATUS_FILE"
}

restore_ap_and_fail() {
    log "ERROR: $*"

    write_status "error" \
        || log "WARNING: Could not write provisioning error status."

    log "Attempting to restore provisioning hotspot."

    if "$SCRIPT_DIR/start_ap.sh"; then
        log "Provisioning hotspot restored."
        log "Reconnect to WiFi SSID: $AP_CON_NAME"
        log "Setup gateway IP: 192.168.4.1"
    else
        log "ERROR: Could not restore provisioning hotspot."
    fi

    exit 1
}

# 1. Validate input.
[[ "$EUID" -eq 0 ]] || fail "Please run this script with sudo"
[[ -n "$SSID" ]] || fail "SSID is missing. Usage: sudo $0 \"<ssid>\" \"<password>\""
[[ -n "$PASSWORD" ]] || fail "Password is missing. Usage: sudo $0 \"<ssid>\" \"<password>\""

# 2. Validate NetworkManager and interface.
command -v nmcli >/dev/null 2>&1 || fail "nmcli command was not found"
command -v systemctl >/dev/null 2>&1 || fail "systemctl command was not found"

nmcli general status >/dev/null 2>&1 || fail "NetworkManager is not available"
nmcli -g GENERAL.DEVICE device show "$IFACE" >/dev/null 2>&1 \
    || fail "WiFi interface $IFACE was not found"

log "Connecting interface: $IFACE"
log "Target SSID: $SSID"
log "Client profile name: $CLIENT_CON_NAME"

write_status "connecting" \
    || log "WARNING: Could not write provisioning connecting status."

# 3. Remove old Smart Speaker client profile, if any.
#    This allows the user to provision a different WiFi network later.
if nmcli -t -f NAME connection show | grep -Fxq "$CLIENT_CON_NAME"; then
    log "Removing old client profile: $CLIENT_CON_NAME"
    nmcli connection delete "$CLIENT_CON_NAME" >/dev/null \
        || fail "Could not remove old client profile"
fi

# 4. Stop provisioning AP only.
#    connect_wifi.sh will create and activate the new client profile afterward.
log "Stopping provisioning hotspot before connecting to new WiFi."

"$SCRIPT_DIR/stop_ap.sh" --only \
    || fail "Could not stop provisioning hotspot"

# 5. Rescan available WiFi networks.
log "Scanning WiFi networks..."
nmcli device wifi rescan ifname "$IFACE" >/dev/null 2>&1 || true
sleep 2

# 6. Create a new client profile and connect to the user-provided WiFi.
log "Attempting to connect to SSID: $SSID"

if ! nmcli --wait 25 device wifi connect "$SSID" \
        password "$PASSWORD" \
        ifname "$IFACE" \
        name "$CLIENT_CON_NAME"; then
    restore_ap_and_fail "Could not connect to WiFi SSID: $SSID"
fi

# 7. Enable automatic reconnect after reboot.
nmcli connection modify "$CLIENT_CON_NAME" \
    connection.autoconnect yes \
    connection.autoconnect-priority 50 >/dev/null \
    || fail "Connected, but could not enable autoconnect"

# 8. Verify connection and IP address.
ACTIVE_CON_NAME="$(nmcli -g GENERAL.CONNECTION device show "$IFACE" 2>/dev/null || true)"
IP_ADDR="$(nmcli -g IP4.ADDRESS device show "$IFACE" 2>/dev/null | head -n 1 || true)"

[[ "$ACTIVE_CON_NAME" == "$CLIENT_CON_NAME" ]] \
    || restore_ap_and_fail "WiFi connection did not become active"

[[ -n "$IP_ADDR" ]] \
    || restore_ap_and_fail "Connected to WiFi but did not receive an IPv4 address"

log "WiFi connection successful"
log "Active profile: $ACTIVE_CON_NAME"
log "IP address: $IP_ADDR"

# 9. Clear temporary provisioning status after success.
rm -f "$STATUS_FILE"

# 10. Provisioning has completed successfully.
#     The setup web page is no longer needed in client mode.
log "Stopping WiFi setup web server after successful provisioning."
systemctl stop smart-speaker-web.service >/dev/null 2>&1 || true

exit 0