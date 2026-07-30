#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The dynamically resolved dependency is linted independently.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../common/bootstrap.sh"

TARGET="${1:-.}"
LIMIT="${2:-10}"

validate_inputs() {
    require_command find
    require_command sort
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

    show_header "Largest Files"
    log_info "Scanning ${TARGET}"

    local results

    results="$(
        {
            find "$TARGET" \
                -type f \
                -printf '%s\t%p\n' \
                2>/dev/null || true
        } |
            sort -nr -k1,1 |
            awk -F '\t' -v limit="$LIMIT" '
                NR <= limit {
                    size_mb = $1 / 1024 / 1024
                    path = $0
                    sub(/^[^\t]*\t/, "", path)
                    printf "%8.2f MB  %s\n", size_mb, path
                }
            '
    )"

    if [[ -z "$results" ]]; then
        log_warn "No accessible regular files found under ${TARGET}."
    else
        printf '%s\n' "$results"
    fi

    log_success "Largest file scan completed."
}

main "$@"