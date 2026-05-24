#!/bin/bash

# Run WiFi provisioning as an independent systemd job.
# Credentials are written temporarily by Flask to /run.

set -u
set -o pipefail

export LC_ALL=C

readonly CREDENTIAL_FILE="/run/smart-speaker-wifi-credentials"
readonly CONNECT_SCRIPT="/opt/wifi/connect_wifi.sh"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    log "ERROR: $*"
    rm -f "$CREDENTIAL_FILE"
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail "Please run this worker as root"
[[ -x "$CONNECT_SCRIPT" ]] || fail "Connect script is missing or not executable"
[[ -f "$CREDENTIAL_FILE" ]] || fail "Credential file was not found"

mapfile -t CREDENTIALS < "$CREDENTIAL_FILE"

readonly SSID="${CREDENTIALS[0]:-}"
readonly PASSWORD="${CREDENTIALS[1]:-}"

rm -f "$CREDENTIAL_FILE"

[[ -n "$SSID" ]] || fail "SSID is empty"
[[ -n "$PASSWORD" ]] || fail "Password is empty"

log "Provisioning job accepted for SSID: $SSID"
log "Waiting briefly before switching network mode."

# Give Flask enough time to return the response page to the browser.
sleep 3

exec "$CONNECT_SCRIPT" "$SSID" "$PASSWORD"