#!/usr/bin/env bats
#
# Tests for scripts/install/install.sh and scripts/install/uninstall.sh.
# Every install/uninstall in this file targets a throwaway PREFIX under
# $BATS_TEST_TMPDIR (never the real ~/.local) and a throwaway HOME (never
# the real ~/.config), so nothing here can touch the host running the
# suite. No test uses sudo or depends on the real HOME/systemd state.

setup() {
    load '../test-helper'
    INSTALL="$REPO_ROOT/scripts/install/install.sh"
    UNINSTALL="$REPO_ROOT/scripts/install/uninstall.sh"
    PREFIX="$BATS_TEST_TMPDIR/prefix"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    unset XDG_CONFIG_HOME MAOPS_CONFIG_FILE
}

teardown() {
    # The archive-mode install tests below build a real package via
    # package.sh, which always writes into the repo's actual (gitignored)
    # dist/ -- the same shared directory tests/release/package.bats also
    # uses. Clean up here so a leftover archive never lingers in the working
    # tree after this file runs, mirroring package.bats's own discipline.
    rm -rf "$REPO_ROOT/dist"
}

@test "install.sh --help exits 0" {
    run "$INSTALL" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "uninstall.sh --help exits 0" {
    run "$UNINSTALL" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "fresh install creates the expected layout" {
    run "$INSTALL" --prefix "$PREFIX"
    [ "$status" -eq 0 ]

    [ -L "$PREFIX/bin/maops" ]
    [ -f "$PREFIX/lib/maops/bin/maops" ]
    [ -d "$PREFIX/lib/maops/scripts" ]
    [ -f "$PREFIX/lib/maops/LICENSE" ]
    [ -f "$PREFIX/lib/maops/CHANGELOG.md" ]
    [ -f "$PREFIX/lib/maops/.install-manifest" ]
}

@test "the installed launcher is a relative symlink to ../lib/maops/bin/maops" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null

    local target
    target="$(readlink "$PREFIX/bin/maops")"
    [ "$target" = "../lib/maops/bin/maops" ]
}

@test "the installed CLI reports the current project version" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null

    run "$PREFIX/bin/maops" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "the installed CLI works when invoked from an unrelated working directory" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null

    run bash -c 'cd /tmp && "$1/bin/maops" --version' -- "$PREFIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "the installed CLI runs doctor successfully" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null

    run "$PREFIX/bin/maops" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"execution_mode"*"installed"* ]]
}

@test "the manifest header records version, prefix, and a files section" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null

    local manifest="$PREFIX/lib/maops/.install-manifest"
    grep -q "^MAOPS_INSTALL_VERSION=$PROJECT_VERSION$" "$manifest"
    grep -q "^MAOPS_INSTALL_PREFIX=$PREFIX$" "$manifest"
    grep -q '^--- files ---$' "$manifest"
    grep -q "^$PREFIX/lib/maops/bin/maops$" "$manifest"
}

@test "install stages the runtime tree under PREFIX/lib, never under /tmp directly" {
    grep -q 'mktemp -d -- "$PREFIX/lib' "$REPO_ROOT/scripts/install/install.sh"
}

@test "empty prefix is rejected with exit 2" {
    run "$INSTALL" --prefix ""
    [ "$status" -eq 2 ]
    [ ! -e "$PREFIX" ]
}

@test "the filesystem root is rejected as a prefix with exit 2" {
    run "$INSTALL" --prefix /
    [ "$status" -eq 2 ]
}

@test "reinstalling without --force fails with exit 1 and leaves the install untouched" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null
    local before
    before="$(cat "$PREFIX/lib/maops/.install-manifest")"

    run "$INSTALL" --prefix "$PREFIX"
    [ "$status" -eq 1 ]
    [ "$(cat "$PREFIX/lib/maops/.install-manifest")" = "$before" ]
}

@test "an unrelated regular file at PREFIX/bin/maops is never overwritten, even with --force" {
    mkdir -p "$PREFIX/bin"
    printf 'not maops\n' >"$PREFIX/bin/maops"

    run "$INSTALL" --prefix "$PREFIX"
    [ "$status" -eq 1 ]
    [ "$(cat "$PREFIX/bin/maops")" = "not maops" ]

    run "$INSTALL" --prefix "$PREFIX" --force
    [ "$status" -eq 1 ]
    [ "$(cat "$PREFIX/bin/maops")" = "not maops" ]
}

@test "upgrading with --force preserves a pre-existing configuration file" {
    mkdir -p "$HOME/.config/maops"
    printf 'output_format=json\n' >"$HOME/.config/maops/config"

    "$INSTALL" --prefix "$PREFIX" >/dev/null
    run "$INSTALL" --prefix "$PREFIX" --force
    [ "$status" -eq 0 ]

    [ "$(cat "$HOME/.config/maops/config")" = "output_format=json" ]
}

@test "a prefix containing spaces is handled safely" {
    local spacey="$BATS_TEST_TMPDIR/pre fix"

    run "$INSTALL" --prefix "$spacey"
    [ "$status" -eq 0 ]
    [ -L "$spacey/bin/maops" ]

    run "$spacey/bin/maops" --version
    [ "$status" -eq 0 ]
}

@test "shell metacharacters in a prefix are never executed" {
    local marker="$BATS_TEST_TMPDIR/marker"
    local evil="$BATS_TEST_TMPDIR/evil-\$(touch $marker)"

    run "$INSTALL" --prefix "$evil"
    [ ! -e "$marker" ]
}

@test "install.sh and uninstall.sh never invoke sudo" {
    ! grep -v '^[[:space:]]*#' "$REPO_ROOT/scripts/install/install.sh" | grep -qw sudo
    ! grep -v '^[[:space:]]*#' "$REPO_ROOT/scripts/install/uninstall.sh" | grep -qw sudo
}

# --- uninstall ------------------------------------------------------------

@test "uninstall without --yes in a non-interactive context requires --yes (exit 2)" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null

    run bash -c '"$1" --prefix "$2" </dev/null' -- "$UNINSTALL" "$PREFIX"
    [ "$status" -eq 2 ]
    [ -f "$PREFIX/lib/maops/.install-manifest" ]
}

@test "uninstall --yes removes the manifest-listed files and the launcher" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null

    run "$UNINSTALL" --prefix "$PREFIX" --yes
    [ "$status" -eq 0 ]
    [ ! -e "$PREFIX/lib/maops" ]
    [ ! -e "$PREFIX/bin/maops" ]
}

@test "uninstall preserves the configuration directory by default" {
    mkdir -p "$HOME/.config/maops"
    printf 'output_format=json\n' >"$HOME/.config/maops/config"
    "$INSTALL" --prefix "$PREFIX" >/dev/null

    run "$UNINSTALL" --prefix "$PREFIX" --yes
    [ "$status" -eq 0 ]
    [ -f "$HOME/.config/maops/config" ]
}

@test "uninstall --purge-config removes the configuration directory" {
    mkdir -p "$HOME/.config/maops"
    printf 'output_format=json\n' >"$HOME/.config/maops/config"
    "$INSTALL" --prefix "$PREFIX" >/dev/null

    run "$UNINSTALL" --prefix "$PREFIX" --yes --purge-config
    [ "$status" -eq 0 ]
    [ ! -d "$HOME/.config/maops" ]
}

@test "uninstalling twice is idempotent" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null
    "$UNINSTALL" --prefix "$PREFIX" --yes >/dev/null

    run "$UNINSTALL" --prefix "$PREFIX" --yes
    [ "$status" -eq 0 ]
}

@test "uninstall refuses to act on a directory with no install manifest" {
    mkdir -p "$PREFIX/lib/maops" "$PREFIX/important-other-stuff"
    touch "$PREFIX/important-other-stuff/keepme.txt"

    run "$UNINSTALL" --prefix "$PREFIX" --yes
    [ "$status" -eq 0 ]
    [ -f "$PREFIX/important-other-stuff/keepme.txt" ]
}

@test "uninstall refuses a manifest whose recorded prefix does not match --prefix" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null

    local other="$BATS_TEST_TMPDIR/other-prefix"
    mkdir -p "$other/lib"
    cp -a "$PREFIX/lib/maops" "$other/lib/maops"

    run "$UNINSTALL" --prefix "$other" --yes
    [ "$status" -eq 1 ]
    [ -d "$other/lib/maops" ]
}

@test "uninstall leaves an unrelated launcher file in place" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null
    rm -- "$PREFIX/bin/maops"
    printf 'not maops\n' >"$PREFIX/bin/maops"

    run "$UNINSTALL" --prefix "$PREFIX" --yes
    [ "$status" -eq 0 ]
    [ "$(cat "$PREFIX/bin/maops")" = "not maops" ]
}

@test "shell metacharacters in an uninstall prefix are never executed" {
    local marker="$BATS_TEST_TMPDIR/marker-uninstall"
    local evil="$BATS_TEST_TMPDIR/evil2-\$(touch $marker)"

    run "$UNINSTALL" --prefix "$evil" --yes
    [ ! -e "$marker" ]
}

# --- Day 6: integrity manifest -------------------------------------------

@test "fresh install creates a .integrity-manifest distinct from .install-manifest" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null

    [ -f "$PREFIX/lib/maops/.integrity-manifest" ]
    [ -f "$PREFIX/lib/maops/.install-manifest" ]
    ! diff -q "$PREFIX/lib/maops/.integrity-manifest" "$PREFIX/lib/maops/.install-manifest" >/dev/null
}

@test ".integrity-manifest lines match MODE<TAB>SHA256<TAB>PATH and are LC_ALL=C sorted" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null
    local manifest="$PREFIX/lib/maops/.integrity-manifest"

    run bash -c "grep -vE \$'^(0644|0755)\t[0-9a-f]{64}\t[^\t]+\$' '$manifest'"
    [ -z "$output" ]

    diff <(cat "$manifest") <(LC_ALL=C sort "$manifest")
}

@test ".integrity-manifest modes are correct even when the source tree observes 0777 (drvfs simulation)" {
    build_drvfs_clone_fixture "$BATS_TEST_TMPDIR/fixture"
    (cd "$BATS_TEST_TMPDIR/fixture" && git add -A)

    "$BATS_TEST_TMPDIR/fixture/scripts/install/install.sh" --prefix "$PREFIX" >/dev/null

    local manifest="$PREFIX/lib/maops/.integrity-manifest"
    local path
    for path in bin/maops scripts/common/bootstrap.sh README.md LICENSE; do
        run grep -P "^$(expected_release_mode "$path" | sed 's/^/0/')\t[0-9a-f]{64}\t${path//\//\\/}\$" "$manifest"
        [ "$status" -eq 0 ]
    done
}

@test "installed file modes are correct even when the source tree observes 0777 (drvfs simulation)" {
    build_drvfs_clone_fixture "$BATS_TEST_TMPDIR/fixture"
    (cd "$BATS_TEST_TMPDIR/fixture" && git add -A)

    "$BATS_TEST_TMPDIR/fixture/scripts/install/install.sh" --prefix "$PREFIX" >/dev/null

    local path expected actual
    for path in bin/maops scripts/common/bootstrap.sh README.md LICENSE; do
        expected="$(expected_release_mode "$path")"
        actual="$(stat -c '%a' "$PREFIX/lib/maops/$path")"
        [ "$actual" = "$expected" ]
    done
}

@test ".install-manifest and .integrity-manifest are both removed on uninstall" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null
    "$UNINSTALL" --prefix "$PREFIX" --yes >/dev/null

    [ ! -f "$PREFIX/lib/maops/.integrity-manifest" ]
    [ ! -f "$PREFIX/lib/maops/.install-manifest" ]
}

# --- Day 6: archive-mode install ------------------------------------------

@test "install.sh installs correctly from an extracted release archive (no .git present)" {
    local dist="$BATS_TEST_TMPDIR/dist"
    (cd "$REPO_ROOT" && "$REPO_ROOT/scripts/release/package.sh" >/dev/null)
    mkdir -p "$dist"
    cp "$REPO_ROOT/dist/"*.tar.gz "$dist/"

    local extract="$BATS_TEST_TMPDIR/extract"
    mkdir -p "$extract"
    tar -xzf "$dist"/*.tar.gz -C "$extract"
    local pkgdir
    pkgdir="$(find "$extract" -mindepth 1 -maxdepth 1 -type d)"
    [ ! -d "$pkgdir/.git" ]
    [ -f "$pkgdir/MAOPS-MANIFEST.tsv" ]

    run "$pkgdir/scripts/install/install.sh" --prefix "$PREFIX"
    [ "$status" -eq 0 ]

    run "$PREFIX/bin/maops" doctor
    [ "$status" -eq 0 ]

    diff <(LC_ALL=C sort "$PREFIX/lib/maops/.integrity-manifest") <(LC_ALL=C sort "$pkgdir/MAOPS-MANIFEST.tsv")
}

@test "archive-mode install refuses tampered content before installing anything" {
    local dist="$BATS_TEST_TMPDIR/dist"
    (cd "$REPO_ROOT" && "$REPO_ROOT/scripts/release/package.sh" >/dev/null)
    mkdir -p "$dist"
    cp "$REPO_ROOT/dist/"*.tar.gz "$dist/"

    local extract="$BATS_TEST_TMPDIR/extract"
    mkdir -p "$extract"
    tar -xzf "$dist"/*.tar.gz -C "$extract"
    local pkgdir
    pkgdir="$(find "$extract" -mindepth 1 -maxdepth 1 -type d)"
    printf 'TAMPERED\n' >>"$pkgdir/README.md"

    run "$pkgdir/scripts/install/install.sh" --prefix "$PREFIX"
    [ "$status" -eq 1 ]
    [ ! -e "$PREFIX/lib/maops" ]
}

# --- Day 6: uninstall LIB_DIR boundary hardening --------------------------

@test "a manifest entry pointing outside LIB_DIR but still under PREFIX is refused" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null
    mkdir -p "$PREFIX/share"
    printf 'keepme\n' >"$PREFIX/share/keepme.txt"
    printf '%s\n' "$PREFIX/share/keepme.txt" >>"$PREFIX/lib/maops/.install-manifest"

    run "$UNINSTALL" --prefix "$PREFIX" --yes
    [ "$status" -eq 1 ]
    [ -f "$PREFIX/share/keepme.txt" ]
    [ -d "$PREFIX/lib/maops" ]
}

@test "a manifest entry with a .. traversal segment is refused" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null
    printf '%s\n' "$PREFIX/lib/maops/../../../etc/passwd" >>"$PREFIX/lib/maops/.install-manifest"

    run "$UNINSTALL" --prefix "$PREFIX" --yes
    [ "$status" -eq 1 ]
    [ -d "$PREFIX/lib/maops" ]
}

@test "a duplicate manifest entry is rejected rather than silently double-processed" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null
    local dup
    dup="$(grep -m1 "^$PREFIX" "$PREFIX/lib/maops/.install-manifest")"
    printf '%s\n' "$dup" >>"$PREFIX/lib/maops/.install-manifest"

    local before after
    before="$(snapshot_tree "$PREFIX")"
    run "$UNINSTALL" --prefix "$PREFIX" --yes
    after="$(snapshot_tree "$PREFIX")"

    [ "$status" -eq 1 ]
    [ "$before" = "$after" ]
}

@test "an empty manifest line is treated as malformed, not silently skipped" {
    "$INSTALL" --prefix "$PREFIX" >/dev/null
    printf '\n' >>"$PREFIX/lib/maops/.install-manifest"

    run "$UNINSTALL" --prefix "$PREFIX" --yes
    [ "$status" -eq 1 ]
    [ -d "$PREFIX/lib/maops" ]
}

@test "a symlink launcher pointing into a different, unrelated install is left in place" {
    local prefix1="$BATS_TEST_TMPDIR/prefix1"
    local prefix2="$BATS_TEST_TMPDIR/prefix2"
    "$INSTALL" --prefix "$prefix1" >/dev/null
    "$INSTALL" --prefix "$prefix2" >/dev/null

    rm -- "$prefix1/bin/maops"
    ln -s -- "$prefix2/lib/maops/bin/maops" "$prefix1/bin/maops"

    run "$UNINSTALL" --prefix "$prefix1" --yes
    [ "$status" -eq 0 ]
    [ -L "$prefix1/bin/maops" ]
    [ "$(readlink "$prefix1/bin/maops")" = "$prefix2/lib/maops/bin/maops" ]
}
