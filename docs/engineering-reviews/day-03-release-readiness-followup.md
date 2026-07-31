# Engineering Review — Day 3 Release-Readiness Follow-Up (v0.2.0)

**Reviewer role:** Senior Platform Engineer
**Scope:** Follow-up pass re-verifying the sole release blocker from the original Day 3 report (`day-03-release-readiness.md`) — the command-injection vulnerability in `scripts/network/port-check.sh` (C1) — plus the Medium (M1) and Low (L1) findings fixed alongside it, and a full re-run of every check from the original report to confirm no regressions.
**Method:** All commands executed live inside WSL Ubuntu against the working tree at `/mnt/f/DevOps-Portfolio/maops-linux-devops-toolkit`. No public internet access was used or required.

---

## 1. What Changed Since the Original Report

| File | Change |
|---|---|
| `scripts/network/port-check.sh` | **C1 fix:** replaced `bash -c "exec 3<>/dev/tcp/$HOST/$PORT"` (string interpolation, re-parsed by the inner shell) with `bash -c 'exec 3<>"/dev/tcp/$1/$2"' bash "$HOST" "$PORT"` (parameterized — `$HOST`/`$PORT` are the inner shell's own positional parameters, never re-tokenized as command syntax). **M1 fix:** `parse_args()` now recognizes a leading-dash negative number (`-[0-9]*`) as a positional argument instead of an unknown flag, so `validate_tcp_port`/`validate_positive_integer` report it with an accurate message. |
| `scripts/network/ping-check.sh` | **M1 fix:** same `-[0-9]*` case-arm addition in `parse_args()` for `COUNT`. |
| `tests/network/network-tools.bats` | Added a regression test proving the injection no longer executes (`port-check.sh does not execute shell metacharacters embedded in HOST`), plus three message-content tests confirming the corrected negative-number error text for `COUNT`, `PORT`, and `TIMEOUT`. Suite grew from 46 to 49 tests. |
| `CONTRIBUTING.md` | **L1 fix:** added Bats to the "Required tools" list. |
| `CHANGELOG.md` | Added a "Fixed" section under the still-untagged `[0.2.0]` entry documenting all three fixes above. |
| `docs/architecture.md` §8 | Documents why `HOST` is intentionally unvalidated (no safe regex that doesn't also reject IPv6 literals) and explains the new parameterized `bash -c` invocation, with a pointer to the historical vulnerability it replaces. |
| `docs/best-practices.md` | New §11, "Parameterized `bash -c`, Instead of String Interpolation" — a general convention for any future script that hands untrusted data to a nested shell, using this exact bug as the worked example. |
| `docs/troubleshooting.md` | New §12 walking through the original vulnerable code, a live reproduction of the exploit, and the fix — written so a future contributor who finds this pattern elsewhere in the codebase knows what to do. |
| `docs/roadmap.md` | Records both fixes under the Network module's "Completed" section with cross-references. |

`README.md` was reviewed for accuracy against these changes; no update was needed — it documents CLI usage and exit-code conventions at a level that doesn't change (the fix is entirely internal to how `port-check.sh` invokes a subshell, not a change to its documented interface or exit-code behavior).

No file outside this set was modified.

---

## 2. Live Re-Verification

### 2.1 The original exploit, re-run against the fixed script

```bash
$ rm -f /tmp/maops_injection_test_marker
$ ./scripts/network/port-check.sh '127.0.0.1;touch /tmp/maops_injection_test_marker;' 80 1
--------------------------------------------------------------------------------
Port Check
--------------------------------------------------------------------------------
[INFO] Checking 127.0.0.1;touch /tmp/maops_injection_test_marker;:80 (timeout 1s)...
[ERROR] Port 80 is not reachable on 127.0.0.1;touch /tmp/maops_injection_test_marker;.
EXIT:1
$ [[ -f /tmp/maops_injection_test_marker ]] && echo VULNERABLE || echo FIXED
FIXED
```

Also re-confirmed through the full CLI dispatcher (`bin/maops network port '127.0.0.1;touch ...;' 80 1`) — same result, no marker file created. The crafted `HOST` is now treated as what it is: a malformed, unresolvable path segment, not executable code.

### 2.2 `ping-check.sh` and `dns-lookup.sh`, re-confirmed as never vulnerable

Both still pass `HOST`/`TARGET` as a plain argument to `ping`/`getent hosts` rather than through any re-parsed shell string; the same crafted value produces only a resolution failure, no side effect. Unchanged from the original report's findings.

### 2.3 Negative-number messages (M1)

```bash
$ ./scripts/network/ping-check.sh 127.0.0.1 -1
[ERROR] COUNT must be a positive integer: -1        # was: "Unknown option: -1"
$ ./scripts/network/port-check.sh 127.0.0.1 -1
[ERROR] Port must be an integer from 1 to 65535: -1  # was: "Unknown option: -1"
$ ./scripts/network/port-check.sh 127.0.0.1 80 -1
[ERROR] TIMEOUT must be a positive integer: -1       # was: "Unknown option: -1"
```

All three still exit `2`, matching the previously-passing Bats expectations — only the message changed, from misleading to accurate.

### 2.4 Full quality gate

```text
$ make quality
Validating Bash syntax...
Bash syntax validation passed.
Running ShellCheck...
ShellCheck passed.
Checking Git executable modes...
Executable-mode validation passed.
Running Bats tests...
1..49
ok 1..49
Bats tests passed.
All repository quality checks passed.
```

49/49 Bats tests pass (up from 46 — the 3 new tests are the regression coverage for C1 and M1). ShellCheck is clean, including the intentionally single-quoted `bash -c` script in the fix (`# shellcheck disable=SC2016` added with a one-line reason, since the whole point of that line is that `$1`/`$2` do *not* expand in the outer shell).

### 2.5 Full re-run of every command from the original report

| Command | Result |
|---|---|
| `bin/maops --help` | Exit `0`, unchanged output. |
| `bin/maops --version` | Exit `0`, `MAOps Linux DevOps Toolkit 0.2.0`. |
| `bin/maops system hostname` | Exit `0`. |
| `bin/maops filesystem largest /usr 5` | Exit `0`, 5 sorted entries. |
| `bin/maops network info` | Exit `0`. |
| `bin/maops network dns localhost` | Exit `0`. |
| `bin/maops network ping 127.0.0.1 1` | Exit `0`. |
| Unknown CLI command | Exit `2`, unchanged. |
| Invalid ping count (`0`, `abc`, `-1`) | Exit `2` in all three; `-1`'s message is now accurate (§2.3). |
| Invalid port (`0`, `65536`, `abc`, `-1`) | Exit `2` in all four; `-1`'s message is now accurate. |
| Invalid timeout (`0`, `-1`, `abc`) | Exit `2` in all three; `-1`'s message is now accurate. |
| Executable-mode sweep | All 21 tracked `.sh`/`bin/maops` files still `100755`. |
| Version consistency | `PROJECT_VERSION="0.2.0"` still matches `CHANGELOG.md`. |

No regression anywhere in the original command set.

---

## 3. Resolved Findings

| Finding | Verdict | Evidence |
|---|---|---|
| **C1** — Command injection via `HOST` in `port-check.sh` | **Resolved** | Live exploit re-run against the fixed script produces no side effect (§2.1); new Bats regression test (`port-check.sh does not execute shell metacharacters embedded in HOST`) passes; fix applies the same way whether invoked directly or through `bin/maops`. |
| **M1** — Misleading "Unknown option" message for negative numeric arguments | **Resolved** | All three call sites (`ping-check.sh COUNT`, `port-check.sh PORT`, `port-check.sh TIMEOUT`) now report the correct, specific validation message; exit code `2` unchanged in all cases; 3 new Bats tests assert the message text directly. |
| **L1** — `CONTRIBUTING.md` missing Bats | **Resolved** | Bats added to the "Required tools" list. |

## 4. Unresolved / Carried-Over Findings

Unchanged from the original report — none of these were in scope for this fix pass and none are release-blocking:

- **L2** — `show_footer()` in `scripts/common/output.sh` remains dead code (carried over from Day 2).
- **L3** — Inconsistent `# shellcheck source=` convention between `scripts/filesystem/`/`templates/script-template.sh` (`/dev/null`) and the rest of the tree (real path); the network module already uses the better, real-path convention.
- **L4** — `actions/checkout@v4` still pinned to a floating major-version tag rather than a commit SHA.

## 5. New Findings

None. This pass was a targeted fix-and-reverify cycle, not a fresh full-repository audit — the original report's Critical/High/Medium/Low breakdown otherwise stands.

---

## 6. Revised Category Scores

| # | Category | Original Score | Current Score | Delta | Rationale |
|---|---|---|---|---|---|
| 1 | Architecture | 9 | 9 | 0 | Unchanged — the fix is internal to one script's subshell invocation, not a structural change. |
| 2 | Bash correctness | 7 | 9 | +2 | The one genuinely unsafe construction in the codebase (string-interpolated `bash -c`) is now the documented, parameterized-safe pattern; everything else that was already correct remains correct. |
| 3 | CLI usability | 8 | 9 | +1 | M1 resolved — every validation failure now reports what actually went wrong, not a misleading "unknown option" for a plain negative number. |
| 4 | Error handling | 8 | 9 | +1 | Same root cause as CLI usability — validation messages now match the actual validator that rejected the input. |
| 5 | Network portability | 9 | 9 | 0 | Unchanged — same tool choices, same portability story. |
| 6 | Automated testing | 7 | 9 | +2 | The exact gap the original report called out — "there is no adversarial-`HOST` test" — is now closed with a live regression test, plus explicit message-assertion coverage for M1. |
| 7 | Security | 2 | 9 | +7 | The disqualifying finding is fixed and independently re-verified via live exploit re-run; docked one point rather than a perfect score because `HOST` remains intentionally unvalidated by design (safe-by-construction via the parameterized invocation, not by input filtering) — a reasonable and well-documented tradeoff, but worth naming as the reason this isn't a 10. |
| 8 | Maintainability | 9 | 9 | 0 | Unchanged — fix follows the same file/function shape as everything else. |
| 9 | CI quality | 7 | 7 | 0 | No change — `make quality` still mirrors CI exactly and still passes; L4 (checkout pinning) remains open. |
| 10 | Documentation | 8 | 9 | +1 | The vulnerability and its fix are now documented in three places (`architecture.md`, `best-practices.md`, `troubleshooting.md`) with cross-references, closing the original report's specific critique that "none of that documentation anticipated... the injection risk." Not a 10 because L2/L3 cleanup items remain open. |

**Overall score: 8.8 / 10** (up from 7.4/10 in the original Day 3 report)

---

## 7. Strongest Three Areas

1. **Security (2 → 9)** — the largest mover by far. A confirmed, live-reproduced command-injection vulnerability reachable from the ordinary public CLI surface is now fixed using the standard-safe idiom (parameterized `bash -c`, not string interpolation), independently re-verified with the exact same exploit string that originally proved the bug.
2. **Automated testing (7 → 9)** — the original report's own stated gap ("no adversarial-`HOST` test... exactly the gap that let C1 through") is now closed with a dedicated regression test, and the message-content assertions for M1 mean a future refactor that reintroduces the misleading error text would also be caught.
3. **Bash correctness (7 → 9)** — the one unsafe shell-construction pattern in the codebase is gone, replaced with a pattern now formally documented as the project's convention (`best-practices.md` §11) for any future script facing the same problem.

## 8. Remaining Priorities (Ranked)

All Critical/High/Medium findings are resolved. What remains is Low-priority cleanup, unchanged in substance from the original report:

1. **Decide the fate of `show_footer()`** (L2) — wire it in or delete it.
2. **Standardize the `shellcheck source=` convention** (L3) on the real-path style the network module already uses correctly.
3. **Pin `actions/checkout` to a commit SHA** (L4) — deferred in this pass since it requires looking up the correct SHA externally; a wrong guess would break CI outright, which is worse than leaving the current major-version pin in place. Do this deliberately, with the real SHA in hand, rather than as a rushed side-fix.

## 9. Final v0.2.0 Readiness Recommendation

**Ready to tag v0.2.0.**

The sole release blocker identified in the original Day 3 report — the `port-check.sh` command injection — is fixed and independently re-verified with the same live exploit that originally demonstrated it, and a permanent regression test now guards against it recurring. The two smaller findings fixed alongside it (the misleading negative-number message, and the missing Bats entry in `CONTRIBUTING.md`) are both confirmed resolved with no regressions anywhere in the original report's command set: `make quality` passes 49/49 Bats tests plus syntax/lint/executable-mode checks, every smoke command and edge case behaves identically or better than before, and executable modes and version metadata remain consistent.

The only items left open (L2, L3, L4) are pre-existing Low-severity cleanup, none of which affect correctness, security, or CI outcome, and none of which were release-blocking in the original report either. There is no remaining Critical, High, or Medium finding in this repository.

**Recommendation: tag v0.2.0.**
