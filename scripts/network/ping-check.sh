#!/usr/bin/env bash

###############################################################################
#
# Script Name : ping-check.sh
# Description : Check host reachability with a bounded, safe-default ping
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.2.0
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"
# shellcheck source=scripts/common/config-file.sh
source "$SCRIPT_DIR/../common/config-file.sh"

readonly DEFAULT_PING_COUNT=4

HOST=""
COUNT=""

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") HOST [COUNT]

Options:
    -h, --help       Show this help message
    -v, --version    Show project version

Arguments:
    HOST             Hostname or IP address to ping
    COUNT            Number of packets to send (default: $DEFAULT_PING_COUNT)

Examples:
    $(basename "$0") example.com
    $(basename "$0") example.com 6
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

            -[0-9]*)
                # A negative number (e.g. "-1"), not a flag — let COUNT
                # validation below report it with a clear message instead of
                # this parser misreporting it as an unknown option.
                positional+=("$1")
                shift
                ;;

            -*)
                cli_usage_error "Unknown option: $1"
                ;;

            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    if [[ -z "${positional[0]:-}" ]]; then
        cli_usage_error "HOST is required."
    fi

    HOST="${positional[0]}"
    COUNT="${positional[1]:-$(config_resolve_value ping_count "" MAOPS_PING_COUNT "$DEFAULT_PING_COUNT")}"

    validate_positive_integer "$COUNT" "COUNT"
}

###############################################################################
# Main
###############################################################################

main() {
    require_linux
    require_command ping

    show_header "Ping Check"
    log_info "Pinging $HOST with $COUNT packet(s) (timeout ${DEFAULT_TIMEOUT}s per packet)..."

    ping -c "$COUNT" -W "$DEFAULT_TIMEOUT" "$HOST"

    log_success "Host $HOST is reachable."
}

parse_args "$@"
main
