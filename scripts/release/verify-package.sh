#!/usr/bin/env bash

###############################################################################
#
# Script Name : verify-package.sh
# Description : Verifies a release archive's SHA-256 checksum, rejects
#               unsafe archive member paths (absolute paths, path
#               traversal, or a member outside the single expected
#               top-level directory) before any extraction happens, and
#               confirms a fixed set of required paths exist inside it.
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.4.0
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$REPO_ROOT/scripts/common/bootstrap.sh"

readonly DIST_DIR="$REPO_ROOT/dist"
readonly PKG_NAME="maops-linux-devops-toolkit-$PROJECT_VERSION"

readonly REQUIRED_ARCHIVE_PATHS=(
    "bin/maops"
    "scripts/common/bootstrap.sh"
    "scripts/config/config-manager.sh"
    "scripts/diagnostics/doctor.sh"
    "scripts/install/install.sh"
    "scripts/install/uninstall.sh"
    "scripts/release/package.sh"
    "templates/script-template.sh"
    "LICENSE"
    "Makefile"
    "README.md"
    "CHANGELOG.md"
)

ARCHIVE_ARG=""
SCRATCH_DIR=""

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [ARCHIVE]

Verifies a release archive's checksum, rejects unsafe archive member
paths, and confirms required paths are present. Defaults to
dist/$PKG_NAME.tar.gz.

Options:
    -h, --help       Show this help message
    -v, --version    Show project version
EOF
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;

            -v | --version)
                cli_show_version
                exit 0
                ;;

            -*)
                cli_usage_error "Unknown option: $1"
                ;;

            *)
                ARCHIVE_ARG="$1"
                shift
                ;;
        esac
    done
}

###############################################################################
# Checks
###############################################################################

verify_checksum() {
    local archive="$1"
    local checksum="$archive.sha256"

    if [[ ! -f "$checksum" ]]; then
        log_error "Checksum file not found: $checksum"
        exit 1
    fi

    if ! (cd "$(dirname -- "$archive")" && sha256sum -c -- "$(basename -- "$checksum")") >/dev/null 2>&1; then
        log_error "Checksum verification failed for $archive"
        exit 1
    fi
}

# is_unsafe_member MEMBER
# True if MEMBER is an absolute path or contains a literal ".." path
# segment (checked component-by-component, not via substring match, so a
# legitimate filename like "v1.2..3" is never a false positive).
is_unsafe_member() {
    local member="$1"
    [[ "$member" == /* ]] && return 0

    local part
    local IFS='/'
    for part in $member; do
        [[ "$part" == ".." ]] && return 0
    done
    return 1
}

verify_member_paths() {
    local archive="$1"
    local expected_prefix="$PKG_NAME/"
    local member

    while IFS= read -r member; do
        if is_unsafe_member "$member"; then
            log_error "Refusing archive with an unsafe member path: $member"
            exit 1
        fi

        if [[ "$member" != "$expected_prefix"* && "$member" != "$PKG_NAME" ]]; then
            log_error "Refusing archive with a member outside $expected_prefix: $member"
            exit 1
        fi
    done < <(tar -tzf "$archive")
}

verify_required_paths() {
    local archive="$1"

    SCRATCH_DIR="$(mktemp -d)"
    trap 'rm -rf -- "$SCRATCH_DIR"' EXIT

    tar -xzf "$archive" -C "$SCRATCH_DIR"

    local rel
    for rel in "${REQUIRED_ARCHIVE_PATHS[@]}"; do
        if [[ ! -e "$SCRATCH_DIR/$PKG_NAME/$rel" ]]; then
            log_error "Required path missing from archive: $rel"
            exit 1
        fi
    done
}

###############################################################################
# Main
###############################################################################

main() {
    require_command tar
    require_command sha256sum

    local archive="${ARCHIVE_ARG:-$DIST_DIR/$PKG_NAME.tar.gz}"

    if [[ ! -f "$archive" ]]; then
        log_error "Archive not found: $archive"
        exit 1
    fi

    verify_checksum "$archive"
    verify_member_paths "$archive"
    verify_required_paths "$archive"

    log_success "Package verified: $archive"
}

parse_args "$@"
main
