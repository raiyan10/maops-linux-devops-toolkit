# Roadmap

Module-level detail behind the summary checklist in
[README.md](../README.md#roadmap). Updated after the Day 2 engineering
review (`docs/engineering-reviews/day-02.md`) closed out its Critical and
High findings.

## Completed in v1.0.0

Everything below shipped by the stable v1.0.0 release: the full toolkit
scope (system/network/user/process/service/filesystem/monitoring
diagnostics), installation and packaging, configuration, operational
reporting, integrity verification, CI, and the complete v1 documentation
set.

**Common library** (`scripts/common/`)
- Bootstrap loader with fixed, dependency-correct load order
- Colors, configuration, logging, and output libraries, each guarded against
  duplicate sourcing

**System module** (`scripts/system/`)
- System information, OS details, hostname report

**Monitoring module** (`scripts/monitoring/`)
- CPU, memory, and load-average reporting

**Filesystem module** (`scripts/filesystem/`)
- Disk usage, largest-files, dry-run temporary-file scanning

**CI and quality gates**
- Bash syntax validation (`bash -n`) in CI and `make validate`
- ShellCheck integration in CI and `make lint`
- Git executable-mode enforcement in CI and `make check-executable`
- Fixed: scripts were tracked as non-executable (`100644`); a WSL/Windows
  `drvfs` mount reports every file as executable locally regardless of the
  tracked git mode, which had masked this from previously passing on a
  native Linux checkout
- Fixed: `largest-files.sh` crashed with exit `141` (SIGPIPE under
  `pipefail`) on any directory with more files than its limit; row-limiting
  now happens in `awk` instead of terminating the pipeline with `head`
- `set -euo pipefail` made consistent across all filesystem-module scripts

**Governance and project files**
- `LICENSE` (MIT), `CHANGELOG.md`, `CONTRIBUTING.md`, and `Makefile`
  populated with real content (previously empty placeholders)

**Claude Code integration**
- `.claude/CLAUDE.md` project guidance
- Claude Code Skills: `bash-review`, `devops-review`, `documentation`,
  `github-actions`, `linux-best-practices`, `new-bash-tool`

**Templates**
- `templates/script-template.sh` — full boilerplate with `--help`/`--version`
  support, used by the `new-bash-tool` skill

**Documentation**
- `docs/architecture.md`, `docs/best-practices.md`, and
  `docs/troubleshooting.md` rewritten as substantive references (previously
  bullet-point stubs)
- `README.md` repository-structure and utilities sections reconciled with
  what is actually tracked in git
- Engineering review process established (`docs/engineering-reviews/`)

**Unified `maops` CLI** (`bin/maops`)
- Thin dispatcher over `system`, `monitoring`, `filesystem`, and `network`;
  see [architecture.md §7](architecture.md#7-unified-maops-cli) for the
  dispatch table and exit-code design
- Shared CLI support library `scripts/common/cli.sh` (version output,
  help/version flag recognition, usage-error handling, positive-integer and
  TCP-port validation)

**Network module** (`scripts/network/`)
- Network information, ping checker, DNS lookup, TCP port checker; see
  [architecture.md §8](architecture.md#8-network-module) for tool choices
- Fixed (Day 3 release-readiness review, before any tag was cut): a command
  injection in `port-check.sh` via an unvalidated `HOST` argument reaching a
  string-interpolated `bash -c` — see
  [architecture.md §8](architecture.md#8-network-module),
  [best-practices.md §11](best-practices.md#11-parameterized-bash--c-instead-of-string-interpolation),
  and [troubleshooting.md §12](troubleshooting.md#12-why-port-checksh-uses-bash--c-with-1-2-instead-of-host-directly)
- Fixed (same review): `ping-check.sh`/`port-check.sh` misreported a
  negative-number `COUNT`/`PORT`/`TIMEOUT` as an "unknown option" instead of
  the correct validation message; both exited `2` either way, but the
  message now matches the actual problem

**Bats automated tests** (`tests/`)
- Covers the CLI dispatcher, `scripts/common/cli.sh`'s validation helpers,
  and the network module's `--help` and invalid-input rejection paths; no
  test requires internet access
- Extended with a deterministic PATH-based command-stub convention
  (`stub_bin_init`/`stub_command` in `tests/test-helper.bash`) so the user,
  process, and service modules can be tested without depending on the
  host's real accounts, process list, logged-in sessions, or init system
- `scripts/common/{colors,config,helpers,logger,output}.sh` and the
  `system`/`monitoring`/`filesystem` leaf scripts still have no dedicated
  Bats coverage — see Planned below

**User module** (`scripts/users/`)
- Read-only user report (`user-report.sh`) via `getent`/`id`/`who`:
  username, UID, primary GID, home directory, login shell, group
  memberships, active-session status; never reads password hashes or
  `/etc/shadow`
- See [architecture.md §9](architecture.md#9-user-process-and-service-modules)

**Process module** (`scripts/process/`)
- Read-only top-N process report (`process-monitor.sh`) via `ps`, sorted by
  CPU or memory, row-truncated in `awk` (never `head`, to avoid the same
  SIGPIPE class of bug fixed in `largest-files.sh`)
- See [architecture.md §9](architecture.md#9-user-process-and-service-modules)

**Service module** (`scripts/service/`)
- Read-only service status inspection (`service-status.sh`); prefers
  `systemctl show` when systemd is genuinely running, falls back to
  `service SERVICE status` (LSB exit codes) otherwise; never
  starts/stops/restarts/enables/disables a service
- See [architecture.md §9](architecture.md#9-user-process-and-service-modules)

**Configuration system** (`scripts/common/config-file.sh`, `scripts/config/`)
- Plain-text config file at `${MAOPS_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/maops/config}`,
  parsed via a `read -r` loop only — never sourced or eval'd
- `output_format`/`process_limit`/`ping_count`/`network_timeout` keys, with
  CLI-argument → `MAOPS_*` env var → config-file → built-in-default
  precedence resolved once (`config_resolve_value`) and reused by
  `config show`, `doctor`, and `process-monitor.sh`/`ping-check.sh`/`port-check.sh`'s
  defaults
- `maops config path|init [--force]|show [--format text|json]|validate [PATH]`
- See [architecture.md §12](architecture.md#12-configuration-system)

**Structured JSON output** (`scripts/common/format.sh`)
- Dependency-free JSON escaping/assembly, no `eval`, no runtime `jq`
- Scoped to exactly `config show --format json` and `doctor --format json`
  in this release
- See [architecture.md §13](architecture.md#13-structured-output-json-scope)

**Doctor command** (`scripts/diagnostics/doctor.sh`)
- Toolkit version, execution mode, OS, Bash version, config state, required
  runtime commands, and optional dev tools — read-only, no network calls
- See [architecture.md §14](architecture.md#14-doctor-command)

**Installation and packaging** (`scripts/install/`, `scripts/release/`)
- User-local install/uninstall with a staged, manifest-verified runtime
  tree; never `sudo`, never system-wide by default
- Reproducible release tarball (`package.sh`) plus SHA-256 checksum
  verification with pre-extraction archive-safety checks (`verify-package.sh`)
- `bin/maops` now resolves its own location through symlinks (a genuine bug
  fix required for the installed launcher to work at all)
- See [architecture.md §11](architecture.md#11-installation-and-runtime-layout)
  and [architecture.md §15](architecture.md#15-packaging-and-release-verification)

**Release integrity hardening** (`scripts/common/integrity.sh`,
`scripts/diagnostics/integrity-check.sh`)
- Fixed: `package.sh`/`install.sh` (source-tree mode) previously trusted
  `cp -a`-propagated source-filesystem permissions, which are not
  trustworthy on WSL/drvfs (`stat` reports `0777` for every tracked file
  regardless of Git's real index mode); every staged/installed mode is now
  derived exclusively from Git's index, applied via a self-verifying
  `chmod`
- `MAOPS-MANIFEST.tsv` — a deterministic, per-file `MODE`/`SHA256`/`PATH`
  manifest shipped inside the release archive, independent of the external
  whole-archive `.sha256` checksum
- `verify-package.sh` now snapshots the archive before any check (closing a
  TOCTOU window), inspects every member's real type via Python's `tarfile`
  module before any extraction (rejecting symlinks, hardlinks, devices,
  FIFOs — not just unsafe paths), and verifies the internal manifest after
  extraction
- `install.sh` now supports installing directly from an extracted release
  archive (no `.git` present), verifying `MAOPS-MANIFEST.tsv` before
  copying anything
- `uninstall.sh`'s removal guard is now scoped to `LIB_DIR`, not merely
  `PREFIX`, with a fully separate, fail-closed manifest-validation pass
  before any file is removed
- `maops integrity [--format text|json]` — read-only, never-repairing
  verification of an installed tree (against `.integrity-manifest`) or a
  source-tree checkout (against Git's index directly)
- New `tests/common/core-libraries.bats`, `tests/system/system-tools.bats`,
  `tests/monitoring/monitoring-tools.bats`,
  `tests/filesystem/filesystem-tools.bats`,
  `tests/diagnostics/integrity-check.bats`,
  `tests/workflows/actions-pinning.bats`, closing the Bats-coverage gap
  called out below for good
- `actions/checkout` pinned to a full commit SHA in
  `.github/workflows/bash-validation.yml`, with a static regression test
  that fails if any external action reference is ever un-pinned again
- See [architecture.md §11](architecture.md#11-installation-and-runtime-layout),
  [§15](architecture.md#15-packaging-and-release-verification), and
  [§16](architecture.md#16-integrity-verification-maops-integrity)

**Operational report command** (`scripts/reports/operational-report.sh`,
`scripts/common/reporting.sh`)
- `maops report summary [--format text|json] [--redact]` and `maops report
  save --output PATH [...] [--force]` — a safe, read-only operational
  snapshot (version, execution mode, system/resource facts, config state,
  and the `doctor`/`integrity` verdicts), never collecting passwords,
  environment dumps, process command lines, usernames, IP addresses, or
  config-file contents, and never making a network request
- Reuses `doctor.sh`/`integrity-check.sh` by exit code only — their check
  logic and JSON documents are never duplicated or reparsed
- `--redact` for sharing a report without hostname/config-path details;
  `report save` writes atomically (same-directory temp file, mode `0600`,
  atomic rename) with symlink/directory/overwrite refusals
- New `tests/reports/operational-report.bats` (53 tests) and a new
  `stub_fixed_output` test helper for deterministic field-content assertions
- Closed several Day 6 non-blocking findings alongside this work: an
  undocumented ordering dependency in `verify-package.sh`'s extra-file scan,
  the `release-check`-vs-`make clean release-check` distinction, deterministic
  PATH-shadowing for the previously host-dependent installed-doctor test, and
  new tests for config extra-argument handling and foreign-launcher-symlink
  refusal/preservation
- See [architecture.md §17](architecture.md#17-operational-report-maops-report)

**Day 8 — v1.0.0 finalization**
- Final CLI-consistency audit: the nine leaf scripts with no `--help`/
  `--version` handling now match every other leaf script's convention; new
  `tests/cli/leaf-script-consistency.bats`
- Resource-report portability hardening: shape validation plus a
  `/proc/loadavg`/`/proc/meminfo` fallback in `scripts/common/reporting.sh`,
  with BusyBox-shaped and malformed-output test fixtures (test-only — see
  `docs/compatibility.md` for what is and isn't actually supported)
- Remaining Day 7 Low findings closed: the SIGKILL/`.maops-report.*`
  residual-risk documented in `docs/troubleshooting.md` §20, plus the
  remaining CLI-coverage tests (`-v`/bare `version`, uppercase `--format`,
  `--redact` forwarding, embedded-newline `--output`, full `--help` command
  listing)
- `SECURITY.md`, `SUPPORT.md`, and the full v1 user documentation set
  (`docs/quickstart.md`, `docs/install-from-release.md`,
  `docs/compatibility.md`, `docs/demo-workflow.md`,
  `docs/portfolio-case-study.md`)
- `examples/` (validated config + automation script) with its own Bats
  coverage
- Architecture diagrams (Mermaid) for runtime dispatch, the
  distribution/integrity chain, and configuration precedence
- Offline documentation validation
  (`scripts/release/validate-documentation.sh`) wired into new
  `docs-check`/`examples-check`/`final-check` Makefile targets and CI
- `RELEASE_FILE_LIST` extended to ship the new v1 docs and examples;
  `docs/engineering-reviews/` and `docs/images/` remain excluded
- README.md polish: stable-v1.0.0 status, architecture summary, quickstart,
  security/privacy model, compatibility summary, documentation index,
  screenshots, and contribution/security/support links
- 517 total Bats tests (up from 443 at v0.6.0)

## Post-v1.0 Possibilities

Ideas under consideration for a future release. **None of these are
committed promises** — they are candidates, not a roadmap in the
scheduling sense.

- **Cryptographic publisher signatures** (GPG or Sigstore) — closing the
  publisher-authenticity gap described below and in
  [SECURITY.md](../SECURITY.md): the existing external `.sha256` and
  internal `MAOPS-MANIFEST.tsv` verify archive-byte and per-file integrity
  today, not *who published* the archive
- **Package-manager-native DEB/RPM packages** — an alternative to the
  current tarball-based install for users who prefer their distribution's
  native package manager
- **Shell completion** (bash/zsh) for `bin/maops`'s command surface
- **Broader distribution testing** — exercising the toolkit against
  environments beyond the two actively-validated ones
  (`docs/compatibility.md`), e.g. other systemd Debian/Ubuntu-family
  distributions, on an ongoing basis rather than as a one-off manual check
- **Optional plugin architecture** — a way to add new leaf commands without
  modifying `bin/maops` directly
- **Last-login report** — a historical login-history report (e.g. via
  `last`/`lastlog`) was considered alongside the Day 4 user module but
  deferred; the current-session report in `user-report.sh` does not cover
  historical logins
- **Medium technical article**
- **Remaining template stubs** — `templates/readme-template.md`,
  `templates/skill-template.md`, and `templates/github-workflow-template.yml`
  are still empty placeholders; only `script-template.sh` is implemented
- **`require_command` adoption audit** — the guard exists in
  `scripts/common/helpers.sh` and is used by the filesystem, network, and
  disk-usage scripts; `system`/`monitoring` scripts (`hostname`, `uname`,
  `free`, `lscpu`, `uptime`) still call their dependency directly without
  it. Day 6's new `tests/system/system-tools.bats` and
  `tests/monitoring/monitoring-tools.bats` document the *actual* current
  behavior of a missing dependency (a command embedded in a `$(...)`
  substitution degrades silently under `set -e` and exits `0`; a bare
  simple command like `free -h` exits `127`) rather than assuming this
  audit had already happened — adopting `require_command` consistently
  would make both cases a clean, identical exit `1` with a clear message
- **Decide on `LOG_DIRECTORY`** in `scripts/common/config.sh` — still defined
  but unused; either implement file-based logging or remove it.
  `DEFAULT_TIMEOUT` is no longer in this category — it is now consumed by
  `ping-check.sh` (per-packet wait) and `port-check.sh` (default connection
  timeout)
- **Archive install path is the largest net-new Day 6 surface** — covered by
  dedicated Bats tests (`tests/install/install.bats`), but has not yet been
  exercised by a long-running/adversarial fuzz-style test; a good candidate
  for a future hardening pass if the installer's manifest-verification logic
  is ever extended further
