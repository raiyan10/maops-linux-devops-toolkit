#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../common/bootstrap.sh"

main() {

    print_title "Hostname Report"

    log_info "Generating hostname report..."

    section "Hostname"

    print_key_value "Hostname" "$(hostname)"
    print_key_value "FQDN" "$(hostname -f 2>/dev/null || echo "Unavailable")"

    log_success "Hostname report completed."
}

main "$@"