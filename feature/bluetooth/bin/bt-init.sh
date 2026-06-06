#!/bin/bash

set -u
set -o pipefail
export LC_ALL=C

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DEVICE_ALIAS="${BT_ALIAS:-SmartAudio}"

source "$BASE_DIR/lib/bt-common.sh"

# 1. Initialize Bluetooth adapter.
info "Powering on Bluetooth adapter"
run_bt_command power on >/dev/null

log "Setting Bluetooth alias to '${DEVICE_ALIAS}'"
run_bt_command system-alias "$DEVICE_ALIAS"

info "Disable pairing mode"
run_bt_command pairable off >/dev/null

info "Disable discoverable mode"
run_bt_command discoverable off >/dev/null

# 2. Check connected device.
if run_bt_command devices Connected | grep -q '^Device '; then
    info "Bluetooth device is connected"
    write_status "$BT_STATE_CONNECTED"

    info "Audio setup is not implemented yet"
    # TODO: call audio_config.sh here later.
else
    info "No connected Bluetooth device"
    write_status "$BT_STATE_IDLE"
fi

exit 0