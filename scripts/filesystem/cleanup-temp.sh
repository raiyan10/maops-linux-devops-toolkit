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
    $(basename "$0") [TARGET] [LIMIT]

Options:
    -h, --help       Show this help message
    -v, --version    Show project version

Arguments:
    TARGET           Directory to scan (default: /tmp)
    LIMIT            Number of results to show (default: 30)
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
    -v | --version)
        cli_show_version
        exit 0
        ;;
esac

TARGET="${1:-/tmp}"
LIMIT="${2:-30}"

validate_inputs() {
    require_command find
    require_command awk

    if [[ ! -d "$TARGET" ]]; then
        log_error "Directory not found: $TARGET"
        return 1
    fi

    if [[ ! "$LIMIT" =~ ^[1-9][0-9]*$ ]]; then
        log_error "Limit must be a positive integer: $LIMIT"
        return 1
    fi
}

main() {
    require_linux
    validate_inputs

    show_header "Temporary Files"
    log_info "Scanning ${TARGET} for accessible temporary files..."

    local results

    results="$(
        {
            find "$TARGET" \
                \( -type d \
                    \( -name 'systemd-private-*' -o -name 'snap-private-tmp' \) \
                    -prune \
                \) \
                -o \
                \( -type f -readable -print \) \
                2>/dev/null || true
        } |
            awk -v limit="$LIMIT" 'NR <= limit'
    )"

    if [[ -z "$results" ]]; then
        log_warn "No accessible regular files found in ${TARGET}."
    else
        printf '%s\n' "$results"
    fi

    log_warn "Dry-run only. No files were removed."
    log_success "Temporary-file scan completed."
}

main "$@"