#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/colors.sh"

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