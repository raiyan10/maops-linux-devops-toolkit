# maops-linux-devops-toolkit# MAOps Linux DevOps Toolkit

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
├── docs
│   ├── architecture.md
│   ├── best-practices.md
│   ├── engineering-reviews
│   │   └── day-02.md
│   ├── images
│   │   └── day-02
│   ├── roadmap.md
│   └── troubleshooting.md
├── scripts
│   ├── common
│   │   ├── bootstrap.sh
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
│   └── system
│       ├── hostname-report.sh
│       ├── os-details.sh
│       └── system-info.sh
├── templates
│   ├── github-workflow-template.yml
│   ├── readme-template.md
│   ├── script-template.sh
│   └── skill-template.md
├── .gitattributes
├── .gitignore
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── Makefile
└── README.md
```

`scripts/network` and `scripts/users` are planned modules and do not exist in the tree yet — see [Utilities](#utilities) below.

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

## Planned

### Network (`scripts/network`, not yet created)

- [ ] Network Information
- [ ] Ping Checker
- [ ] Port Checker

### Users (`scripts/users`, not yet created)

- [ ] User Report
- [ ] Last Login Report

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
- [ ] Unified `maops` CLI
- [ ] Network utilities
- [ ] User and process utilities
- [ ] Bats automated tests
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