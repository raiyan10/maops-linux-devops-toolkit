#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"

main() {

    require_linux

    print_title "Operating System Details"

    log_info "Collecting operating system information..."

    section "General"

    print_key_value "Operating System" "$(uname -o)"
    print_key_value "Kernel" "$(uname -r)"
    print_key_value "Architecture" "$(uname -m)"

    if [[ -f /etc/os-release ]]; then

        # shellcheck source=/dev/null
        source /etc/os-release

        print_key_value "Distribution" "$PRETTY_NAME"
        print_key_value "Version" "$VERSION_ID"
    fi

    log_success "Operating system report completed."
}

main "$@"