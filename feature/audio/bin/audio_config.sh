#!/bin/bash

# Configure Smart Speaker audio pipeline.

set -u
set -o pipefail
export LC_ALL=C

# 1. Source common
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BASE_DIR/lib/audio-common.sh"

# 2. Parse command
readonly COMMAND="${1:-help}"

usage()
{
    cat <<EOF_USAGE
Usage:
  sudo $0 <command>

Commands:
  set-default-sink       Set WM8960 as default sink
  setup-loopback         Route Bluetooth A2DP source to WM8960 sink
  set-volume             Unmute and set WM8960 output volume
  reset-loopback         Remove all module-loopback instances
  setup                  Set default sink, volume, and loopback if possible
  help                   Show this help message
EOF_USAGE
}

# 3. Function: require_wm8960_sink()
require_wm8960_sink()
{
    WM8960_SINK="$(get_wm8960_sink)"

    if [[ -z "$WM8960_SINK" ]]; then
        error "WM8960 sink not found"
        write_status "$AUDIO_STATE_NO_SINK"
        return 1
    fi

    info "WM8960 sink: $WM8960_SINK"
    return 0
}

# 4. Function: require_bt_source()
require_bt_source()
{
    BT_SOURCE="$(get_bt_a2dp_source)"

    if [[ -z "$BT_SOURCE" ]]; then
        warn "Bluetooth A2DP source not found"
        write_status "$AUDIO_STATE_NO_BT_SOURCE"
        return 1
    fi

    info "Bluetooth source: $BT_SOURCE"
    return 0
}

# 5. Function: set_default_sink()
set_default_sink()
{
    local current_sink

    require_wm8960_sink || return 1

    current_sink="$(get_default_sink)"

    if [[ "$current_sink" == "$WM8960_SINK" ]]; then
        info "Default sink is already WM8960: $WM8960_SINK"
        return 0
    fi

    info "Setting default sink to: $WM8960_SINK"

    pactl set-default-sink "$WM8960_SINK" || {
        error "Failed to set default sink"
        write_status "$AUDIO_STATE_ERROR"
        return 1
    }

    info "Default sink set successfully"
    return 0
}

# 6. Function: setup_loopback()
setup_loopback()
{
    require_wm8960_sink || return 1
    require_bt_source || return 1

    if is_loopback_configured "$BT_SOURCE" "$WM8960_SINK"; then
        info "Loopback is already configured"
        return 0
    fi

    info "Creating loopback"
    info "  source: $BT_SOURCE"
    info "  sink  : $WM8960_SINK"
    info "  latency_msec: $LOOPBACK_LATENCY_MS"

    pactl load-module module-loopback \
        source="$BT_SOURCE" \
        sink="$WM8960_SINK" \
        latency_msec="$LOOPBACK_LATENCY_MS" \
        adjust_time=0 \
        >/dev/null || {
            error "Failed to load module-loopback"
            write_status "$AUDIO_STATE_ERROR"
            return 1
        }

    info "Loopback created successfully"
    write_status "$AUDIO_STATE_CONFIGURED"
    return 0
}

# 7. Function: set_output_volume()
set_output_volume()
{
    require_wm8960_sink || return 1

    info "Unmuting sink: $WM8960_SINK"
    pactl set-sink-mute "$WM8960_SINK" 0 || {
        error "Failed to unmute sink"
        write_status "$AUDIO_STATE_ERROR"
        return 1
    }

    info "Setting sink volume to $OUTPUT_VOLUME"
    pactl set-sink-volume "$WM8960_SINK" "$OUTPUT_VOLUME" || {
        error "Failed to set sink volume"
        write_status "$AUDIO_STATE_ERROR"
        return 1
    }

    return 0
}

# 8. Function: reset_loopback()
reset_loopback()
{
    local module_ids
    local id

    module_ids="$(pactl list short modules 2>/dev/null | awk '$2 == "module-loopback" { print $1 }')"

    if [[ -z "$module_ids" ]]; then
        info "No loopback module to unload"
        return 0
    fi

    for id in $module_ids; do
        info "Unloading loopback module: $id"
        pactl unload-module "$id" || {
            error "Failed to unload loopback module: $id"
            write_status "$AUDIO_STATE_ERROR"
            return 1
        }
    done

    return 0
}

# 9. Function: setup_all()
setup_all()
{
    set_default_sink || return 1
    set_output_volume || return 1

    # No BT source after reboot is normal, so do not treat it as a hard failure here.
    if ! require_bt_source; then
        warn "Skip loopback setup because no Bluetooth source is available"
        return 0
    fi

    setup_loopback || return 1
    return 0
}

# 10. Dispatch command
case "$COMMAND" in
    set-default-sink)
        set_default_sink
        ;;
    setup-loopback)
        setup_loopback
        ;;
    set-volume)
        set_output_volume
        ;;
    reset-loopback)
        reset_loopback
        ;;
    setup)
        setup_all
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
