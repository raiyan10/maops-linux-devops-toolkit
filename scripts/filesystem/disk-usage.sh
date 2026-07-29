#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/bootstrap.sh"

main() {

    require_linux

    show_header "Disk Usage Report"

    log_info "Collecting disk usage..."

    df -h

    log_success "Disk usage report completed."
}

main "$@"