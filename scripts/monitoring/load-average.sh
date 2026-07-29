#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../common/bootstrap.sh"

main() {

    require_linux

    show_header "Load Average"

    log_info "Collecting load average..."

    show_section "System Load"

    uptime

    log_success "Load average report completed."
}

main "$@"