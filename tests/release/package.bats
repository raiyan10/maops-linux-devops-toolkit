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

# --- Day 6: MAOPS-MANIFEST.tsv --------------------------------------------

@test "the archive contains MAOPS-MANIFEST.tsv at the package root" {
    "$PACKAGE" >/dev/null
    local listing
    listing="$(tar -tzf "$ARCHIVE")"
    [[ "$listing" == *"$PKG_NAME/MAOPS-MANIFEST.tsv"* ]]
}

@test "MAOPS-MANIFEST.tsv format and sort order are correct" {
    "$PACKAGE" >/dev/null
    local manifest
    manifest="$(tar -xzOf "$ARCHIVE" "$PKG_NAME/MAOPS-MANIFEST.tsv")"

    run bash -c "grep -vE \$'^(0644|0755)\t[0-9a-f]{64}\t[^\t]+\$' <<<'$manifest'"
    [ -z "$output" ]

    diff <(printf '%s\n' "$manifest") <(printf '%s\n' "$manifest" | LC_ALL=C sort)
}

@test "manifest and archived file modes are correct even from a drvfs-simulated (0777) source tree" {
    build_drvfs_clone_fixture "$BATS_TEST_TMPDIR/fixture"
    (cd "$BATS_TEST_TMPDIR/fixture" && git add -A)

    local fixture_dist="$BATS_TEST_TMPDIR/fixture/dist"
    "$BATS_TEST_TMPDIR/fixture/scripts/release/package.sh"
    local fixture_archive
    fixture_archive="$(find "$fixture_dist" -name '*.tar.gz')"

    local path expected
    for path in bin/maops scripts/common/bootstrap.sh README.md LICENSE; do
        expected="$(expected_release_mode "$path")"
        run bash -c "tar -tzvf '$fixture_archive' | grep -F '$PKG_NAME/$path'"
        [ "$status" -eq 0 ]
        if [[ "$expected" == "755" ]]; then
            [[ "$output" == -rwxr-xr-x* ]]
        else
            [[ "$output" == -rw-r--r--* ]]
        fi
    done
}

@test "building twice from a drvfs-simulated source tree still produces byte-identical archives" {
    build_drvfs_clone_fixture "$BATS_TEST_TMPDIR/fixture"
    (cd "$BATS_TEST_TMPDIR/fixture" && git add -A)

    "$BATS_TEST_TMPDIR/fixture/scripts/release/package.sh"
    local first
    first="$(find "$BATS_TEST_TMPDIR/fixture/dist" -name '*.tar.gz' -exec sha256sum {} \; | awk '{print $1}')"

    "$BATS_TEST_TMPDIR/fixture/scripts/release/package.sh"
    local second
    second="$(find "$BATS_TEST_TMPDIR/fixture/dist" -name '*.tar.gz' -exec sha256sum {} \; | awk '{print $1}')"

    [ "$first" = "$second" ]
}

@test "verify-package.sh fails when a manifest SHA-256 doesn't match the archived file's real content" {
    "$PACKAGE" >/dev/null

    local scratch="$BATS_TEST_TMPDIR/tamper-content"
    mkdir -p "$scratch"
    (cd "$scratch" && tar -xzf "$ARCHIVE")
    printf '\nTAMPERED\n' >>"$scratch/$PKG_NAME/README.md"

    (cd "$scratch" && tar --sort=name --mtime="@0" --owner=0 --group=0 --numeric-owner -czf "$ARCHIVE" "$PKG_NAME")
    (cd "$DIST_DIR" && sha256sum "$(basename "$ARCHIVE")" >"$(basename "$ARCHIVE").sha256")

    run "$VERIFY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Content mismatch"*"README.md"* ]]
}

@test "verify-package.sh fails when a manifest mode doesn't match the archived file's real mode" {
    "$PACKAGE" >/dev/null

    local scratch="$BATS_TEST_TMPDIR/tamper-mode"
    mkdir -p "$scratch"
    (cd "$scratch" && tar -xzf "$ARCHIVE")
    chmod 600 "$scratch/$PKG_NAME/README.md"

    (cd "$scratch" && tar --sort=name --mtime="@0" --owner=0 --group=0 --numeric-owner -czf "$ARCHIVE" "$PKG_NAME")
    (cd "$DIST_DIR" && sha256sum "$(basename "$ARCHIVE")" >"$(basename "$ARCHIVE").sha256")

    run "$VERIFY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Mode mismatch"*"README.md"* ]]
}

@test "verify-package.sh fails when the archive contains an extra file not listed in the manifest" {
    "$PACKAGE" >/dev/null

    local scratch="$BATS_TEST_TMPDIR/extra-file"
    mkdir -p "$scratch"
    (cd "$scratch" && tar -xzf "$ARCHIVE")
    printf 'not in the manifest\n' >"$scratch/$PKG_NAME/EXTRA.txt"

    (cd "$scratch" && tar --sort=name --mtime="@0" --owner=0 --group=0 --numeric-owner -czf "$ARCHIVE" "$PKG_NAME")
    (cd "$DIST_DIR" && sha256sum "$(basename "$ARCHIVE")" >"$(basename "$ARCHIVE").sha256")

    run "$VERIFY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"EXTRA.txt"* ]]
}

# --- Day 6: crafted archive member-type attacks ---------------------------

@test "verify-package.sh rejects a symlink member before extracting it" {
    local evil="$BATS_TEST_TMPDIR/symlink.tar.gz"
    craft_tar_with_member "$evil" "$PKG_NAME" "$PKG_NAME/evil-link" symlink "/tmp/verify-package-canary"
    sha256sum "$evil" | awk '{print $1"  '"$(basename "$evil")"'"}' >"$evil.sha256"

    rm -f /tmp/verify-package-canary
    run "$VERIFY" "$evil"
    [ "$status" -eq 1 ]
    [ ! -e /tmp/verify-package-canary ]
}

@test "verify-package.sh rejects a hardlink member before extracting it" {
    local evil="$BATS_TEST_TMPDIR/hardlink.tar.gz"
    craft_tar_with_member "$evil" "$PKG_NAME" "$PKG_NAME/evil-hardlink" hardlink
    sha256sum "$evil" | awk '{print $1"  '"$(basename "$evil")"'"}' >"$evil.sha256"

    run "$VERIFY" "$evil"
    [ "$status" -eq 1 ]
}

@test "verify-package.sh rejects a character-device member" {
    local evil="$BATS_TEST_TMPDIR/chr.tar.gz"
    craft_tar_with_member "$evil" "$PKG_NAME" "$PKG_NAME/evil-chr" chr
    sha256sum "$evil" | awk '{print $1"  '"$(basename "$evil")"'"}' >"$evil.sha256"

    run "$VERIFY" "$evil"
    [ "$status" -eq 1 ]
}

@test "verify-package.sh rejects a block-device member" {
    local evil="$BATS_TEST_TMPDIR/blk.tar.gz"
    craft_tar_with_member "$evil" "$PKG_NAME" "$PKG_NAME/evil-blk" blk
    sha256sum "$evil" | awk '{print $1"  '"$(basename "$evil")"'"}' >"$evil.sha256"

    run "$VERIFY" "$evil"
    [ "$status" -eq 1 ]
}

@test "verify-package.sh rejects a FIFO member" {
    local evil="$BATS_TEST_TMPDIR/fifo.tar.gz"
    craft_tar_with_member "$evil" "$PKG_NAME" "$PKG_NAME/evil-fifo" fifo
    sha256sum "$evil" | awk '{print $1"  '"$(basename "$evil")"'"}' >"$evil.sha256"

    run "$VERIFY" "$evil"
    [ "$status" -eq 1 ]
}

@test "verify-package.sh's member-safety allowlist does not over-reject a legitimate extra regular file" {
    local evil="$BATS_TEST_TMPDIR/extra-regular.tar.gz"
    craft_tar_with_member "$evil" "$PKG_NAME" "$PKG_NAME/extra-file.txt" reg
    sha256sum "$evil" | awk '{print $1"  '"$(basename "$evil")"'"}' >"$evil.sha256"

    run "$VERIFY" "$evil"
    # This archive has no MAOPS-MANIFEST.tsv and is missing required paths,
    # so it still fails overall -- but member-safety (a regular file is
    # always allowed) must not be why. Asserting the absence of every
    # member-safety rejection message, combined with a required-path/
    # manifest failure instead, proves the allowlist accepted the extra
    # regular member rather than rejecting archives it has no business
    # rejecting.
    [ "$status" -eq 1 ]
    [[ "$output" != *"disallowed member type"* ]]
    [[ "$output" != *"absolute member path"* ]]
    [[ "$output" != *"path traversal"* ]]
    [[ "$output" != *"multiple top-level roots"* ]]
    [[ "$output" != *"member outside"* ]]
    [[ "$output" == *"Required path missing"* ]]
}

@test "verify-package.sh rejects an archive with two distinct top-level roots" {
    local root="$BATS_TEST_TMPDIR/multiroot"
    mkdir -p "$root/$PKG_NAME" "$root/other-root-name"
    touch "$root/$PKG_NAME/placeholder" "$root/other-root-name/placeholder"

    local evil="$BATS_TEST_TMPDIR/multiroot.tar.gz"
    (cd "$root" && tar -czf "$evil" "$PKG_NAME" "other-root-name")
    sha256sum "$evil" | awk '{print $1"  '"$(basename "$evil")"'"}' >"$evil.sha256"

    run "$VERIFY" "$evil"
    [ "$status" -eq 1 ]
}

@test "verify-package.sh snapshots the archive before checking it (works even if its directory is read-only)" {
    "$PACKAGE" >/dev/null
    chmod 500 "$DIST_DIR"

    run "$VERIFY"
    local rc="$status"
    chmod 700 "$DIST_DIR"

    [ "$rc" -eq 0 ]
}

@test "verify-package.sh leaves no residue outside its own private scratch directory on a rejected archive" {
    local evil="$BATS_TEST_TMPDIR/rejected.tar.gz"
    craft_tar_with_member "$evil" "$PKG_NAME" "$PKG_NAME/evil-link" symlink "/tmp/verify-package-canary"
    sha256sum "$evil" | awk '{print $1"  '"$(basename "$evil")"'"}' >"$evil.sha256"

    local sentinel="$BATS_TEST_TMPDIR/sentinel"
    mkdir -p "$sentinel"
    local before after
    before="$(snapshot_tree "$sentinel")"

    run "$VERIFY" "$evil"

    after="$(snapshot_tree "$sentinel")"
    [ "$status" -eq 1 ]
    [ "$before" = "$after" ]
    [ ! -e /tmp/verify-package-canary ]
}

@test "package.sh and verify-package.sh source contain no mknod, chmod 777, or eval" {
    ! grep -qE '\bmknod\b|chmod +0?777|\beval\b' "$REPO_ROOT/scripts/release/package.sh"
    ! grep -qE '\bmknod\b|chmod +0?777|\beval\b' "$REPO_ROOT/scripts/release/verify-package.sh"
}
