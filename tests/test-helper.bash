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
    hostname whoami sha256sum tar gzip touch
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

# --- drvfs (WSL) permission-symptom simulation ------------------------------
#
# Day 6 fixes a real bug: on WSL/drvfs, `stat` reports 0777 for every
# tracked file regardless of Git's actual index mode. build_drvfs_clone_fixture
# produces a self-contained copy of the repository -- a plain filesystem
# copy, not `git clone`, so any change currently staged-but-uncommitted in
# REPO_ROOT's index/working tree is carried over exactly, and .git is
# copied wholesale so `git ls-files -s` inside the fixture reports the
# same index modes as the real repo -- with every path forced to 0777.
# This reproduces the *observed symptom* deterministically on any host,
# including a normal ext4 CI runner, without needing an actual drvfs mount.
#
# Callers follow this with `(cd "$dest" && git add -A)`. That call is a
# no-op for the mode question specifically because the fixture's own
# `core.fileMode` is force-set to false below -- never inherited from
# `.git` (copied above), since the *host* repo's `core.fileMode` is
# environment-dependent (e.g. false on a WSL/drvfs checkout, but the real
# git default of true on a fresh CI checkout on ext4). Without pinning it
# here, `git add -A` on a true-default host would re-stage the forced
# `chmod -R 0777` as a genuine 100755 index mode on every file, corrupting
# the very index `git ls-files -s` reads and defeating the fixture's
# purpose. Pinning it explicitly is what makes the *observed symptom*
# (stat lies, index stays correct) reproduce deterministically on any
# host, including a normal ext4 CI runner, without needing an actual
# drvfs mount. The `git add -A` call is kept as defensive/correct usage,
# not redundant boilerplate: it *does* matter the moment a
# fixture-consuming test starts editing tracked file *content* inside the
# fixture (see the "reports a modified tracked release file" tests)
# rather than only mode, since integrity-check.sh's source-tree mode
# compares the working tree against the index via `git diff`, and any
# genuinely new/staged content needs `git add` to be reflected there.
build_drvfs_clone_fixture() {
    local dest="$1"
    mkdir -p -- "$dest"
    cp -a -- "$REPO_ROOT/." "$dest/"
    rm -rf -- "$dest/dist"
    git -C "$dest" config core.fileMode false
    find "$dest" -exec chmod 0777 {} +
}

# expected_release_mode PATH
# Oracle mirroring the Makefile's own check-executable rule: tracked *.sh
# files and bin/maops are 755, everything else distributed is 644.
expected_release_mode() {
    case "$1" in
        *.sh | bin/maops) printf '755' ;;
        *) printf '644' ;;
    esac
}

# --- JSON assertion helpers (DRY wrapper around the python3 -m json.tool /
# json.load pattern already used inline across doctor.bats and maops.bats)

assert_valid_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

# json_field JSON PYEXPR
# PYEXPR is a Python expression with `doc` bound to the parsed JSON.
json_field() {
    printf '%s' "$1" | python3 -c "
import json, sys
doc = json.load(sys.stdin)
print($2)
"
}

# --- MAOPS-MANIFEST.tsv fixture helpers -------------------------------------

# write_manifest_line MODE ABS_FILE REL_PATH
write_manifest_line() {
    local mode="$1" abs_file="$2" rel_path="$3"
    printf '%s\t%s\t%s\n' "$mode" "$(sha256sum -- "$abs_file" | awk '{print $1}')" "$rel_path"
}

# Canned malformed MAOPS-MANIFEST.tsv lines for parametrized tests: bad
# field count, non-hex sha, wrong-length sha, non-{0644,0755} mode, a path
# with a ".." segment, an absolute path.
MALFORMED_MANIFEST_LINES=(
    $'0644\tnotahash\tfoo.txt'
    $'0644\tdeadbeef\tfoo.txt'
    $'0999\t0000000000000000000000000000000000000000000000000000000000000000\tfoo.txt'
    $'0644\t0000000000000000000000000000000000000000000000000000000000000000\t../foo.txt'
    $'0644\t0000000000000000000000000000000000000000000000000000000000000000\t/etc/passwd'
    $'0644\t0000000000000000000000000000000000000000000000000000000000000000'
)

# snapshot_tree DIR
# A fingerprint of every path/size/mtime/mode under DIR, used to prove an
# operation made no unexpected filesystem changes -- including a change
# that only touches permission bits (content and mtime unchanged), which a
# size/mtime-only fingerprint would miss entirely.
snapshot_tree() {
    find "$1" -printf '%p %s %T@ %m\n' 2>/dev/null | LC_ALL=C sort
}

# --- Crafted-archive helper for verify-package.sh attack fixtures ----------

# craft_tar_with_member ARCHIVE PKG_NAME MEMBER_NAME TYPE [LINK_TARGET]
# Builds ARCHIVE (a .tar.gz) containing a minimal valid PKG_NAME/ layout
# (a directory entry plus PKG_NAME/README.md) and one additional member of
# the given TYPE: "symlink" | "hardlink" | "chr" | "blk" | "fifo" | "reg".
# Uses Python's stdlib tarfile module so each member's exact type flag is
# under direct, unambiguous control -- the same module verify-package.sh
# itself uses to inspect archives, so these fixtures exercise real member
# semantics rather than a hand-rolled tar byte layout.
craft_tar_with_member() {
    local archive="$1" pkg_name="$2" member_name="$3" type="$4" link_target="${5:-}"
    python3 - "$archive" "$pkg_name" "$member_name" "$type" "$link_target" <<'PYEOF'
import sys
import io
import tarfile

archive, pkg_name, member_name, mtype, link_target = sys.argv[1:6]

with tarfile.open(archive, "w:gz") as tf:
    root = tarfile.TarInfo(name=f"{pkg_name}/")
    root.type = tarfile.DIRTYPE
    root.mode = 0o755
    tf.addfile(root)

    readme_data = b"hello\n"
    readme = tarfile.TarInfo(name=f"{pkg_name}/README.md")
    readme.size = len(readme_data)
    readme.mode = 0o644
    tf.addfile(readme, io.BytesIO(readme_data))

    extra = tarfile.TarInfo(name=member_name)
    if mtype == "symlink":
        extra.type = tarfile.SYMTYPE
        extra.linkname = link_target or "/etc/passwd"
        tf.addfile(extra)
    elif mtype == "hardlink":
        extra.type = tarfile.LNKTYPE
        extra.linkname = link_target or f"{pkg_name}/README.md"
        tf.addfile(extra)
    elif mtype == "chr":
        extra.type = tarfile.CHRTYPE
        extra.devmajor = 1
        extra.devminor = 5
        tf.addfile(extra)
    elif mtype == "blk":
        extra.type = tarfile.BLKTYPE
        extra.devmajor = 1
        extra.devminor = 5
        tf.addfile(extra)
    elif mtype == "fifo":
        extra.type = tarfile.FIFOTYPE
        tf.addfile(extra)
    elif mtype == "reg":
        extra_data = b"extra\n"
        extra.size = len(extra_data)
        extra.mode = 0o644
        tf.addfile(extra, io.BytesIO(extra_data))
    else:
        raise SystemExit(f"craft_tar_with_member: unknown type {mtype!r}")
PYEOF
}
