#!/bin/bash

# Configure SmartAudio Bluetooth adapter for pairing and connection.
# This script does not route audio and does not force-connect a phone.

set -u
set -o pipefail

export LC_ALL=C

readonly DEVICE_ALIAS="${BT_ALIAS:-SmartAudio}"
readonly DISCOVERABLE_TIMEOUT="${BT_DISCOVERABLE_TIMEOUT:-0}"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

run_bt_command() {
    local output

    output="$(bluetoothctl "$@" 2>&1)" || {
        printf '%s\n' "$output"
        fail "bluetoothctl command failed: $*"
    }

    printf '%s\n' "$output"
}

# 1. Validate environment.
[[ "$EUID" -eq 0 ]] || fail "Please run this script with sudo."

command -v bluetoothctl >/dev/null 2>&1 || fail "bluetoothctl was not found."
command -v systemctl >/dev/null 2>&1 || fail "systemctl was not found."

# 2. Ensure Bluetooth service is running.
log "Checking Bluetooth service."

if systemctl is-active --quiet bluetooth; then
    log "Bluetooth service is already running."
else
    log "Starting Bluetooth service."
    systemctl start bluetooth || fail "Could not start Bluetooth service."
fi

# 3. Configure Bluetooth adapter.
log "Powering on Bluetooth adapter."
run_bt_command power on

log "Setting Bluetooth alias to '${DEVICE_ALIAS}'."
run_bt_command system-alias "$DEVICE_ALIAS"

log "Enabling pairing mode."
run_bt_command pairable on

log "Setting discoverable timeout to ${DISCOVERABLE_TIMEOUT} seconds."
run_bt_command discoverable-timeout "$DISCOVERABLE_TIMEOUT"

log "Enabling discoverable mode."
run_bt_command discoverable on

# 4. Show resulting adapter state.
log "Bluetooth configuration completed."

bluetoothctl show | grep -E 'Name:|Alias:|Powered:|Discoverable:|DiscoverableTimeout:|Pairable:' || true
