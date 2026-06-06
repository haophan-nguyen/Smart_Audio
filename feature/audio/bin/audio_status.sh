#!/bin/bash

# Check Smart Speaker audio pipeline status.
# This script checks only; it does not modify audio configuration.

set -u
set -o pipefail
export LC_ALL=C

# 1. Source common
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BASE_DIR/lib/audio-common.sh"

# 2. Function: check_audio_server()
check_audio_server()
{
    pactl info >/dev/null 2>&1
}

# 3. Function: find_wm8960_sink()
find_wm8960_sink()
{
    WM8960_SINK="$(get_wm8960_sink)"

    if [[ -n "$WM8960_SINK" ]]; then
        info "Found WM8960 sink: $WM8960_SINK"
        return 0
    fi

    warn "WM8960 sink not found"
    return 1
}

# 4. Function: find_bt_source()
find_bt_source()
{
    BT_SOURCE="$(get_bt_a2dp_source)"

    if [[ -n "$BT_SOURCE" ]]; then
        info "Found Bluetooth A2DP source: $BT_SOURCE"
        return 0
    fi

    warn "Bluetooth A2DP source not found"
    return 1
}

# 5. Function: show_default_sink()
show_default_sink()
{
    local default_sink

    default_sink="$(get_default_sink)"

    if [[ -n "$default_sink" ]]; then
        info "Default sink: $default_sink"
    else
        warn "No default sink found"
    fi
}

# 6. Function: check_loopback()
check_loopback()
{
    if is_loopback_configured "$BT_SOURCE" "$WM8960_SINK"; then
        info "Loopback is already configured"
        return 0
    fi

    warn "Loopback is not configured"
    return 1
}

# 7. Function: main()
main()
{
    if ! check_audio_server; then
        error "PulseAudio server is not available"
        write_status "$AUDIO_STATE_NO_SERVER"
        exit "$AUDIO_EXIT_NO_SERVER"
    fi

    show_default_sink

    if ! find_wm8960_sink; then
        write_status "$AUDIO_STATE_NO_SINK"
        exit "$AUDIO_EXIT_NO_SINK"
    fi

    if ! find_bt_source; then
        write_status "$AUDIO_STATE_NO_BT_SOURCE"
        exit "$AUDIO_EXIT_NO_BT_SOURCE"
    fi

    if ! check_loopback; then
        write_status "$AUDIO_STATE_NO_LOOPBACK"
        exit "$AUDIO_EXIT_NO_LOOPBACK"
    fi

    info "Audio pipeline is OK"
    write_status "$AUDIO_STATE_OK"
    exit "$AUDIO_EXIT_OK"
}

main "$@"
