#!/usr/bin/env bash

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

main() {

    require_linux

    show_header "Memory Report"

    log_info "Collecting memory information..."

    show_section "Memory"

    free -h

    log_success "Memory report completed."
}

parse_args "$@"
main