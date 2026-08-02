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

    print_title "$PROJECT_NAME"

    log_info "Collecting system information..."

    echo

    echo "Hostname : $(hostname)"

    echo "Kernel   : $(uname -r)"

    echo "OS       : $(uname -s)"

    echo "User     : $(whoami)"

    echo "Uptime   : $(uptime -p)"

    log_success "Report completed."
}

parse_args "$@"
main