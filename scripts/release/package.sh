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
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$REPO_ROOT/scripts/common/bootstrap.sh"
# shellcheck source=scripts/common/release-files.sh
source "$REPO_ROOT/scripts/common/release-files.sh"
# shellcheck source=scripts/common/integrity.sh
source "$REPO_ROOT/scripts/common/integrity.sh"

readonly DIST_DIR="$REPO_ROOT/dist"
readonly PKG_NAME="maops-linux-devops-toolkit-$PROJECT_VERSION"

# Staging happens under mktemp's default location (never under $DIST_DIR)
# specifically because $REPO_ROOT may sit on a filesystem (e.g. WSL/drvfs)
# where chmod is a silent no-op -- see integrity_chmod_verified, which
# would otherwise catch this at staging time and abort. mktemp's default
# location is a plain filesystem that reliably honors chmod; only the
# final binary archive (a plain file write, no chmod required) is written
# into $DIST_DIR.
STAGE_ROOT=""
STAGE_DIR=""

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

# init_staging_root
# Creates STAGE_ROOT via mktemp (see the STAGE_ROOT comment above for why)
# and registers an EXIT trap so it is removed on every exit path, success
# or failure alike -- unlike a cleanup step only reached after the whole
# build succeeds.
init_staging_root() {
    STAGE_ROOT="$(mktemp -d)"
    trap 'rm -rf -- "$STAGE_ROOT"' EXIT
    STAGE_DIR="$STAGE_ROOT/$PKG_NAME"
}

# build_staging
# Copies every entry in RELEASE_FILE_LIST into STAGE_DIR, expanded to its
# Git-tracked files (git ls-files -- ENTRY handles both a directory entry
# like "scripts" and a single-file entry like "README.md" uniformly, so a
# stray untracked temp/editor file is never packaged). Every file's
# filesystem mode is derived from Git's index, never from the source
# filesystem's stat/cp -a -- this is what keeps the archive reproducible
# regardless of whether the checkout sits on a filesystem (e.g. WSL/drvfs)
# that misreports tracked-file permissions. The per-file manifest lines
# integrity_copy_git_tracked prints are captured into MAOPS-MANIFEST.tsv,
# sorted deterministically, so the archive ships an independent per-file
# integrity record alongside the external whole-archive checksum.
build_staging() {
    mkdir -p -- "$STAGE_DIR"

    local manifest_tmp="$STAGE_ROOT/.manifest.tmp"
    if ! integrity_copy_git_tracked "$STAGE_DIR" "$REPO_ROOT" "${RELEASE_FILE_LIST[@]}" >"$manifest_tmp"; then
        log_error "${INTEGRITY_LAST_ERROR:-Failed to stage Git-tracked release files.}"
        exit 1
    fi

    LC_ALL=C sort -o "$STAGE_DIR/MAOPS-MANIFEST.tsv" "$manifest_tmp"
    rm -f -- "$manifest_tmp"

    find "$STAGE_DIR" -type d -exec chmod 0755 {} +
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

###############################################################################
# Main
###############################################################################

main() {
    require_git_checkout
    init_staging_root
    build_staging
    build_archive
}

parse_args "$@"
main
