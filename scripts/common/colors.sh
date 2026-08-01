#!/usr/bin/env bash
# shellcheck disable=SC2034 # color codes are consumed by scripts that source this file (e.g. logger.sh)

# Prevent multiple sourcing
[[ -n "${MAOPS_COLORS_LOADED:-}" ]] && return
readonly MAOPS_COLORS_LOADED=1

# Colors are suppressed (empty) when NO_COLOR is set to any non-empty value
# (https://no-color.org) or when stdout is not a terminal (piped to a file,
# captured by a test, redirected in CI), so log output never embeds raw
# ANSI escapes in a non-interactive context.
if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly PURPLE=''
    readonly CYAN=''
    readonly WHITE=''
    readonly NC=''
else
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly NC='\033[0m'
fi
