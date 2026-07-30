#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"

main() {

    require_linux

    show_header "CPU Report"

    log_info "Collecting CPU information..."

    show_section "CPU"

    lscpu

    log_success "CPU report completed."
}

main "$@"