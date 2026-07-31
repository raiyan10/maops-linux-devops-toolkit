#!/usr/bin/env bash

###############################################################################
#
# Script Name : network-info.sh
# Description : Report hostname, active interfaces, IPv4 addresses, default
#               gateway, and configured DNS resolvers
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.2.0
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [OPTIONS]

Options:
    -h, --help       Show this help message
    -v, --version    Show project version

Examples:
    $(basename "$0")
    $(basename "$0") --help
EOF
}

###############################################################################
# Argument parsing
###############################################################################

parse_args() {
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

            *)
                cli_usage_error "Unexpected argument: $1"
                ;;
        esac
    done
}

###############################################################################
# Reporting
###############################################################################

report_interfaces() {
    section "Active Interfaces"
    ip -brief link show

    section "IPv4 Addresses"
    ip -4 -brief addr show
}

report_gateway() {
    section "Default Gateway"

    local gateway
    gateway="$(ip route show default 2>/dev/null || true)"

    if [[ -n "$gateway" ]]; then
        printf '%s\n' "$gateway"
    else
        log_warn "No default gateway configured."
    fi
}

report_dns() {
    section "DNS Resolvers"

    if [[ -r /etc/resolv.conf ]]; then
        local resolvers
        resolvers="$(grep '^nameserver' /etc/resolv.conf || true)"

        if [[ -n "$resolvers" ]]; then
            printf '%s\n' "$resolvers"
        else
            log_warn "No nameserver entries found in /etc/resolv.conf."
        fi
    else
        log_warn "/etc/resolv.conf is not readable or does not exist."
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    require_linux
    require_command ip

    show_header "Network Information"
    log_info "Collecting network information..."

    print_key_value "Hostname" "$(hostname)"

    report_interfaces
    report_gateway
    report_dns

    log_success "Network information report completed."
}

parse_args "$@"
main
