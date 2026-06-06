#!/bin/bash

# Common helpers for Smart Speaker audio feature.
# This file is meant to be sourced by other scripts.

[[ "${AUDIO_COMMON_SH_LOADED:-0}" == "1" ]] && return 0
readonly AUDIO_COMMON_SH_LOADED=1

# 1. Common settings
export LC_ALL=C

# 2. Status values
readonly AUDIO_STATE_OK="OK"
readonly AUDIO_STATE_NO_SERVER="NO_SERVER"
readonly AUDIO_STATE_NO_SINK="NO_SINK"
readonly AUDIO_STATE_NO_BT_SOURCE="NO_BT_SOURCE"
readonly AUDIO_STATE_NO_LOOPBACK="NO_LOOPBACK"
readonly AUDIO_STATE_CONFIGURED="CONFIGURED"
readonly AUDIO_STATE_ERROR="ERROR"

# 3. Exit codes used by audio_status.sh and audio_manager.sh
readonly AUDIO_EXIT_OK=0
readonly AUDIO_EXIT_ERROR=1
readonly AUDIO_EXIT_NO_SERVER=10
readonly AUDIO_EXIT_NO_SINK=11
readonly AUDIO_EXIT_NO_BT_SOURCE=12
readonly AUDIO_EXIT_NO_LOOPBACK=13

# 4. Common paths and patterns
readonly AUDIO_STATUS_FILE="${XDG_RUNTIME_DIR:-/tmp}/smart-speaker-audio-status"
readonly WM8960_SINK_PATTERN="${WM8960_SINK_PATTERN:-platform-soc_sound}"
readonly BT_SOURCE_PATTERN="${BT_SOURCE_PATTERN:-bluez_source.*a2dp_source}"
readonly LOOPBACK_LATENCY_MS="${LOOPBACK_LATENCY_MS:-300}"
readonly OUTPUT_VOLUME="${OUTPUT_VOLUME:-60%}"

# 5. Log helpers
log()
{
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

info()
{
    log "INFO: $*"
}

warn()
{
    log "WARN: $*"
}

error()
{
    log "ERROR: $*" >&2
}

fail()
{
    error "$*"
    exit 1
}

# 6. Status helpers
write_status()
{
    local state="$1"

    printf '%s\n' "$state" > "$AUDIO_STATUS_FILE" \
        || fail "Could not write status: $AUDIO_STATUS_FILE"
}

read_status()
{
    cat "$AUDIO_STATUS_FILE" 2>/dev/null || printf '%s\n' "$AUDIO_STATE_NO_SERVER"
}

# 7. PulseAudio helpers
get_default_sink()
{
    pactl info 2>/dev/null | awk -F': ' '/Default Sink/ { print $2; exit }'
}

get_wm8960_sink()
{
    pactl list short sinks 2>/dev/null \
        | awk -v pattern="$WM8960_SINK_PATTERN" '$2 ~ pattern { print $2; exit }'
}

get_bt_a2dp_source()
{
    pactl list short sources 2>/dev/null \
        | awk -v pattern="$BT_SOURCE_PATTERN" '$2 ~ pattern { print $2; exit }'
}

is_loopback_configured()
{
    local bt_source="$1"
    local wm8960_sink="$2"

    [[ -n "$bt_source" && -n "$wm8960_sink" ]] || return 1

    pactl list short modules 2>/dev/null \
        | grep -F "module-loopback" \
        | grep -F "source=$bt_source" \
        | grep -F "sink=$wm8960_sink" \
        >/dev/null 2>&1
}

is_bt_loopback_exists()
{
    local bt_source="$1"

    pactl list short modules 2>/dev/null \
        | awk '$2 == "module-loopback" {print}' \
        | grep -F "source=" \
        | grep -F "$bt_source" \
        >/dev/null 2>&1
}
