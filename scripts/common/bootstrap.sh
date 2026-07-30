#!/usr/bin/env bash

[[ -n "${MAOPS_BOOTSTRAP_LOADED:-}" ]] && return
readonly MAOPS_BOOTSTRAP_LOADED=1

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/colors.sh
source "$COMMON_DIR/colors.sh"
# shellcheck source=scripts/common/config.sh
source "$COMMON_DIR/config.sh"
# shellcheck source=scripts/common/helpers.sh
source "$COMMON_DIR/helpers.sh"
# shellcheck source=scripts/common/logger.sh
source "$COMMON_DIR/logger.sh"
# shellcheck source=scripts/common/output.sh
source "$COMMON_DIR/output.sh"