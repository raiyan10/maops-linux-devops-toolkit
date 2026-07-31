#!/usr/bin/env bash

###############################################################################
#
# Script Name : dns-lookup.sh
# Description : Resolve a hostname or IP address using the system resolver
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.2.0
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"

TARGET=""

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") HOSTNAME_OR_IP

Options:
    -h, --help       Show this help message
    -v, --version    Show project version

Arguments:
    HOSTNAME_OR_IP   Hostname or IP address to resolve

Examples:
    $(basename "$0") localhost
    $(basename "$0") example.com
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
        cli_usage_error "HOSTNAME_OR_IP is required."
    fi

    TARGET="${positional[0]}"
}

###############################################################################
# Main
###############################################################################

main() {
    require_linux
    require_command getent

    show_header "DNS Lookup"
    log_info "Resolving $TARGET..."

    local result

    if result="$(getent hosts "$TARGET" 2>/dev/null)"; then
        printf '%s\n' "$result"
        log_success "DNS lookup completed."
    else
        log_error "No DNS record found for: $TARGET"
        exit 1
    fi
}

parse_args "$@"
main
