# Bash Best Practices

Concrete conventions used throughout this toolkit, with real examples from
the codebase. When in doubt, match what an existing script under `scripts/`
already does before inventing a new pattern.

---

## 1. Strict Mode

Every executable script starts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

- `-e` — exit immediately if a command fails, instead of continuing with a
  corrupted assumption about state.
- `-u` — treat an unset variable as an error, instead of silently expanding
  to an empty string (catches typos like `$TARGT` instead of `$TARGET`).
- `-o pipefail` — a pipeline's exit status is the *last non-zero* status of
  any stage, not just the final one. Without it, `false | true` exits `0`.

`#!/usr/bin/env bash` (rather than a hardcoded `#!/bin/bash`) is used because
it resolves `bash` through `$PATH`, which matters on systems where Bash isn't
at `/bin/bash` (some macOS setups, Nix, minimal containers).

Library files under `scripts/common/` are sourced, not executed, so they
intentionally omit `set -euo pipefail` — that setting is a property of the
process, and the *calling* script already owns it. A sourced library forcing
strict mode on its caller would be a surprising side effect.

---

## 2. Quoting

Every variable expansion that can contain a path, a filename, or user input
is quoted:

```bash
# scripts/filesystem/largest-files.sh
if [[ ! -d "$TARGET" ]]; then
    log_error "Directory not found: $TARGET"
    return 1
fi
```

Unquoted expansion is a routine source of both bugs and security issues, since
it triggers word-splitting and glob expansion:

```bash
# Wrong: breaks on paths with spaces, and globs on paths containing * or ?
if [[ ! -d $TARGET ]]; then
```

The one place this project intentionally skips quoting is a bare glob brace
expansion with no variable involved, e.g. `divider()`'s `{1..80}` in
`scripts/common/helpers.sh` — there is nothing to word-split because it isn't
a variable expansion.

---

## 3. Input Validation

Scripts that accept positional arguments validate them before use, not after
a downstream command fails on bad input:

```bash
# scripts/filesystem/largest-files.sh
TARGET="${1:-.}"
LIMIT="${2:-10}"

validate_inputs() {
    require_command find
    require_command sort
    require_command awk

    if [[ ! -d "$TARGET" ]]; then
        log_error "Directory not found: $TARGET"
        return 1
    fi

    if [[ ! "$LIMIT" =~ ^[1-9][0-9]*$ ]]; then
        log_error "Limit must be a positive integer: $LIMIT"
        return 1
    fi
}
```

Two things worth noting:

- The numeric check uses `^[1-9][0-9]*$`, not `-eq` or a bare `[[ $LIMIT
  -gt 0 ]]`, precisely because arithmetic comparisons on a non-numeric string
  throw a Bash syntax error before validation even gets a chance to log a
  clean message. Validate the *shape* of the string first with a regex, then
  use it arithmetically.
- Validation happens in its own function (`validate_inputs`) called from
  `main`, not inline — so `main()` reads as a sequence of steps rather than a
  mix of guards and logic.

---

## 4. Dependency Validation

`scripts/common/helpers.sh` provides two guard functions:

```bash
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    if ! command_exists "$1"; then
        echo "Required command not found: $1"
        exit 1
    fi
}

require_linux() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "This toolkit supports Linux only."
        exit 1
    fi
}
```

Scripts call `require_command` for every external binary they depend on
beyond core Bash builtins — `require_command find`, `require_command sort`,
`require_command awk`, `require_command df` — so a minimal or container image
missing one of them fails with an explicit, actionable message instead of a
raw `command not found` from deep inside a pipeline. `require_linux` is
called first in `main()` by every script whose behavior is Linux-specific
(anything relying on `/proc`, `lscpu`, or GNU-specific `find`/`df` flags).

---

## 5. Safe Defaults

Two conventions keep destructive behavior from happening by accident:

**Positional defaults point at something safe, not something broad.**

```bash
# scripts/filesystem/cleanup-temp.sh
TARGET="${1:-/tmp}"
LIMIT="${2:-30}"
```

**Anything that looks like cleanup is read-only until explicitly told
otherwise.** `cleanup-temp.sh` only ever *lists* candidate files — it never
calls `rm`, and it says so explicitly before exiting:

```bash
log_warn "Dry-run only. No files were removed."
log_success "Temporary-file scan completed."
```

If a future script needs to actually delete or modify files, the convention
to follow is an explicit opt-in flag (e.g. `--force` / `--yes`) rather than
making destructive behavior the default path.

---

## 6. Reusable Libraries

Shared behavior lives once in `scripts/common/` and is sourced everywhere
else — see [architecture.md](architecture.md#2-common-library-architecture)
for the full breakdown. In practice this means a leaf script never redefines
its own logging or formatting:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/bootstrap.sh"

main() {
    require_linux
    show_header "CPU Report"
    log_info "Collecting CPU information..."
    lscpu
    log_success "CPU report completed."
}
```

`bootstrap.sh` resolves its own directory via `BASH_SOURCE[0]` rather than
`$0`, so sourcing works correctly even when the calling script is itself
invoked via a symlink or from a different working directory.

Each common-library file guards against duplicate sourcing:

```bash
[[ -n "${MAOPS_HELPERS_LOADED:-}" ]] && return
readonly MAOPS_HELPERS_LOADED=1
```

This is what allows the same library file to be sourced indirectly more than
once (e.g. two different scripts sourcing `bootstrap.sh` within the same
shell) without tripping a `readonly variable` error. See
[troubleshooting.md](troubleshooting.md#1-readonly-variable-errors-from-duplicate-sourcing).

---

## 7. SIGPIPE and Pipefail

`set -o pipefail` (bundled into `set -euo pipefail`) makes a pipeline fail if
*any* stage fails — not just the last one. This is usually what you want, but
it interacts badly with any pipeline whose downstream stage exits early by
design, most commonly `... | head -n N`:

```bash
# Dangerous under `set -euo pipefail`:
results="$(find . -type f -printf '%s\t%p\n' | sort -nr | head -n 10)"
```

When `head` has read its 10 lines, it exits and closes its end of the pipe.
`sort`, still writing, receives `SIGPIPE` and dies with a signal-based exit
status. `pipefail` propagates that non-zero status into the command
substitution, which then trips `set -e` and kills the whole script —
silently, with no error message, typically reported as `exit 141` (128 + `SIGPIPE`'s
signal number 13). See
[troubleshooting.md](troubleshooting.md#7-exit-141-caused-by-sigpipe) for how
to recognize and reproduce this.

This codebase avoids the failure mode by not truncating with `head` inside a
`pipefail`-sensitive substitution. `scripts/filesystem/largest-files.sh`
instead lets the full pipeline run to completion and does the truncation
inside `awk`, which reads its entire input rather than closing the pipe
early:

```bash
results="$(
    { find "$TARGET" -type f -printf '%s\t%p\n' 2>/dev/null || true; } |
        sort -nr -k1,1 |
        awk -F '\t' -v limit="$LIMIT" '
            NR <= limit { ... }
        '
)"
```

Other valid fixes if a `head`-terminated pipeline is unavoidable: scope
`set +o pipefail` around just that one pipeline and restore it immediately
after, or trap `SIGPIPE` (`trap '' PIPE`) in the subshell that runs the
pipeline. Prefer the `awk`-reads-everything approach shown above when
practical — it doesn't require toggling shell options at all.

---

## 8. ShellCheck

Every script and template is expected to pass `shellcheck` with no warnings
at the default severity. Run it locally with:

```bash
make lint          # find scripts templates -name '*.sh' | xargs shellcheck
shellcheck scripts/filesystem/largest-files.sh   # single file
```

Two directives show up deliberately in this codebase, both documented with a
reason rather than dropped in silently:

```bash
# shellcheck disable=SC2034 # color codes are consumed by scripts that source this file
```

used in `colors.sh` and `config.sh`, because ShellCheck analyzes each file in
isolation and can't see that `RED`, `PROJECT_NAME`, etc. are consumed by
whatever *sources* the file, not by the file itself.

```bash
# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"
```

The `# shellcheck source=` comment tells ShellCheck where to actually find
the sourced file for analysis, since it can't always resolve a dynamically
built path like `"$SCRIPT_DIR/../common/bootstrap.sh"` on its own. See
[troubleshooting.md](troubleshooting.md#5-sc1091) for what happens when this
comment is missing or wrong.

CI runs the same check (`.github/workflows/bash-validation.yml`) on every
push and pull request to `main`, so a script that passes locally but wasn't
linted before committing will still be caught before merge.

---

## 9. Git Executable Modes Under WSL

Scripts under `scripts/` and `templates/` must be tracked by git with mode
`100755` (executable), not `100644`. This is enforced by both `make
check-executable` and a dedicated CI step, because it is easy to get wrong
without noticing:

- On native Linux, `chmod +x file.sh && git add file.sh` records `100755` in
  the index, as expected.
- On a Windows filesystem mounted into WSL as `/mnt/c/...` (`drvfs`), **every
  file reports as `777`/executable to `ls -l`, regardless of what git actually
  has recorded in its index.** This means a script can look executable in
  your WSL terminal, run fine locally, and still be committed as `100644` —
  the local filesystem's reporting is not the source of truth; the git index
  is.
- The failure only surfaces on a real Linux checkout — e.g. GitHub Actions'
  `ubuntu-latest` runner — where the tracked `100644` mode is honored and
  `./script.sh` (or a CI step that shells out to it directly) fails with
  `Permission denied`.

Recommended workflow when developing under WSL against a Windows-mounted
path: clone the repository onto the native Linux filesystem (e.g. `~/code/...`
inside WSL, not `/mnt/c/...`) so `chmod` and git's recorded mode stay in sync.
If a script's mode is ever wrong, fix it explicitly rather than relying on
`chmod` picking it up from a drvfs mount:

```bash
git update-index --chmod=+x scripts/system/new-script.sh
git commit -m "fix: mark new-script.sh executable"
```

`make check-executable` reproduces the CI check locally:

```bash
git ls-files -s | awk '$4 ~ /\.sh$/ && $1 != "100755" {print $4}'
```

Any line printed by that command is a script that will fail CI on push. See
[troubleshooting.md](troubleshooting.md#4-wsl-and-windows-git-executable-mode-behavior)
for the full symptom-to-fix walkthrough.

**This problem is not limited to `git status`/CI — it used to leak into
packaged and installed output too.** `scripts/release/package.sh` and
`scripts/install/install.sh` (source-tree mode) previously staged files with
`cp -a`, which propagates whatever the *source filesystem* reports — on
drvfs, that's `0777` for everything, meaning a release built or installed
from a drvfs checkout could silently ship world-writable executables and
configuration files. The fix: neither script trusts `stat` on the source
tree at all anymore. Every staged/installed file's mode is derived
exclusively from `git ls-files -s` (the same index data `check-executable`
above already trusts) via the shared `integrity_copy_git_tracked` helper in
`scripts/common/integrity.sh`, applied with a plain `cp` (never `cp -a`) plus
an explicit `chmod` that immediately re-reads the mode back via `stat` and
aborts loudly if it didn't take — so a destination filesystem that silently
ignores `chmod` produces a hard build/install failure, not a package or
install that only looks correct. See
[architecture.md §11](architecture.md#11-installation-and-runtime-layout) and
[§15](architecture.md#15-packaging-and-release-verification) for the full
mechanism, and `tests/release/package.bats`/`tests/install/install.bats`'s
`build_drvfs_clone_fixture`-based tests for the regression coverage — they
simulate the `0777`-observed-permission symptom deterministically on any
filesystem (via a plain-copy-then-`chmod -R 0777` fixture) rather than
requiring an actual drvfs mount to test against.

Release policy for distributed files is exactly two modes, never anything
else: **`0755`** for `bin/maops`, every tracked `*.sh` script, and
`templates/script-template.sh`; **`0644`** for everything else distributed
(`README.md`, `LICENSE`, `CHANGELOG.md`, `CONTRIBUTING.md`, `Makefile`,
`.gitattributes`, and non-executable files under `scripts/`/`templates/`).
`MAOPS-MANIFEST.tsv` (§15/§16 below) encodes and enforces exactly this rule.

---

## 10. CLI Argument Validation via `scripts/common/cli.sh`

`bin/maops` and the `scripts/network/` scripts share validation helpers from
`scripts/common/cli.sh` rather than each hand-rolling their own regex:

```bash
is_positive_integer() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
validate_positive_integer() {
    is_positive_integer "$1" || cli_usage_error "$2 must be a positive integer: $1"
}
```

This reuses the same principle already established in
[§3](#3-input-validation): validate the *shape* of a string with a regex
before ever using it arithmetically or handing it to an external command
(`ping -c`, a `timeout` invocation, and so on). `is_valid_port()` goes one
step further and forces base-10 arithmetic with `10#$1` before the range
check, so a value like `"065"` can't be misread as octal by `((...))`.

`cli_usage_error()` always calls `exit` directly (never `return`), matching
`require_command`/`require_linux`'s existing direct-exit convention in
`helpers.sh` — this guarantees a consistent exit code (`2`) regardless of
whether the failing validation call happens to be inside a conditional,
where a `return`-based failure wouldn't trip `set -e` on its own.

Existing scripts under `scripts/filesystem/` that already validate a
positive integer inline (`largest-files.sh`, `cleanup-temp.sh`) were left
as-is rather than retrofitted to call `cli.sh` — `cli.sh` is for new CLI
surface area, not a mandate to rewrite working Day 2 code.

---

## 11. Parameterized `bash -c`, Instead of String Interpolation

Never build a `bash -c` (or any `sh -c`/`ssh ... "..."`/similar) command by
interpolating a variable directly into the command string:

```bash
# Dangerous: $HOST is re-parsed as shell syntax by the inner bash
bash -c "exec 3<>/dev/tcp/$HOST/$PORT"
```

If `$HOST` contains a shell metacharacter — `;`, `` ` ``, `$(...)`, `|`, `&&`
— the inner `bash` doesn't see "a hostname with weird characters," it sees
more shell syntax to execute. This is exactly what happened in an earlier
version of `scripts/network/port-check.sh`: a crafted `HOST` argument such as
`127.0.0.1;touch /tmp/pwned;` executed the injected `touch` command, because
the outer shell only performed ordinary variable substitution before handing
the resulting string to `bash -c`, and the inner `bash` then parsed that
string as a full command line, `;` and all.

The fix is to pass the untrusted value as one of `bash -c`'s own positional
parameters instead of splicing it into the script text:

```bash
# Safe: $1/$2 are the inner bash's own positional parameters, bound from
# $HOST/$PORT — the script itself is a fixed, single-quoted literal
timeout "$TIMEOUT" bash -c 'exec 3<>"/dev/tcp/$1/$2"' bash "$HOST" "$PORT"
```

Two things make this safe, both necessary together:

1. The script argument to `-c` is **single-quoted**, so the outer shell
   performs no expansion on it at all — `$1`/`$2` reach the inner `bash`
   completely literally, not pre-substituted by the outer shell into
   arbitrary text.
2. `$HOST`/`$PORT` are passed as **extra arguments after the script**, which
   `bash -c` binds to the inner shell's own `$1`/`$2` (the argument right
   after the script text becomes the inner shell's `$0`, by convention
   usually written as `bash` or `_`). The inner shell only ever *substitutes*
   `$1`/`$2` into the redirection target — a substituted value is never
   re-tokenized as command syntax the way `bash -c "$interpolated_string"`
   would re-tokenize it.

This is the general pattern any future script should follow if it needs to
hand a shell a piece of untrusted or externally supplied data to run inside
a nested `-c` invocation: pass it as a parameter, never splice it into the
script text. See
[architecture.md §8](architecture.md#8-network-module) for how this applies
specifically to `port-check.sh`, and
[troubleshooting.md §12](troubleshooting.md#12-why-port-checksh-uses-bash--c-with-1-2-instead-of-host-directly)
for the symptom this fixes.

---

## 12. Read-Only Operations by Default

The user, process, and service modules
([architecture.md §9](architecture.md#9-user-process-and-service-modules))
extend the safe-defaults principle from §5 further: it is not enough that a
*destructive* operation defaults to a dry run — an entire module can be
scoped so that no destructive operation is reachable through it at all.
`user-report.sh`, `process-monitor.sh`, and `service-status.sh` each only
ever call query-style subcommands (`getent`, `id`, `who`, `ps`, `systemctl
show`, `service ... status`); none of them contain `kill`, `pkill`,
`renice`, `nice`, or a systemd/`service` verb that mutates state (`start`,
`stop`, `restart`, `reload`, `enable`, `disable`, `mask`). None of the three
require `sudo` — every command they run works for an unprivileged caller.

This also extends to *what* is reported, not just what is done:
`process-monitor.sh` reports `ps -o comm` (the executable name) rather than
`ps -o args` (the full command line) specifically because `args` routinely
contains secrets — `--password=...`, API tokens, database connection
strings — passed as process arguments on a shared host. Similarly,
`user-report.sh` reads the passwd password-placeholder field into `_` and
never prints it, and never calls `getent shadow` or reads `/etc/shadow` — a
read-only report should not become a second way to leak what the read-only
policy was supposed to protect in the first place.

## 13. Service-Manager Detection and Fallback

`service-status.sh` needs to answer "is systemd the running init system?"
before it knows whether to run `systemctl` or `service`. `command -v
systemctl` is not a sufficient test: the `systemctl` binary is commonly
installed in environments where systemd is *not* PID 1 — most container
images and WSL among them — and running it there fails with something like
`Failed to connect to bus: No such file or directory`, which is a confusing
result if the script had already committed to the systemd branch.

The correct check is whether `/run/systemd/system` exists — the same
runtime marker systemd's own `sd_booted(3)` function checks to mean "systemd
is genuinely running":

```bash
readonly SYSTEMD_RUNTIME_DIR="${MAOPS_SYSTEMD_RUNTIME_DIR:-/run/systemd/system}"
systemd_is_running() {
    command_exists systemctl && [[ -d "$SYSTEMD_RUNTIME_DIR" ]]
}
```

`MAOPS_SYSTEMD_RUNTIME_DIR` exists purely as a test seam: it lets a test
force either branch deterministically (point it at a real directory to
select `systemctl`, or a nonexistent path to force the `service` fallback)
without needing root, a container, or a host that genuinely lacks systemd.
It is read-only — it only changes which query the script runs, never what
the query does — so overriding it cannot cause a mutation.

Once a branch is selected, the two backends are queried differently on
purpose:

- **`systemctl show --property=LoadState,ActiveState,SubState`**, not
  `systemctl is-active`. `show` exits `0` in every normal case, including a
  unit that does not exist (`LoadState=not-found`) — so a non-zero exit from
  `show` unambiguously means `systemctl` itself failed (bus error,
  permission problem), and must be surfaced as a failure rather than mapped
  to "inactive." `is-active` conflates these cases: it returns different
  non-zero codes for "inactive," "not found," *and* a genuine bus failure,
  making them impossible to tell apart from the exit code alone.
- **`service SERVICE status`**, interpreted by its LSB init-script exit code
  (`0` running, `3` stopped, `4` unknown/no-such-service) — never by
  pattern-matching its free-form status text, which varies across
  distributions and individual init scripts and would be a fragile,
  spoofable signal to make a pass/fail decision on.

Either way, an exit code that doesn't fit a recognized case (e.g. `service`
returning `1` or `2` for a malformed invocation) is reported as an explicit
lookup failure, not silently folded into "stopped" — see §15.

## 14. Deterministic PATH-Based Test Stubs

`user-report.sh`, `process-monitor.sh`, and `service-status.sh` wrap host
commands (`getent`, `id`, `who`, `ps`, `systemctl`, `service`) whose real
output depends on the host's actual accounts, process list, logged-in
sessions, and init system — none of which a test suite should depend on
(see [troubleshooting.md](troubleshooting.md) for the general principle of
keeping CI deterministic). `tests/test-helper.bash` provides two helpers to
fake these commands per test:

```bash
stub_bin_init            # creates $BATS_TEST_TMPDIR/stubs, prepends it to $PATH
stub_command NAME <<'STUB'
...stub body, reads its own "$@" like a real command would...
STUB
```

A stub is a plain executable script generated fresh into
`$BATS_TEST_TMPDIR` for that one test, not a file checked into the
repository. This is deliberate: a `$PATH`-discoverable stub must be named
exactly `systemctl`/`ps`/etc — no `.sh` suffix — or the shell would never
find it via a bare-name lookup. A checked-in extensionless file would sit
outside `make check-executable`'s `*.sh`/`bin/maops` glob, which is exactly
the kind of gap that let scripts get tracked as non-executable in the past
(see
[troubleshooting.md §4](troubleshooting.md#4-wsl-and-windows-git-executable-mode-behavior)).
Generating stubs at test time keeps them entirely outside that risk. No
`teardown()` is needed either — Bats gives every test its own subshell and
environment and removes `$BATS_TEST_TMPDIR` itself once the test finishes.

Guardrails when writing a new stub-based test:

- **Prepend, don't replace** `$PATH` — the script under test still needs
  every real coreutil it depends on (`awk`, `date`, `printf`, ...).
- **Never stub `date`, `uname`, `awk`, `printf`, or `cat`** — the common
  library and Bats' own test machinery depend on the real versions of these.
- **Prefer a recording stub** — have it append its own `"$*"` to a
  `*.calls` log file under `$BATS_TEST_TMPDIR` — so a test can assert what
  the script under test actually invoked (e.g. "the `service` stub was
  called and the `systemctl` stub was not," or "no stub was ever invoked
  with `start`/`stop`/`enable`"), turning read-only and
  injection-resistance guarantees into behavioral assertions instead of
  assumptions about output text.

## 15. Exit-Code Conventions

Every script in this toolkit follows the same three-way exit-code contract,
enforced consistently by `scripts/common/cli.sh`'s `cli_usage_error` (always
exit `2`) and by each script's own `main()`:

| Exit | Meaning | Example |
|---|---|---|
| `0` | Success | A service is active; a user/process report was produced |
| `1` | Operational failure — the command ran but the real-world answer is "no"/"not found"/"unavailable," or a required dependency/platform check failed | Unknown user (`user-report.sh`), inactive/unknown service (`service-status.sh`), a missing required command (`require_command`) |
| `2` | CLI usage error — the caller's input was invalid before any real work started | Missing required argument, option-like value, out-of-range/non-numeric value, unrecognized enum value |

The rule that keeps this contract meaningful is: **never let an unexpected
failure masquerade as a normal negative result.** `service-status.sh` is the
clearest example — `systemctl show` exiting non-zero (a bus error) is a
*different* situation from a unit legitimately being inactive, and the
script deliberately keeps them distinguishable (both still exit `1`, since
both are operational rather than usage failures, but the message differs
and the bus error's stderr is captured and shown rather than discarded). The
same discipline applies to `service`'s fallback exit codes (§13): an exit
code outside the known LSB set (`0`, `3`, `4`) is reported as an explicit
lookup failure, never silently treated as "stopped."

## 16. Manifest-Based Install/Uninstall Safety

`scripts/install/install.sh`/`uninstall.sh` (full design in
[architecture.md §11](architecture.md#11-installation-and-runtime-layout))
establish a discipline not needed anywhere else in this codebase until now:
every other script only ever reads paths or writes to a handful of
well-known, fixed locations, but the installer takes a user-supplied
directory (`--prefix`) as an argument to genuinely mutating operations
(`mkdir`, `mv`, `ln`, `rm`). Three rules make that safe:

**Never `rm -rf` a variable — only ever a manifest-verified file list,
scoped to `LIB_DIR`, validated entirely before anything is removed.**
`PREFIX` (`$HOME/.local` by default) is frequently a *shared* location —
other tools can and do install their own files under sibling directories
like `PREFIX/bin` or `PREFIX/share`. Scoping the removal guard to `PREFIX`
itself would let a corrupted or tampered manifest reach those siblings, so
the guard is scoped to `LIB_DIR` (`PREFIX/lib/maops`) specifically — the one
subtree this installer actually owns. Validation is also a fully separate,
read-only pass that runs *before* `remove_files` ever calls `rm`, and it
fails the whole manifest closed on the first problem, not just the
offending entry:

```bash
validate_manifest_files() {
    local path
    local -A seen=()

    for path in "${MANIFEST_FILES[@]}"; do
        [[ -z "$path" ]] && { log_error "Malformed manifest: empty file entry."; exit 1; }

        case "$path" in
            "$LIB_DIR"/*) : ;;
            *) log_error "Refusing manifest entry outside $LIB_DIR: $path"; exit 1 ;;
        esac

        integrity_path_has_dotdot_component "$path" && {
            log_error "Refusing manifest entry with path traversal: $path"; exit 1
        }

        [[ -n "${seen[$path]:-}" ]] && { log_error "Duplicate manifest entry: $path"; exit 1; }
        seen[$path]=1
    done
}
```

Only after every entry passes does `remove_files` run its simple
existence-check-then-`rm -f --` loop — one file at a time, never `rm -rf` on
a directory built from `$PREFIX`/`$LIB_DIR` or any other variable. Empty
directories are cleaned up afterward with plain `rmdir --` (which fails
loudly, not silently, if a directory turns out to be unexpectedly
non-empty), not `rm -rf`. `tests/install/install.bats` includes regression
tests proving a manifest entry pointing at `PREFIX/share/...` (outside
`LIB_DIR` but still under `PREFIX`), a `..`-traversal entry, and a duplicate
entry are all refused with the target file(s) provably untouched.

**Quote every path, and use `--` before it in every mutating command.** A
prefix value starting with `-` must never be misread as a flag:

```bash
mkdir -p -- "$staging"
mv -- "$staging" "$LIB_DIR"
ln -sfn -- "../lib/maops/bin/maops" "$LAUNCHER"
rm -f -- "$path"
```

**Never `eval`, never `bash -c` with an interpolated path.** A prefix
containing `;`, `$(...)`, or backticks is always inert — it is only ever
used as a literal argv element, never handed to something that would
re-parse it as shell syntax. This is the same discipline established for
`port-check.sh`'s `HOST` argument in §11, extended here to a value that
additionally drives filesystem mutation, not just a network call.

**Symlink verification without `realpath`.** Two situations need to know
whether a symlink at a fixed path resolves to a specific expected target —
install's "is the unrelated-file-at-launcher guard actually looking at our
own prior symlink" check, and uninstall's "does this launcher belong to
this install" check. Both resolve a possibly-relative symlink target
against the symlink's *own* directory (never the caller's `$PWD`), without
shelling out to `readlink -f`/`realpath` (neither is a required runtime
command):

```bash
dir="$(cd -- "$(dirname -- "$link")" && pwd)"
target="$(readlink -- "$link")"
[[ "$target" == /* ]] || target="$dir/$target"
```

## 17. Config File Parsing Without `eval` or `source`

`scripts/common/config-file.sh` ([architecture.md §12](architecture.md#12-configuration-system))
parses a user-editable file that this project's threat model explicitly
calls out as untrusted input: a value could contain command substitution or
shell metacharacters, whether by an operator's mistake or deliberately. The
file is therefore never `source`d and never passed to `eval` — it is read
exclusively via:

```bash
while IFS= read -r line || [[ -n "$line" ]]; do
    ...
done <"$path"
```

Line classification and key/value extraction share **one** regex
(`^([a-z_][a-z0-9_]*)[[:space:]]*=(.*)$`), matched once per line with
`BASH_REMATCH` capturing both groups — not a classifier regex and a separate
`cut`/`awk`-based extractor, which could disagree on what counts as a valid
line. Because a value is only ever compared against a validator regex
(`is_one_of` for `output_format`, `is_positive_integer` for the numeric
keys) and never expanded or executed, a value like
`process_limit=$(touch /tmp/pwned)` simply fails `is_positive_integer` — the
`$(...)` never has a chance to run. `tests/config/config-manager.bats`
proves this both ways: the malicious value is rejected *and* the command it
contains is never actually invoked (verified via a stubbed, call-logging
replacement for the command it tries to run).

A static regression test (mirroring the existing "no eval" check for
`service-status.sh`, §13) greps `config-file.sh` itself for `eval`, `source`,
`bash -c`, and `sh -c`, excluding comment lines (so prose describing this
very guarantee doesn't false-positive against itself).

## 18. Hand-Rolled JSON Without `eval` or `jq`

`scripts/common/format.sh` ([architecture.md §13](architecture.md#13-structured-output-json-scope))
assembles JSON with `printf` and parameter expansion only — no `eval`, and
no runtime dependency on `jq` (a requirement carried over from the project's
"minimal, well-known dependencies only" principle already applied
throughout §8's tool choices).

`json_escape` performs five substitutions in a fixed order — backslash
first, then double quote, then tab/CR/newline:

```bash
s="${s//\\/\\\\}"     # backslash MUST come first
s="${s//\"/\\\"}"
s="${s//$'\t'/\\t}"
s="${s//$'\r'/\\r}"
s="${s//$'\n'/\\n}"
```

Escaping backslashes first is not a stylistic choice: if quote-escaping ran
first, its own inserted backslashes would then get double-escaped by the
backslash substitution running second. `json_kv KEY VALUE [--raw]` wraps a
single field, with `--raw` for values that must appear unquoted in the
output (numbers, booleans) rather than as an escaped string; `json_object`
is a thin convenience wrapper for the common flat, all-string case.

Both JSON-emitting commands (`config show --format json`, `doctor --format
json`) print exactly one complete document and suppress `log_info`/
`show_header` entirely in JSON mode — a stray line before or after the
document would break any consumer piping into `python3 -m json.tool` or
`jq`. `doctor`'s array-of-checks shape is composed by joining several
`json_kv`-built fragments with `,` in the caller, rather than teaching
`format.sh` a general array/nesting API — keeping the shared library itself
small and easy to verify by inspection. `maops integrity --format json`
(§19 below) follows the exact same discipline: one document, no stray
output, same `json_kv` composition style.

## 19. Archive Member-Type Allowlisting, Not a Blocklist

`scripts/release/verify-package.sh` ([architecture.md
§15](architecture.md#15-packaging-and-release-verification)) must reject a
malicious or corrupted archive's symlink/hardlink/device/FIFO members before
extraction ever runs. Two implementation choices matter here:

**Allowlist member types, don't blocklist them.** The check is "accept only
`isreg()` or `isdir()`," not "reject `issym()`, reject `islnk()`, reject
`ischr()`, reject `isblk()`, reject `isfifo()`, reject ...". A blocklist has
to be complete to be safe — miss one tar extension type and it silently
passes through. An allowlist is safe by construction: anything not
explicitly permitted is rejected, with no way to forget a case.

**Inspect real member type flags via Python's `tarfile` module, not GNU
tar's own text output.** `tar -tv`'s verbose listing is a human-readable
convenience, not a documented, version-stable interface — relying on its
leading permission character or a `"link to"` substring to distinguish a
hardlink from a regular file would mean trusting the very tool ("the
extracting tar implementation") this check exists to not rely on.
`tarfile.TarInfo.type` is an unambiguous, directly-inspectable byte read
from the archive header itself:

```python
if not (member.isreg() or member.isdir()):
    fail(f"disallowed member type for: {member.name}")
```

This is release-engineering-only tooling — `verify-package.sh` requires
`python3` in addition to `tar`/`sha256sum`, but the installed runtime CLI's
own dependency list (`doctor.sh`'s `REQUIRED_COMMANDS`/`OPTIONAL_COMMANDS`)
is unrelated and unchanged; an end user running `maops` day to day never
needs `python3` for anything this project ships.

Symlinks are refused unconditionally, with no "validate the target and
allow it" carve-out — the project ships zero legitimate symlinks today
(confirmed via `git ls-files -s`), so there is no legitimate case to
special-case, and parsing a symlink's target safely out of a generic
listing is exactly the kind of added complexity that tends to hide the next
bug. `tests/release/package.bats`'s `craft_tar_with_member` helper (built on
the same `tarfile` module) constructs one crafted archive per rejected type
— symlink, hardlink, character device, block device, FIFO — so each
rejection path has a concrete, real archive to test against, not just an
assertion about what the code is supposed to do.

## 20. Two-Tier Archive Integrity: External Checksum vs. Internal Manifest

A single SHA-256 checksum for the whole archive answers one question: "are
these exactly the bytes I was told to trust?" It cannot answer a second,
narrower question that matters just as much: "is *this specific file inside
the archive* exactly what it's supposed to be, independent of who signed the
checksum?" If an archive-hosting service is itself compromised, an attacker
who can modify the archive can typically also re-sign its `.sha256`
sidecar — at which point the external checksum, though technically
"correct," has stopped meaning anything.

`MAOPS-MANIFEST.tsv` is the second, independent layer: a
`MODE<TAB>SHA256<TAB>RELATIVE_PATH` line for every distributed file, sorted
deterministically (`LC_ALL=C`), generated once by `package.sh` from
Git-tracked content, shipped inside the archive, and verified by
`verify-package.sh` *after* the archive-member safety checks (§19) but using
the same content-hashing logic (`integrity_sha256_file`) the mode-
normalization code (§9 above) already relies on. The two checksums are
never conflated or compared to each other — the external `.sha256` remains
the sole authority for "is this the archive," and the internal manifest is
the sole authority for "is this file, inside a trusted archive, unmodified."
A tampered file inside an otherwise-checksum-valid archive fails the second
check even though it passed the first.

The same manifest format, and the same parsing/validation code
(`integrity_read_manifest` in `scripts/common/integrity.sh`), is reused a
third time by `maops integrity` (§16 in architecture.md) against an
*installed* copy of the manifest (`.integrity-manifest`) — one deterministic
format, one parser, three different trust contexts (package build, archive
verification, post-install verification), rather than three subtly
different reimplementations that could drift apart.

**What neither layer proves.** The external `.sha256` verifies the archive's
*bytes*; `MAOPS-MANIFEST.tsv` verifies each distributed file's *content and
mode* once inside a trusted archive. Neither one proves *who published* the
archive — a party who can replace both the archive and its `.sha256`
sidecar can produce a pair that is internally self-consistent by
construction and passes every check described above. This is a deliberate,
documented scope boundary, not an oversight: publisher-identity signing
(e.g. GPG or Sigstore) is explicitly out of scope for the toolkit until a
post-v1.0 milestone (see `docs/roadmap.md`'s Planned section).

## 21. Secure Temp-File Handling: Race-Free, Mode-0600, Atomic Rename

Any code path that writes a file a caller will later read as trusted output
— `config_write_atomic()` in `scripts/common/config-file.sh` and
`report_save_atomic()` in `scripts/common/reporting.sh` are the two
instances in this codebase — follows the same three-part pattern rather
than writing the destination path directly:

1. **Create the temp file in the *same directory* as the final target**,
   via `mktemp -- "$dir/.PREFIX.XXXXXX"`. Same-directory placement is what
   makes the final step a same-filesystem atomic rename instead of a
   cross-device copy-then-unlink, which is not atomic and can leave a
   half-written destination if interrupted. The two call sites use
   distinct prefixes (`.config.XXXXXX` vs. `.maops-report.XXXXXX`) so they
   can never collide even if one target path happens to sit inside the
   other's directory.
2. **`chmod 0600` the temp file explicitly**, before writing any content to
   it, rather than relying solely on the caller's `umask`. Setting the mode
   explicitly means the guarantee holds even if some future call site
   forgets to set `umask 077` first — the permission is a property of the
   function, not of every caller's discipline.
3. **`mv -f` the temp file onto the final target** as the last step. This
   single rename either fully succeeds or fully fails; a reader can never
   observe a partially-written destination file.

Every failure path (mktemp failure, chmod failure, write failure, mv
failure) explicitly `rm -f`s the temp file before returning, so a normal
failure never leaves debris behind. The one case this pattern cannot cover
is a fatal, untrappable signal — `SIGKILL`, `SIGXFSZ` — arriving between
step 1 and step 3: no `trap` can run in that case, on any Unix system, so a
`.maops-report.*`/`.config.*` temp file can be left on disk. This is an
accepted residual risk, not a bug: the destination file is still never
partially replaced (the rename never started), the leftover file is still
mode `0600`, and it is safe to delete by hand. See
[troubleshooting.md §20](troubleshooting.md#20-a-stray-maops-report-file-is-left-in-the-destination-directory)
for the user-facing version of this note. The toolkit deliberately never
scans for and auto-deletes files matching either temp-file pattern — doing
so would mean globbing and removing files by name in a directory the user
chose, which is a larger blast radius than the problem it would solve.
