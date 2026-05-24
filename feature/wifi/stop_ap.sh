#!/bin/bash

# Stop Smart Speaker provisioning hotspot.
#
# Usage:
#   sudo ./stop_ap.sh --only
#       Stop provisioning AP only. Do not reconnect any WiFi profile.
#       Used by connect_wifi.sh before creating a new client connection.
#
#   sudo ./stop_ap.sh
#       Stop provisioning AP and let NetworkManager autoconnect
#       to an eligible previously saved client profile.
#
#   sudo ./stop_ap.sh "PROFILE_NAME"
#       Stop provisioning AP and explicitly reconnect to PROFILE_NAME.

set -u
set -o pipefail

export LC_ALL=C

readonly IFACE="${WIFI_IFACE:-wlan0}"
readonly AP_CON_NAME="${AP_CON_NAME:-SmartSpeaker-Setup}"
readonly MODE_OR_PROFILE="${1:-}"

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

nmcli general status >/dev/null 2>&1 \
    || fail "NetworkManager is not available"

nmcli -g GENERAL.DEVICE device show "$IFACE" >/dev/null 2>&1 \
    || fail "WiFi interface $IFACE does not exist in NetworkManager"

log "Stopping provisioning AP mode."
log "Interface: $IFACE"

# 2. Stop AP profile if it is active.
if nmcli --escape no -t -f NAME connection show --active \
        | grep -Fxq "$AP_CON_NAME"; then

    log "Stopping active hotspot: $AP_CON_NAME"

    nmcli connection down "$AP_CON_NAME" >/dev/null \
        || fail "Unable to stop provisioning hotspot"
else
    log "Provisioning hotspot is not currently active."
fi

# 3. AP-only mode is used by connect_wifi.sh.
#    Keep Flask running while it attempts the new WiFi connection.
if [[ "$MODE_OR_PROFILE" == "--only" ]]; then
    log "AP-only mode selected."
    log "Keeping WiFi setup web server running during connection attempt."
    log "No WiFi client connection will be activated here."
    exit 0
fi

# 4. Manual exit from provisioning mode: stop the setup web server.
log "Stopping WiFi setup web server."
systemctl stop smart-speaker-web.service >/dev/null 2>&1 || true

# 5. Reconnect to an explicitly provided saved profile.
if [[ -n "$MODE_OR_PROFILE" ]]; then
    readonly CLIENT_CON_NAME="$MODE_OR_PROFILE"

    if ! nmcli --escape no -t -f NAME connection show \
            | grep -Fxq "$CLIENT_CON_NAME"; then
        fail "Saved WiFi profile does not exist: $CLIENT_CON_NAME"
    fi

    log "Connecting to saved WiFi profile: $CLIENT_CON_NAME"

    nmcli connection up "$CLIENT_CON_NAME" ifname "$IFACE" >/dev/null \
        || fail "Unable to activate WiFi client profile: $CLIENT_CON_NAME"
else
    # 6. No explicit profile: ask NetworkManager to reconnect
    #    using an eligible saved client profile.
    log "No client profile specified."
    log "Requesting NetworkManager autoconnect on $IFACE."

    nmcli device connect "$IFACE" >/dev/null \
        || fail "NetworkManager could not autoconnect a saved profile on $IFACE"
fi

# 7. Verify client connection.
STATE="$(nmcli -g GENERAL.STATE device show "$IFACE" 2>/dev/null || true)"
ACTIVE_CONNECTION="$(nmcli --escape no -g GENERAL.CONNECTION device show "$IFACE" 2>/dev/null || true)"
IP_CIDR="$(nmcli --escape no -g IP4.ADDRESS device show "$IFACE" 2>/dev/null | head -n 1 || true)"

case "$STATE" in
    100*)
        log "WiFi client mode restored."
        log "Active connection: ${ACTIVE_CONNECTION:---}"
        log "IPv4 address: ${IP_CIDR:---}"
        ;;
    *)
        fail "No connected WiFi client profile is active after stopping AP mode"
        ;;
esac

exit 0