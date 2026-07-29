#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../common/bootstrap.sh"

main() {

    require_linux

    show_header "Memory Report"

    log_info "Collecting memory information..."

    show_section "Memory"

    free -h

    log_success "Memory report completed."
}

main "$@"