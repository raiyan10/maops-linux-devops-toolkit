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
│   │   └── bash-test-engineer.md
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
│   │   ├── helpers.sh
│   │   ├── logger.sh
│   │   └── output.sh
│   ├── filesystem
│   │   ├── cleanup-temp.sh
│   │   ├── disk-usage.sh
│   │   └── largest-files.sh
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
│   │   └── helpers.bats
│   ├── network
│   │   └── network-tools.bats
│   ├── process
│   │   └── process-monitor.bats
│   ├── service
│   │   └── service-status.bats
│   ├── users
│   │   └── user-report.bats
│   └── test-helper.bash
├── .gitattributes
├── .gitignore
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── Makefile
└── README.md
```

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
```

Unknown groups or commands print an actionable error and exit with status `2`. Every dispatched command exits with that underlying script's own exit code.

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
- [ ] Installation and packaging
- [ ] Architecture diagrams
- [ ] Medium technical article

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