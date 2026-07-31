#!/usr/bin/env bash

###############################################################################
#
# Script Name : service-status.sh
# Description : Read-only service state inspection via systemctl, falling
#               back to the service(8) command when systemd is not the
#               running init system
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.3.0
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"

# /run/systemd/system existing is the same probe systemd's own sd_booted(3)
# uses to mean "systemd is the running init system". It is more reliable
# than `command -v systemctl` alone, which is also true in containers/WSL
# where the systemctl binary is installed but systemd is not PID 1 (running
# systemctl there fails with "Failed to connect to bus").
#
# MAOPS_SYSTEMD_RUNTIME_DIR is a documented, read-only test seam: it only
# selects which status query this script runs, so it can never cause a
# mutation. It exists because a real systemd host (e.g. this project's CI
# runner) can never exercise the service(8) fallback branch otherwise, and a
# plain container can never exercise the systemd branch otherwise.
readonly SYSTEMD_RUNTIME_DIR="${MAOPS_SYSTEMD_RUNTIME_DIR:-/run/systemd/system}"

SERVICE=""

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") SERVICE

Options:
    -h, --help       Show this help message
    -v, --version    Show project version

Arguments:
    SERVICE          Name of the service to inspect

Examples:
    $(basename "$0") cron
    $(basename "$0") nginx
EOF
}

###############################################################################
# Argument parsing
###############################################################################

parse_args() {
    local positional=()

    while (($# > 0)); do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;

            -v | --version)
                cli_show_version
                exit 0
                ;;

            # No other flags are supported; everything else (including a
            # leading-dash value) is collected as the candidate SERVICE so
            # validate_non_option_argument below can report a precise,
            # label-specific error instead of a generic "Unknown option".
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    if [[ -z "${positional[0]:-}" ]]; then
        cli_usage_error "SERVICE is required."
    fi

    if ((${#positional[@]} > 1)); then
        cli_usage_error "Too many arguments. Expected exactly one SERVICE."
    fi

    SERVICE="${positional[0]}"

    validate_non_option_argument "$SERVICE" "SERVICE"
}

###############################################################################
# Service-manager detection
###############################################################################

systemd_is_running() {
    command_exists systemctl && [[ -d "$SYSTEMD_RUNTIME_DIR" ]]
}

###############################################################################
# systemd path
###############################################################################

check_via_systemctl() {
    local show_output
    if ! show_output="$(systemctl show --no-pager --property=LoadState,ActiveState,SubState -- "$SERVICE" 2>&1)"; then
        # systemctl show exits 0 for every normal case, including a unit
        # that does not exist (LoadState=not-found). A non-zero exit here
        # means systemctl itself failed (bus error, permission issue, etc.)
        # and must be surfaced, never silently treated as "inactive".
        log_error "systemctl query failed for $SERVICE: $show_output"
        exit 1
    fi

    local load_state="" active_state="" sub_state=""
    local line
    while IFS= read -r line; do
        case "${line%%=*}" in
            LoadState) load_state="${line#*=}" ;;
            ActiveState) active_state="${line#*=}" ;;
            SubState) sub_state="${line#*=}" ;;
        esac
    done <<<"$show_output"

    if [[ "$load_state" == "not-found" ]]; then
        log_error "Unknown service: $SERVICE (no such unit)"
        exit 1
    fi

    print_key_value "Service" "$SERVICE"
    print_key_value "Load state" "$load_state"
    print_key_value "Active state" "$active_state"
    print_key_value "Sub state" "$sub_state"

    if [[ "$active_state" == "active" ]]; then
        log_success "Service is active: $SERVICE"
        exit 0
    fi

    log_warn "Service is not active: $SERVICE ($active_state)"
    exit 1
}

###############################################################################
# service(8) fallback path
###############################################################################

check_via_service_command() {
    local output rc=0
    output="$(service "$SERVICE" status 2>&1)" || rc=$?

    printf '%s\n' "$output"

    # The LSB init-script exit-code convention is the sole signal used to
    # decide the outcome; the free-form status text is only ever printed
    # for the operator, never pattern-matched, since output wording varies
    # across distributions and init scripts.
    case "$rc" in
        0)
            log_success "Service is running: $SERVICE"
            exit 0
            ;;
        3)
            log_warn "Service is not running: $SERVICE"
            exit 1
            ;;
        4)
            log_error "Unknown service: $SERVICE"
            exit 1
            ;;
        *)
            log_error "Service status lookup failed for $SERVICE (exit $rc)."
            exit 1
            ;;
    esac
}

###############################################################################
# Main
###############################################################################

main() {
    require_linux

    show_header "Service Status"
    log_info "Checking service: $SERVICE..."

    if systemd_is_running; then
        require_command systemctl
        check_via_systemctl
    elif command_exists service; then
        check_via_service_command
    else
        log_error "No supported service manager found (systemd is not running and 'service' is unavailable)."
        exit 1
    fi
}

parse_args "$@"
main
