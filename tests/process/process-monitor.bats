#!/usr/bin/env bats
#
# Tests for scripts/process/process-monitor.sh. `ps` is stubbed via
# tests/test-helper.bash's stub_bin_init/stub_command so row counts and sort
# order are deterministic and independent of the host's real process list.

setup() {
    load '../test-helper'
    SCRIPT="$REPO_ROOT/scripts/process/process-monitor.sh"
    stub_bin_init
}

# A `ps` stub that ignores its arguments except for recording them, and
# always emits one header line plus 50 fixed data rows (more than any
# LIMIT used below), so row-truncation and SIGPIPE behavior can be tested
# deterministically regardless of the host's real process count.
stub_ps_many_rows() {
    stub_command ps <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/ps.calls"
printf '  PID USER             %%CPU %%MEM     ELAPSED COMMAND\n'
for i in $(seq 1 50); do
    printf '%5d %-16s %4d.0  0.1       00:%02d bash\n' "$((1000 + i))" "user$i" "$i" "$((i % 60))"
done
STUB
}

@test "process-monitor.sh --help exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "process-monitor.sh --version exits 0 and shows the current project version" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "process top with no arguments defaults to LIMIT=10 and sort=cpu" {
    stub_ps_many_rows

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q -- "--sort=-pcpu" "$BATS_TEST_TMPDIR/ps.calls"

    local data_rows
    data_rows="$(printf '%s\n' "$output" | grep -c 'bash$' || true)"
    [ "$data_rows" -eq 10 ]
}

@test "process top forwards an explicit LIMIT" {
    stub_ps_many_rows

    run "$SCRIPT" 3
    [ "$status" -eq 0 ]

    local data_rows
    data_rows="$(printf '%s\n' "$output" | grep -c 'bash$' || true)"
    [ "$data_rows" -eq 3 ]
}

@test "process top cpu sort requests the --sort=-pcpu flag" {
    stub_ps_many_rows

    run "$SCRIPT" 5 cpu
    [ "$status" -eq 0 ]
    grep -q -- "--sort=-pcpu" "$BATS_TEST_TMPDIR/ps.calls"
    ! grep -q -- "--sort=-pmem" "$BATS_TEST_TMPDIR/ps.calls"
}

@test "process top memory sort requests the --sort=-pmem flag" {
    stub_ps_many_rows

    run "$SCRIPT" 5 memory
    [ "$status" -eq 0 ]
    grep -q -- "--sort=-pmem" "$BATS_TEST_TMPDIR/ps.calls"
    ! grep -q -- "--sort=-pcpu" "$BATS_TEST_TMPDIR/ps.calls"
}

@test "process top rejects LIMIT=0 with exit 2 and never invokes ps" {
    run "$SCRIPT" 0
    [ "$status" -eq 2 ]
    [ ! -f "$BATS_TEST_TMPDIR/ps.calls" ]
}

@test "process top rejects a negative LIMIT with a positive-integer message, not 'Unknown option'" {
    run "$SCRIPT" -1
    [ "$status" -eq 2 ]
    [[ "$output" == *"positive integer"* ]]
    [[ "$output" != *"Unknown option"* ]]
    [ ! -f "$BATS_TEST_TMPDIR/ps.calls" ]
}

@test "process top rejects a non-numeric LIMIT with exit 2" {
    run "$SCRIPT" abc
    [ "$status" -eq 2 ]
    [ ! -f "$BATS_TEST_TMPDIR/ps.calls" ]
}

@test "process top rejects an invalid SORT value and lists the allowed choices" {
    run "$SCRIPT" 10 disk
    [ "$status" -eq 2 ]
    [[ "$output" == *"cpu, memory"* ]]
    [ ! -f "$BATS_TEST_TMPDIR/ps.calls" ]
}

@test "process top does not SIGPIPE when ps produces more rows than LIMIT" {
    stub_ps_many_rows

    run "$SCRIPT" 1
    [ "$status" -eq 0 ]
    [ "$status" -ne 141 ]
}

@test "process top output includes the expected column headers" {
    stub_ps_many_rows

    run "$SCRIPT" 5
    [ "$status" -eq 0 ]
    [[ "$output" == *"PID"* ]]
    [[ "$output" == *"USER"* ]]
    [[ "$output" == *"COMMAND"* ]]
}

@test "process top never invokes kill, pkill, or renice" {
    ! grep -qE '\b(kill|pkill|renice|nice)\b' "$REPO_ROOT/scripts/process/process-monitor.sh"
}

@test "process top is not tricked by shell metacharacters in LIMIT" {
    local marker="$BATS_TEST_TMPDIR/marker"

    run "$SCRIPT" "5;touch $marker;"
    [ "$status" -eq 2 ]
    [ ! -e "$marker" ]
}
