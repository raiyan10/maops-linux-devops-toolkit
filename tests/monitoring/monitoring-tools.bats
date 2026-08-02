#!/usr/bin/env bats
#
# Tests for scripts/monitoring/memory-report.sh, cpu-monitor.sh, and
# load-average.sh. Each wraps a single external report command (free,
# lscpu, uptime) invoked directly as a simple command -- unlike
# system-info.sh's embedded $(...) calls, a missing dependency here is the
# script's primary command and does trigger `set -e` (exit 127).

bats_require_minimum_version 1.5.0

setup() {
    load '../test-helper'
}

# --- memory-report.sh ----------------------------------------------------

@test "memory-report.sh exits 0 and reproduces free -h output verbatim" {
    stub_bin_init
    stub_command free <<'STUB'
printf 'Mem:   stub-mem-line\nSwap:  stub-swap-line\n'
STUB

    run "$REPO_ROOT/scripts/monitoring/memory-report.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"stub-mem-line"* ]]
    [[ "$output" == *"stub-swap-line"* ]]
}

@test "memory-report.sh invokes free with exactly the -h flag" {
    stub_bin_init
    stub_command free <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/free.calls"
STUB

    run "$REPO_ROOT/scripts/monitoring/memory-report.sh"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/free.calls")" = "-h" ]
}

@test "memory-report.sh fails when free is unavailable" {
    stub_shadow_path_except free
    run -127 "$REAL_BASH" "$REPO_ROOT/scripts/monitoring/memory-report.sh"
}

@test "memory-report.sh exits 1 on a non-Linux uname" {
    stub_bin_init
    stub_command uname <<'STUB'
echo "Darwin"
STUB

    run "$REPO_ROOT/scripts/monitoring/memory-report.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Linux"* ]]
}

@test "memory-report.sh --help exits 0" {
    run "$REPO_ROOT/scripts/monitoring/memory-report.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "memory-report.sh --version exits 0 and shows the current project version" {
    run "$REPO_ROOT/scripts/monitoring/memory-report.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "memory-report.sh rejects an unrecognized argument with exit 2" {
    run "$REPO_ROOT/scripts/monitoring/memory-report.sh" --bogus
    [ "$status" -eq 2 ]
}

# --- cpu-monitor.sh --------------------------------------------------------

@test "cpu-monitor.sh exits 0 and reproduces lscpu output verbatim" {
    stub_bin_init
    stub_command lscpu <<'STUB'
printf 'Architecture: stub-arch\n'
STUB

    run "$REPO_ROOT/scripts/monitoring/cpu-monitor.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"stub-arch"* ]]
}

@test "cpu-monitor.sh fails when lscpu is unavailable" {
    stub_shadow_path_except lscpu
    run -127 "$REAL_BASH" "$REPO_ROOT/scripts/monitoring/cpu-monitor.sh"
}

@test "cpu-monitor.sh --help exits 0" {
    run "$REPO_ROOT/scripts/monitoring/cpu-monitor.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "cpu-monitor.sh --version exits 0 and shows the current project version" {
    run "$REPO_ROOT/scripts/monitoring/cpu-monitor.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

# --- load-average.sh --------------------------------------------------------

@test "load-average.sh exits 0 and reproduces uptime output verbatim" {
    stub_bin_init
    stub_command uptime <<'STUB'
printf ' 11:16:00 up 1 day, stub load average: 0.10, 0.05, 0.01\n'
STUB

    run "$REPO_ROOT/scripts/monitoring/load-average.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"stub load average"* ]]
}

@test "load-average.sh fails when uptime is unavailable" {
    stub_shadow_path_except uptime
    run -127 "$REAL_BASH" "$REPO_ROOT/scripts/monitoring/load-average.sh"
}

@test "load-average.sh --help exits 0" {
    run "$REPO_ROOT/scripts/monitoring/load-average.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "load-average.sh --version exits 0 and shows the current project version" {
    run "$REPO_ROOT/scripts/monitoring/load-average.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

# --- shared safety guarantee -----------------------------------------------

@test "monitoring scripts never invoke a mutating command" {
    ! grep -qE '\bkill\b|\brm\b|\bmount\b' \
        "$REPO_ROOT/scripts/monitoring/memory-report.sh" \
        "$REPO_ROOT/scripts/monitoring/cpu-monitor.sh" \
        "$REPO_ROOT/scripts/monitoring/load-average.sh"
}
