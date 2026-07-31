#!/usr/bin/env bash
# shellcheck disable=SC2034 # config values are consumed by scripts that source this file

[[ -n "${MAOPS_CONFIG_LOADED:-}" ]] && return
readonly MAOPS_CONFIG_LOADED=1

readonly PROJECT_NAME="MAOps Linux DevOps Toolkit"
readonly PROJECT_VERSION="0.2.0"
readonly PROJECT_AUTHOR="Raiyan Yousuf"
readonly PROJECT_LICENSE="MIT"

readonly LOG_DIRECTORY="/tmp"

readonly DEFAULT_TIMEOUT=5