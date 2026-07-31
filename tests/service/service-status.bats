#!/usr/bin/env bats
#
# Tests for scripts/service/service-status.sh. systemctl and service(8) are
# stubbed via tests/test-helper.bash's stub_bin_init/stub_command so results
# never depend on the host's actual init system or the state of any real
# unit. The systemd/fallback branch itself is selected deterministically via
# MAOPS_SYSTEMD_RUNTIME_DIR, a documented read-only test seam in the script
# (see scripts/service/service-status.sh) — never systemd being PID 1.

setup() {
    load '../test-helper'
    SCRIPT="$REPO_ROOT/scripts/service/service-status.sh"
    stub_bin_init
}

use_systemd_branch() {
    export MAOPS_SYSTEMD_RUNTIME_DIR="$BATS_TEST_TMPDIR"
}

use_fallback_branch() {
    export MAOPS_SYSTEMD_RUNTIME_DIR="$BATS_TEST_TMPDIR/absent-systemd-dir"
}

# stub_systemctl_show LOAD_STATE ACTIVE_STATE SUB_STATE
stub_systemctl_show() {
    local load_state="$1" active_state="$2" sub_state="$3"
    stub_command systemctl <<STUB
printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/systemctl.calls"
if [[ "\$1" == "show" ]]; then
    printf 'LoadState=$load_state\nActiveState=$active_state\nSubState=$sub_state\n'
    exit 0
fi
exit 1
STUB
}

stub_systemctl_bus_failure() {
    stub_command systemctl <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/systemctl.calls"
printf 'Failed to connect to bus: No such file or directory\n' >&2
exit 1
STUB
}

# stub_service_status EXIT_CODE
stub_service_status() {
    local rc="$1"
    stub_command service <<STUB
printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/service.calls"
printf 'stub service status output\n'
exit $rc
STUB
}

@test "service-status.sh --help exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "service-status.sh --version exits 0 and shows the current project version" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "service status missing SERVICE exits 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"required"* ]]
}

@test "service status rejects an option-like SERVICE with exit 2" {
    use_systemd_branch
    stub_systemctl_show loaded active running

    run "$SCRIPT" -x
    [ "$status" -eq 2 ]
    [ ! -f "$BATS_TEST_TMPDIR/systemctl.calls" ]
}

@test "service status rejects an empty-string SERVICE with exit 2" {
    run "$SCRIPT" ""
    [ "$status" -eq 2 ]
}

@test "service status (systemd) reports an active unit with exit 0" {
    use_systemd_branch
    stub_systemctl_show loaded active running

    run "$SCRIPT" demo
    [ "$status" -eq 0 ]
    [[ "$output" == *"active"* ]]
}

@test "service status (systemd) reports an inactive unit with exit 1" {
    use_systemd_branch
    stub_systemctl_show loaded inactive dead

    run "$SCRIPT" demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"inactive"* ]]
}

@test "service status (systemd) reports an unknown unit with exit 1 and a distinct message" {
    use_systemd_branch
    stub_systemctl_show not-found inactive dead

    run "$SCRIPT" ghost
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown service"* ]]
}

@test "service status (systemd) surfaces a bus/connection failure instead of masking it as inactive" {
    use_systemd_branch
    stub_systemctl_bus_failure

    run "$SCRIPT" demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to connect to bus"* ]]
}

@test "service status falls back to service(8) when systemd is not running" {
    use_fallback_branch
    stub_service_status 0
    stub_systemctl_show loaded active running

    run "$SCRIPT" demo
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/service.calls" ]
    [ ! -f "$BATS_TEST_TMPDIR/systemctl.calls" ]
}

@test "service status fallback reports a running service with exit 0" {
    use_fallback_branch
    stub_service_status 0

    run "$SCRIPT" demo
    [ "$status" -eq 0 ]
    [[ "$output" == *"running"* ]]
}

@test "service status fallback reports a stopped service with exit 1" {
    use_fallback_branch
    stub_service_status 3

    run "$SCRIPT" demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"not running"* ]]
}

@test "service status fallback reports an unknown service with exit 1" {
    use_fallback_branch
    stub_service_status 4

    run "$SCRIPT" ghost
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown service"* ]]
}

@test "service status fallback surfaces an unexpected exit code as a failure, not as stopped" {
    use_fallback_branch
    stub_service_status 1

    run "$SCRIPT" demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed"* ]] || [[ "$output" == *"lookup failed"* ]]
}

@test "service status never invokes start, stop, restart, enable, or disable" {
    use_systemd_branch
    stub_systemctl_show loaded active running

    run "$SCRIPT" demo
    [ "$status" -eq 0 ]
    ! grep -qE '\b(start|stop|restart|reload|enable|disable|mask)\b' "$BATS_TEST_TMPDIR/systemctl.calls"
}

@test "service status source contains no eval and no re-parsed shell string" {
    ! grep -qE '\beval\b|bash -c|sh -c' "$REPO_ROOT/scripts/service/service-status.sh"
}

@test "service status is not tricked by shell metacharacters in SERVICE" {
    use_systemd_branch
    stub_systemctl_show loaded active running
    local marker="$BATS_TEST_TMPDIR/marker"

    run "$SCRIPT" "demo;touch $marker;"
    [ ! -e "$marker" ]
}
