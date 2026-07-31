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

# Read once from the single source of truth so version-string assertions
# never need hand-editing on the next version bump.
# shellcheck source=scripts/common/config.sh
source "$REPO_ROOT/scripts/common/config.sh"
export PROJECT_VERSION

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

# --- Configuration-system isolation ------------------------------------------
#
# Config/doctor tests must never read or write the real user's ~/.config.
# isolate_config_env points HOME and XDG_CONFIG_HOME at fresh directories
# under $BATS_TEST_TMPDIR and clears every MAOPS_* override, so each test
# starts from a known, empty configuration state.

isolate_config_env() {
    export HOME="$BATS_TEST_TMPDIR/home"
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg-config"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME"
    unset MAOPS_CONFIG_FILE MAOPS_OUTPUT_FORMAT MAOPS_PROCESS_LIMIT MAOPS_PING_COUNT MAOPS_NETWORK_TIMEOUT
}

# --- Doctor "missing command" shadow PATH -----------------------------------
#
# doctor.sh reports a command as present/missing via `command -v`, so
# testing "missing" deterministically requires a PATH that genuinely lacks
# the command being tested — not just a stub prepended ahead of the real
# PATH (stub_bin_init above), since the real binary would still be found
# further down PATH. stub_shadow_path_except rebuilds PATH from scratch as
# a directory of thin passthrough wrappers for every command doctor.sh (and
# its sourced library chain) might invoke, omitting only the command(s)
# named as arguments.
#
# Wrapper shebangs use the real bash's own absolute path, never
# `/usr/bin/env bash`: with PATH fully replaced, an env-based shebang would
# have to resolve "bash" via the very same restricted PATH, and if that
# lookup found this shadow directory's own "bash" wrapper (also shebanged
# with `/usr/bin/env bash`), it would recurse into itself indefinitely.
# `bash` is deliberately included in the roster like any other command (so
# a "healthy" shadow reports it present) — the absolute-path shebang makes
# this safe.
DOCTOR_SHADOW_ROSTER=(
    bash awk find sort ps getent ip ping timeout df free lscpu uptime
    systemctl service git make shellcheck bats python3
    uname date dirname basename cat mkdir mktemp mv tr grep sed head tail wc stat rm cp chmod
)

stub_shadow_path_except() {
    local omit=("$@")
    REAL_BASH="$(command -v bash)"
    SHADOW_DIR="$BATS_TEST_TMPDIR/shadow"
    mkdir -p "$SHADOW_DIR"

    local cmd real skip o
    for cmd in "${DOCTOR_SHADOW_ROSTER[@]}"; do
        skip=0
        for o in "${omit[@]}"; do
            [[ "$cmd" == "$o" ]] && skip=1
        done
        ((skip)) && continue

        real="$(command -v "$cmd" 2>/dev/null)" || continue
        printf '#!%s\nexec "%s" "$@"\n' "$REAL_BASH" "$real" >"$SHADOW_DIR/$cmd"
        chmod 755 "$SHADOW_DIR/$cmd"
    done

    PATH="$SHADOW_DIR"
}
