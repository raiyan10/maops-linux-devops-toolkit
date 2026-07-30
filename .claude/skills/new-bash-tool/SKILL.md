---
name: new-bash-tool
description: Creates a new MAOps Linux Toolkit utility from the project Bash template. Use when adding a system, monitoring, filesystem, network, user, process, or service command.
argument-hint: "<relative-script-path> \"<purpose>\""
arguments:
  - script_path
  - purpose
disable-model-invocation: true
---

Create the Bash utility at `$script_path`.

Purpose:

`$purpose`

Follow this procedure:

1. Read `CLAUDE.md`.
2. Read `templates/script-template.sh`.
3. Read the libraries under `scripts/common/`.
4. Verify that `$script_path` is inside `scripts/` and ends in `.sh`.
5. Create its parent directory when necessary.
6. Copy the repository script template as the starting point.
7. Replace all template placeholders and metadata.
8. Implement only the requested functionality.
9. Use `scripts/common/bootstrap.sh`.
10. Support `--help` and `--version`.
11. Validate all user-supplied arguments.
12. Use safe, non-destructive defaults.
13. Keep functions focused and generally below 25 lines.
14. Make the script executable.
15. Run `bash -n` against the new script.
16. Run ShellCheck against the new script.
17. Update `docs/roadmap.md` and the root `README.md` only when the implementation changes an existing milestone or feature list.
18. Show the files changed and summarize important design decisions.
19. Do not commit or push changes.