#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The dynamically resolved dependency is linted independently.
# shellcheck source=/dev/null
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
    require_command df

    show_header "Disk Usage Report"
    log_info "Collecting filesystem usage..."

    df -h \
        --output=source,fstype,size,used,avail,pcent,target \
        -x tmpfs \
        -x devtmpfs

    log_success "Disk usage report completed."
}

parse_args "$@"
main