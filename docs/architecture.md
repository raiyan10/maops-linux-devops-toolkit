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
├── .github/workflows    # CI: make release-check (quality, package, verify-package, smoke-install)
├── bin                  # maops — unified CLI dispatcher
├── docs                 # This documentation set, plus engineering reviews
├── scripts
│   ├── common           # Shared library — no script in the other folders is
│   │                    # meant to duplicate what lives here
│   ├── config           # `maops config` subcommands (path/init/show/validate)
│   ├── diagnostics      # `maops doctor` environment/health check
│   ├── filesystem       # Disk usage, largest files, temp-file scanning
│   ├── install          # User-local install/uninstall (staged, manifest-based)
│   ├── monitoring       # CPU, memory, load-average reporting
│   ├── network          # Network info, ping, DNS lookup, port checking
│   ├── process          # Read-only top-N process reporting
│   ├── release          # Release packaging and archive verification
│   ├── service          # Read-only service status inspection
│   ├── system           # Host identity and OS reporting
│   └── users            # Read-only user account reporting
├── templates            # Boilerplate for generating new scripts/docs/workflows
├── tests                # Bats test suite
├── dist                 # Generated release artifacts (gitignored, not tracked)
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
`main`, plus `workflow_dispatch`, with `permissions: contents: read` (no
write permissions, no release/publish permissions). It checks out the
repository via `actions/checkout` **pinned to a full 40-character commit
SHA** (`de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2`) rather than a
mutable tag like `@v4` — a tag can be re-pointed by the action's maintainer
(or, in a compromise scenario, an attacker) to different code without the
workflow file itself changing, whereas a commit SHA is immutable. A dedicated
static regression test, `tests/workflows/actions-pinning.bats`, greps every
`.github/workflows/*.yml` file and fails if any external (`uses:`, not
`./`-prefixed) action reference is ever a tag or branch instead of a full SHA
— catching a future accidental un-pin, not just today's.

The job installs `shellcheck`, `bats`, and `python3` on the `ubuntu-latest`
runner, then runs a single command: **`make release-check`** — CI and local
development run the exact same command, so nothing can pass locally and
still fail in CI (or vice versa) due to divergent logic. `make release-check`
chains, in order: `quality` (`validate` → `lint` → `check-executable` → the
full Bats suite), `package`, `verify-package`, and `smoke-install` (§11, §15,
§16). `HOME` is overridden to a runner-scoped temporary directory for the
entire `make release-check` step, so nothing in it — including the
smoke-install's install/doctor/integrity/uninstall cycle, which itself uses
its own `mktemp -d` prefix — can ever touch the runner's real home. None of
these steps publish or upload anything, so no separate pull-request-vs-push
conditional is needed.

---

## 7. Unified `maops` CLI

`bin/maops` is a thin dispatcher, not a reimplementation. It resolves its own
location via `BASH_SOURCE[0]` (working regardless of the caller's current
directory), sources `scripts/common/bootstrap.sh` once, and then `exec`s
straight into the appropriate leaf script — so the leaf script's own exit
code becomes `maops`'s exit code, with no wrapper process left behind:

**Symlink resolution.** Once installed (§11), `PREFIX/bin/maops` is a
relative symlink to `../lib/maops/bin/maops`. A plain
`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` resolves the
*symlink's own* directory, not its target's — which would silently break
every `exec "$REPO_ROOT/scripts/..."` dispatch once installed. `bin/maops`
instead resolves its real path first, via a small bounded manual loop:

```bash
resolve_script_path() {
    local target="${BASH_SOURCE[0]}"
    local dir hops=0
    while [[ -L "$target" ]]; do
        hops=$((hops + 1))
        ((hops > 40)) && { echo "too many levels of symbolic links" >&2; exit 1; }
        dir="$(cd "$(dirname "$target")" && pwd)"
        target="$(readlink "$target")"
        [[ "$target" != /* ]] && target="$dir/$target"
    done
    cd "$(dirname "$target")" && pwd
}
```

This deliberately avoids `readlink -f`/`realpath`: neither is a required
runtime command (§14), and a manual bounded loop needs only `readlink`
itself, which is already universally available. A non-symlink invocation
(running directly from the source tree) never enters the `while [[ -L ]]`
loop body, so this is a pure addition with no behavior change for the
existing source-tree case.

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
| `config` | `path` / `init` / `show` / `validate` | `scripts/config/config-manager.sh` |
| `doctor` | *(no sub-action)* | `scripts/diagnostics/doctor.sh` |

`user`, `process`, and `service` each have exactly one command today, but
they still get their own `dispatch_<group>()` function rather than an inline
`exec` in `main()`. `main()`'s group-match case arm calls `"dispatch_$group"
"$@"` generically for every known group name — that dynamic dispatch is the
whole mechanism, not per-group special-casing, so giving a single-command
group its own function keeps every group uniform instead of forking `main()`
into two different dispatch styles.

`config` and `doctor` are dispatched slightly differently: both get their own
`dispatch_config`/`dispatch_doctor` function and their own `case` arm in
`main()`, but neither goes through the generic `"dispatch_$group" "$@"` path
the other seven groups share, and neither gets the "missing command for
group" pre-check that arm performs. `doctor` takes no sub-action at all
(only flags), and `config`'s own subcommand validation is owned entirely by
`config-manager.sh` — `bin/maops` stays a pure passthrough
(`exec "$REPO_ROOT/scripts/config/config-manager.sh" "$@"` /
`exec "$REPO_ROOT/scripts/diagnostics/doctor.sh" "$@"`) rather than
duplicating validation logic the leaf script already owns.

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
`tests/service/`, `tests/system/`, `tests/monitoring/`, `tests/filesystem/`,
`tests/diagnostics/`, `tests/install/`, `tests/release/`,
`tests/workflows/`). It is intentionally excluded from `bash -n`/ShellCheck
(`.bats` files aren't plain Bash) and instead run via `make test`, which is
itself one stage of `make quality`. No test depends on real internet
access — invalid-input tests are rejected before any network call is made,
and the one optional network-adjacent check stays on loopback.

`tests/test-helper.bash` also provides `build_drvfs_clone_fixture` (a plain
filesystem copy of the repository — not `git clone`, so any change currently
staged-but-uncommitted in the working tree/index is carried over exactly —
with every path forced to `chmod 0777` afterward) so mode-normalization
tests can deterministically reproduce the WSL/drvfs `0777`-observed-
permission symptom on any host, including a normal CI runner, without
needing an actual drvfs mount; and `craft_tar_with_member` (built on
Python's stdlib `tarfile` module — the same module `verify-package.sh` uses
to inspect real archives) for constructing crafted symlink/hardlink/device/
FIFO archive-attack fixtures.

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

---

## 11. Installation and Runtime Layout

`scripts/install/install.sh`/`uninstall.sh` install the toolkit into a
**user-local prefix** — `$HOME/.local` by default, never system-wide, never
`sudo` — as:

```text
PREFIX/bin/maops                  -> ../lib/maops/bin/maops   (relative symlink)
PREFIX/lib/maops/bin/maops
PREFIX/lib/maops/scripts/
PREFIX/lib/maops/LICENSE
PREFIX/lib/maops/CHANGELOG.md
PREFIX/lib/maops/.install-manifest
PREFIX/lib/maops/.integrity-manifest
```

**Shared file list.** Both `install.sh` and `scripts/release/package.sh`
(§15) copy from the exact same array, `scripts/common/release-files.sh`'s
`RELEASE_FILE_LIST` (`bin/maops`, `scripts/`, `templates/script-template.sh`,
`README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`, `Makefile`,
`.gitattributes`), so the installed tree and the released tarball can never
drift apart.

**Two install sources, two mode authorities.** `install_detect_source_mode`
looks at `REPO_ROOT` (install.sh's own resolved location, same trick as
`bin/maops`, §7) and picks exactly one of two modes, refusing outright if
both or neither apply:

- **Git checkout** (`.git` present): every file's filesystem mode is derived
  from Git's own index (`git ls-files -s`; `100644` → `0644`, `100755` →
  `0755`) via the shared `integrity_copy_git_tracked` helper in
  `scripts/common/integrity.sh` — the *same* helper `package.sh` uses (§15),
  so the two can never disagree about what a correct mode is. This is
  deliberate: on a filesystem such as WSL/drvfs, `stat` reports `0777` for
  every tracked file regardless of Git's real index mode, so trusting the
  source tree's own `stat` (the old behavior, via `cp -a`) could silently
  ship world-writable installed files. `cp -a` is not used anywhere in this
  path; every copy is a plain `cp` followed by an explicit,
  self-verifying `chmod` (`integrity_chmod_verified`, which re-reads the
  mode back via `stat` and aborts loudly if the destination filesystem
  silently ignored the change, rather than allowing an install that only
  looks correct).
- **Extracted release archive** (`MAOPS-MANIFEST.tsv` present, no `.git`):
  every entry in the manifest is verified — source file exists, real
  SHA-256 matches — *before* anything is copied, and modes are applied from
  the manifest's `MODE` field, never re-derived from the extracted files'
  own `stat`. A single bad entry means the install refuses entirely; nothing
  partial is ever written to `LIB_DIR`.

**Staged, then swapped atomically.** The runtime tree is built in a
`mktemp -d` staging directory created *under `PREFIX/lib`* — the same
filesystem as the final destination, so the swap into place is a same-
filesystem `mv` (a rename) rather than a cross-device copy-then-unlink. (If
`PREFIX` itself sits on a filesystem that silently ignores `chmod`, the
self-verifying `chmod` above surfaces that as a loud install failure rather
than a silently-broken install — see §15 for why `package.sh`'s own staging
directory, unlike this one, was moved *off* the repository tree instead.) On
an upgrade, the previous tree is renamed aside, the staging directory is
renamed into place, and only then is the previous tree removed — bounding
the "no working install" window to two rename syscalls rather than the
whole copy.

**Install manifest** (`.install-manifest`): a header (`MAOPS_INSTALL_VERSION`,
`MAOPS_INSTALL_PREFIX`, `MAOPS_INSTALL_DATE`) followed by `--- files ---` and
one absolute installed path per line. It is parsed with a plain `read -r`
loop, never sourced or eval'd. `uninstall.sh` treats the manifest as the
sole authority for what it's allowed to remove:

- No manifest at the resolved prefix → nothing to do, exit `0` (idempotent).
- The manifest's recorded prefix must match the resolved `--prefix` exactly,
  or uninstall refuses outright — this is what stops uninstall from acting
  on a manifest copied from elsewhere or a prefix that merely happens to
  contain a `lib/maops` directory.
- A read-only `validate_manifest_files` pass runs over every manifest entry
  **before** any file is removed, scoped to `LIB_DIR` specifically — not
  merely `PREFIX`, since a shared prefix like `$HOME/.local` commonly hosts
  other tools' files under sibling directories such as `PREFIX/bin` or
  `PREFIX/share`, which a `PREFIX`-scoped guard could still reach. Any entry
  that is empty, outside `LIB_DIR`, contains a `..` traversal component
  (checked component-by-component, not a substring match), or duplicates an
  earlier entry fails the *entire* manifest closed — zero files are removed,
  not just the offending one. Only after validation passes does
  `remove_files` run its simple existence-check-then-`rm -f --` loop. There
  is no `rm -rf` on the prefix itself, or on any directory derived from raw
  user input — only `rm -f --` on individually-validated manifest-listed
  files, then `rmdir --` on now-empty directories in reverse-depth order
  (via `find -depth`, which visits a directory's contents before the
  directory itself).

This is a distinct manifest from `.integrity-manifest` (below) — the two
have different responsibilities (what to *remove* vs. what to *verify*) and
are never merged into one file.

**`.integrity-manifest`**: a `MODE<TAB>SHA256<TAB>RELATIVE_PATH` file, in the
same format as the release archive's internal `MAOPS-MANIFEST.tsv` (§15),
written into `LIB_DIR` by whichever install mode ran (regenerated from Git's
index in Git-checkout mode; copied from the verified package manifest in
archive mode). It exists purely so `maops integrity` (§16) can later verify
the installed tree independently of whatever installed it. It is not
consulted by `uninstall.sh`.

**Safety guards, with no override:**

- An unrelated regular file (or a symlink pointing elsewhere) found at
  `PREFIX/bin/maops` is never overwritten — **`--force` does not override
  this refusal.** `--force` only ever permits replacing a *verified* prior
  MAOps install (an existing, prefix-matching manifest).
- Empty prefix or the resolved filesystem root (`/`) is rejected with exit
  `2`, checked *after* canonicalization (`cd ... && pwd -P`) so a symlink
  pointing at `/` can't slip past a naive string comparison of the raw
  argument.
- Uninstall requires `--yes` for non-interactive removal, or an interactive
  `y`/`N` confirmation.
- Configuration (§12) lives at `${XDG_CONFIG_HOME:-$HOME/.config}/maops`,
  structurally outside `PREFIX` — it is preserved automatically by both
  install and uninstall, since nothing under `PREFIX` ever references it.
  `--purge-config` is the one explicit, separate code path that touches it.
- Every mutating command (`mkdir -p --`, `mv --`, `ln -sfn --`, `rm -f --`)
  quotes its path arguments and uses a `--` end-of-options marker, so a
  prefix value starting with `-` (or containing spaces or shell
  metacharacters) is always treated as a literal path, never as a flag or
  re-parsed shell syntax. Neither script uses `eval` or `bash -c` with an
  interpolated path anywhere.

**Execution-mode detection** (used by `doctor`, §14): a script under
`scripts/` checks for `.install-manifest` alongside its own resolved repo
root — present means "installed," absent means "running from a source
checkout." This is a read-only presence check, not a mutation.

See `tests/install/install.bats` for the regression coverage of every guard
above, and `.claude/agents/release-engineer.md`'s review focus for the
threat model this design was checked against.

---

## 12. Configuration System

`scripts/common/config-file.sh` implements parsing, validation, precedence
resolution, and atomic writes for a plain-text config file at:

```text
${MAOPS_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/maops/config}
```

Supported keys: `output_format` (`text`/`json`), `process_limit`,
`ping_count`, `network_timeout` (the latter three: positive integers).

**Never sourced or eval'd.** The file is read exclusively via a
`while IFS= read -r line` loop; one regex
(`^([a-z_][a-z0-9_]*)[[:space:]]*=(.*)$`) both classifies a line (`blank` /
`comment` / `kv` / `malformed`) and extracts its key/value via
`BASH_REMATCH`, so there is no risk of a separate classifier and extractor
disagreeing. Per-key value validation reuses `scripts/common/cli.sh`'s
existing `is_one_of` (for `output_format`) and `is_positive_integer` (for the
three numeric keys) rather than duplicating regex logic. Because the file is
never sourced, a value containing command substitution or shell
metacharacters (e.g. `process_limit=$(rm -rf /)`) is inert text that simply
fails the positive-integer regex — it is never at any point handed to
anything that would expand it.

`config validate` (strict mode) rejects unknown keys, duplicate keys, and
malformed lines outright. `config_load` (used internally by the precedence
resolver below) is deliberately more permissive — it silently skips a bad
line rather than crashing a leaf script over a stray line in the user's
config file, on the principle that `config validate` is the dedicated place
to be strict.

**Precedence resolution** is implemented exactly once, as
`config_resolve_value KEY CLI_VALUE ENV_VAR_NAME DEFAULT`:

```text
explicit CLI argument  >  MAOPS_* environment variable  >  config file  >  built-in default
```

Every consumer — `config show`, `doctor`, and the three leaf scripts below —
calls this same function, so precedence logic cannot drift between call
sites. `process-monitor.sh`'s default `LIMIT`, `ping-check.sh`'s default
`COUNT`, and `port-check.sh`'s default `TIMEOUT` each changed from a bare
`readonly DEFAULT_*` fallback to
`"${positional[0]:-$(config_resolve_value ... "$DEFAULT_*")}"` — the
explicit positional argument, when given, is checked first and always wins;
the resolver is only ever consulted as the fallback value.

**Atomic writes.** `config_write_atomic` creates a temp file with `mktemp`
in the *same directory* as the target (guaranteeing a same-filesystem,
atomic `mv`), then renames it into place. `config init` sets `umask 077`
before calling it and refuses to overwrite an existing file without
`--force`.

**CLI routes** (`scripts/config/config-manager.sh`, dispatched as
`maops config <subcommand>`): `path` (prints the resolved path), `init
[--force]`, `show [--format text|json]`, `validate [PATH]` (0 valid / 1
invalid; a missing PATH is also 1, since it's a problem with the config
*content* being pointed at, not the command's own argument shape — argument-
shape errors, like an invalid `--format` value, are exit `2`).

---

## 13. Structured Output (JSON) Scope

`scripts/common/format.sh` provides `json_escape` (backslash → quote → tab →
carriage-return → newline, in that order — backslashes first, or the later
substitutions would double-escape the backslashes they themselves introduce),
`json_kv KEY VALUE [--raw]`, and a flat-object convenience wrapper,
`json_object`. No `eval`, no runtime `jq` dependency — JSON is assembled
entirely through `printf` and parameter expansion.

**Scope for v0.4.0 is deliberately narrow**: only `maops config show
--format json` and `maops doctor --format json` produce JSON. No other leaf
command gained a `--format` flag in this release. Both commands print
exactly one JSON document per invocation and skip `log_info`/`show_header`
entirely in JSON mode, so there is never a stray line before or after the
document — a hard requirement for piping into `python3 -m json.tool` or a
downstream `jq`/monitoring consumer.

`doctor`'s JSON shape composes an array of check objects by hand (joining
several `json_kv`-built fragments with `,` and wrapping in `[...]`) rather
than extending `format.sh` with array/nesting support nobody else needs yet —
`format.sh` itself stays a small, trivially-testable set of string-escaping
and flat-object primitives.

---

## 14. Doctor Command

`scripts/diagnostics/doctor.sh` (`maops doctor [--format text|json]`) runs a
fixed set of checks, each contributing to the overall exit code only if
marked required:

| Check | Required? |
|---|---|
| Toolkit version, execution mode, config path | info only |
| Operating system is Linux | required |
| Bash version ≥ 4 | required |
| Config file exists | **warning only** — normal on a fresh install/checkout |
| Config file is valid (only evaluated if it exists) | required if present-but-invalid |
| Required runtime commands: `bash awk find sort ps getent ip ping timeout df free lscpu uptime` | required, one check per command |
| Service manager: `systemctl` **or** `service` | required (either/or — mirrors `service-status.sh`'s own systemd-vs-fallback detection, §9; not both hard-required) |
| Optional dev tools: `git make shellcheck bats python3` | **warning only**, never fails |

Every check resolves commands via `command -v` (`command_exists`, from
`helpers.sh`) only — doctor never actually invokes `ping`, `ip`, `timeout`,
or any other roster command against a real target, so it makes no network
requests and never modifies the system. `main()` builds the complete check
list first, prints exactly once (text or a single JSON document), and only
then computes the exit code — so a required failure can never truncate the
JSON document mid-stream; a failing check is just another array element with
`"status":"fail"`.

Exit `1` only if a **required** check fails; exit `0` otherwise. Missing
optional dev tools and a missing (as opposed to invalid) config file are
always warnings.

---

## 15. Packaging and Release Verification

`scripts/release/package.sh` builds `dist/maops-linux-devops-toolkit-<version>.tar.gz`
and a sibling `.sha256` checksum from the current git checkout:

- Copies exactly `scripts/common/release-files.sh`'s `RELEASE_FILE_LIST`
  (the same list `install.sh` uses, §11) into a staging directory, via the
  shared `integrity_copy_git_tracked` helper (`scripts/common/integrity.sh`).
  `git ls-files -s` both expands directory entries (e.g. `scripts`) to their
  tracked files only — so a stray untracked temp or editor file is never
  silently packaged — and supplies each file's mode from Git's own index,
  never from the source filesystem's `stat`/`cp -a`. This is the fix for a
  real bug: on a filesystem such as WSL/drvfs, `stat` reports `0777` for
  every tracked file regardless of Git's real index mode, and `cp -a` (the
  old behavior) propagated that straight into the archive. Each copied
  file's mode is applied via an explicit, self-verifying `chmod`; every
  staged directory is separately normalized to `0755` in one pass at the
  end. **The staging directory itself lives under `mktemp`'s default
  location, not under `dist/`** — `dist/` is inside the repository and can
  sit on the same permission-unreliable filesystem as the checkout, whereas
  `mktemp`'s default location is reliably a plain filesystem that honors
  `chmod`. Only the final binary archive (a plain file write, no `chmod`
  needed) is ever written into `dist/`.
- While staging, also generates **`MAOPS-MANIFEST.tsv`** — one
  `MODE<TAB>SHA256<TAB>RELATIVE_PATH` line per distributed file (mode from
  Git's index, SHA-256 of the staged copy, path relative to the archive
  root), `LC_ALL=C`-sorted, written into the staging directory and so
  included in the archive. Because it's generated purely from Git-tracked
  content and is not itself committed to Git, it never lists itself. This is
  a second, independent integrity layer alongside the external `.sha256`:
  the external checksum answers "is this the exact archive bytes I was told
  to trust," the manifest answers "is every individual file inside it
  exactly what it claims to be" — a compromised archive host that manages to
  re-sign a tampered external checksum still cannot make internal manifest
  verification (below) pass.
- Builds the tarball with `tar --sort=name --mtime="@0" --owner=0 --group=0
  --numeric-owner`, piped through `gzip -n` (rather than relying on `tar -z`
  to suppress gzip's own header timestamp) — repeated builds from an
  unchanged tree are byte-for-byte identical, including when built from a
  drvfs-simulated `0777` source tree (proven by
  `tests/release/package.bats`'s `build_drvfs_clone_fixture`-based tests).
- The archive contains exactly one top-level directory,
  `maops-linux-devops-toolkit-<version>/`.
- Requires a git checkout (`git rev-parse --is-inside-work-tree`) — packaging
  is a release-time operation distinct from `install.sh`, which (§11) also
  supports installing directly from an already-extracted tarball with no
  `.git` present, using the shipped `MAOPS-MANIFEST.tsv` instead.

`scripts/release/verify-package.sh` checks, strictly in this order:

1. **Snapshot.** The archive and its `.sha256` sidecar are copied into a
   private `mktemp -d` scratch directory first (cleaned up via an `EXIT`
   trap); every check below reads only this snapshot, never the caller-
   supplied archive path again. This closes a TOCTOU window: a concurrent
   modification to the original archive after verification starts can't
   affect any check performed here.
2. **Checksum** (`sha256sum -c`, against the snapshot) — fails loudly on any
   modification. This remains the sole external authority for "is this the
   archive I was told to trust."
3. **Archive member safety, before any extraction.** Every member is
   inspected via Python's stdlib `tarfile` module — not GNU tar's own
   verbose-listing text output, which is not a documented, version-stable
   interface, and is exactly the "extracting tar implementation" this check
   must not rely on. A member is rejected if its name is absolute, contains
   a `..` component, sits outside the single expected
   `maops-linux-devops-toolkit-<version>/` root, belongs to a second
   top-level root, or is anything other than a regular file or directory —
   symlinks, hardlinks, character/block devices, and FIFOs are all refused
   outright, unconditionally (the project ships zero legitimate symlinks
   today, so there is no "validate the target" carve-out to get wrong). Any
   violation aborts before `tar -xzf` ever runs anywhere.
4. **Extraction and required paths.** Only after step 3 passes, the snapshot
   is extracted to its own `mktemp -d` scratch subdirectory and a fixed
   checklist of paths (`bin/maops`, `scripts/common/bootstrap.sh`,
   `MAOPS-MANIFEST.tsv`, `LICENSE`, `Makefile`, etc.) is confirmed present.
5. **Internal manifest verification.** `MAOPS-MANIFEST.tsv` is parsed
   (deterministically, via the same `integrity_read_manifest` shared
   function §16 uses) and every entry's existence, SHA-256 content, and mode
   are checked against the extracted tree — and the reverse direction too:
   any extracted file *not* listed in the manifest is also a failure. This
   is the check that catches content tampering a whole-archive checksum
   alone cannot distinguish from a legitimate rebuild.

Neither script uses `sudo` or `eval`; `verify-package.sh` requires `python3`
in addition to `tar`/`sha256sum` specifically for step 3 (a release-
engineering-only dependency — the installed runtime CLI's own dependency
list in `doctor.sh` is unchanged). `make release-check` (§6) chains
`quality` → `package` → `verify-package` → `smoke-install` in one command,
run in CI on every push and pull request, so a release-readiness regression
is caught immediately rather than only when a maintainer remembers to run it
locally.

---

## 16. Integrity Verification (`maops integrity`)

`scripts/diagnostics/integrity-check.sh` (routed as `maops integrity
[--format text|json]`) is a read-only, never-repairing check that answers
"does what's actually on disk match what it's supposed to be" — for either
an installed tree or a source-tree checkout. It shares its mode-detection
trick with `doctor.sh` (§14): `REPO_ROOT` resolves to `LIB_DIR` when run from
an installed copy, so a simple file-presence check distinguishes the two
modes without any separate `--prefix` flag.

- **Installed mode** (`LIB_DIR/.integrity-manifest` present): every manifest
  entry is checked in priority order — existence (`missing` on failure),
  then SHA-256 content (`modified`), then mode (`unexpected-mode`) — so each
  file contributes at most one failure. A manifest that fails to parse at
  all (malformed field count, invalid mode, non-hex/wrong-length checksum,
  an unsafe relative path, a duplicate path) is reported as
  `malformed-manifest` rather than crashing.
- **Source-tree mode** (no installed manifest, but real Git metadata):
  verifies content via `git diff --quiet` against Git's index (immune to
  the drvfs mode-confusion problem, since `core.fileMode=false` already
  makes Git itself ignore permission-bit noise for this comparison) and
  expected executable modes via `git ls-files -s` — reusing the exact rule
  `Makefile`'s `check-executable` target already encodes (`*.sh` and
  `bin/maops` must be `100755`, everything else `100644`) rather than
  reinventing it. **Working-tree `stat` is never consulted for either
  check** — this is the whole point: a WSL/drvfs checkout reporting `0777`
  on every file cannot produce a false pass or false fail here.
- Neither mode present (no `.integrity-manifest` and no Git metadata) is a
  hard failure, exit `1` — there is nothing trustworthy to verify against,
  so the script refuses to guess rather than silently reporting "healthy."

**Exit codes**: `0` every check passed; `1` any check failed, or the
manifest/Git metadata was unavailable; `2` a CLI usage error (bad `--format`
value, unknown flag) — the same three-tier convention `doctor.sh` uses.

**JSON output** (`--format json`) is one document, no `jq` dependency, no
`eval`, assembled manually via `scripts/common/format.sh`'s `json_kv`/escape
helpers exactly like `doctor.sh`'s JSON renderer:

```json
{
  "version": "0.5.0",
  "execution_mode": "installed",
  "manifest_path": "/home/user/.local/lib/maops/.integrity-manifest",
  "overall": "fail",
  "checked_count": 41,
  "passed_count": 40,
  "failed_count": 1,
  "failures": [
    {"path": "README.md", "category": "modified", "detail": "content does not match the installed manifest"}
  ]
}
```

(Source-tree mode emits `repository_root` in place of `manifest_path`.)

The shared parsing/validation/mode-normalization logic behind all of this —
`integrity_git_mode_to_perm`, `integrity_read_manifest`,
`integrity_validate_manifest_line`, `integrity_is_unsafe_relative_path`,
`integrity_copy_git_tracked`, `integrity_verify_and_copy_from_manifest`,
`integrity_sha256_file`, `integrity_chmod_verified` — lives in one place,
`scripts/common/integrity.sh`, and is deliberately free of any CLI
output/routing of its own (callers own their own logging and exit codes; on
failure this library only returns `1` and sets `INTEGRITY_LAST_ERROR` for
the caller to report). It is sourced explicitly wherever needed (`package.sh`,
`install.sh`, `uninstall.sh`, `verify-package.sh`,
`integrity-check.sh`) rather than added to `bootstrap.sh`'s fixed load order,
the same pattern already used for `release-files.sh` (§2) — most leaf
scripts never need any of this.
