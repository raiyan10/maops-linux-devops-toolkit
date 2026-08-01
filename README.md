# MAOps Linux DevOps Toolkit

> A production-inspired Linux automation toolkit for DevOps, Platform Engineering and Cloud Operations.

![Linux](https://img.shields.io/badge/Linux-Ubuntu-E95420?logo=ubuntu&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-5.x-4EAA25?logo=gnubash&logoColor=white)
[![Bash Validation](https://github.com/raiyan10/maops-linux-devops-toolkit/actions/workflows/bash-validation.yml/badge.svg)](https://github.com/raiyan10/maops-linux-devops-toolkit/actions/workflows/bash-validation.yml)
![ShellCheck](https://img.shields.io/badge/ShellCheck-enabled-4E9A06)
![GitHub Actions](https://img.shields.io/badge/CI-GitHub%20Actions-blue)
![License](https://img.shields.io/badge/License-MIT-blue)

---

# Overview

The **MAOps Linux DevOps Toolkit** is a collection of reusable Bash utilities designed to automate common Linux administration and DevOps tasks.

Unlike simple collections of Linux commands, this project follows production-inspired engineering practices including modular scripting, centralized logging, reusable helper libraries, documentation, testing, and CI/CD.

This repository is part of the **MAOps Technologies Engineering Portfolio**.

---

# Objectives

- Learn Linux automation
- Practice production-quality Bash scripting
- Build reusable DevOps tools
- Apply Infrastructure Automation principles
- Demonstrate Platform Engineering practices
- Build an interview-ready GitHub portfolio

---

# Features

- Modular Bash scripts
- Shared logging library
- Configuration management
- Error handling
- Input validation
- Colored console output
- Documentation
- GitHub Actions
- Claude Code integration
- Production-inspired project structure

---

# Repository Structure

```text
.
├── .claude
│   ├── CLAUDE.md
│   ├── agents
│   │   ├── bash-test-engineer.md
│   │   └── release-engineer.md
│   ├── settings.local.json
│   └── skills
│       ├── bash-review
│       ├── devops-review
│       ├── documentation
│       ├── github-actions
│       ├── linux-best-practices
│       └── new-bash-tool
├── .github
│   └── workflows
│       └── bash-validation.yml
├── bin
│   └── maops
├── docs
│   ├── architecture.md
│   ├── best-practices.md
│   ├── engineering-reviews
│   │   ├── day-02.md
│   │   ├── day-02-release-readiness.md
│   │   ├── day-03-release-readiness.md
│   │   └── day-03-release-readiness-followup.md
│   ├── images
│   │   ├── day-02
│   │   └── day-03
│   ├── roadmap.md
│   └── troubleshooting.md
├── scripts
│   ├── common
│   │   ├── bootstrap.sh
│   │   ├── cli.sh
│   │   ├── colors.sh
│   │   ├── config.sh
│   │   ├── config-file.sh
│   │   ├── format.sh
│   │   ├── helpers.sh
│   │   ├── integrity.sh
│   │   ├── logger.sh
│   │   ├── output.sh
│   │   └── release-files.sh
│   ├── config
│   │   └── config-manager.sh
│   ├── diagnostics
│   │   ├── doctor.sh
│   │   └── integrity-check.sh
│   ├── filesystem
│   │   ├── cleanup-temp.sh
│   │   ├── disk-usage.sh
│   │   └── largest-files.sh
│   ├── install
│   │   ├── install.sh
│   │   ├── lib.sh
│   │   └── uninstall.sh
│   ├── monitoring
│   │   ├── cpu-monitor.sh
│   │   ├── load-average.sh
│   │   └── memory-report.sh
│   ├── network
│   │   ├── dns-lookup.sh
│   │   ├── network-info.sh
│   │   ├── ping-check.sh
│   │   └── port-check.sh
│   ├── process
│   │   └── process-monitor.sh
│   ├── release
│   │   ├── package.sh
│   │   └── verify-package.sh
│   ├── reports
│   │   └── operational-report.sh
│   ├── service
│   │   └── service-status.sh
│   ├── system
│   │   ├── hostname-report.sh
│   │   ├── os-details.sh
│   │   └── system-info.sh
│   └── users
│       └── user-report.sh
├── templates
│   ├── github-workflow-template.yml
│   ├── readme-template.md
│   ├── script-template.sh
│   └── skill-template.md
├── tests
│   ├── cli
│   │   └── maops.bats
│   ├── common
│   │   ├── core-libraries.bats
│   │   └── helpers.bats
│   ├── config
│   │   └── config-manager.bats
│   ├── diagnostics
│   │   ├── doctor.bats
│   │   └── integrity-check.bats
│   ├── filesystem
│   │   └── filesystem-tools.bats
│   ├── install
│   │   └── install.bats
│   ├── monitoring
│   │   └── monitoring-tools.bats
│   ├── network
│   │   └── network-tools.bats
│   ├── process
│   │   └── process-monitor.bats
│   ├── release
│   │   └── package.bats
│   ├── reports
│   │   └── operational-report.bats
│   ├── service
│   │   └── service-status.bats
│   ├── system
│   │   └── system-tools.bats
│   ├── users
│   │   └── user-report.bats
│   ├── workflows
│   │   └── actions-pinning.bats
│   └── test-helper.bash
├── .gitattributes
├── .gitignore
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── Makefile
└── README.md
```

`dist/` (generated release artifacts from `make package`) is gitignored and intentionally not shown above.

---

# Utilities

## Implemented

### System (`scripts/system`)

- [x] System Information — `system-info.sh`
- [x] OS Details — `os-details.sh`
- [x] Hostname Report — `hostname-report.sh`

### Monitoring (`scripts/monitoring`)

- [x] CPU Monitor — `cpu-monitor.sh`
- [x] Memory Report — `memory-report.sh`
- [x] Load Average — `load-average.sh`

### Filesystem (`scripts/filesystem`)

- [x] Disk Usage — `disk-usage.sh`
- [x] Largest Files — `largest-files.sh`
- [x] Temporary File Cleanup (dry-run scanner, no deletion) — `cleanup-temp.sh`

### Network (`scripts/network`)

- [x] Network Information — `network-info.sh`
- [x] Ping Checker — `ping-check.sh`
- [x] DNS Lookup — `dns-lookup.sh`
- [x] Port Checker — `port-check.sh`

### Users (`scripts/users`)

- [x] User Report (read-only: username, UID, primary GID, home directory, login shell, group memberships, active-session status) — `user-report.sh`

### Process (`scripts/process`)

- [x] Top Processes by CPU or Memory (read-only) — `process-monitor.sh`

### Service (`scripts/service`)

- [x] Service Status (read-only; `systemctl` with a `service(8)` fallback) — `service-status.sh`

### Configuration (`scripts/config`, `scripts/common/config-file.sh`)

- [x] Config path/init/show/validate, with CLI-argument → `MAOPS_*` env var → config-file → built-in-default precedence — `config-manager.sh`

### Diagnostics (`scripts/diagnostics`)

- [x] Environment/health check — toolkit version, execution mode, OS, Bash version, config state, required/optional command availability (read-only, no network calls) — `doctor.sh`
- [x] Integrity verification — installed-tree-vs-manifest or source-tree-vs-Git-index, read-only, never repairs — `integrity-check.sh`

### Installation and Packaging (`scripts/install`, `scripts/release`)

- [x] User-local install/uninstall with a staged, manifest-based runtime tree, supporting both a Git checkout and an extracted release archive as the install source — `install.sh`, `uninstall.sh`
- [x] Reproducible release tarball, Git-index-derived file modes, an internal per-file integrity manifest, and hardened archive-member/checksum verification — `package.sh`, `verify-package.sh`

### Reporting (`scripts/reports`, `scripts/common/reporting.sh`)

- [x] Operational report — version, execution mode, system/resource facts, config state, and doctor/integrity verdicts, in text or JSON, with `--redact` and secure atomic file saving (read-only, no network calls) — `operational-report.sh`

All utilities above are also reachable through the unified [`maops` CLI](#cli-usage) at `bin/maops`.

## Planned

- [ ] Last Login Report (historical login history, e.g. via `last`/`lastlog` — distinct from the current-session check in `user-report.sh`)

---

# CLI Usage

`bin/maops` is a thin dispatcher over the scripts above — it does not reimplement their logic.

```bash
maops --help
maops --version

maops system info
maops system os
maops system hostname

maops monitoring memory
maops monitoring cpu
maops monitoring load

maops filesystem disk
maops filesystem largest /var/log 20
maops filesystem temp /tmp 30

maops network info
maops network ping example.com 4
maops network dns example.com
maops network port example.com 443 2

maops user report
maops user report alice

maops process top
maops process top 5 cpu
maops process top 15 memory

maops service status cron

maops config path
maops config init
maops config show
maops config show --format json

maops doctor
maops doctor --format json

maops integrity
maops integrity --format json

maops report summary
maops report summary --format json
maops report summary --redact
maops report save --output /tmp/report.json --format json
maops report save --output /tmp/report.json --format json --force
```

Unknown groups or commands print an actionable error and exit with status `2`. Every dispatched command exits with that underlying script's own exit code.

---

# Installation

`maops` defaults to a **user-local** install — never `sudo`, never system-wide by default:

```bash
make install                                    # installs to $HOME/.local
make install PREFIX=/opt/maops                  # or any custom prefix
make install INSTALL_ARGS="--force"             # reinstall/upgrade over an existing install
make uninstall                                  # removes it again
make uninstall UNINSTALL_ARGS="--purge-config"  # also remove the configuration directory
```

Default layout under `PREFIX` (`$HOME/.local` unless overridden):

```text
PREFIX/bin/maops                  -> ../lib/maops/bin/maops   (relative symlink)
PREFIX/lib/maops/bin/maops
PREFIX/lib/maops/scripts/
PREFIX/lib/maops/LICENSE
PREFIX/lib/maops/CHANGELOG.md
PREFIX/lib/maops/.install-manifest
PREFIX/lib/maops/.integrity-manifest
```

Install stages the whole runtime tree in a temporary directory under `PREFIX/lib` before ever replacing anything, refuses to overwrite an unrelated file it finds at `PREFIX/bin/maops` (even with `--force`), and records every installed path in `.install-manifest` so `uninstall.sh` only ever removes files it verifiably owns — scoped to `PREFIX/lib/maops` specifically, never a sibling directory under a shared `PREFIX`. Re-running install over an existing MAOps installation requires `--force`; your configuration file (outside `PREFIX` entirely) is untouched by both install and uninstall unless you pass `--purge-config` to uninstall. Install works both from a Git checkout and from an already-extracted release archive (verifying `MAOPS-MANIFEST.tsv` before copying anything in the latter case) — every installed file's permission mode is derived from Git's index or the package manifest, never from the source filesystem's own `stat` (relevant on WSL/drvfs, where `stat` misreports tracked-file permissions). See [docs/architecture.md §11](docs/architecture.md#11-installation-and-runtime-layout) for the full design and threat model.

---

# Configuration

Config lives at `${MAOPS_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/maops/config}` — a plain `key=value` text file, never sourced or evaluated as Bash:

```bash
maops config init            # create a default config file
maops config show            # show effective values (after precedence)
maops config validate        # validate the resolved config file
```

Supported keys: `output_format` (`text`/`json`), `process_limit`, `ping_count`, `network_timeout`. Precedence for every value is **explicit CLI argument → `MAOPS_*` environment variable → config file → built-in default**. See [docs/architecture.md §12](docs/architecture.md#12-configuration-system) for the parsing/validation rules and [docs/troubleshooting.md](docs/troubleshooting.md) for common config-rejection causes.

---

# Doctor

`maops doctor` reports toolkit version, source-tree-vs-installed execution mode, OS, Bash version, config state, and the availability of every required runtime command and optional development tool — read-only, no network calls:

```bash
maops doctor
maops doctor --format json | python3 -m json.tool
```

Exits `0` when every required check passes, `1` if a required command or an existing-but-invalid config fails. Missing optional development tools (`git`, `make`, `shellcheck`, `bats`, `python3`) are warnings, never failures. See [docs/architecture.md §14](docs/architecture.md#14-doctor-command) for the full check list.

---

# Integrity

`maops integrity` is a read-only, never-repairing check that verifies what's actually on disk against what it's supposed to be — an installed tree against `PREFIX/lib/maops/.integrity-manifest`, or a source-tree checkout directly against Git's tracked index (never against working-tree `stat`, which is not trustworthy on WSL/drvfs):

```bash
maops integrity
maops integrity --format json | python3 -m json.tool
```

Exits `0` when every file matches, `1` if any file is missing, has modified content, has an unexpected mode, or the manifest itself is malformed — or if neither an installed manifest nor Git metadata is available at all. `maops integrity` never modifies or repairs anything; see [docs/architecture.md §16](docs/architecture.md#16-integrity-verification-maops-integrity) for the full verification model and [docs/troubleshooting.md §17](docs/troubleshooting.md#17-interpreting-a-maops-integrity-failure) for how to interpret a failure.

---

# Report

`maops report summary` consolidates toolkit version, execution mode, system/resource facts (hostname, OS, kernel, architecture, CPU count, load average, memory, root filesystem usage), configuration state, and the `doctor`/`integrity` verdicts into one document — read-only, no network calls, no passwords/environment dumps/process command lines/usernames/IP addresses/config-file contents ever collected:

```bash
maops report summary
maops report summary --format json | python3 -m json.tool
maops report summary --redact
maops report save --output /tmp/report.json --format json
maops report save --output /tmp/report.json --format json --force
```

Exits `0` when doctor/integrity pass and every field is collected, `1` when either fails or only optional system/resource info is unavailable (the report is still emitted in full either way), `2` for a CLI usage error. `--redact` replaces `hostname` and `configuration.path` with `<redacted>`. `report save --output PATH` requires the parent directory to already exist, refuses to overwrite an existing file without `--force`, refuses a symlink target even with `--force`, and writes atomically (a same-directory temp file, mode `0600`, then an atomic rename) so a saved report is never partially written. See [docs/architecture.md §17](docs/architecture.md#17-operational-report-maops-report) for the full field schema and [docs/troubleshooting.md](docs/troubleshooting.md) for how to interpret a failure.

---

# User, Process, and Service Utilities

These three modules are strictly read-only — none of them ever starts, stops, restarts, enables, disables, kills, or renices anything, and none require `sudo`.

```bash
# Read-only account report: username, UID, primary GID, home directory,
# login shell, group memberships, active-session status. USERNAME is
# optional and defaults to the current effective user.
./scripts/users/user-report.sh
./scripts/users/user-report.sh alice

# Top-N processes by CPU (default) or memory. LIMIT defaults to 10.
./scripts/process/process-monitor.sh
./scripts/process/process-monitor.sh 5 cpu
./scripts/process/process-monitor.sh 15 memory

# Read-only service status. Prefers systemctl when systemd is genuinely the
# running init system, falls back to the service(8) command otherwise.
./scripts/service/service-status.sh cron
```

See [docs/architecture.md §9](docs/architecture.md#9-user-process-and-service-modules) for tool choices and the service-manager detection strategy, and [docs/best-practices.md §12–§15](docs/best-practices.md#12-read-only-operations-by-default) for the read-only, detection/fallback, test-stub, and exit-code conventions these modules establish.

---

# Network Utilities

```bash
# Hostname, interfaces, IPv4 addresses, default gateway, DNS resolvers
./scripts/network/network-info.sh

# Ping a host with a bounded, safe-default packet count
./scripts/network/ping-check.sh example.com
./scripts/network/ping-check.sh example.com 6

# Resolve a hostname or IP using the system resolver (getent)
./scripts/network/dns-lookup.sh localhost
./scripts/network/dns-lookup.sh example.com

# Check TCP port reachability with a bounded connection timeout
./scripts/network/port-check.sh example.com 443
./scripts/network/port-check.sh example.com 443 2
```

---

# Testing

The test suite uses [Bats](https://github.com/bats-core/bats-core) and requires no internet access — every network-related test either validates rejected input before any connection is attempted, or stays on loopback/`/etc/hosts`.

```bash
make test      # run the full Bats suite
make quality   # syntax validation + ShellCheck + executable-mode check + Bats
```

Individual files can also be run directly, e.g. `bats tests/cli/maops.bats`.

Release and install-specific checks are separate, filesystem-heavier targets not folded into `make quality`:

```bash
make package         # build dist/*.tar.gz and its .sha256 checksum
make verify-package  # verify the checksum, archive-member safety, and internal manifest
make smoke-install   # install to a temporary prefix, run the CLI + doctor + integrity, then uninstall
make integrity       # run `maops integrity` against the source tree
make release-check   # quality -> package -> verify-package -> smoke-install, in order
```

`make release-check` is the single command CI runs — reproduce it locally before pushing to catch anything CI would catch.

---

# Engineering Principles

This project follows:

- Infrastructure as Code
- Automation First
- Documentation as Code
- Reusable Components
- Secure by Design
- Production-inspired Engineering

---

# Technology Stack

- Linux
- Bash
- Git
- GitHub Actions
- ShellCheck
- shfmt
- Claude Code

---

# Roadmap

- [x] Common utility library
- [x] Logging framework
- [x] Output framework
- [x] System utilities
- [x] Initial monitoring utilities
- [x] Initial filesystem utilities
- [x] Bash syntax validation
- [x] ShellCheck integration
- [x] GitHub Actions CI
- [x] Claude Code project guidance
- [x] Claude Code Skills
- [x] Git executable-mode and SIGPIPE release-blocker fixes (Engineering Review Day 2)
- [x] Unified `maops` CLI
- [x] Network utilities
- [x] Bats automated tests
- [x] User, process, and service utilities
- [x] Configuration system with precedence resolution and JSON output
- [x] Doctor diagnostic command
- [x] Installation and packaging
- [x] Release integrity hardening (Git-index mode normalization, internal release manifest, hardened archive verification, `maops integrity`)
- [x] Operational report command (`maops report summary|save`, text/JSON, redaction, atomic file saving)
- [ ] Architecture diagrams
- [ ] Medium technical article
- [ ] Publisher authenticity / archive signing (see [docs/roadmap.md](docs/roadmap.md))

See [docs/roadmap.md](docs/roadmap.md) for the detailed, module-level roadmap.

---

# Future Improvements

- Docker Support
- Kubernetes Diagnostics
- Remote Server Automation
- Ansible Integration
- AWS CLI Automation
- Azure CLI Automation
- Security Hardening Scripts

---

# Related Projects

This project is part of the MAOps Technologies Engineering Portfolio.

- Enterprise DevOps Platform
- Docker Platform
- Kubernetes Platform
- DevSecOps
- GitHub Actions
- Terraform AWS
- Terraform Azure
- MLOps
- LLMOps
- RAG Platform
- AIOps
- AI Infrastructure

---

# License

MIT License