# Demo Workflow

A complete, copy/paste demonstration of the toolkit that is fully
sandboxed: no `sudo`, no public network access, no changes to real system
services, and no writes to your actual configuration. Everything happens
inside a throwaway temporary directory that is removed at the end.

Run this from a Git checkout of the repository.

```bash
set -uo pipefail
# Deliberately not `set -e` for this whole script: doctor/integrity/report's
# exit code reflects the health verdict they found (0=pass, 1=warn or
# fail), not "did the command run correctly" -- see troubleshooting.md §19.
# A warn/fail verdict on your particular machine is expected and is not a
# demo failure, so each diagnostic step below is allowed to return non-zero
# without aborting the walkthrough.

# --- Setup: an isolated, disposable HOME -----------------------------------
# Every step below operates against this temporary HOME, never your real
# one, so config-init and report-save in this demo can never touch
# anything you actually care about.
DEMO_HOME="$(mktemp -d)"
export HOME="$DEMO_HOME"
export XDG_CONFIG_HOME="$DEMO_HOME/.config"
mkdir -p "$XDG_CONFIG_HOME"

MAOPS_BIN="$(pwd)/bin/maops"

# --- 1. Verify version -------------------------------------------------
"$MAOPS_BIN" --version

# --- 2. Initialize configuration in the temporary HOME ------------------
"$MAOPS_BIN" config init
"$MAOPS_BIN" config path
"$MAOPS_BIN" config show

# --- 3. Run doctor --------------------------------------------------------
"$MAOPS_BIN" doctor

# --- 4. Run integrity -------------------------------------------------
"$MAOPS_BIN" integrity

# --- 5. Generate a text report ---------------------------------------
"$MAOPS_BIN" report summary

# --- 6. Generate a redacted JSON report -------------------------------
"$MAOPS_BIN" report summary --format json --redact | python3 -m json.tool

# --- 7. Save a mode-0600 report ----------------------------------------
REPORT_PATH="$DEMO_HOME/report.json"
"$MAOPS_BIN" report save --output "$REPORT_PATH" --format json --redact
stat -c 'mode: %a  path: %n' "$REPORT_PATH"

# --- 8. Inspect a process report ---------------------------------------
"$MAOPS_BIN" process top 10

# --- 9. Inspect service status safely -----------------------------------
# Reads status only -- never starts, stops, restarts, enables, or disables
# anything. "cron" is a common, harmless example service name; substitute
# any service you'd like to check the status of.
"$MAOPS_BIN" service status cron

# --- 10. Clean up ----------------------------------------------------------
rm -rf -- "$DEMO_HOME"
echo "Demo complete. $DEMO_HOME removed."
```

## Notes

- **No `sudo` anywhere.** Every command above runs as your normal user.
- **No public network access.** Every command reads local system state
  only; `service status` and `report` never make a network request.
- **Real system services are never mutated.** `service status` is
  read-only by construction — see
  [best-practices.md](best-practices.md) §13 for how the underlying
  `systemctl show`/`service status` calls are chosen specifically to avoid
  any mutating verb.
- **Your real configuration is never touched.** `HOME`/`XDG_CONFIG_HOME`
  are redirected to a `mktemp -d` directory before `config init` runs, so
  the default config path (normally
  `${XDG_CONFIG_HOME:-$HOME/.config}/maops/config`) resolves entirely
  inside the throwaway directory.
- **Any step from 3–9 may print a warn/fail verdict or exit non-zero** on
  your particular machine (for example, if an optional resource field is
  unavailable, or "cron" isn't installed) — that's expected, and is exactly
  why the script uses `set -uo pipefail` rather than `set -e`. The point of
  each step is to show the command runs safely and produces a sensible
  result, not that every check passes on every machine.
- Every path above is quoted, and the final `rm -rf --` uses `--` to guard
  against a variable that happens to start with `-`.
