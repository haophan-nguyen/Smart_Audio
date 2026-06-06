#!/bin/bash

set -u
set -o pipefail
export LC_ALL=C

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DEVICE_ALIAS="${BT_ALIAS:-SmartAudio}"
readonly AUDIO_MANAGER_SCRIPT="/opt/audio/bin/audio_manager.sh"

source "$BASE_DIR/lib/bt-common.sh"
setup_audio_after_bt_connected()
{
    local i

    if [[ ! -x "$AUDIO_MANAGER_SCRIPT" ]]; then
        warn "Audio manager script not found or not executable: $AUDIO_MANAGER_SCRIPT"
        return 1
    fi

    for i in 1 2 3 4 5; do
        info "Running audio manager, attempt $i..."

        if "$AUDIO_MANAGER_SCRIPT"; then
            info "Audio manager completed"
            return 0
        fi

        warn "Audio manager failed or audio source not ready yet"
        sleep 1
    done

    warn "Audio manager did not complete successfully after retries"
    return 1
}

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

    setup_audio_after_bt_connected || {
        warn "Bluetooth connected, but audio setup is not ready"
    }
else
    info "No connected Bluetooth device"
    write_status "$BT_STATE_IDLE"
fi

exit 0