#!/usr/bin/env bash

###############################################################################
#
# Script Name : <script-name>
# Description : <description>
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : <version>
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# This path becomes valid after the template is copied under scripts/<module>/.
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
    $(basename "$0") --version
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
                printf '%s %s\n' "$PROJECT_NAME" "$PROJECT_VERSION"
                exit 0
                ;;

            --)
                shift

                if (($# > 0)); then
                    log_error "This template does not yet accept positional arguments."
                    usage >&2
                    return 2
                fi

                break
                ;;

            -*)
                log_error "Unknown option: $1"
                usage >&2
                return 2
                ;;

            *)
                log_error "Unexpected positional argument: $1"
                usage >&2
                return 2
                ;;
        esac
    done
}

###############################################################################
# Main
###############################################################################

main() {
    require_linux

    show_header "<TITLE>"
    log_info "Starting <operation description>..."

    # Implement the utility here.

    log_success "<Operation description> completed."
}

parse_args "$@"
main