#!/bin/bash

[[ "${COMMON_SH_LOADED:-0}" == "1" ]] && return 0
readonly COMMON_SH_LOADED=1

# COMMON STATUS VALUES
readonly BT_STATE_IDLE="IDLE"
readonly BT_STATE_PAIRING="PAIRING"
readonly BT_STATE_CONNECTED="CONNECTED"
readonly BT_STATE_AUDIO_READY="AUDIO_READY"
readonly BT_STATE_AUDIO_FAILED="AUDIO_FAILED"
readonly BT_STATE_RECONNECTING="RECONNECTING"
readonly BT_STATE_ERROR="ERROR"

# COMMON PATHS
readonly BT_STATUS_FILE="/run/smart-speaker-bluetooth-status"

# COMMON LOG FUNCTIONS
log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

info() {
    log "INFO: $*"
}

warn() {
    log "WARN: $*"
}

error() {
    log "ERROR: $*" >&2
}

fail() {
    error "$*"
    exit 1
}

# COMMON STATUS FUNCTIONS
write_status() {
    local state="$1"

    printf '%s\n' "$state" > "$BT_STATUS_FILE" || fail "Could not write status: $BT_STATUS_FILE"
}

read_status() {
    cat "$BT_STATUS_FILE" 2>/dev/null || printf '%s\n' "$BT_STATE_IDLE"
}

run_bt_command() {
    local output

    output="$(bluetoothctl "$@" 2>&1)" || {
        printf '%s\n' "$output"
        fail "bluetoothctl command failed: $*"
    }

    printf '%s\n' "$output"
}