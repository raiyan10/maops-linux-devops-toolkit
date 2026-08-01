#!/usr/bin/env bats
#
# Tests for scripts/system/system-info.sh, os-details.sh, and
# hostname-report.sh. Uses stub_shadow_path_except / stub_command
# (tests/test-helper.bash) for deterministic dependency-handling coverage.

setup() {
    load '../test-helper'
}

# --- system-info.sh ----------------------------------------------------

@test "system-info.sh exits 0 and reports the expected fields" {
    run "$REPO_ROOT/scripts/system/system-info.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hostname"* ]]
    [[ "$output" == *"Kernel"* ]]
    [[ "$output" == *"OS"* ]]
    [[ "$output" == *"User"* ]]
    [[ "$output" == *"Uptime"* ]]
}

@test "system-info.sh ignores unrecognized trailing arguments" {
    run "$REPO_ROOT/scripts/system/system-info.sh" --bogus
    [ "$status" -eq 0 ]
}

@test "system-info.sh reports whatever hostname/uptime stubs return" {
    stub_bin_init
    stub_command hostname <<'STUB'
echo "stub-hostname"
STUB
    stub_command uptime <<'STUB'
echo "up 42 minutes"
STUB

    run "$REPO_ROOT/scripts/system/system-info.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"stub-hostname"* ]]
}

@test "system-info.sh continues (degraded, not crashed) when hostname is entirely unavailable" {
    stub_shadow_path_except hostname
    run "$REAL_BASH" "$REPO_ROOT/scripts/system/system-info.sh"
    # hostname's failure is inside a $(...) substitution embedded in an
    # echo argument, so `set -e` does not abort the script -- this test
    # documents that actual (degraded-output, exit 0) behavior rather
    # than assuming an idealized hard failure.
    [ "$status" -eq 0 ]
    [[ "$output" == *"Report completed."* ]]
}

# --- os-details.sh -------------------------------------------------------

@test "os-details.sh exits 1 with a Linux-only message on a non-Linux uname" {
    stub_bin_init
    stub_command uname <<'STUB'
case "$1" in
    -s) echo "Darwin" ;;
    -o) echo "Darwin" ;;
    -r) echo "23.0.0" ;;
    -m) echo "x86_64" ;;
esac
STUB

    run "$REPO_ROOT/scripts/system/os-details.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Linux"* ]]
}

@test "os-details.sh reports the General section on a real Linux host" {
    run "$REPO_ROOT/scripts/system/os-details.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Operating System"* ]]
    [[ "$output" == *"Kernel"* ]]
    [[ "$output" == *"Architecture"* ]]
}

@test "os-details.sh reports Distribution/Version when /etc/os-release exists" {
    [ -f /etc/os-release ] || skip "no /etc/os-release on this host"
    run "$REPO_ROOT/scripts/system/os-details.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Distribution"* ]]
}

@test "os-details.sh never invokes lsb_release or reads /etc/shadow" {
    ! grep -qE 'lsb_release|/etc/shadow' "$REPO_ROOT/scripts/system/os-details.sh"
}

# --- hostname-report.sh --------------------------------------------------

@test "hostname-report.sh falls back to Unavailable when hostname -f fails" {
    stub_bin_init
    stub_command hostname <<'STUB'
if [[ "${1:-}" == "-f" ]]; then
    exit 1
fi
echo "plain-host"
STUB

    run "$REPO_ROOT/scripts/system/hostname-report.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"plain-host"* ]]
    [[ "$output" == *"Unavailable"* ]]
}

@test "hostname-report.sh reports the real FQDN when hostname -f succeeds" {
    stub_bin_init
    stub_command hostname <<'STUB'
if [[ "${1:-}" == "-f" ]]; then
    echo "host.example.test"
    exit 0
fi
echo "plain-host"
STUB

    run "$REPO_ROOT/scripts/system/hostname-report.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"host.example.test"* ]]
    [[ "$output" != *"Unavailable"* ]]
}

@test "hostname-report.sh continues (degraded, not crashed) when hostname is entirely unavailable" {
    stub_shadow_path_except hostname
    run "$REAL_BASH" "$REPO_ROOT/scripts/system/hostname-report.sh"
    # Both hostname calls are embedded inside print_key_value arguments, so
    # `set -e` does not abort the script even for the plain (no ||
    # fallback) call -- documents actual behavior, not an idealized one.
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hostname report completed."* ]]
}
