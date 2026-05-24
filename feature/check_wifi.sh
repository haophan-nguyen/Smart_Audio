#!/usr/bin/env bash

# Check WiFi client connection status through NetworkManager.
# This script is read-only: it does not modify network configuration.

set -u
set -o pipefail

export LC_ALL=C

readonly IFACE="${WIFI_IFACE:-wlan0}"
readonly PROBE_HOST_1="${PROBE_HOST_1:-1.1.1.1}"
readonly PROBE_HOST_2="${PROBE_HOST_2:-8.8.8.8}"
readonly PING_TIMEOUT="${PING_TIMEOUT:-2}"

readonly RC_WIFI_OK=0
readonly RC_NO_INTERFACE=1
readonly RC_NO_INTERNET=2
readonly RC_NOT_CONNECTED=3
readonly RC_NM_ERROR=4

log() {
    printf '%s\n' "$*"
}

log "===== WiFi status check ====="
log "Interface: $IFACE"

# 1. Check whether nmcli / NetworkManager is available.
if ! command -v nmcli >/dev/null 2>&1; then
    log "Status: NetworkManager CLI is not installed"
    log "Reason: nmcli command was not found"
    exit "$RC_NM_ERROR"
fi

if ! nmcli general status >/dev/null 2>&1; then
    log "Status: NetworkManager is not available"
    log "Reason: unable to query NetworkManager status"
    exit "$RC_NM_ERROR"
fi

# 2. Check whether the WiFi device exists in NetworkManager.
if ! nmcli -g GENERAL.DEVICE device show "$IFACE" >/dev/null 2>&1; then
    log "Status: No WiFi interface"
    log "Reason: $IFACE does not exist in NetworkManager"
    exit "$RC_NO_INTERFACE"
fi

# 3. Read the connection state managed by NetworkManager.
NM_STATE="$(nmcli -g GENERAL.STATE device show "$IFACE" 2>/dev/null || true)"
CONNECTION="$(nmcli --escape no -g GENERAL.CONNECTION device show "$IFACE" 2>/dev/null || true)"

log "NetworkManager state: ${NM_STATE:-unknown}"
log "Active connection: ${CONNECTION:---}"

# GENERAL.STATE begins with 100 when the device is connected.
case "$NM_STATE" in
    100*)
        ;;
    *)
        log "Status: WiFi is not connected"
        exit "$RC_NOT_CONNECTED"
        ;;
esac

# 4. Do not treat provisioning hotspot/AP mode as normal client WiFi.
WIFI_MODE="$(nmcli --escape no -g 802-11-wireless.mode connection show "$CONNECTION" 2>/dev/null || true)"

if [ "$WIFI_MODE" = "ap" ]; then
    log "WiFi mode: AP / hotspot"
    log "Status: WiFi client connection is not ready"
    exit "$RC_NOT_CONNECTED"
fi

# 5. Read SSID and IPv4 information from the active NetworkManager profile/device.
SSID="$(nmcli --escape no -g 802-11-wireless.ssid connection show "$CONNECTION" 2>/dev/null || true)"
IP_CIDR="$(nmcli --escape no -g IP4.ADDRESS device show "$IFACE" 2>/dev/null | head -n 1 || true)"
GATEWAY="$(nmcli --escape no -g IP4.GATEWAY device show "$IFACE" 2>/dev/null | head -n 1 || true)"

IP="${IP_CIDR%%/*}"

log "SSID: ${SSID:---}"
log "IPv4 address: ${IP:---}"
log "IPv4 gateway: ${GATEWAY:---}"

if [ -z "$IP" ]; then
    log "Status: WiFi is connected but has no IPv4 address"
    exit "$RC_NOT_CONNECTED"
fi

# 6. Check internet reachability through wlan0 only.
# Using -I avoids reporting success through eth0 if Ethernet is connected later.
if ping -I "$IFACE" -c 1 -W "$PING_TIMEOUT" "$PROBE_HOST_1" >/dev/null 2>&1 ||
   ping -I "$IFACE" -c 1 -W "$PING_TIMEOUT" "$PROBE_HOST_2" >/dev/null 2>&1; then
    log "Internet: reachable"
    log "Status: WiFi OK"
    exit "$RC_WIFI_OK"
else
    log "Internet: unreachable"
    log "Status: WiFi connected but internet is unavailable"
    exit "$RC_NO_INTERNET"
fi