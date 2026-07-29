#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/bootstrap.sh"

main() {

    require_linux

    show_header "Temporary Files"

    log_info "Listing temporary files..."

    find /tmp \
        -type f \
        ! -path "/tmp/systemd-private-*" \
        2>/dev/null \
        | head -30

    log_warn "Dry-run only. No files removed."

    log_success "Scan completed."
}

main "$@"