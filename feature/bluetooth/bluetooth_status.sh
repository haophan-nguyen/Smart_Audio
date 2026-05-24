#!/bin/bash

# Show SmartAudio Bluetooth connection status.
# This script only checks status; it does not change configuration.

set -u
set -o pipefail

export LC_ALL=C

print_header() {
    printf '\n===== %s =====\n' "$1"
}

print_ok() {
    printf '[OK] %s\n' "$1"
}

print_warn() {
    printf '[WARN] %s\n' "$1"
}

print_error() {
    printf '[ERROR] %s\n' "$1"
}

# 1. Check Bluetooth service.
print_header "BLUETOOTH SERVICE"

if systemctl is-active --quiet bluetooth; then
    print_ok "Bluetooth service is running."
else
    print_error "Bluetooth service is not running."
fi

# 2. Check Bluetooth adapter configuration.
print_header "BLUETOOTH ADAPTER"

ADAPTER_INFO="$(bluetoothctl show 2>/dev/null || true)"

if [[ -z "$ADAPTER_INFO" ]]; then
    print_error "Bluetooth adapter was not found."
    exit 1
fi

printf '%s\n' "$ADAPTER_INFO" | grep -E 'Name:|Alias:|Powered:|Discoverable:|Pairable:' || true

POWERED="$(printf '%s\n' "$ADAPTER_INFO" | awk -F': ' '/Powered:/ {print $2}')"
DISCOVERABLE="$(printf '%s\n' "$ADAPTER_INFO" | awk -F': ' '/Discoverable:/ {print $2}')"
PAIRABLE="$(printf '%s\n' "$ADAPTER_INFO" | awk -F': ' '/Pairable:/ {print $2}')"

if [[ "$POWERED" == "yes" ]]; then
    print_ok "Bluetooth adapter is powered on."
else
    print_error "Bluetooth adapter is powered off."
fi

if [[ "$PAIRABLE" == "yes" ]]; then
    print_ok "SmartAudio accepts pairing requests."
else
    print_warn "SmartAudio is not pairable."
fi

if [[ "$DISCOVERABLE" == "yes" ]]; then
    print_ok "SmartAudio is visible to new devices."
else
    print_warn "SmartAudio is not discoverable to new devices."
fi

# 3. Show paired devices.
print_header "PAIRED DEVICES"

PAIRED_DEVICES="$(bluetoothctl devices Paired 2>/dev/null || true)"

if [[ -n "$PAIRED_DEVICES" ]]; then
    printf '%s\n' "$PAIRED_DEVICES"
    print_ok "At least one Bluetooth device is paired."
else
    print_warn "No paired Bluetooth devices found."
fi

# 4. Show connected devices.
print_header "CONNECTED DEVICES"

CONNECTED_DEVICES="$(bluetoothctl devices Connected 2>/dev/null || true)"

if [[ -n "$CONNECTED_DEVICES" ]]; then
    printf '%s\n' "$CONNECTED_DEVICES"
    print_ok "A Bluetooth device is connected."
else
    print_warn "No Bluetooth device is currently connected."
fi

# 5. Final result.
print_header "RESULT"

if [[ "$POWERED" == "yes" ]] && [[ -n "$CONNECTED_DEVICES" ]]; then
    print_ok "Bluetooth connection is active."
elif [[ "$POWERED" == "yes" ]] && [[ "$PAIRABLE" == "yes" ]]; then
    print_ok "Bluetooth is ready for connection."
else
    print_warn "Bluetooth is not fully ready."
fi