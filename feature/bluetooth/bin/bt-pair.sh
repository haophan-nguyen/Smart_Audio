#!/bin/bash

set -u
set -o pipefail
export LC_ALL=C

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DISCOVERABLE_TIMEOUT="${BT_DISCOVERABLE_TIMEOUT:-60}"

source "$BASE_DIR/lib/bt-common.sh"

clean_up()
{
    info "Disable discoverable mode"
    run_bt_command discoverable off >/dev/null || true

    info "Disable pairable mode"
    run_bt_command pairable off >/dev/null || true
}

# 0. Validate config.
case "$DISCOVERABLE_TIMEOUT" in
    ''|*[!0-9]*)
        fail "BT_DISCOVERABLE_TIMEOUT must be a positive integer"
        ;;
esac

if [ "$DISCOVERABLE_TIMEOUT" -le 0 ]; then
    fail "BT_DISCOVERABLE_TIMEOUT must be greater than 0"
fi

# 1. Config Bluetooth adapter.
info "Powering on Bluetooth adapter"
run_bt_command power on >/dev/null

info "Setting discoverable timeout to ${DISCOVERABLE_TIMEOUT} seconds"
run_bt_command discoverable-timeout "$DISCOVERABLE_TIMEOUT" >/dev/null

info "Enabling pairable mode"
run_bt_command pairable on >/dev/null

info "Enabling discoverable mode"
run_bt_command discoverable on >/dev/null

write_status "$BT_STATE_PAIRING"

# Make sure pairing mode is closed if the script is interrupted.
trap clean_up EXIT INT TERM

info "Pairing mode enabled"
info "Waiting for Bluetooth device connection within ${DISCOVERABLE_TIMEOUT} seconds"

# 2. Show resulting adapter state.
bluetoothctl show | grep -E 'Name:|Alias:|Powered:|Discoverable:|DiscoverableTimeout:|Pairable:' || true

# 3. Check connected device.
elapsed=0
interval=1

while [ "$elapsed" -lt "$DISCOVERABLE_TIMEOUT" ]; do
    if run_bt_command devices Connected | grep -q '^Device '; then
        info "Bluetooth device is connected"
        write_status "$BT_STATE_CONNECTED"
        clean_up
        trap - EXIT INT TERM
        exit 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
done

info "No Bluetooth device connected after ${DISCOVERABLE_TIMEOUT} seconds"
write_status "$BT_STATE_IDLE"
clean_up
trap - EXIT INT TERM
exit 0