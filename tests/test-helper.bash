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

# --- Deterministic PATH-based command stubs --------------------------------
#
# Some Day 4 scripts (user-report.sh, process-monitor.sh, service-status.sh)
# wrap host commands (getent/id/who/ps/systemctl/service) whose real output
# varies by host and session state. stub_bin_init/stub_command let a test
# fake one or more of these commands deterministically by prepending a
# generated, per-test stub directory to $PATH.
#
# Stubs are generated fresh into $BATS_TEST_TMPDIR rather than checked into
# the repo as static files: a checked-in stub must be named exactly
# `systemctl`/`ps`/etc (no .sh suffix) to be found via PATH lookup, which
# would put it outside `make check-executable`'s *.sh/bin/maops glob and
# could silently reintroduce this project's known WSL/drvfs executable-mode
# gotcha. Bats gives each test its own subshell/env and removes
# $BATS_TEST_TMPDIR itself, so no teardown is required.

stub_bin_init() {
    STUB_DIR="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUB_DIR"
    PATH="$STUB_DIR:$PATH"
}

# stub_command NAME <<'STUB'
# ...stub body (reads $@ / $1 etc like a real command)...
# STUB
stub_command() {
    local name="$1"
    {
        printf '#!/usr/bin/env bash\n'
        cat
    } >"$STUB_DIR/$name"
    chmod 755 "$STUB_DIR/$name"
}
