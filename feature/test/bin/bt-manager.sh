#!/bin/bash

# Decide and activate the operating Bluetooth mode for the Smart Speaker.
#
# This manager does not directly implement all Bluetooth operations.
# It decides which flow to run and delegates work to smaller scripts.

set -u
set -o pipefail
export LC_ALL=C

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BASE_DIR/lib/bt-common.sh"

readonly BT_INIT_SCRIPT="$SCRIPT_DIR/bt-init.sh"
readonly BT_PAIR_SCRIPT="$SCRIPT_DIR/bt-pair.sh"
readonly BT_RECONNECT_SCRIPT="$SCRIPT_DIR/bt-reconnect.sh"
readonly BT_STATUS_SCRIPT="$SCRIPT_DIR/bt-status.sh"
readonly BT_SWITCH_SCRIPT="$SCRIPT_DIR/bt-switch.sh"

readonly COMMAND="${1:-help}"

usage() {
    cat <<EOF
Usage:
  sudo $0 <command>

Commands:
  init        Initialize Bluetooth service and audio state
  pair        Enable pairing mode for a limited time
  reconnect  Reconnect to the last known device
  status     Show Bluetooth and audio status
  switch     Run switch mode
  help       Show this help message
EOF
}

require_executable() {
    local path="$1"

    [[ -x "$path" ]] || fail "Required script is missing or not executable: $path"
}

ensure_bluetooth_service() {
    log "Checking Bluetooth service."

    if systemctl is-active --quiet bluetooth; then
        log "Bluetooth service is already running."
    else
        log "Starting Bluetooth service."
        systemctl start bluetooth || fail "Could not start Bluetooth service."
    fi
}

init_flow() {
    require_executable "$BT_INIT_SCRIPT"

    if "$BT_INIT_SCRIPT"; then
        info "Init Bluetooth successfully"
        write_status "$BT_STATE_IDLE"
        return 0
    else
        error "Init Bluetooth failed"
        write_status "$BT_STATE_ERROR"
        return 1
    fi
}

pair_flow() {
    require_executable "$BT_PAIR_SCRIPT"

    write_status "$BT_STATE_PAIRING"

    if "$BT_PAIR_SCRIPT"; then
        info "Pair flow finished successfully"
        return 0
    else
        error "Pair flow failed"
        write_status "$BT_STATE_ERROR"
        return 1
    fi
}

reconnect_flow() {
    require_executable "$BT_RECONNECT_SCRIPT"

    if "$BT_RECONNECT_SCRIPT"; then
        info "Reconnect flow finished successfully"
        return 0
    else
        warn "Reconnect failed"
        write_status "$BT_STATE_IDLE"
        return 1
    fi
}

status_flow() {
    printf 'STATE=%s\n' "$(read_status)"

    if [[ -x "$BT_STATUS_SCRIPT" ]]; then
        "$BT_STATUS_SCRIPT"
    fi
}

switch_flow() {
    require_executable "$BT_SWITCH_SCRIPT"

    if "$BT_SWITCH_SCRIPT"; then
        info "Switch flow finished successfully"
        return 0
    else
        error "Switch flow failed"
        write_status "$BT_STATE_ERROR"
        return 1
    fi
}

# 1. Validate environment.
[[ "$EUID" -eq 0 ]] || fail "Please run this script with sudo."

command -v bluetoothctl >/dev/null 2>&1 || fail "bluetoothctl was not found."
command -v systemctl >/dev/null 2>&1 || fail "systemctl was not found."

# 2. Dispatch command.
case "$COMMAND" in
    init)
        info "Run init flow"
        ensure_bluetooth_service
        init_flow
        ;;
    pair)
        info "Run pair flow"
        ensure_bluetooth_service
        pair_flow
        ;;
    reconnect)
        info "Run reconnect flow"
        ensure_bluetooth_service
        reconnect_flow
        ;;
    status)
        info "Show status"
        status_flow
        ;;
    switch)
        info "Run switch flow"
        ensure_bluetooth_service
        switch_flow
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac