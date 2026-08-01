# Engineering Review — Day 6 Release-Readiness Follow-Up (v0.5.0)

**Reviewer role:** Senior Platform / Release Engineer
**Scope:** Follow-up pass against the original Day 6 report (`day-06-release-readiness.md`). Two things were done:

1. An independent, adversarial re-verification of the original report's central claim — **zero Critical and zero High severity findings** — since that report's tone and length warranted a skeptical second look rather than a blind carry-forward.
2. A fix for the one concretely actionable item raised anywhere in the original report's findings: **L3**, the `BW01` Bats advisory warning in `tests/monitoring/monitoring-tools.bats`, which the user separately flagged directly from live `make quality` output.

**Method:** The independent verification was commissioned as a from-scratch adversarial review (not a re-read of the original report's prose) covering the six highest-risk files touched by Day 6: `scripts/common/integrity.sh`, `scripts/release/verify-package.sh`, `scripts/install/install.sh`, `scripts/install/uninstall.sh`, `scripts/diagnostics/integrity-check.sh`, and `scripts/release/package.sh`. It read the current code directly and exercised the safety logic with crafted adversarial inputs (malicious tar members, traversal/prefix-collision manifest paths, dangling/foreign symlinks) in an isolated `mktemp` sandbox — no repository files were modified during this check. The `BW01` fix was applied directly and re-verified with a live `bats` run plus a full `make quality` pass.

---

## 1. Independent Verification of "No Critical/High Findings"

| File | Verdict |
|---|---|
| `scripts/common/integrity.sh` | No Critical/High issue found. `integrity_validate_manifest_line` correctly rejects absolute paths, `../../etc/passwd`, embedded `..` segments, malformed mode/SHA fields. `integrity_git_mode_to_perm` fails closed on any Git mode other than `100644`/`100755` (a symlink or gitlink aborts staging rather than being silently coerced). `integrity_chmod_verified` re-reads the mode via `stat` after every `chmod`, so a filesystem that silently no-ops the call (the exact drvfs failure mode Day 5's H1 was about) is caught, not trusted. |
| `scripts/release/verify-package.sh` | No Critical/High issue found. Six crafted malicious archives (absolute-path member, `../..` traversal, symlink-to-`/etc/passwd`, hardlink-to-`/etc/passwd`, character device, second top-level root) were built and run against the actual embedded Python `tarfile` check — every one was rejected pre-extraction. The check is invoked without a pipeline (`if ! python3 - ... <<'PYEOF'`), so its exit status cannot be swallowed. Snapshot → check → extract all operate on one private `mktemp` copy; no reachable modification window between check and use. |
| `scripts/install/install.sh` | No Critical/High issue found. Archive-mode install performs its **own** independent per-file SHA-256/mode verification (`integrity_verify_and_copy_from_manifest`) rather than trusting a prior `verify-package.sh` run, so a tampered already-extracted tree is still caught at install time. `check_launcher_safety` is re-checked immediately before any mutation (no TOCTOU gap). One sub-High, threat-model-level observation carried to §3 below: the manifest scheme authenticates internal consistency, not publisher identity — a wholesale attacker-crafted archive+manifest pair is internally self-consistent by construction. This is a documented design tradeoff, not a defect, and does not change the release recommendation. |
| `scripts/install/uninstall.sh` | No Critical/High issue found. `validate_manifest_files`'s `case "$path" in "$LIB_DIR"/*)` + `..`-rejection logic was fuzzed with `$LIB_DIR/../evil`, `$LIB_DIR/subdir/../../../etc/passwd`, and a `${LIB_DIR}evil/file` prefix-collision attempt (a path that starts with the same characters as `$LIB_DIR` but is not actually inside it) — all three correctly rejected. Fail-closed behavior on duplicate/empty entries reconfirmed. |
| `scripts/diagnostics/integrity-check.sh` | No Critical/High issue found. Strictly read-only; reuses the same hardened path-validation primitives as `integrity.sh`; never writes or attempts repair. |
| `scripts/release/package.sh` | No Critical/High issue found. Staging derives every path and mode from `git ls-files`; `cp -a` is not used anywhere in this file. |

**Conclusion:** the original Day 6 report's finding — zero Critical, zero High — is independently confirmed, not merely restated. No code changes were required or made as a result of this check.

---

## 2. Fix Applied: L3 (`BW01`/`BW02` Bats Advisory Warnings)

**Before:** `make quality` passed 370/370 tests but printed three `BW01` advisory warnings from `tests/monitoring/monitoring-tools.bats`:

```
BW01: `run`'s command ... exited with code 127, indicating 'Command not found'.
Use run's return code checks, e.g. `run -127`, to fix this message.
```

**Root cause:** the three "fails when `<dep>` is unavailable" tests (`memory-report.sh`/`cpu-monitor.sh`/`load-average.sh`, each run with its one required command shadowed off `PATH`) captured the resulting `127` exit via plain `run ...` followed by a separate `[ "$status" -eq 127 ]` assertion. Bats treats an unchecked `127`/`126`/`>128` exit captured by plain `run` as a likely mistake (usually an accidentally-misspelled command) and emits `BW01` to flag it, even when the `127` is fully intentional and asserted immediately afterward.

**Fix:** `tests/monitoring/monitoring-tools.bats` — changed all three tests to `run -127 "$REAL_BASH" ...`, which tells Bats the `127` is expected and asserts it as part of `run` itself (the separate `[ "$status" -eq 127 ]` line is now redundant and was removed). Using `run`'s flag form additionally requires declaring a minimum Bats version, so `bats_require_minimum_version 1.5.0` was added once at file scope (the installed `bats` is 1.10.0, well above this floor).

**Verification:**
- `bats tests/monitoring/monitoring-tools.bats` — 9/9 pass, zero `BW01`/`BW02` warnings (confirmed both before-and-after: adding `run -127` alone still triggered a new `BW02` version-guard warning, which the `bats_require_minimum_version` line then cleared).
- Full `make quality` — 370/370 Bats tests pass, `validate`/`lint`/`check-executable` all clean, no regressions introduced anywhere else in the suite.

**Scope discipline:** only `tests/monitoring/monitoring-tools.bats` was touched for the fix itself; `CHANGELOG.md` received one new `### Fixed` bullet under the still-untagged `[0.5.0]` entry documenting it. No other file was modified.

---

## 3. Findings Carried Forward, Unchanged

Per the original Day 6 report (§5), the following remain open and are explicitly **not** addressed by this follow-up, since none is Critical or High and none was the subject of this pass:

- **L1** — `verify-package.sh`'s extra-file scan layering is correct but undocumented; a one-line comment would help future readers.
- **L2** — `check-executable` is only actually exercised when `release-check`'s `quality → package` ordering is followed; worth a documentation note.
- **L4** — local `make release-check` iteration does not auto-clean `dist/` between runs.
- **L5** — `install.bats`'s "installed CLI runs doctor successfully" test still doesn't shadow `PATH` via `stub_shadow_path_except`.
- **L6** — a handful of non-security-relevant branches (`config-manager.sh` unexpected-argument paths, `install.sh`'s foreign-symlink-at-launcher case, `uninstall.sh`'s `remove_launcher` warn branch) remain untested.
- The threat-model observation on `install.sh` noted in §1 above (manifest-based integrity, not publisher-identity signing) is worth a documentation callout in a future pass but does not block this release — it is an explicit, reasonable design boundary, not a gap relative to what Day 6 claimed to deliver.

---

## 4. Final v0.5.0 Readiness Recommendation

**Ready to tag v0.5.0 — unchanged from the original Day 6 recommendation.**

The only fix this follow-up required was cosmetic (a Bats advisory-warning cleanup, L3), and it is applied and verified with zero regressions across the full 370-test suite. The original report's "zero Critical, zero High" finding was independently re-derived from the code itself, under adversarial testing, rather than taken on faith — and it holds. No new Critical, High, or Medium finding was discovered in this pass.
