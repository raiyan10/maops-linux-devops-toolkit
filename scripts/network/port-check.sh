#!/usr/bin/env bash

###############################################################################
#
# Script Name : port-check.sh
# Description : Check TCP port reachability with a bounded connection timeout
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.2.0
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"

HOST=""
PORT=""
TIMEOUT=""

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") HOST PORT [TIMEOUT]

Options:
    -h, --help       Show this help message
    -v, --version    Show project version

Arguments:
    HOST             Hostname or IP address to check
    PORT             TCP port number (1-65535)
    TIMEOUT          Connection timeout in seconds (default: $DEFAULT_TIMEOUT)

Examples:
    $(basename "$0") example.com 443
    $(basename "$0") example.com 443 2
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
                # A negative number (e.g. "-1"), not a flag — let PORT/TIMEOUT
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

    if [[ -z "${positional[0]:-}" || -z "${positional[1]:-}" ]]; then
        cli_usage_error "HOST and PORT are required."
    fi

    HOST="${positional[0]}"
    PORT="${positional[1]}"
    TIMEOUT="${positional[2]:-$DEFAULT_TIMEOUT}"

    validate_tcp_port "$PORT"
    validate_positive_integer "$TIMEOUT" "TIMEOUT"
}

###############################################################################
# Main
###############################################################################

main() {
    require_linux
    require_command timeout

    show_header "Port Check"
    log_info "Checking $HOST:$PORT (timeout ${TIMEOUT}s)..."

    # $1/$2 are the inner bash's own positional parameters (bound from $HOST
    # and $PORT below), not this shell's — the script stays single-quoted so
    # neither ever gets re-parsed as shell syntax by the child bash.
    # shellcheck disable=SC2016
    if timeout "$TIMEOUT" bash -c 'exec 3<>"/dev/tcp/$1/$2"' bash "$HOST" "$PORT" 2>/dev/null; then
        log_success "Port $PORT is open on $HOST."
    else
        log_error "Port $PORT is not reachable on $HOST."
        exit 1
    fi
}

parse_args "$@"
main
