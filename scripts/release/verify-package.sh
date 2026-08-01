#!/usr/bin/env bash

###############################################################################
#
# Script Name : verify-package.sh
# Description : Verifies a release archive. Snapshots the archive into a
#               private scratch directory so every check reads the same
#               immutable copy, rejects unsafe or disallowed archive
#               members (absolute paths, path traversal, multiple
#               top-level roots, symlinks, hardlinks, devices, FIFOs,
#               sockets -- only regular files and directories are ever
#               accepted) before any extraction happens, then verifies
#               every distributed file's mode and content against the
#               package's internal MAOPS-MANIFEST.tsv, independently of the
#               external whole-archive SHA-256 checksum.
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$REPO_ROOT/scripts/common/bootstrap.sh"
# shellcheck source=scripts/common/integrity.sh
source "$REPO_ROOT/scripts/common/integrity.sh"

readonly DIST_DIR="$REPO_ROOT/dist"
readonly PKG_NAME="maops-linux-devops-toolkit-$PROJECT_VERSION"

readonly REQUIRED_ARCHIVE_PATHS=(
    "bin/maops"
    "scripts/common/bootstrap.sh"
    "scripts/common/integrity.sh"
    "scripts/config/config-manager.sh"
    "scripts/diagnostics/doctor.sh"
    "scripts/diagnostics/integrity-check.sh"
    "scripts/install/install.sh"
    "scripts/install/uninstall.sh"
    "scripts/release/package.sh"
    "templates/script-template.sh"
    "LICENSE"
    "Makefile"
    "README.md"
    "CHANGELOG.md"
    "MAOPS-MANIFEST.tsv"
)

ARCHIVE_ARG=""
SNAPSHOT_DIR=""
SNAPSHOT_ARCHIVE=""
EXTRACT_DIR=""

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [ARCHIVE]

Verifies a release archive's checksum, rejects unsafe/disallowed archive
members before extraction, and validates every distributed file against
the package's internal MAOPS-MANIFEST.tsv. Defaults to
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
# Snapshot
###############################################################################

# snapshot_archive ARCHIVE
# Copies ARCHIVE and its .sha256 sidecar into a private mktemp directory
# and registers an EXIT trap to remove it. Every check that follows reads
# only this private copy, never ARCHIVE's original path again -- closing
# the window for a concurrent modification to the source archive to affect
# any check performed here.
snapshot_archive() {
    local archive="$1"
    local checksum="$archive.sha256"

    SNAPSHOT_DIR="$(mktemp -d)"
    trap 'rm -rf -- "$SNAPSHOT_DIR"' EXIT

    SNAPSHOT_ARCHIVE="$SNAPSHOT_DIR/$(basename -- "$archive")"
    cp -- "$archive" "$SNAPSHOT_ARCHIVE"

    if [[ -f "$checksum" ]]; then
        cp -- "$checksum" "$SNAPSHOT_ARCHIVE.sha256"
    fi
}

###############################################################################
# Checksum (external authority: is this the exact archive we were told to
# trust)
###############################################################################

verify_checksum() {
    local checksum="$SNAPSHOT_ARCHIVE.sha256"

    if [[ ! -f "$checksum" ]]; then
        log_error "Checksum file not found: $checksum"
        exit 1
    fi

    if ! (cd "$(dirname -- "$SNAPSHOT_ARCHIVE")" && sha256sum -c -- "$(basename -- "$checksum")") >/dev/null 2>&1; then
        log_error "Checksum verification failed for $SNAPSHOT_ARCHIVE"
        exit 1
    fi
}

###############################################################################
# Member safety (pre-extraction; deliberately independent of the
# extracting tar implementation's own protections)
###############################################################################

# verify_member_safety
# Rejects any archive member that is absolute, contains a ".." path
# component, sits outside the single expected $PKG_NAME/ root, or is
# anything other than a regular file or directory (symlink, hardlink,
# character/block device, FIFO, socket). Uses Python's stdlib tarfile
# module to read each member's exact type flag directly from the tar
# header -- not GNU tar's own verbose-listing text format, which is not a
# documented, version-stable interface and is exactly the kind of "trust
# the extracting tar implementation" this check must not depend on.
verify_member_safety() {
    if ! python3 - "$SNAPSHOT_ARCHIVE" "$PKG_NAME" <<'PYEOF'
import sys
import tarfile

archive_path, pkg_name = sys.argv[1], sys.argv[2]


def fail(msg):
    print(f"verify-package: {msg}", file=sys.stderr)
    sys.exit(1)


try:
    tf = tarfile.open(archive_path, mode="r:gz")
except Exception as exc:
    fail(f"cannot open archive: {exc}")

roots = set()
for member in tf.getmembers():
    name = member.name

    if name.startswith("/"):
        fail(f"absolute member path: {name}")

    parts = name.split("/")
    if ".." in parts:
        fail(f"path traversal in member: {name}")

    if not (name == pkg_name or name.startswith(pkg_name + "/")):
        fail(f"member outside {pkg_name}/: {name}")

    if not (member.isreg() or member.isdir()):
        fail(f"disallowed member type for: {name}")

    roots.add(parts[0])

if len(roots) > 1:
    fail(f"multiple top-level roots in archive: {sorted(roots)}")

tf.close()
PYEOF
    then
        log_error "Archive failed member-safety validation."
        exit 1
    fi
}

###############################################################################
# Extraction (only after every safety check above has passed)
###############################################################################

extract_snapshot() {
    EXTRACT_DIR="$SNAPSHOT_DIR/extract"
    mkdir -p -- "$EXTRACT_DIR"
    tar -xzf "$SNAPSHOT_ARCHIVE" -C "$EXTRACT_DIR"
}

###############################################################################
# Required paths
###############################################################################

verify_required_paths() {
    local rel
    for rel in "${REQUIRED_ARCHIVE_PATHS[@]}"; do
        if [[ ! -e "$EXTRACT_DIR/$PKG_NAME/$rel" ]]; then
            log_error "Required path missing from archive: $rel"
            exit 1
        fi
    done
}

###############################################################################
# Internal manifest verification -- independent of the external checksum,
# so a compromised archive host that also re-signs a tampered .sha256 is
# still caught here.
###############################################################################

verify_integrity_manifest() {
    local manifest="$EXTRACT_DIR/$PKG_NAME/MAOPS-MANIFEST.tsv"

    if ! integrity_read_manifest "$manifest"; then
        log_error "$INTEGRITY_LAST_ERROR"
        exit 1
    fi

    local failed=0
    local i path abs_path actual_sha actual_mode

    for i in "${!INTEGRITY_MANIFEST_PATHS[@]}"; do
        path="${INTEGRITY_MANIFEST_PATHS[$i]}"
        abs_path="$EXTRACT_DIR/$PKG_NAME/$path"

        if [[ ! -f "$abs_path" ]]; then
            log_error "Manifest entry missing from archive: $path"
            failed=1
            continue
        fi

        actual_sha="$(integrity_sha256_file "$abs_path")"
        if [[ "$actual_sha" != "${INTEGRITY_MANIFEST_SHAS[$i]}" ]]; then
            log_error "Content mismatch for manifest entry: $path"
            failed=1
        fi

        actual_mode="$(stat -c '%a' -- "$abs_path")"
        if [[ "$actual_mode" != "${INTEGRITY_MANIFEST_MODES[$i]#0}" ]]; then
            log_error "Mode mismatch for manifest entry: $path (expected ${INTEGRITY_MANIFEST_MODES[$i]}, found $actual_mode)"
            failed=1
        fi
    done

    local -A manifest_path_set=()
    for path in "${INTEGRITY_MANIFEST_PATHS[@]}"; do
        manifest_path_set[$path]=1
    done

    local extra
    while IFS= read -r extra; do
        if [[ -z "${manifest_path_set[$extra]:-}" ]]; then
            log_error "Extra distributed file not listed in manifest: $extra"
            failed=1
        fi
    done < <(cd "$EXTRACT_DIR/$PKG_NAME" && find . -type f -not -name MAOPS-MANIFEST.tsv -printf '%P\n')

    if ((failed)); then
        exit 1
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    require_command tar
    require_command sha256sum
    require_command python3

    local archive="${ARCHIVE_ARG:-$DIST_DIR/$PKG_NAME.tar.gz}"

    if [[ ! -f "$archive" ]]; then
        log_error "Archive not found: $archive"
        exit 1
    fi

    snapshot_archive "$archive"
    verify_checksum
    verify_member_safety
    extract_snapshot
    verify_required_paths
    verify_integrity_manifest

    log_success "Package verified: $archive"
}

parse_args "$@"
main
