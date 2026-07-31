#!/usr/bin/env bats
#
# Tests for scripts/release/package.sh and scripts/release/verify-package.sh.
# Every test builds into a real dist/ (the repo's actual, gitignored dist/
# directory), since package.sh always packages from REPO_ROOT — each test
# removes dist/ in its own setup/teardown so runs don't interfere with each
# other or leave artifacts behind. No test uses sudo or depends on the
# public internet.

setup() {
    load '../test-helper'
    PACKAGE="$REPO_ROOT/scripts/release/package.sh"
    VERIFY="$REPO_ROOT/scripts/release/verify-package.sh"
    DIST_DIR="$REPO_ROOT/dist"
    PKG_NAME="maops-linux-devops-toolkit-$PROJECT_VERSION"
    ARCHIVE="$DIST_DIR/$PKG_NAME.tar.gz"
    rm -rf "$DIST_DIR"
}

teardown() {
    rm -rf "$DIST_DIR"
    rm -f "$REPO_ROOT/scripts/network/.stray-untracked-test-file"
    rm -f /tmp/verify-package-canary
}

@test "package.sh --help exits 0" {
    run "$PACKAGE" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "verify-package.sh --help exits 0" {
    run "$VERIFY" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "package.sh produces an archive and a checksum file" {
    run "$PACKAGE"
    [ "$status" -eq 0 ]
    [ -f "$ARCHIVE" ]
    [ -f "$ARCHIVE.sha256" ]
}

@test "the package version matches PROJECT_VERSION" {
    "$PACKAGE" >/dev/null
    [ -f "$DIST_DIR/maops-linux-devops-toolkit-$PROJECT_VERSION.tar.gz" ]
}

@test "the archive contains exactly one top-level directory named after the package" {
    "$PACKAGE" >/dev/null

    local top_dirs
    top_dirs="$(tar -tzf "$ARCHIVE" | awk -F/ '{print $1}' | sort -u)"
    [ "$top_dirs" = "$PKG_NAME" ]
}

@test "required files exist inside the archive" {
    "$PACKAGE" >/dev/null

    local listing
    listing="$(tar -tzf "$ARCHIVE")"
    [[ "$listing" == *"$PKG_NAME/bin/maops"* ]]
    [[ "$listing" == *"$PKG_NAME/scripts/common/bootstrap.sh"* ]]
    [[ "$listing" == *"$PKG_NAME/scripts/config/config-manager.sh"* ]]
    [[ "$listing" == *"$PKG_NAME/scripts/diagnostics/doctor.sh"* ]]
    [[ "$listing" == *"$PKG_NAME/scripts/install/install.sh"* ]]
    [[ "$listing" == *"$PKG_NAME/templates/script-template.sh"* ]]
    [[ "$listing" == *"$PKG_NAME/LICENSE"* ]]
    [[ "$listing" == *"$PKG_NAME/Makefile"* ]]
    [[ "$listing" == *"$PKG_NAME/README.md"* ]]
    [[ "$listing" == *"$PKG_NAME/CHANGELOG.md"* ]]
}

@test "excluded directories are absent from the archive" {
    "$PACKAGE" >/dev/null

    local listing
    listing="$(tar -tzf "$ARCHIVE")"
    [[ "$listing" != *"/.git/"* ]]
    [[ "$listing" != *"/.github/"* ]]
    [[ "$listing" != *"/.claude/"* ]]
    [[ "$listing" != *"/dist/"* ]]
    [[ "$listing" != *"tests/"* ]]
    [[ "$listing" != *"docs/"* ]]
}

@test "no user configuration or secrets are packaged" {
    "$PACKAGE" >/dev/null

    local listing
    listing="$(tar -tzf "$ARCHIVE")"
    [[ "$listing" != *".config/maops"* ]]
    [[ "$listing" != *".env"* ]]
}

@test "a stray untracked file inside scripts/ is never packaged" {
    local canary="$REPO_ROOT/scripts/network/.stray-untracked-test-file"
    touch "$canary"

    "$PACKAGE" >/dev/null
    rm -f "$canary"

    local listing
    listing="$(tar -tzf "$ARCHIVE")"
    [[ "$listing" != *"stray-untracked-test-file"* ]]
}

@test "building twice from an unchanged tree produces byte-identical archives" {
    "$PACKAGE" >/dev/null
    local first
    first="$(sha256sum "$ARCHIVE" | awk '{print $1}')"

    "$PACKAGE" >/dev/null
    local second
    second="$(sha256sum "$ARCHIVE" | awk '{print $1}')"

    [ "$first" = "$second" ]
}

@test "verify-package.sh succeeds on a freshly built archive" {
    "$PACKAGE" >/dev/null
    run "$VERIFY"
    [ "$status" -eq 0 ]
}

@test "verify-package.sh fails on a checksum mismatch" {
    "$PACKAGE" >/dev/null
    printf 'deadbeef  %s\n' "$(basename "$ARCHIVE")" >"$ARCHIVE.sha256"

    run "$VERIFY"
    [ "$status" -eq 1 ]
}

@test "verify-package.sh fails on a tampered archive" {
    "$PACKAGE" >/dev/null
    printf 'X' | dd of="$ARCHIVE" bs=1 seek=200 count=1 conv=notrunc 2>/dev/null

    run "$VERIFY"
    [ "$status" -eq 1 ]
}

@test "verify-package.sh fails when a required path is missing from the archive" {
    "$PACKAGE" >/dev/null

    local scratch="$BATS_TEST_TMPDIR/rebuild"
    mkdir -p "$scratch/$PKG_NAME"
    (cd "$scratch" && tar -xzf "$ARCHIVE")
    rm -f "$scratch/$PKG_NAME/bin/maops"

    (cd "$scratch" && tar -czf "$ARCHIVE" "$PKG_NAME")
    (cd "$DIST_DIR" && sha256sum "$(basename "$ARCHIVE")" >"$(basename "$ARCHIVE").sha256")

    run "$VERIFY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bin/maops"* ]]
}

@test "verify-package.sh rejects an archive with a path-traversal member, without extracting it" {
    "$PACKAGE" >/dev/null

    local evil_root="$BATS_TEST_TMPDIR/evil"
    mkdir -p "$evil_root/$PKG_NAME" "$evil_root/evil"
    touch "$evil_root/$PKG_NAME/placeholder"
    touch "$evil_root/evil/pwned"

    local evil_archive="$BATS_TEST_TMPDIR/evil.tar.gz"
    (cd "$evil_root" && tar --transform "s|^evil/pwned|../../tmp/verify-package-canary|" \
        -czf "$evil_archive" "$PKG_NAME" evil/pwned)
    sha256sum "$evil_archive" | awk '{print $1"  '"$(basename "$evil_archive")"'"}' >"$evil_archive.sha256"

    rm -f /tmp/verify-package-canary
    run "$VERIFY" "$evil_archive"
    [ "$status" -eq 1 ]
    [ ! -e /tmp/verify-package-canary ]
    rm -f /tmp/verify-package-canary
}

@test "verify-package.sh rejects an archive whose top-level directory does not match the expected name" {
    "$PACKAGE" >/dev/null

    local mismatched_root="$BATS_TEST_TMPDIR/mismatched"
    mkdir -p "$mismatched_root/wrong-name-0.0.0"
    touch "$mismatched_root/wrong-name-0.0.0/placeholder"

    local mismatched_archive="$BATS_TEST_TMPDIR/mismatched.tar.gz"
    (cd "$mismatched_root" && tar -czf "$mismatched_archive" "wrong-name-0.0.0")
    sha256sum "$mismatched_archive" | awk '{print $1"  '"$(basename "$mismatched_archive")"'"}' >"$mismatched_archive.sha256"

    run "$VERIFY" "$mismatched_archive"
    [ "$status" -eq 1 ]
}

@test "verify-package.sh fails clearly when the archive does not exist" {
    run "$VERIFY" "$BATS_TEST_TMPDIR/nonexistent.tar.gz"
    [ "$status" -eq 1 ]
}

@test "package.sh requires a git checkout and never uses sudo" {
    ! grep -v '^[[:space:]]*#' "$REPO_ROOT/scripts/release/package.sh" | grep -qw sudo
    ! grep -v '^[[:space:]]*#' "$REPO_ROOT/scripts/release/verify-package.sh" | grep -qw sudo
}
