# Architecture

This document describes how the MAOps Linux DevOps Toolkit is organized, how its
shared library loads, and how the existing modules are built on top of it. It
reflects the repository as it exists today — see [roadmap.md](roadmap.md) for
what is intentionally not built yet.

---

## 1. Repository Organization

```text
.
├── .claude              # Claude Code project guidance and Skills
├── .github/workflows    # CI: Bash syntax + ShellCheck + executable-mode gate
├── docs                 # This documentation set, plus engineering reviews
├── scripts
│   ├── common           # Shared library — no script in the other folders is
│   │                    # meant to duplicate what lives here
│   ├── filesystem       # Disk usage, largest files, temp-file scanning
│   ├── monitoring       # CPU, memory, load-average reporting
│   └── system           # Host identity and OS reporting
├── templates            # Boilerplate for generating new scripts/docs/workflows
├── CHANGELOG.md / CONTRIBUTING.md / LICENSE / Makefile
└── README.md
```

The guiding rule is **one shared library, many thin leaf scripts**. Every
executable under `scripts/<module>/` is a consumer of `scripts/common/`; none
of them reimplement logging, argument echoing, or output formatting locally.
`scripts/network` and `scripts/users` are planned modules (see
[README.md](../README.md#utilities)) and do not exist yet — when they are
added, they follow the same pattern described below.

---

## 2. Common Library Architecture

`scripts/common/` is split into five single-responsibility files:

| File | Responsibility |
|---|---|
| `colors.sh` | ANSI color constants (`RED`, `GREEN`, `YELLOW`, `BLUE`, `PURPLE`, `CYAN`, `WHITE`, `NC`) |
| `config.sh` | Project metadata (`PROJECT_NAME`, `PROJECT_VERSION`, `PROJECT_AUTHOR`, `PROJECT_LICENSE`) and reserved configuration (`LOG_DIRECTORY`, `DEFAULT_TIMEOUT`) |
| `helpers.sh` | Generic utilities: `command_exists`, `require_command`, `require_linux`, `divider`, `print_title`, `section`, `print_key_value` |
| `logger.sh` | Leveled console logging: `log_info`, `log_success`, `log_warn`, `log_error`, all timestamped and colorized |
| `output.sh` | Thin presentation wrappers over `helpers.sh` primitives: `show_header`, `show_section`, `show_footer` |

Each file guards against being sourced twice using the same pattern:

```bash
[[ -n "${MAOPS_COLORS_LOADED:-}" ]] && return
readonly MAOPS_COLORS_LOADED=1
```

This guard is what makes `readonly` safe here. Bash's `readonly` raises
`readonly variable` errors if the same `readonly NAME=value` line executes
twice in one shell. Because every common-library file is sourced (not
executed in a subshell) into whatever script called it, re-sourcing would
otherwise crash any script that pulled the same file in twice — for example,
indirectly through two different helper scripts. The guard turns a second
`source` of the same file into a no-op `return` instead of a fatal error. See
[troubleshooting.md](troubleshooting.md#1-readonly-variable-errors-from-duplicate-sourcing)
for what it looks like when this guard is missing or bypassed.

`helpers.sh` and `config.sh` intentionally know nothing about each other or
about `colors.sh` — they hold no cross-file dependency. `logger.sh` and
`output.sh` do have a dependency, which is why load order matters (next
section).

---

## 3. Bootstrap Dependency-Loading Order

`scripts/common/bootstrap.sh` is the single entry point every leaf script
sources. It resolves its own directory (so it works no matter where the
caller's current working directory is) and sources the other five files in a
fixed order:

```bash
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$COMMON_DIR/colors.sh"    # 1. no dependencies
source "$COMMON_DIR/config.sh"    # 2. no dependencies
source "$COMMON_DIR/helpers.sh"   # 3. no dependencies
source "$COMMON_DIR/logger.sh"    # 4. depends on colors.sh ($RED, $BLUE, ..., $NC)
source "$COMMON_DIR/output.sh"    # 5. depends on helpers.sh (print_title, section, divider)
```

The order is not arbitrary: `logger.sh` references `$BLUE`, `$GREEN`,
`$YELLOW`, `$RED`, and `$NC` inside its `_log()` function, so `colors.sh` must
already be sourced by the time `logger.sh` runs. Likewise, `output.sh`'s
`show_header()`/`show_section()` call straight into `print_title()` and
`section()` from `helpers.sh`, so `helpers.sh` must precede it. `config.sh`
has no dependents among the other common files and could load anywhere, but
it is kept second, ahead of the two files that depend on `colors.sh`, purely
for readability of the list.

`bootstrap.sh` carries the same double-source guard as the files it loads
(`MAOPS_BOOTSTRAP_LOADED`), so a leaf script — or a future script that sources
another leaf script — can safely `source bootstrap.sh` more than once.

Every leaf script follows the same three-line resolution pattern to find and
source it regardless of the caller's `$PWD`:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"
```

---

## 4. System, Monitoring, and Filesystem Modules

All nine current leaf scripts share one shape:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/bootstrap.sh"

main() {
    require_linux            # most, not all, scripts gate on Linux
    show_header "<Title>"
    log_info "..."
    # module-specific work
    log_success "... completed."
}

main "$@"
```

### `scripts/system/`

| Script | What it reports | Notable behavior |
|---|---|---|
| `system-info.sh` | Hostname, kernel, OS, user, uptime | Does **not** call `require_linux` — it uses only `uname`/`hostname`/`whoami`, which are portable |
| `os-details.sh` | OS, kernel, architecture, distro name/version | Calls `require_linux`; conditionally sources `/etc/os-release` to read `PRETTY_NAME`/`VERSION_ID` |
| `hostname-report.sh` | Hostname and FQDN | Falls back to `"Unavailable"` if `hostname -f` fails (no reverse DNS) |

`os-details.sh` sources `/etc/os-release` directly rather than parsing it
with `awk`/`grep`. That file is normally trustworthy on a stock Linux
install, but sourcing it does execute its contents as shell — worth knowing
if this pattern is ever copied onto a script that reads a less-trusted file.

### `scripts/monitoring/`

| Script | Underlying command |
|---|---|
| `cpu-monitor.sh` | `lscpu` |
| `memory-report.sh` | `free -h` |
| `load-average.sh` | `uptime` |

These three are intentionally thin — they add `require_linux`, header/section
framing, and log lines around a single well-known Linux command rather than
reimplementing what that command already does well.

### `scripts/filesystem/`

| Script | Purpose | Key safety property |
|---|---|---|
| `disk-usage.sh` | `df -h` excluding `tmpfs`/`devtmpfs` | Read-only |
| `largest-files.sh` | Top-N largest files under a target directory | Validates `LIMIT` against `^[1-9][0-9]*$` before use; see below for its pipefail handling |
| `cleanup-temp.sh` | Lists candidate temp files under a target directory | **Dry-run only** — it never deletes anything; it prunes `systemd-private-*` and `snap-private-tmp` directories rather than descending into them |

`largest-files.sh` and `cleanup-temp.sh` both build their `find` pipeline
inside a `results="$( ... )"` command substitution and append `|| true` to
the `find` stage specifically so that a permission-denied entry (`find`
exiting non-zero because one subdirectory was unreadable) does not abort the
whole script under `set -e`. This is different from — and does not by
itself solve — the `SIGPIPE`/`pipefail` interaction discussed in
[best-practices.md](best-practices.md#7-sigpipe-and-pipefail) and
[troubleshooting.md](troubleshooting.md#7-exit-141-caused-by-sigpipe); it is
the `find | sort | head` shape (no longer present in `largest-files.sh`,
which now pipes into `awk` instead of `head`) that historically triggered
that failure.

---

## 5. Templates

`templates/` is the source for the `new-bash-tool` Claude Code Skill
(`.claude/skills/new-bash-tool/SKILL.md`), which copies a template and fills
in placeholders rather than generating a script from scratch.

| File | Status |
|---|---|
| `script-template.sh` | Implemented — full boilerplate: shebang, header block, `set -euo pipefail`, `bootstrap.sh` sourcing, `usage()`, `parse_args()` supporting `-h/--help` and `-v/--version`, and a `main()` stub |
| `readme-template.md` | Stub (empty) — reserved for scaffolding new sibling-project READMEs |
| `skill-template.md` | Stub (empty) — reserved for scaffolding new Claude Code Skills |
| `github-workflow-template.yml` | Stub (empty) — reserved for scaffolding new workflow files |

Only `script-template.sh` is load-bearing today: it is the one the
`new-bash-tool` Skill actually reads and copies. The other three are placeholders
for a documented-but-not-yet-built templating flow and should not be assumed
to contain usable content — track their completion in
[roadmap.md](roadmap.md).

`script-template.sh`'s `parse_args()` explicitly rejects positional arguments
and unknown flags (`return 2`), so any new script generated from it starts
from a fail-closed argument parser rather than silently ignoring bad input.

---

## 6. GitHub Actions Validation

`.github/workflows/bash-validation.yml` runs on push and pull request to
`main`, plus `workflow_dispatch`, with `permissions: contents: read`. It
mirrors the Makefile's `quality` target step for step:

1. **Checkout** — `actions/checkout@v4`.
2. **Install ShellCheck** — `apt-get install shellcheck` on the `ubuntu-latest` runner.
3. **Validate Bash syntax** — `find scripts -name '*.sh' | xargs -0 -n1 bash -n` (parse-only, no execution).
4. **Run ShellCheck** — `find scripts -name '*.sh' | xargs -0 shellcheck`.
5. **Verify executable modes** — reads `git ls-files -s`, and fails the job if any tracked `*.sh` file's mode is anything other than `100755`. This step is what originally caught the release blocker recorded in `docs/engineering-reviews/day-02.md` (finding C1): scripts committed as `100644` pass every local check on a Windows/WSL `drvfs` mount (which reports `777` regardless of the tracked git mode) but fail this exact CI step on a real Linux checkout.
6. **Validation completed** — a final marker step for readability in the Actions log.

The corresponding local targets in the `Makefile` (`make validate`, `make
lint`, `make check-executable`, `make quality`) let a contributor reproduce
every one of these checks before pushing, without needing GitHub Actions to
tell them it failed. `make quality` is the umbrella target that runs all
three.

---

## 7. Planned: Unified `maops` CLI

Not yet implemented. Today, each utility is invoked directly:

```bash
./scripts/system/system-info.sh
./scripts/monitoring/cpu-monitor.sh
./scripts/filesystem/largest-files.sh /var/log 20
```

The roadmap calls for a single `maops` entry point that dispatches to these
scripts by subcommand, e.g. `maops system info`, `maops monitor cpu`, `maops
fs largest /var/log 20`. Based on the structure already in place, the
intended design is:

- A single top-level `maops` executable (or a thin wrapper installed onto
  `$PATH`) that sources `scripts/common/bootstrap.sh` once and then dispatches
  by module/subcommand name to the existing leaf scripts — not a rewrite of
  their logic.
- Subcommand names mapped directly to the existing `scripts/<module>/` and
  filename structure, so the CLI is additive rather than a breaking change to
  the scripts that already work standalone.
- Continued use of `require_command`/`require_linux` guards per subcommand,
  since the CLI itself should not assume every dependency (`lscpu`, `df`,
  `find`, etc.) is present on every system it runs on.
- `--help`/`--version` at both the top level and per-subcommand, following the
  convention already established in `templates/script-template.sh`.

This section will be replaced with the actual design once implementation
starts; until then, treat it as a statement of intent rather than a
description of existing code.
