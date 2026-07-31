#!/usr/bin/env bash
#
# Shared Bats test setup for the MAOps Linux DevOps Toolkit test suite.
# Loaded from each .bats file via: load '../test-helper' (path relative to
# the .bats file's own directory, per bats' `load` resolution rules).

# Resolve the repository root robustly from this file's own location,
# regardless of which .bats file (or directory depth) sources it.
TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT
REPO_ROOT="$(cd "$TEST_HELPER_DIR/.." && pwd)"

export MAOPS_BIN="$REPO_ROOT/bin/maops"
