#!/usr/bin/env bash

###############################################################################
#
# Script Name : process-monitor.sh
# Description : Read-only top-N process report, sorted by CPU or memory use
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"
# shellcheck source=scripts/common/config-file.sh
source "$SCRIPT_DIR/../common/config-file.sh"

readonly DEFAULT_PROCESS_LIMIT=10
readonly DEFAULT_PROCESS_SORT="cpu"

LIMIT=""
SORT_MODE=""

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [LIMIT] [cpu|memory]

Options:
    -h, --help       Show this help message
    -v, --version    Show project version

Arguments:
    LIMIT            Number of processes to show (default: $DEFAULT_PROCESS_LIMIT)
    cpu|memory       Sort key (default: $DEFAULT_PROCESS_SORT)

Examples:
    $(basename "$0")
    $(basename "$0") 5
    $(basename "$0") 15 memory
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
                # A negative number (e.g. "-1"), not a flag — let LIMIT
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

    LIMIT="${positional[0]:-$(config_resolve_value process_limit "" MAOPS_PROCESS_LIMIT "$DEFAULT_PROCESS_LIMIT")}"
    SORT_MODE="${positional[1]:-$DEFAULT_PROCESS_SORT}"

    validate_positive_integer "$LIMIT" "LIMIT"
    validate_one_of "$SORT_MODE" "SORT" cpu memory
}

###############################################################################
# Main
###############################################################################

main() {
    require_linux
    require_command ps
    require_command awk

    # SORT_MODE is validated above against a fixed enum, then mapped through
    # this fixed literal case — user input never reaches the ps sort flag
    # directly, closing off flag-injection via SORT.
    local sort_key
    case "$SORT_MODE" in
        cpu) sort_key="-pcpu" ;;
        memory) sort_key="-pmem" ;;
    esac

    show_header "Process Monitor"
    log_info "Showing top $LIMIT process(es) by $SORT_MODE usage..."

    # comm (executable name only) is used instead of args (full command line)
    # so secrets that are sometimes passed on a command line (--password=...,
    # tokens, connection strings) are never printed.
    #
    # Row truncation happens in awk, not by piping into `head`: `head -n N`
    # closing its read end early would send `ps` a SIGPIPE once the pipeline
    # produces more rows than LIMIT, turning this command's exit status into
    # 141 under `set -o pipefail` (the exact bug previously fixed in
    # largest-files.sh). awk reads its input to EOF, so ps always exits
    # normally.
    local results
    results="$(
        ps -eo pid,user:16,pcpu,pmem,etime,comm --sort="$sort_key" |
            awk -v limit="$LIMIT" 'NR <= limit + 1'
    )"

    printf '%s\n' "$results"

    log_success "Process report completed."
}

parse_args "$@"
main
