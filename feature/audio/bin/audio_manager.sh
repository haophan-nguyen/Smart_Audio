#!/bin/bash

# Decide and recover Smart Speaker audio pipeline.
# This manager delegates checks to audio_status.sh and actions to audio_config.sh.

set -u
set -o pipefail
export LC_ALL=C

# 1. Source common
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly AUDIO_CONFIG_SCRIPT="$SCRIPT_DIR/audio_config.sh"
readonly AUDIO_STATUS_SCRIPT="$SCRIPT_DIR/audio_status.sh"

source "$BASE_DIR/lib/audio-common.sh"

# 2. Function: run_audio_status()
run_audio_status()
{
    "$AUDIO_STATUS_SCRIPT"
}

# 3. Function: verify_after_recovery()
verify_after_recovery()
{
    local ret

    run_audio_status
    ret=$?

    if [[ "$ret" -eq "$AUDIO_EXIT_OK" ]]; then
        info "Audio pipeline recovered successfully"
        write_status "$AUDIO_STATE_OK"
        return 0
    fi

    error "Audio pipeline is still not OK after recovery. status code: $ret"
    write_status "$AUDIO_STATE_ERROR"
    return 1
}

# 4. Function: recover_no_server()
recover_no_server()
{
    warn "PulseAudio server is not available"
    write_status "$AUDIO_STATE_NO_SERVER"
    exit 1
}

# 5. Function: recover_no_sink()
recover_no_sink()
{
    warn "No WM8960 PulseAudio sink found"

    if ! aplay -l 2>/dev/null | grep -qi "wm8960"; then
        error "WM8960 is not detected by ALSA"
        error "Skip auto recovery because this may be a hardware, driver, or device-tree issue"
        write_status "$AUDIO_STATE_NO_SINK"
        exit 1
    fi

    warn "WM8960 is detected by ALSA, but PulseAudio sink is missing"
    warn "Try restarting PulseAudio manually if this keeps happening"
    write_status "$AUDIO_STATE_NO_SINK"
    exit 1
}

# 6. Function: handle_no_bt_source()
handle_no_bt_source()
{
    info "No Bluetooth A2DP source. This is normal when no phone is connected."

    # Still prepare local output path.
    "$AUDIO_CONFIG_SCRIPT" set-default-sink || exit 1
    "$AUDIO_CONFIG_SCRIPT" set-volume || exit 1

    write_status "$AUDIO_STATE_NO_BT_SOURCE"
    exit 0
}

# 7. Function: recover_no_loopback()
recover_no_loopback()
{
    info "Loopback is missing. Running audio configuration."
    write_status "$AUDIO_STATE_NO_LOOPBACK"

    "$AUDIO_CONFIG_SCRIPT" setup-loopback || {
        error "Audio loopback configuration failed"
        write_status "$AUDIO_STATE_ERROR"
        exit 1
    }

    verify_after_recovery || exit 1
    exit 0
}

# 8. Function: main()
main()
{
    local ret

    run_audio_status
    ret=$?

    case "$ret" in
        "$AUDIO_EXIT_OK")
            info "Audio pipeline is OK"
            write_status "$AUDIO_STATE_OK"
            exit 0
            ;;
        "$AUDIO_EXIT_NO_SERVER")
            recover_no_server
            ;;
        "$AUDIO_EXIT_NO_SINK")
            recover_no_sink
            ;;
        "$AUDIO_EXIT_NO_BT_SOURCE")
            handle_no_bt_source
            ;;
        "$AUDIO_EXIT_NO_LOOPBACK")
            recover_no_loopback
            ;;
        *)
            error "Unknown audio status code: $ret"
            write_status "$AUDIO_STATE_ERROR"
            exit 1
            ;;
    esac
}

main "$@"
