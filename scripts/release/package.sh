#!/usr/bin/env bash

###############################################################################
#
# Script Name : package.sh
# Description : Builds a reproducible release tarball and SHA-256 checksum
#               from the current git checkout. Only git-tracked files are
#               packaged (never stray untracked/temp/editor files), and the
#               same scripts/common/release-files.sh list used by
#               install.sh is reused here, so the installed tree and the
#               released tarball can never drift apart.
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
# shellcheck source=scripts/common/release-files.sh
source "$REPO_ROOT/scripts/common/release-files.sh"

readonly DIST_DIR="$REPO_ROOT/dist"
readonly PKG_NAME="maops-linux-devops-toolkit-$PROJECT_VERSION"
readonly STAGE_ROOT="$DIST_DIR/.package-staging"
readonly STAGE_DIR="$STAGE_ROOT/$PKG_NAME"

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0")

Builds dist/$PKG_NAME.tar.gz and dist/$PKG_NAME.tar.gz.sha256 from the
current source tree. Must be run from a git checkout — only git-tracked
files are packaged.

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

            *)
                cli_usage_error "Unknown option: $1"
                ;;
        esac
    done
}

###############################################################################
# Staging
###############################################################################

require_git_checkout() {
    require_command git
    require_command tar
    require_command sha256sum

    if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "package.sh must be run from a git checkout of the repository."
        exit 1
    fi
}

# copy_entry ENTRY
# ENTRY is a path relative to REPO_ROOT, per scripts/common/release-files.sh.
# A directory entry is expanded to its git-tracked files only, so a stray
# untracked temp/editor file left inside e.g. scripts/ is never packaged.
copy_entry() {
    local entry="$1"
    local src="$REPO_ROOT/$entry"

    if [[ -d "$src" ]]; then
        local rel
        while IFS= read -r rel; do
            mkdir -p -- "$(dirname -- "$STAGE_DIR/$rel")"
            cp -a -- "$REPO_ROOT/$rel" "$STAGE_DIR/$rel"
        done < <(cd "$REPO_ROOT" && git ls-files -z -- "$entry" | tr '\0' '\n')
    else
        mkdir -p -- "$(dirname -- "$STAGE_DIR/$entry")"
        cp -a -- "$src" "$STAGE_DIR/$entry"
    fi
}

build_staging() {
    rm -rf -- "$STAGE_ROOT"
    mkdir -p -- "$STAGE_DIR"

    local entry
    for entry in "${RELEASE_FILE_LIST[@]}"; do
        copy_entry "$entry"
    done
}

###############################################################################
# Archive
###############################################################################

build_archive() {
    mkdir -p -- "$DIST_DIR"

    local archive="$DIST_DIR/$PKG_NAME.tar.gz"
    local checksum_name
    checksum_name="$(basename -- "$archive").sha256"

    # --sort=name, --mtime, --owner/--group/--numeric-owner make the tar
    # stream itself reproducible; gzip -n additionally suppresses the
    # original-name/timestamp fields gzip would otherwise embed in its own
    # header, so repeated builds from the same tree are byte-identical.
    tar --sort=name --mtime="@0" --owner=0 --group=0 --numeric-owner \
        -cf - -C "$STAGE_ROOT" "$PKG_NAME" | gzip -n >"$archive"

    (cd "$DIST_DIR" && sha256sum -- "$(basename -- "$archive")" >"$checksum_name")

    log_success "Built $archive"
    log_success "Built $DIST_DIR/$checksum_name"
}

cleanup_staging() {
    rm -rf -- "$STAGE_ROOT"
}

###############################################################################
# Main
###############################################################################

main() {
    require_git_checkout
    build_staging
    build_archive
    cleanup_staging
}

parse_args "$@"
main
