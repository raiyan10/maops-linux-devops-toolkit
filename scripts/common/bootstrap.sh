#!/usr/bin/env bash

set -euo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${MAOPS_COMMON_BOOTSTRAP_LOADED:-}" ]]; then
    MAOPS_COMMON_BOOTSTRAP_LOADED=1

    source "$COMMON_DIR/colors.sh"
    source "$COMMON_DIR/logger.sh"
    source "$COMMON_DIR/helpers.sh"
    source "$COMMON_DIR/output.sh"
    source "$COMMON_DIR/config.sh"
fi