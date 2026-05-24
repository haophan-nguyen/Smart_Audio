#!/bin/bash

# Start Smart Speaker provisioning hotspot through NetworkManager.
# WARNING: Activating this AP on wlan0 disconnects the current WiFi client link.

set -u
set -o pipefail

export LC_ALL=C

readonly IFACE="${WIFI_IFACE:-wlan0}"
readonly AP_CON_NAME="${AP_CON_NAME:-SmartSpeaker-Setup}"
readonly AP_SSID="${AP_SSID:-SmartSpeaker-Setup}"
readonly AP_PASSWORD="${AP_PASSWORD:-12345678}"
readonly AP_ADDRESS="${AP_ADDRESS:-192.168.4.1/24}"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

# 1. Validate requirements.
[[ "$EUID" -eq 0 ]] || fail "Please run this script with sudo"
command -v nmcli >/dev/null 2>&1 || fail "nmcli command was not found"
command -v systemctl >/dev/null 2>&1 || fail "systemctl command was not found"
nmcli general status >/dev/null 2>&1 || fail "NetworkManager is not available"
nmcli -g GENERAL.DEVICE device show "$IFACE" >/dev/null 2>&1 ||
    fail "WiFi interface $IFACE does not exist in NetworkManager"

if [ "${#AP_PASSWORD}" -lt 8 ]; then
    fail "AP password must contain at least 8 characters"
fi

log "Preparing hotspot profile: $AP_CON_NAME"
log "SSID: $AP_SSID"
log "Interface: $IFACE"
log "Gateway IP: $AP_ADDRESS"

# 2. Create the hotspot profile once, or update it on later runs.
if nmcli -t -f NAME connection show | grep -Fxq "$AP_CON_NAME"; then
    log "Existing hotspot profile found; updating configuration."
else
    log "Creating hotspot profile."
    nmcli connection add \
        type wifi \
        ifname "$IFACE" \
        con-name "$AP_CON_NAME" \
        autoconnect no \
        ssid "$AP_SSID" >/dev/null
fi

# 3. Configure the profile as a protected WiFi access point.
nmcli connection modify "$AP_CON_NAME" \
    connection.interface-name "$IFACE" \
    connection.autoconnect no \
    802-11-wireless.mode ap \
    802-11-wireless.band bg \
    802-11-wireless.ssid "$AP_SSID" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$AP_PASSWORD" \
    ipv4.method shared \
    ipv4.addresses "$AP_ADDRESS" \
    ipv6.method disabled

log "Hotspot profile is ready."

# 4. Start the setup web server before switching wlan0 to AP mode.
#    Once the AP is activated, the current SSH-over-WiFi session may disconnect.
log "Starting WiFi setup web server."
systemctl start smart-speaker-web.service \
    || fail "Unable to start WiFi setup web server"

log "Starting provisioning AP mode now..."

# 5. Activation disconnects any current WiFi client connection on wlan0.
if ! nmcli connection up "$AP_CON_NAME" ifname "$IFACE"; then
    log "Unable to start provisioning hotspot."
    log "Stopping WiFi setup web server because AP startup failed."
    systemctl stop smart-speaker-web.service >/dev/null 2>&1 || true
    fail "Unable to activate provisioning hotspot"
fi

log "Provisioning AP mode started."
exit 0
