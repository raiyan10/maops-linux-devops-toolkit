# Engineering Review — Day 4 Release-Readiness (v0.3.0)

**Reviewer role:** Senior Platform Engineer
**Scope:** Full-repository release-readiness review for v0.3.0, covering the new read-only `scripts/users/user-report.sh`, `scripts/process/process-monitor.sh`, and `scripts/service/service-status.sh` modules, their `bin/maops` dispatch routes (`user report`, `process top`, `service status`), the new `is_non_option_argument`/`validate_non_option_argument` and `is_one_of`/`validate_one_of` helpers in `scripts/common/cli.sh`, the deterministic PATH-based Bats stub convention (`stub_bin_init`/`stub_command` in `tests/test-helper.bash`), preservation of all Day 1–3 functionality and tests, executable-mode hygiene, version metadata, and documentation accuracy.
**Method:** All commands executed live inside WSL Ubuntu against the working tree at `/mnt/f/DevOps-Portfolio/maops-linux-devops-toolkit` (branch `feature/day-4-operations-modules`) — no public internet access was used or required. Adversarial input (shell metacharacters, command-substitution syntax, option-like values, out-of-range and non-numeric values) was tested against `user report`, `process top`, and `service status` without starting, stopping, restarting, enabling, disabling, killing, or renicing any real service or process. No implementation, workflow, or other documentation files were modified; only this report was added.

---

## 1. Commands Run and Results

| Command | Result |
|---|---|
| `make quality` | **Pass.** `validate` → `lint` → `check-executable` → `test` all pass; **116/116** Bats tests green. |
| `bin/maops --version` | Exit `0`, `MAOps Linux DevOps Toolkit 0.3.0`. |
| `bin/maops user report` | Exit `0`. Reported the current effective user (`raiyan10`, resolved via `id -un`) — username, UID, primary GID/name, home directory, shell, groups, session count, active-session flag. No password hash or GECOS field present in output. |
| `bin/maops process top 5 cpu` | Exit `0`. Five rows, sorted by `%CPU` descending (verified: `claude` 16.4 → `bash` 11.1 → three `0.0` entries), `COMMAND` column shows executable name only (no full command line/args). |
| `bin/maops process top 5 memory` | Exit `0`. Five rows, sorted by `%MEM` descending, distinct ordering from the CPU run as expected. |
| `bin/maops user report <nonexistent>` | Exit `1`, `User not found: <name>`. |
| `bin/maops user report 'alice;touch /tmp/pwned_test;'` | Exit `1` (treated as a literal, nonexistent username by `getent passwd`) — **no file created**, no shell metacharacter executed. |
| `bin/maops user report --bogus` | Exit `2`, `USERNAME must not be empty or start with '-': --bogus`. |
| `bin/maops user report alice bob` | Exit `2`, `Too many arguments. Expected at most one USERNAME.` |
| `bin/maops process top 0` | Exit `2`, `LIMIT must be a positive integer: 0`. |
| `bin/maops process top -1` | Exit `2`, `LIMIT must be a positive integer: -1` (correct, specific message — not a generic "unknown option"). |
| `bin/maops process top "5;touch /tmp/pwned_proc;"` | Exit `2`, rejected by `validate_positive_integer` before any `ps` invocation — **no file created**. |
| `bin/maops process top '$(touch /tmp/pwned_sub)'` | Exit `2`, rejected before use — **no file created**, no command substitution executed. |
| `bin/maops process top 5 disk` | Exit `2`, `SORT must be one of: cpu, memory (got: disk)`. |
| `bin/maops process top 100000 cpu` | Exit `0` in 0.09s, output naturally bounded by the real process count — no hang, no resource issue. |
| `bin/maops service status` (no arg) | Exit `2`, `SERVICE is required.` |
| `bin/maops service status -x` | Exit `2`, `SERVICE must not be empty or start with '-': -x`. |
| `bin/maops service status <nonexistent unit>` | Exit `1`, `Unknown service: <name> (no such unit)`. |
| `bin/maops service status 'cron;touch /tmp/pwned_svc;'` | Exit `1` (treated as a literal, unrecognized unit name) — **no file created**. |
| `bin/maops bogus group` / `bin/maops` (no args) | Exit `2` in both cases, full usage text printed to stderr. |
| Executable-mode sweep (`git ls-files -s`) | `bin/maops`, `scripts/common/cli.sh`, `scripts/common/config.sh`, and all three new leaf scripts are `100755`. The three new `.bats` files are `100644` — correct per the documented convention (Bats files are intentionally excluded from `make check-executable`'s `*.sh`/`bin/maops` glob). |
| Version consistency sweep | `PROJECT_VERSION="0.3.0"` (`config.sh`) matches `CHANGELOG.md`'s `## [0.3.0]` entry, the `Version:` header comments in `user-report.sh`/`process-monitor.sh`/`service-status.sh`, and every `--version` assertion across `tests/*.bats`. |
| Day 1–3 preservation check | `tests/network/network-tools.bats` (19 tests, last touched in the Day 3 commit) is unmodified and passes unchanged as part of the same `make quality` run. |
| `bash -n` on every script | All pass (part of `make validate`). |

---

## 2. Findings

### Critical

None found.

### High

None found. Extensive live adversarial testing (shell metacharacters, `$(...)` command substitution, option-like values, negative/zero/non-numeric/out-of-range values, oversized `LIMIT`) against all three new modules produced no injection, no unintended mutation, and no crash — every case was rejected with the correct exit code before any side-effecting command ran, or resolved to a correct, harmless negative result (`User not found`, `Unknown service`).

### Medium

None found.

### Low

**L1 — Inconsistent option-like-argument error wording between `process-monitor.sh` and `user-report.sh`/`service-status.sh`.**
`user-report.sh` and `service-status.sh` route every leading-dash value (numeric or not) through `validate_non_option_argument`, producing a consistent, label-specific message: `USERNAME must not be empty or start with '-': --bogus`. `process-monitor.sh` instead special-cases only the *numeric* leading-dash case (`-[0-9]*`) to get the equivalent specific message (`LIMIT must be a positive integer: -1`); a non-numeric leading-dash value like `--bogus` still falls through to the generic `cli_usage_error "Unknown option: $1"` branch. Both paths correctly exit `2` in every case tested, so this is a wording/UX consistency nit, not a functional or security defect.

**L2 — No `--` end-of-options marker support.**
`bin/maops process top -- -1` prints `Unknown option: --` rather than treating `-1` as `LIMIT` after an explicit end-of-options marker. None of the three new scripts (or the pre-existing network scripts) support `--`, so this is consistent with the rest of the codebase rather than a regression — flagged only because a negative `LIMIT` is otherwise reachable exclusively through `process-monitor.sh`'s existing `-[0-9]*` special case.

**L3 (carried over from Day 3, unchanged) — `scripts/network/*.sh` still stamp `Version: 0.2.0`** in their header comments while `PROJECT_VERSION` and the three new Day 4 scripts correctly say `0.3.0`. Already tracked as a known, deferred cleanup in `docs/roadmap.md` ("Per-script `Version:` header stamps are inconsistent"); cosmetic only, since `bin/maops --version`/`cli_show_version` always read the single source of truth (`config.sh`'s `PROJECT_VERSION`), never a per-script header comment.

### Future Enhancements

- Extend Bats coverage to `scripts/common/{colors,config,helpers,logger,output}.sh` and the `system`/`monitoring`/`filesystem` leaf scripts (already tracked in `docs/roadmap.md` as Planned) — the Day 4 additions themselves are thoroughly covered, but this gap predates Day 4 and remains open.
- Consider pinning `actions/checkout@v4` to a commit SHA rather than a floating major-version tag in `.github/workflows/bash-validation.yml`, for defense-in-depth supply-chain hardening (carried over from the Day 3 review's L4, still unresolved, still non-blocking).
- Resolve L1/L2 above together if `scripts/common/cli.sh`'s option-parsing convention is ever revisited — e.g. giving every leaf script's generic `-*` branch the same `validate_non_option_argument`-style fallback that `process-monitor.sh` only applies to the numeric case today.
- The last-login / historical login-history report deferred from the Day 4 user module (noted in `docs/roadmap.md`) remains a reasonable Day 5+ candidate.

---

## 3. Category Scores

| # | Category | Score /10 | Rationale |
|---|---|---|---|
| 1 | Architecture | 9 | `user`/`process`/`service` each get their own `dispatch_<group>()` following the exact same pattern as every existing group, despite having only one command each — verified in `bin/maops` and confirmed by `architecture.md` §7's stated rationale ("keeps every group uniform instead of forking `main()`"). |
| 2 | Bash correctness | 9 | `set -euo pipefail` and consistent quoting throughout; `process-monitor.sh`'s `awk`-based row truncation (never `head`) correctly avoids the SIGPIPE/141 class of bug already fixed once in `largest-files.sh` — confirmed live with `ps` stubbed to emit far more rows than `LIMIT` and no SIGPIPE observed. |
| 3 | CLI usability | 8 | Clear, consistent `--help`/`--version`/usage text across all three new scripts; docked for L1/L2's minor option-like-argument wording inconsistency between `process-monitor.sh` and the other two new scripts. |
| 4 | Error handling | 9 | The three-way exit-code contract (`0`/`1`/`2`) from `best-practices.md` §15 is applied without exception; `service-status.sh` correctly distinguishes a genuine bus/connection failure from a legitimately inactive unit (both exit `1`, but never silently conflated) — confirmed live via the systemd-branch and fallback-branch stub tests. |
| 5 | Security and privacy | 10 | Zero injection vectors found under live adversarial testing across all three new modules (shell metacharacters, `$(...)`, option-injection); no `eval`, `bash -c`, or re-parsed shell string anywhere in the three scripts; `SORT`/`LIMIT`/`USERNAME`/`SERVICE` never reach a downstream command except as a validated value or a fixed-literal `case`/`awk -v` binding. |
| 6 | User reporting | 9 | `user-report.sh` structurally cannot leak a password hash — the passwd password field is read into `_` and discarded, `/etc/shadow`/`getent shadow` are never touched — confirmed live: real output for `raiyan10` contained no hash-shaped field, and the Bats suite has a dedicated regression test asserting this. |
| 7 | Process monitoring | 9 | Sort key is chosen via a fixed `case` statement only after `SORT` passes `validate_one_of`, so user input never reaches `ps --sort=` directly; `comm` (not `args`) is reported so command-line secrets are never exposed — confirmed live and via a dedicated Bats test asserting `kill`/`pkill`/`renice`/`nice` never appear in the script's source. |
| 8 | Service portability | 9 | The `/run/systemd/system` probe (matching `sd_booted(3)`) correctly avoids the "systemctl binary present but systemd not PID 1" trap that affects containers and WSL; `MAOPS_SYSTEMD_RUNTIME_DIR` is a genuinely read-only test seam — confirmed both branches are exercised deterministically in the Bats suite and that neither ever invokes a mutating `systemctl`/`service` verb. |
| 9 | Automated testing | 10 | 116/116 Bats tests pass, up from Day 3's 46 — all 70 new tests, plus injection/option-injection regression coverage for `USERNAME`, `SERVICE`, and `LIMIT`; the deterministic PATH-based stub convention (`stub_bin_init`/`stub_command`) cleanly isolates `getent`/`id`/`who`/`ps`/`systemctl`/`service` from host state without checking a stub into the repo (which would have bypassed `check-executable`'s glob, the exact class of gap the convention's own documentation calls out). |
| 10 | CI and documentation | 9 | `make quality` (unchanged target) still mirrors CI exactly; `CHANGELOG.md`, `architecture.md` §9, `best-practices.md` §12–§15, and `roadmap.md` are unusually thorough and were spot-checked line-by-line against the actual implementation with no discrepancy found — docked only for the pre-existing, already-tracked items (L3, and the Day 3 carryover on `actions/checkout` pinning). |

**Overall score: 9.1 / 10**

This is a clear step up from Day 3's closing score of 7.4/10 (which was capped by a since-fixed Critical command-injection finding). Day 4's three new modules were purpose-built around the lesson from that review — every one of `user-report.sh`, `process-monitor.sh`, and `service-status.sh` explicitly documents, in-source, why it cannot be tricked into `eval`-style re-parsing — and live adversarial testing this session found no exception to that claim.

---

## 4. Strongest Three Areas

1. **Security and privacy (10/10)** — the elimination of injection vectors is structural, not incidental: `awk -v user=`/`awk -v limit=` bindings, a fixed `case` statement gating the `ps --sort=` value, and passwd's password field discarded into `_` before it can ever reach output. This session's live testing (`;touch ...`, `$(touch ...)`, option-like values) against `user report`, `process top`, and `service status` produced zero successful injections and zero unintended file creations.
2. **Automated testing (10/10)** — the deterministic PATH-based stub convention (`stub_bin_init`/`stub_command`) solves a real problem (real `getent`/`ps`/`systemctl` output is host-dependent and non-reproducible in CI) without introducing the WSL/drvfs executable-mode risk a checked-in stub would have created, and the resulting 70 new tests include explicit injection-regression coverage, not just happy-path assertions.
3. **Documentation accuracy (part of the 9/10 CI-and-documentation score)** — `architecture.md` §9 and `best-practices.md` §12–§15 describe the systemd-detection probe, the LSB exit-code fallback, the `awk`-over-`head` SIGPIPE avoidance, and the read-only guarantee in enough concrete detail that every claim could be (and was) independently verified against the live source and live command output with no discrepancy.

---

## 5. Five Highest-Priority Improvements

1. **Unify option-like-argument rejection wording (L1)** — give `process-monitor.sh`'s generic `-*` branch the same `validate_non_option_argument`-style message the other two new scripts use, so `--bogus` reads the same way across `user report`, `process top`, and `service status`.
2. **Decide on `--` end-of-options support project-wide (L2)** — either document that none of `maops`'s leaf scripts support it (matching current behavior) or add it consistently; low risk either way, but worth a single explicit decision rather than leaving it implicit.
3. **Extend Bats coverage to the core `scripts/common/*.sh` libraries and the `system`/`monitoring`/`filesystem` leaf scripts** — already tracked in `roadmap.md`; closing this gap would bring the *whole* repository, not just the Day 4 additions, up to the same testing bar this review scored 10/10.
4. **Resolve the two carried-over Day 3 Low findings** — pin `actions/checkout` to a commit SHA, and reconcile the `scripts/network/*.sh` `Version:` header stamps with `PROJECT_VERSION` (L3) — both are one-line fixes that remove the last sources of drift between what a reader sees and what is actually true.
5. **Consider a machine-readable output mode** (`--json` or similar) for `user report`/`process top`/`service status` now that all three have a stable, well-tested field set — a natural next step if these modules are ever consumed by other automation rather than a human operator, carried forward from the same suggestion made in the Day 3 review.

---

## 6. Unresolved Release Blockers

None. `make quality` (116/116 Bats tests), all four required smoke commands, all documented adversarial-input cases, the executable-mode sweep, and the version-consistency sweep all passed cleanly. No Day 1–3 Critical/High finding has regressed — the Day 3 command-injection fix in `port-check.sh` remains in place and its regression test still passes as part of the unmodified `tests/network/network-tools.bats`.

---

## 7. Final v0.3.0 Readiness Recommendation

**Ready to tag v0.3.0.**

The three new read-only modules — `user-report.sh`, `process-monitor.sh`, `service-status.sh` — work exactly as documented and as demonstrated live in this review: correct default/explicit-user resolution, correct CPU/memory sort ordering with SIGPIPE-safe truncation, and correct systemd/`service(8)` detection and fallback with a genuinely read-only test seam. Every adversarial input attempted this session (shell metacharacters, command substitution, option-like values, out-of-range and oversized numeric values) was rejected safely with the correct exit code and no side effect, and the read-only guarantee — no `start`/`stop`/`restart`/`enable`/`disable`/`kill`/`pkill`/`renice` anywhere in the three modules — held under both source inspection and live execution. `PROJECT_VERSION`, `CHANGELOG.md`, and all `--version` assertions agree on `0.3.0`; all newly added scripts are correctly tracked as `100755`; and documentation (`README.md`, `architecture.md`, `best-practices.md`, `roadmap.md`) was independently verified against the real implementation with no discrepancy found. The three Low findings and four future enhancements above are all genuine improvements worth scheduling, but none of them individually or collectively rises to release-blocking severity.
