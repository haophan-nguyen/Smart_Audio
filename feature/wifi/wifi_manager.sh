#!/bin/bash

# Decide and activate the operating WiFi mode for the Smart Speaker.
#
# Boot behavior:
#   - If SmartSpeaker-Client exists and connects successfully:
#       keep/use client mode.
#   - If SmartSpeaker-Client does not exist or cannot connect:
#       start provisioning AP mode.

set -u
set -o pipefail

export LC_ALL=C

readonly IFACE="${WIFI_IFACE:-wlan0}"
readonly CLIENT_CON_NAME="${CLIENT_CON_NAME:-SmartSpeaker-Client}"
readonly AP_CON_NAME="${AP_CON_NAME:-SmartSpeaker-Setup}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly START_AP_SCRIPT="$SCRIPT_DIR/start_ap.sh"

readonly MAX_CONNECT_ATTEMPTS=3
readonly CONNECT_TIMEOUT=15

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

profile_exists() {
    nmcli --escape no -t -f NAME connection show \
        | grep -Fxq "$1"
}

active_connection() {
    nmcli --escape no -g GENERAL.CONNECTION device show "$IFACE" 2>/dev/null || true
}

ipv4_address() {
    nmcli --escape no -g IP4.ADDRESS device show "$IFACE" 2>/dev/null \
        | head -n 1 || true
}

start_provisioning_ap() {
    log "ACTION: Starting provisioning AP mode."

    "$START_AP_SCRIPT" \
        || fail "Could not start provisioning AP mode"

    log "DECISION: Provisioning AP mode is active."
    log "SSID: $AP_CON_NAME"
    log "Setup gateway: 192.168.4.1"
}

log "======================================"
log "WiFi Manager Starting"
log "Interface: $IFACE"
log "Client profile: $CLIENT_CON_NAME"
log "AP profile: $AP_CON_NAME"
log "======================================"

# 1. Validate requirements.
[[ "$EUID" -eq 0 ]] || fail "Please run this script with sudo"

command -v nmcli >/dev/null 2>&1 \
    || fail "nmcli command was not found"

nmcli general status >/dev/null 2>&1 \
    || fail "NetworkManager is not available"

nmcli -g GENERAL.DEVICE device show "$IFACE" >/dev/null 2>&1 \
    || fail "WiFi interface $IFACE does not exist in NetworkManager"

[[ -x "$START_AP_SCRIPT" ]] \
    || fail "$START_AP_SCRIPT does not exist or is not executable"

# 2. First-time setup: no client profile has been provisioned yet.
if ! profile_exists "$CLIENT_CON_NAME"; then
    log "DECISION: No provisioned client profile exists."
    log "REASON: Device has not been configured with user WiFi yet."

    start_provisioning_ap

    log "======================================"
    log "WiFi Manager Finished"
    log "======================================"
    exit 0
fi

# 3. Ensure the Smart Speaker client profile owns normal autoconnect.
log "Provisioned client profile exists."

nmcli connection modify "$CLIENT_CON_NAME" \
    connection.autoconnect yes \
    connection.autoconnect-priority 50 >/dev/null \
    || fail "Could not configure client profile autoconnect"

# 4. If the expected client profile is already active and has IPv4, keep it.
CURRENT_ACTIVE="$(active_connection)"
CURRENT_IP="$(ipv4_address)"

if [[ "$CURRENT_ACTIVE" == "$CLIENT_CON_NAME" && -n "$CURRENT_IP" ]]; then
    log "DECISION: Provisioned WiFi client is already active."
    log "Active connection: $CURRENT_ACTIVE"
    log "IPv4 address: $CURRENT_IP"
    log "ACTION: Keep client mode."
    log "======================================"
    log "WiFi Manager Finished"
    log "======================================"
    exit 0
fi

# 5. Try to connect specifically to SmartSpeaker-Client.
log "Provisioned client is not currently active."
log "ACTION: Attempting to connect to saved client profile."

for (( attempt=1; attempt<=MAX_CONNECT_ATTEMPTS; attempt++ )); do
    log "Connection attempt: $attempt/$MAX_CONNECT_ATTEMPTS"

    if nmcli --wait "$CONNECT_TIMEOUT" connection up "$CLIENT_CON_NAME" \
            ifname "$IFACE" >/dev/null 2>&1; then

        CURRENT_ACTIVE="$(active_connection)"
        CURRENT_IP="$(ipv4_address)"

        if [[ "$CURRENT_ACTIVE" == "$CLIENT_CON_NAME" && -n "$CURRENT_IP" ]]; then
            log "DECISION: WiFi client connection restored."
            log "Active connection: $CURRENT_ACTIVE"
            log "IPv4 address: $CURRENT_IP"
            log "ACTION: Keep client mode."
            log "======================================"
            log "WiFi Manager Finished"
            log "======================================"
            exit 0
        fi
    fi

    log "Attempt $attempt did not establish a usable client connection."

    if (( attempt < MAX_CONNECT_ATTEMPTS )); then
        sleep 3
    fi
done

# 6. Recovery: the saved WiFi exists but is currently unusable.
log "DECISION: Saved WiFi client could not be connected."
log "REASON: Router may be unavailable, password may have changed, or network is out of range."
log "ACTION: Enter recovery provisioning mode."

start_provisioning_ap

log "======================================"
log "WiFi Manager Finished"
log "======================================"

exit 0