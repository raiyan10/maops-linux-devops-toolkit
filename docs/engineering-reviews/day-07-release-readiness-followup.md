# Engineering Review — Day 7 Release-Readiness Follow-Up (v0.6.0)

**Reviewer role:** Senior Platform / Release Engineer
**Scope:** Follow-up pass against the original Day 7 report (`day-07-release-readiness.md`). That report found zero Critical and zero High findings; per instruction, this follow-up fixes verified Critical/High findings — there were none to fix. In their place, the report's one Medium finding (M1) is fixed here instead, since it was the highest-severity actionable item and had a known, low-risk, one-line resolution already identified in the original report's recommendations.

**Method:** Read the affected code directly, applied the fix, added two new regression tests proving both the fixed behavior and its `--output=VALUE` combined-flag counterpart, and re-ran the full test suite plus the `validate`/`lint`/`check-executable` quality gates. No other file was touched.

---

## 1. Fix Applied: M1 (`report save --output` Did Not Reject a Flag-Shaped Value)

**Before:** `scripts/reports/operational-report.sh`'s `cmd_save()` accepted whatever token followed `--output`/`--output=` unconditionally, unlike the equivalent `validate_non_option_argument` pattern this codebase already uses for comparable positional values (`scripts/service/service-status.sh`, `scripts/users/user-report.sh`). A user typo omitting the real path — e.g. `report save --output --force` — silently "succeeded," writing a confusingly-named file (literally `--force`) instead of failing with a clear usage error. This was not a security defect (every downstream `mktemp`/`chmod`/`mv` call already uses a `--` end-of-options marker, so the write itself was always safe and inert), but it was an input-validation inconsistency with the rest of the project.

**Fix:** one line added immediately after the existing `--output PATH is required` check in `cmd_save()`:

```bash
[[ -z "$output" ]] && cli_usage_error "report save: --output PATH is required."
validate_non_option_argument "$output" "--output"
```

`validate_non_option_argument` (`scripts/common/cli.sh`) rejects an empty value or one starting with `-`, exiting `2` with a clear message — the same three-tier exit-code convention (`0`/`1`/`2`) every other command in this project already follows.

**Verification:**
- New tests added to `tests/reports/operational-report.bats`: `"report save rejects an --output value that looks like a flag"` (`--output --force` → exit `2`, no file named `--force` created) and `"report save rejects an --output=VALUE that looks like a flag"` (`--output=-rf` → exit `2`, no file named `-rf` created). Both pass.
- Full `tests/reports/operational-report.bats` run: **67/67 pass** (65 from the Day 7 implementation + 2 new for this fix).
- `bash -n`, `make lint` (ShellCheck via the real project-gating batched invocation), `make validate`, and `make check-executable` all pass clean.
- Full `make quality`: **443/443 Bats tests pass** (441 + 2 new), `validate`/`lint`/`check-executable` all clean, zero regressions anywhere else in the suite.
- Manually reconfirmed the two adversarial reproductions from the original review no longer succeed:
  ```
  $ bin/maops report save --output --force
  [ERROR] --output must not be empty or start with '-': --force
  (exit 2, no file created)

  $ bin/maops report save --output=-rf
  [ERROR] --output must not be empty or start with '-': -rf
  (exit 2, no file created)
  ```
- Reconfirmed the fix does not affect any legitimate usage: relative paths, absolute paths, paths containing spaces/shell metacharacters, and both `--output PATH`/`--output=PATH` syntaxes all continue to work exactly as before (existing tests for all of these still pass unchanged).

**Scope discipline:** only `scripts/reports/operational-report.sh` (the fix) and `tests/reports/operational-report.bats` (the two new tests) were touched. No other file was modified, and neither of the two remaining Low findings from the original report (L1: signal-fatal write leaving an inert temp file; L2/L3: coverage gaps in non-GNU `free`/`df` parsing and a few CLI edge-case spellings) was addressed — all three remain open, exactly as the original report recommended deferring them to a future, low-priority pass.

---

## 2. Findings Carried Forward, Unchanged

Per the original Day 7 report (§4), the following remain open and are explicitly **not** addressed by this follow-up, since none is Critical or High and this pass's scope was limited to M1:

- **L1** — a signal-fatal failure (e.g. `SIGKILL`, `SIGXFSZ`) during `report_save_atomic`'s write step leaves a stray, empty, inert `0600` temp file behind; no `trap` can run after a fatal signal. Accepted residual risk, not yet documented in `docs/troubleshooting.md`.
- **L2** — `free`/`df`/`uptime` field parsing assumes a standard GNU coreutils/procps column layout; not yet tested against a BusyBox/non-GNU variant.
- **L3** — a handful of CLI argument-parsing edges remain untested (`-v`/bare-`version` spellings, uppercase `--format JSON`, `--redact` forwarded specifically through `bin/maops`, an embedded-newline `--output` path).

---

## 3. Final v0.6.0 Readiness Recommendation

**Ready to tag v0.6.0 — unchanged from the original Day 7 recommendation, now with one fewer open finding.**

The original report already concluded there were no release blockers with M1 open; fixing it removes the only Medium-severity item from the outstanding list, leaving three Low findings, none of which represents an exploitable gap, a broken safety guarantee, or a regression from Day 6's shipped behavior. The fix was small, targeted, verified with new regression tests, and re-confirmed against the full 443-test suite with zero collateral impact.
