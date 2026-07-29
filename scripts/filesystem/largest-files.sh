#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/bootstrap.sh"

TARGET="${1:-.}"
LIMIT="${2:-10}"

main() {

    require_linux

    show_header "Largest Files"

    log_info "Scanning ${TARGET}"

    if [[ ! -d "$TARGET" ]]; then
        log_error "Directory not found: $TARGET"
        exit 1
    fi

    find "$TARGET" -type f -printf "%s\t%p\n" 2>/dev/null \
        | sort -nr \
        | head -n "$LIMIT" \
        | awk '{
            size=$1/1024/1024
            $1=""
            sub(/^\t/,"")
            printf "%8.2f MB  %s\n",size,$0
        }'

    log_success "Largest file scan completed."
}

main "$@"