#!/usr/bin/env bash

[[ -n "${MAOPS_LOGGER_LOADED:-}" ]] && return
readonly MAOPS_LOGGER_LOADED=1

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

_log() {

    local level="$1"
    local color="$2"
    local message="$3"

    echo -e "${color}[$(timestamp)] [$level]${NC} ${message}"
}

log_info() {
    _log "INFO" "$BLUE" "$1"
}

log_success() {
    _log "SUCCESS" "$GREEN" "$1"
}

log_warn() {
    _log "WARNING" "$YELLOW" "$1"
}

log_error() {
    _log "ERROR" "$RED" "$1"
}