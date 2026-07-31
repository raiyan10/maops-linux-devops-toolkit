# Changelog

All notable changes to the MAOps Linux DevOps Toolkit are documented here.

The project follows Semantic Versioning.

## [0.3.0] - 2026-07-31

### Added

- User module (`scripts/users/user-report.sh`): read-only account report via `getent passwd`, `id -gn`/`id -nG`, and `who` — username, UID, primary GID, home directory, login shell, group memberships, and whether the target user currently has a logged-in session. USERNAME is optional and defaults to the current effective user (`id -un`). The passwd password field is read and immediately discarded; the script never calls `getent shadow` and never reads `/etc/shadow`, so no password hash is ever handled, let alone printed.
- Process module (`scripts/process/process-monitor.sh`): read-only top-N process report via `ps -eo pid,user,pcpu,pmem,etime,comm`, sorted by CPU (default) or memory. `comm` (executable name) is used instead of `args` (full command line) so secrets sometimes passed on a command line, such as `--password=...`, are never exposed. Row truncation happens in `awk`, not by piping into `head`, for the same reason `largest-files.sh` was fixed in 0.1.0 — `head` closing its read end early sends the producer a `SIGPIPE`, turning the pipeline's exit status into 141 under `pipefail`.
- Service module (`scripts/service/service-status.sh`): read-only service state inspection. Prefers `systemctl show --property=LoadState,ActiveState,SubState` when systemd is genuinely the running init system (detected via `/run/systemd/system`, the same probe systemd's own `sd_booted(3)` uses — more reliable than checking whether the `systemctl` binary merely exists, which is misleading in containers/WSL where the binary is present but systemd is not PID 1), and falls back to `service SERVICE status` (interpreted via LSB init-script exit codes: 0 running, 3 stopped, 4 unknown) otherwise. `systemctl show` is used instead of `systemctl is-active` because `show` exits 0 in every normal case including "unit not found," so any non-zero exit unambiguously means `systemctl` itself failed (bus error, permission issue) and is surfaced as a failure rather than silently mapped to "inactive." A new environment variable, `MAOPS_SYSTEMD_RUNTIME_DIR` (default `/run/systemd/system`), is a documented, read-only test seam that lets tests select either branch deterministically; it cannot cause a mutation, and the script never runs `start`, `stop`, `restart`, `reload`, `enable`, `disable`, `eval`, or a re-parsed shell string.
- Three new `maops` CLI routes: `maops user report [USERNAME]`, `maops process top [LIMIT] [cpu|memory]`, `maops service status SERVICE`, each wired into `bin/maops` with its own `dispatch_*` function following the existing group-dispatch pattern.
- Shared CLI validators in `scripts/common/cli.sh`: `is_non_option_argument`/`validate_non_option_argument` (rejects an empty value or one starting with `-`; used by USERNAME and SERVICE) and `is_one_of`/`validate_one_of` (generic allow-listed-value validator in the same family as `is_positive_integer`/`is_valid_port`; used today by process-monitor's `cpu|memory` SORT argument).
- A deterministic PATH-based command-stub convention for tests (`stub_bin_init`/`stub_command` in `tests/test-helper.bash`): a test-scoped stub directory generated fresh into `$BATS_TEST_TMPDIR` and prepended to `$PATH`, used to fake `getent`, `id`, `who`, `ps`, `systemctl`, and `service` so results never depend on the host's real accounts, process list, logged-in sessions, or init system.
- Bats coverage: `tests/users/user-report.bats`, `tests/process/process-monitor.bats`, `tests/service/service-status.bats`, plus new dispatch-route tests in `tests/cli/maops.bats` and validator tests in `tests/common/helpers.bats` — including command-injection and option-injection regression tests for USERNAME, SERVICE, and LIMIT.

### Changed

- `bin/maops`: `usage()` now lists the `user`, `process`, and `service` groups and includes them in the unknown-group error message.
- `scripts/common/config.sh`: `PROJECT_VERSION` bumped to `0.3.0`.
- `tests/cli/maops.bats`: the two version-string assertions updated from `0.2.0` to `0.3.0`.

## [0.2.0] - 2026-07-30

### Added

- Unified `maops` CLI (`bin/maops`) dispatching to the existing system, monitoring, and filesystem utilities, plus a new network module
- Shared CLI support library (`scripts/common/cli.sh`): version output, help/version flag recognition, usage-error handling, positive-integer validation, TCP port validation
- Network module (`scripts/network/`): network information, ping checker, DNS lookup, TCP port checker
- Bats test suite (`tests/`) covering the CLI dispatcher, shared CLI validation helpers, and network utilities
- `make test` runs the Bats suite; `make cli-help` runs `bin/maops --help`

### Changed

- `Makefile`: `quality` now includes the Bats test suite; `validate`/`lint`/`check-executable` cover `bin/` in addition to `scripts/` and `templates/`; `run` now invokes `bin/maops system info`
- `.github/workflows/bash-validation.yml`: installs Bats alongside ShellCheck and runs `make quality` instead of duplicating each check inline
- `scripts/common/config.sh`: `PROJECT_VERSION` bumped to `0.2.0`

### Fixed

- **Security:** `scripts/network/port-check.sh` built its TCP-connect check as `bash -c "exec 3<>/dev/tcp/$HOST/$PORT"`, interpolating the unvalidated `HOST` argument directly into a string re-parsed as shell code by the inner `bash` — any shell metacharacter in `HOST` executed as an arbitrary command. Fixed by passing `HOST`/`PORT` as the inner `bash -c`'s own positional parameters (`bash -c 'exec 3<>"/dev/tcp/$1/$2"' bash "$HOST" "$PORT"`) instead of string interpolation, so `HOST`'s content is only ever substituted as a value, never re-parsed as command syntax. Found and fixed as part of the Day 3 release-readiness review before any tag was cut; `ping-check.sh` and `dns-lookup.sh` were checked and were never vulnerable to this class of bug, since both pass `HOST`/`TARGET` as a normal argument to `ping`/`getent` rather than through a re-parsed shell string.
- `ping-check.sh`/`port-check.sh`: a negative numeric argument (e.g. `-1` for `COUNT`, `PORT`, or `TIMEOUT`) was previously caught by the generic unknown-flag branch and reported as `Unknown option: -1`, even though the exit code (`2`) was already correct. Both scripts now recognize a leading-dash argument that looks like a negative number and route it to the existing positive-integer/port validators, which report it with a specific, accurate message (e.g. `COUNT must be a positive integer: -1`).
- `CONTRIBUTING.md`: added Bats to the "Required tools" list — `make test`/`make quality` have required it since this release, but the list was never updated.

## [0.1.0] - 2026-07-30

### Added

- Reusable Bash bootstrap framework
- Centralized color, configuration, logging, helper, and output libraries
- System information utilities
- Operating-system details utility
- Hostname reporting utility
- CPU, memory, and load-average monitoring utilities
- Disk-usage reporting utility
- Largest-files reporting utility
- Safe temporary-file dry-run scanner
- Reusable Bash script template
- ShellCheck and Bash syntax validation
- GitHub Actions Bash validation workflow
- Claude Code project guidance
- Project-specific Claude Code Skills
- Initial engineering documentation and review process

### Fixed

- Duplicate sourcing of readonly color variables
- `largest-files.sh` SIGPIPE failure under `pipefail`
- Empty temporary-file output
- Missing strict Bash mode in filesystem utilities
- Git executable modes for shell files