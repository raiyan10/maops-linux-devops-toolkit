#!/usr/bin/env bats
#
# Tests for scripts/users/user-report.sh. getent/id/who are stubbed via
# tests/test-helper.bash's stub_bin_init/stub_command so results never
# depend on the host's actual accounts or logged-in sessions.

setup() {
    load '../test-helper'
    SCRIPT="$REPO_ROOT/scripts/users/user-report.sh"
    stub_bin_init
}

# A getent stub that answers `getent passwd -- TARGET`. Any target named
# "ghost" simulates a nonexistent user (rc 2, no output, matching real
# getent). Any other target gets a synthetic passwd entry that echoes the
# target back, plus a fake password-hash-shaped field 2 so tests can assert
# it is never printed.
stub_getent_passwd() {
    stub_command getent <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/getent.calls"
if [[ "$1" == "passwd" ]]; then
    target="$3"
    if [[ "$target" == "ghost" ]]; then
        exit 2
    fi
    printf '%s:$6$fakesalt$fakehash:1500:1500:Test User:/home/%s:/bin/bash\n' "$target" "$target"
    exit 0
fi
exit 1
STUB
}

stub_id_default() {
    stub_command id <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/id.calls"
case "$1" in
    -un)
        printf 'testuser\n'
        ;;
    -gn)
        printf 'testgroup\n'
        ;;
    -nG)
        printf '%s wheel docker\n' "$3"
        ;;
    *)
        exit 1
        ;;
esac
STUB
}

stub_who_no_session() {
    stub_command who <<'STUB'
true
STUB
}

stub_who_with_session() {
    local user="$1"
    stub_command who <<STUB
printf '%s\n' "$user pts/1 2026-07-30 21:31"
STUB
}

@test "user-report.sh --help exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "user-report.sh --version exits 0 and shows the current project version" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "user report with no USERNAME resolves the current effective user via id -un" {
    stub_getent_passwd
    stub_id_default
    stub_who_no_session

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"testuser"* ]]
    grep -q "passwd -- testuser" "$BATS_TEST_TMPDIR/getent.calls"
}

@test "user report with an explicit USERNAME overrides the default and does not call id -un" {
    stub_getent_passwd
    stub_id_default
    stub_who_no_session

    run "$SCRIPT" alice
    [ "$status" -eq 0 ]
    [[ "$output" == *"alice"* ]]
    grep -q "passwd -- alice" "$BATS_TEST_TMPDIR/getent.calls"
    ! grep -q '^-un$' "$BATS_TEST_TMPDIR/id.calls"
}

@test "user report shows UID, GID, home directory, and login shell from the passwd entry" {
    stub_getent_passwd
    stub_id_default
    stub_who_no_session

    run "$SCRIPT" alice
    [ "$status" -eq 0 ]
    [[ "$output" == *"1500"* ]]
    [[ "$output" == *"/home/alice"* ]]
    [[ "$output" == *"/bin/bash"* ]]
}

@test "user report lists group memberships from id -nG" {
    stub_getent_passwd
    stub_id_default
    stub_who_no_session

    run "$SCRIPT" alice
    [ "$status" -eq 0 ]
    [[ "$output" == *"wheel"* ]]
    [[ "$output" == *"docker"* ]]
}

@test "user report reflects no active session when who has no matching line" {
    stub_getent_passwd
    stub_id_default
    stub_who_no_session

    run "$SCRIPT" alice
    [ "$status" -eq 0 ]
    [[ "$output" == *"Logged-in sessions   : 0"* ]]
    [[ "$output" == *"Has active session   : no"* ]]
}

@test "user report reflects an active session when who has a matching line" {
    stub_getent_passwd
    stub_id_default
    stub_who_with_session alice

    run "$SCRIPT" alice
    [ "$status" -eq 0 ]
    [[ "$output" == *"Logged-in sessions   : 1"* ]]
    [[ "$output" == *"Has active session   : yes"* ]]
}

@test "user report exits 1 for a nonexistent user" {
    stub_getent_passwd
    stub_id_default
    stub_who_no_session

    run "$SCRIPT" ghost
    [ "$status" -eq 1 ]
    [[ "$output" == *"User not found: ghost"* ]]
}

@test "user report rejects an option-like USERNAME with exit 2" {
    run "$SCRIPT" --bad-user
    [ "$status" -eq 2 ]
    [[ "$output" == *"USERNAME"* ]]
    [ ! -f "$BATS_TEST_TMPDIR/getent.calls" ]
}

@test "user report never prints the passwd password/hash field" {
    stub_getent_passwd
    stub_id_default
    stub_who_no_session

    run "$SCRIPT" alice
    [ "$status" -eq 0 ]
    [[ "$output" != *'$6$fakesalt$fakehash'* ]]
}

@test "user report is not tricked by shell metacharacters in USERNAME" {
    stub_getent_passwd
    stub_id_default
    stub_who_no_session
    local marker="$BATS_TEST_TMPDIR/marker"

    run "$SCRIPT" "alice;touch $marker;"
    [ ! -e "$marker" ]
}

@test "user report is not tricked by command substitution syntax in USERNAME" {
    stub_getent_passwd
    stub_id_default
    stub_who_no_session
    local marker="$BATS_TEST_TMPDIR/marker"

    run "$SCRIPT" "\$(touch $marker)"
    [ ! -e "$marker" ]
}
