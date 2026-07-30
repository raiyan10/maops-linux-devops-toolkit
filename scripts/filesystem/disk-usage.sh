#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The dynamically resolved dependency is linted independently.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../common/bootstrap.sh"

main() {
    require_linux
    require_command df

    show_header "Disk Usage Report"
    log_info "Collecting filesystem usage..."

    df -h \
        --output=source,fstype,size,used,avail,pcent,target \
        -x tmpfs \
        -x devtmpfs

    log_success "Disk usage report completed."
}

main "$@"