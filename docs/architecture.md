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
├── .github/workflows    # CI: make quality (syntax, ShellCheck, executable-mode, Bats)
├── bin                  # maops — unified CLI dispatcher
├── docs                 # This documentation set, plus engineering reviews
├── scripts
│   ├── common           # Shared library — no script in the other folders is
│   │                    # meant to duplicate what lives here
│   ├── filesystem       # Disk usage, largest files, temp-file scanning
│   ├── monitoring       # CPU, memory, load-average reporting
│   ├── network          # Network info, ping, DNS lookup, port checking
│   ├── process          # Read-only top-N process reporting
│   ├── service          # Read-only service status inspection
│   ├── system           # Host identity and OS reporting
│   └── users            # Read-only user account reporting
├── templates            # Boilerplate for generating new scripts/docs/workflows
├── tests                # Bats test suite
├── CHANGELOG.md / CONTRIBUTING.md / LICENSE / Makefile
└── README.md
```

The guiding rule is **one shared library, many thin leaf scripts**. Every
executable under `scripts/<module>/` is a consumer of `scripts/common/`; none
of them reimplement logging, argument echoing, or output formatting locally.
`bin/maops` follows the same rule at the dispatch level — it sources
`scripts/common/bootstrap.sh` once and `exec`s into the leaf scripts rather
than reimplementing them (see §7).

---

## 2. Common Library Architecture

`scripts/common/` is split into six single-responsibility files:

| File | Responsibility |
|---|---|
| `colors.sh` | ANSI color constants (`RED`, `GREEN`, `YELLOW`, `BLUE`, `PURPLE`, `CYAN`, `WHITE`, `NC`) |
| `config.sh` | Project metadata (`PROJECT_NAME`, `PROJECT_VERSION`, `PROJECT_AUTHOR`, `PROJECT_LICENSE`) and reserved configuration (`LOG_DIRECTORY`, `DEFAULT_TIMEOUT`) |
| `helpers.sh` | Generic utilities: `command_exists`, `require_command`, `require_linux`, `divider`, `print_title`, `section`, `print_key_value` |
| `logger.sh` | Leveled console logging: `log_info`, `log_success`, `log_warn`, `log_error`, all timestamped and colorized |
| `output.sh` | Thin presentation wrappers over `helpers.sh` primitives: `show_header`, `show_section`, `show_footer` |
| `cli.sh` | CLI-only concerns consumed by `bin/maops` and the network/users/process/service scripts: `cli_show_version`, `is_help_flag`, `is_version_flag`, `cli_usage_error` (log + exit 2), `is_positive_integer`/`validate_positive_integer`, `is_valid_port`/`validate_tcp_port`, `is_non_option_argument`/`validate_non_option_argument` (rejects empty or leading-dash values), `is_one_of`/`validate_one_of` (generic allow-listed-value validator) |

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
source "$COMMON_DIR/cli.sh"       # 6. depends on logger.sh (log_error) and config.sh (PROJECT_NAME/PROJECT_VERSION)
```

The order is not arbitrary: `logger.sh` references `$BLUE`, `$GREEN`,
`$YELLOW`, `$RED`, and `$NC` inside its `_log()` function, so `colors.sh` must
already be sourced by the time `logger.sh` runs. Likewise, `output.sh`'s
`show_header()`/`show_section()` call straight into `print_title()` and
`section()` from `helpers.sh`, so `helpers.sh` must precede it. `config.sh`
has no dependents among the other common files and could load anywhere, but
it is kept second, ahead of the two files that depend on `colors.sh`, purely
for readability of the list. `cli.sh` is loaded last because its
`cli_usage_error()` calls `log_error()` and its `cli_show_version()` reads
`$PROJECT_NAME`/`$PROJECT_VERSION`, so both `logger.sh` and `config.sh` must
already be loaded.

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
installs `shellcheck` and `bats` on the `ubuntu-latest` runner, then runs
`make quality` directly — CI and local development run the exact same
command, so nothing can pass locally and still fail in CI (or vice versa) due
to divergent logic. `make quality` is the umbrella target that chains
`validate` (Bash syntax via `bash -n`), `lint` (ShellCheck), `check-executable`
(fails if any tracked `*.sh` file or `bin/maops` is not mode `100755` — this
is what originally caught the release blocker recorded in
`docs/engineering-reviews/day-02.md`, finding C1), and `test` (the Bats
suite). Run `make quality` locally before pushing to reproduce CI exactly.

---

## 7. Unified `maops` CLI

`bin/maops` is a thin dispatcher, not a reimplementation. It resolves its own
location via `BASH_SOURCE[0]` (working regardless of the caller's current
directory), sources `scripts/common/bootstrap.sh` once, and then `exec`s
straight into the appropriate leaf script — so the leaf script's own exit
code becomes `maops`'s exit code, with no wrapper process left behind:

```bash
maops help | --help | -h        # global help
maops version | --version       # global version (from config.sh's PROJECT_VERSION)
maops <group> <command> [ARGS]  # e.g. maops system info, maops network ping example.com 4
```

Dispatch table (`bin/maops`'s `dispatch_<group>()` functions):

| Group | Command | Target |
|---|---|---|
| `system` | `info` / `os` / `hostname` | `scripts/system/{system-info,os-details,hostname-report}.sh` |
| `monitoring` | `memory` / `cpu` / `load` | `scripts/monitoring/{memory-report,cpu-monitor,load-average}.sh` |
| `filesystem` | `disk` / `largest` / `temp` | `scripts/filesystem/{disk-usage,largest-files,cleanup-temp}.sh` |
| `network` | `info` / `ping` / `dns` / `port` | `scripts/network/{network-info,ping-check,dns-lookup,port-check}.sh` |
| `user` | `report` | `scripts/users/user-report.sh` |
| `process` | `top` | `scripts/process/process-monitor.sh` |
| `service` | `status` | `scripts/service/service-status.sh` |

`user`, `process`, and `service` each have exactly one command today, but
they still get their own `dispatch_<group>()` function rather than an inline
`exec` in `main()`. `main()`'s group-match case arm calls `"dispatch_$group"
"$@"` generically for every known group name — that dynamic dispatch is the
whole mechanism, not per-group special-casing, so giving a single-command
group its own function keeps every group uniform instead of forking `main()`
into two different dispatch styles.

**Exit-code split**: `maops` itself only ever returns exit code `2` for its
*own* usage errors — no command given, an unknown group, or an unknown
command within a known group. It never pre-validates a leaf script's own
positional arguments (e.g. a missing `HOST` for `maops network ping`); that
stays each leaf script's responsibility, which is what keeps the dispatcher
"thin" rather than duplicating validation logic that already lives in the
leaf scripts. `--help`/`--version` recognition and version output route
through `scripts/common/cli.sh` (`is_help_flag`, `is_version_flag`,
`cli_show_version`). `maops` never uses `eval`.

---

## 8. Network Module

`scripts/network/` follows the same shared-library convention as every other
module, adapted from `templates/script-template.sh` with one change: the
template's `parse_args()` rejects all positional arguments, but every network
script needs at least one (`HOST`, `HOSTNAME`, or `HOST PORT`), so each
script's `parse_args()` collects non-flag arguments into a local
`positional=()` array instead of rejecting them outright.

| Script | Tool(s) used | Why |
|---|---|---|
| `network-info.sh` | `ip -brief link/addr show`, `ip route show default`, `/etc/resolv.conf` | `ip` (iproute2) is the standard modern Linux networking tool; `/etc/resolv.conf` is read defensively (`log_warn`, not a hard failure) since systemd-resolved stub files and absent files are both common |
| `ping-check.sh` | `ping -c COUNT -W $DEFAULT_TIMEOUT` | `$DEFAULT_TIMEOUT` (from `config.sh`, previously defined but unused) bounds the per-packet wait so a ping against an unreachable host can't hang indefinitely. `ping` is run as the last statement in `main()` with no wrapping `if`/`&&`, so under `set -euo pipefail` its own exit status becomes the script's exit status directly — satisfying "return the ping command's real status" without manual exit-code plumbing |
| `dns-lookup.sh` | `getent hosts` | A single, always-present glibc NSS tool, chosen over a `dig`/`host`/`nslookup` fallback chain (none of which are installed by default) — simpler and equally standard |
| `port-check.sh` | bash's `/dev/tcp/HOST/PORT` + the `timeout` coreutil | Avoids a hard dependency on `nc`/`ncat` (not guaranteed installed); both `/dev/tcp` (bash builtin) and `timeout` (coreutils) are already available everywhere this toolkit runs |

All four validate their arguments via `scripts/common/cli.sh` before doing
any I/O (`validate_positive_integer` for `COUNT`/`TIMEOUT`, `validate_tcp_port`
for `PORT`), so invalid input is rejected with exit code `2` before any
network activity is attempted — this is also why the Bats suite (§9) can
cover invalid-input rejection without needing internet access.

**`PORT` and `TIMEOUT` are validated; `HOST` intentionally is not** — a
hostname or IP address has no single safe regex without also rejecting valid
IPv6 literals, so `port-check.sh` instead makes `HOST`'s content harmless by
construction (see below) rather than trying to validate its shape, the same
approach `ping-check.sh` and `dns-lookup.sh` already took by passing `HOST`
straight through to `ping`/`getent` as a normal argument.

`port-check.sh`'s TCP connect check runs the redirection inside a nested
`bash -c`, because `timeout` needs a command to bound, not a bare shell
redirection:

```bash
timeout "$TIMEOUT" bash -c 'exec 3<>"/dev/tcp/$1/$2"' bash "$HOST" "$PORT" 2>/dev/null
```

`$HOST`/`$PORT` are passed as the *inner* `bash -c`'s own positional
parameters (`$1`/`$2`), and the script text itself (`'exec 3<>"/dev/tcp/$1/$2"'`)
is a fixed, single-quoted literal — so nothing from `$HOST` is ever
interpolated into a string that gets re-parsed as shell syntax; it is only
ever substituted as a value inside a redirection target. This replaced an
earlier version that built the inner command by string interpolation
(`bash -c "exec 3<>/dev/tcp/$HOST/$PORT"`), which let a `HOST` value
containing shell metacharacters execute as an arbitrary command in the child
shell — a command-injection vulnerability found and fixed during the Day 3
release-readiness review, before any tag was cut. See
[best-practices.md §11](best-practices.md#11-parameterized-bash--c-instead-of-string-interpolation)
for the general convention this establishes, and
[troubleshooting.md §12](troubleshooting.md#12-why-port-checksh-uses-bash--c-with-1-2-instead-of-host-directly)
for the failure mode this prevents.

---

## 9. User, Process, and Service Modules

These three modules are strictly read-only: none of them ever starts, stops,
restarts, reloads, enables, disables, kills, or renices anything. Each
follows the same `parse_args()`/`main()` shape established by the network
module (§8), adapted from `templates/script-template.sh`.

| Script | Tool(s) used | Why |
|---|---|---|
| `users/user-report.sh` | `getent passwd`, `id -gn`/`id -nG`, `who` | `getent passwd` returns both existence and every passwd(5) field in one call — a nonexistent user is a normal non-zero exit, not a special case. Group *names* (as opposed to the numeric GID already in the passwd entry) need `id`, since passwd only stores the numeric primary GID. Session presence is derived from `who`'s output with a fixed, single-quoted `awk` program (`awk -v user="$target" '$1 == user {...}'`) — the target username enters only as an `awk` variable value, never string-interpolated into the program, so a crafted username cannot inject `awk` code (e.g. via `system(...)`) |
| `process/process-monitor.sh` | `ps -eo pid,user,pcpu,pmem,etime,comm --sort=...` | `comm` (executable name only) is used instead of `args` (full command line) so process secrets — `--password=...`, tokens, connection strings routinely visible on a full command line — are never printed. `--sort=-pcpu`/`--sort=-pmem` is chosen by a fixed `case` statement after `SORT` passes `validate_one_of`, so user input is never spliced into the sort flag itself |
| `service/service-status.sh` | `systemctl show` **or** `service STATUS` | See detection strategy below |

**Password/shadow disclosure is closed off structurally, not by convention**:
`user-report.sh` reads the passwd password-placeholder field into `_` and
never prints it, and never calls `getent shadow` or reads `/etc/shadow` — so
there is no code path through which a password hash could reach the output,
regardless of caller privilege.

**No `head`-truncation in `process-monitor.sh`**: row-limiting happens via
`ps ... | awk -v limit="$LIMIT" 'NR <= limit + 1'`, not `ps ... | head -n
"$LIMIT"`. This is the same fix already applied to `largest-files.sh` (§4) —
`head` closing its read end as soon as it has enough lines sends the
upstream process a `SIGPIPE`, which turns the pipeline's exit status into
`141` under `set -o pipefail`. `awk` always reads its input to EOF, so `ps`
exits normally regardless of how large `LIMIT` is relative to the real
process count.

**Service-manager detection** (`service-status.sh`): a Linux host can have
the `systemctl` *binary* installed without systemd actually being the running
init system — true of most containers and of WSL. Checking `command -v
systemctl` alone would wrongly select the systemd path there and then fail
with a bus-connection error. The script instead checks whether
`/run/systemd/system` exists — the same probe systemd's own `sd_booted(3)`
function uses to mean "systemd is genuinely running" — and only takes the
`systemctl` path when that directory is present:

```bash
readonly SYSTEMD_RUNTIME_DIR="${MAOPS_SYSTEMD_RUNTIME_DIR:-/run/systemd/system}"
systemd_is_running() {
    command_exists systemctl && [[ -d "$SYSTEMD_RUNTIME_DIR" ]]
}
```

`MAOPS_SYSTEMD_RUNTIME_DIR` is a documented, read-only test seam: it only
selects which status query the script runs, so it cannot cause a mutation.
It exists because a real systemd host (including this project's CI runner)
can never otherwise exercise the `service(8)` fallback branch, and a plain
container can never otherwise exercise the `systemctl` branch — see
[best-practices.md §13](best-practices.md#13-service-manager-detection-and-fallback).

`systemctl show --property=LoadState,ActiveState,SubState`, not `systemctl
is-active`, is used to query state: `show` exits `0` in every normal case,
including a unit that does not exist (`LoadState=not-found`), so a non-zero
exit unambiguously means `systemctl` itself failed (bus error, permission
issue) rather than "the service is in some particular state." That failure
is surfaced as exit `1` with the captured error text, never silently mapped
to "inactive." The `service(8)` fallback instead relies purely on the LSB
init-script exit-code convention (`0` running, `3` stopped, `4` unknown) —
the free-form status text is only ever echoed for the operator, never
pattern-matched, since wording varies across distributions and init
scripts.

Full exit-code mapping:

| Exit | Meaning |
|---|---|
| `0` | Service is active/running |
| `1` | Inactive, stopped, unknown/not-found, no supported service manager available, or the status lookup itself failed |
| `2` | CLI usage error (missing `SERVICE`, option-like `SERVICE`) |

Neither `user-report.sh`, `process-monitor.sh`, nor `service-status.sh` ever
uses `eval` or interpolates a user-supplied value into a string that gets
re-parsed as shell syntax (the same command-injection class fixed in
`port-check.sh`, §8) — `USERNAME`/`SERVICE`/`LIMIT` are always passed as
normal argv elements or `awk -v` values.

---

## 10. Tests

`tests/` holds the Bats suite (`tests/test-helper.bash` plus `tests/cli/`,
`tests/common/`, `tests/network/`, `tests/users/`, `tests/process/`,
`tests/service/`). It is intentionally excluded from `bash -n`/ShellCheck
(`.bats` files aren't plain Bash) and instead run via `make test`, which is
itself one stage of `make quality`. No test depends on real internet
access — invalid-input tests are rejected before any network call is made,
and the one optional network-adjacent check stays on loopback.

The user, process, and service test files additionally depend on
deterministic PATH-based command stubs, since real `getent`/`id`/`who`/`ps`/
`systemctl`/`service` output varies by host, session state, and init system.
`tests/test-helper.bash` provides `stub_bin_init` (creates a fresh stub
directory under `$BATS_TEST_TMPDIR` and prepends it to `$PATH`) and
`stub_command NAME <<'STUB' ... STUB` (writes an executable fake `NAME` into
that directory from a heredoc body). Stubs are generated per-test rather than
checked into the repository as static files, because a checked-in stub must
be named exactly `systemctl`/`ps`/etc. (no `.sh` suffix) to be found via
`$PATH` lookup — which would put it outside `make check-executable`'s
`*.sh`/`bin/maops` glob and could silently reintroduce the WSL/drvfs
executable-mode gotcha recorded in
[troubleshooting.md §4](troubleshooting.md#4-wsl-and-windows-git-executable-mode-behavior).
See
[best-practices.md §14](best-practices.md#14-deterministic-path-based-test-stubs)
for the full convention and its guardrails.
