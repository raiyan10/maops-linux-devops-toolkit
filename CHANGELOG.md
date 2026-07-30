# Changelog

All notable changes to the MAOps Linux DevOps Toolkit are documented here.

The project follows Semantic Versioning.

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