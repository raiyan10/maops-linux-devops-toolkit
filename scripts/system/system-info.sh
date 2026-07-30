#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"

main() {

    print_title "$PROJECT_NAME"

    log_info "Collecting system information..."

    echo

    echo "Hostname : $(hostname)"

    echo "Kernel   : $(uname -r)"

    echo "OS       : $(uname -s)"

    echo "User     : $(whoami)"

    echo "Uptime   : $(uptime -p)"

    log_success "Report completed."
}

main "$@"