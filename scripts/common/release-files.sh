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
    "SECURITY.md"
    "SUPPORT.md"
    "docs/quickstart.md"
    "docs/install-from-release.md"
    "docs/compatibility.md"
    "docs/demo-workflow.md"
    "examples"
)

# Paths deliberately NOT included above, so `docs/engineering-reviews/` and
# `docs/images/` (dev-only engineering-review material and screenshots) are
# never distributed: the rest of docs/ (architecture.md, best-practices.md,
# troubleshooting.md, roadmap.md, portfolio-case-study.md) and tests/,
# dist/, .git/, .github/, .claude/ are simply never listed above. Because
# only paths explicitly listed here are ever staged (via
# integrity_copy_git_tracked's `git ls-files -s -z -- "$@"`), omission alone
# is a complete exclusion mechanism -- no separate exclude-list is needed.
