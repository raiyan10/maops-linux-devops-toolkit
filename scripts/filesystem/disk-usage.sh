#!/usr/bin/env bash
set -euo pipefail

source "../common/logger.sh"
source "../common/helpers.sh"
source "../common/colors.sh"

main() {
  info "Checking disk usage"
  df -h
}

main "$@"
