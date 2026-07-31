#!/usr/bin/env bash

###############################################################################
#
# Script Name : release-files.sh
# Description : Single source of truth for which repository paths ship in
#               both the installed runtime tree (scripts/install/install.sh)
#               and the release tarball (scripts/release/package.sh), so the
#               two can never drift apart. Paths are relative to the
#               repository root. Data-only file — no functions, no side
#               effects when sourced.
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.4.0
#
###############################################################################

[[ -n "${MAOPS_RELEASE_FILES_LOADED:-}" ]] && return
readonly MAOPS_RELEASE_FILES_LOADED=1

# shellcheck disable=SC2034 # consumed by install.sh and package.sh
readonly RELEASE_FILE_LIST=(
    "bin/maops"
    "scripts"
    "templates/script-template.sh"
    "README.md"
    "CHANGELOG.md"
    "CONTRIBUTING.md"
    "LICENSE"
    "Makefile"
    ".gitattributes"
)
