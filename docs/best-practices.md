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
