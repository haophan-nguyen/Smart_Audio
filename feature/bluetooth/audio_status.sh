#!/bin/bash

# Show SmartAudio Bluetooth audio pipeline status.
# This script only checks status; it does not change configuration.

# 1. Shell settings
set -u
set -o pipefail

export LC_ALL=C

readonly USB_SINK_PATTERN="alsa_output.usb-C-Media_Electronics_Inc._USB_Audio_Device"

# 2. Print helper functions
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

# 3. Check audio server and default output
print_header "AUDIO SERVER"

SERVER_NAME="$(pactl info 2>/dev/null | awk -F': ' '/Server Name/ {print $2}')"
DEFAULT_SINK="$(pactl info 2>/dev/null | awk -F': ' '/Default Sink/ {print $2}')"

printf 'Server Name : %s\n' "${SERVER_NAME:-Unknown}"
printf 'Default Sink: %s\n' "${DEFAULT_SINK:-Unknown}"

if [[ "${DEFAULT_SINK:-}" == *"$USB_SINK_PATTERN"* ]]; then
    print_ok "USB sound card is the default output."
else
    print_warn "USB sound card is not the default output."
fi

# 4. Check USB sound card output sink
print_header "USB SOUND CARD SINK"

USB_SINK_INFO="$(pactl list sinks short 2>/dev/null | grep -i "$USB_SINK_PATTERN" || true)"

if [[ -n "$USB_SINK_INFO" ]]; then
    printf '%s\n' "$USB_SINK_INFO"
    print_ok "USB sound card sink is available."
else
    print_error "USB sound card sink was not found."
fi

# 5. Check Bluetooth audio input source
print_header "BLUETOOTH AUDIO SOURCE"

BT_SOURCE_INFO="$(pactl list sources short 2>/dev/null | grep -i 'bluez_source' || true)"

if [[ -n "$BT_SOURCE_INFO" ]]; then
    printf '%s\n' "$BT_SOURCE_INFO"
    print_ok "Bluetooth audio source is available."
else
    print_warn "No Bluetooth audio source found. Connect a phone and play audio."
fi

# 6. Check PulseAudio Bluetooth modules
print_header "PULSEAUDIO BLUETOOTH POLICY"

BT_POLICY_INFO="$(pactl list modules short 2>/dev/null | grep -E 'module-bluetooth-policy|module-bluetooth-discover' || true)"

if [[ -n "$BT_POLICY_INFO" ]]; then
    printf '%s\n' "$BT_POLICY_INFO"
    print_ok "PulseAudio Bluetooth policy modules are loaded."
else
    print_error "PulseAudio Bluetooth policy modules were not found."
fi

# 7. Check Bluetooth-to-output loopback route
print_header "AUDIO LOOPBACK"

LOOPBACK_INFO="$(pactl list modules short 2>/dev/null | grep 'module-loopback' || true)"

if [[ -n "$LOOPBACK_INFO" ]]; then
    printf '%s\n' "$LOOPBACK_INFO"
    print_ok "Bluetooth audio is being routed to an output sink."
else
    print_warn "No loopback module found. Start playing audio from the connected phone."
fi

# 8. Show active output streams
print_header "ACTIVE OUTPUT STREAMS"

SINK_INPUT_INFO="$(pactl list sink-inputs short 2>/dev/null || true)"

if [[ -n "$SINK_INPUT_INFO" ]]; then
    printf '%s\n' "$SINK_INPUT_INFO"
else
    printf 'No active sink input stream.\n'
fi

# 9. Show final pipeline result
print_header "RESULT"

if [[ -n "$USB_SINK_INFO" ]] &&
   [[ "${DEFAULT_SINK:-}" == *"$USB_SINK_PATTERN"* ]] &&
   [[ -n "$BT_SOURCE_INFO" ]] &&
   [[ -n "$LOOPBACK_INFO" ]]; then
    print_ok "Bluetooth audio pipeline is running: Phone -> Raspberry Pi -> USB sound card."
else
    print_warn "Audio pipeline is not fully active yet."
fi