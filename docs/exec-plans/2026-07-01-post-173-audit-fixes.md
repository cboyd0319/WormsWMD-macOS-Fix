# Post-1.7.3 Audit Fixes

Status: Completed

## Problem

The post-release adversarial audit found edge-case gaps after v1.7.3: not all
mutated config files are backed up and restored, verify/dry-run detection is
less complete than apply/preflight detection, a custom launch-helper reapply can
lose `GAME_APP`, multiple installs can be silently targeted, and docs can
overstate exact commit verification for tag bootstraps.

## Scope and non-goals

In scope:

- Main installer game detection, backup, rollback, restore, dry-run, and verify
  behavior.
- Config URL mutation and verification lists.
- Enhanced launch helper custom `GAME_APP` reapply path.
- Regression tests, docs, and harness indexes for the changed behavior.
- Repo harness tightening inspired by the Tamworth harness: repo-local agent
  layer, stricter docs/path/CI/CODEOWNERS gates, and action workflow linting.
- Fresh local Steam validation and a second adversarial audit.
- Cross-check of the five most recent reported GitHub issues (#12 through #8)
  against current tests and fixes.

Out of scope:

- Publishing a new release.
- Replacing the Qt archive.
- Changing the core Qt/AGL runtime strategy beyond the audited edge fixes.

## Constraints and risks

- Preserve save data and the game-bundle backup/rollback contract.
- Do not add privileges, dependencies, or system-wide writes.
- Preserve Steam and GOG behavior, custom `GAME_APP` paths, macOS 26+, and local
  Steam validation.
- Treat user-provided paths and refs as untrusted.

## Milestones

- [x] Milestone 1: Add failing regressions for all audit findings.
- [x] Milestone 2: Patch the smallest production changes.
- [x] Milestone 3: Update docs and validation indexes.
- [x] Milestone 3a: Tighten repo harness configuration, rules, and enforcement.
- [x] Milestone 4: Run focused checks, full relevant suite, local Steam smoke,
  and fresh adversarial review.
- [x] Milestone 5: Run final issue-driven hardening, destructive-path checks,
  real local Steam reapply, and final adversarial review.

## Verification

```bash
./tools/test_issue_11_game_detection.sh
./tools/test_installer_rollback_regression.sh
./tools/test_launcher_friction.sh
./tools/test_mutation_safety.sh
./tools/test_bootstrap_installer_safety.sh
./tools/validate_harness.sh
./tools/test_dependency_parsing.sh
./tools/test_issue_10_regression.sh
./tools/test_issue_12_agl_install_failure.sh
./tools/test_support_bundle_sanitization.sh
./tools/test_backup_saves_regression.sh
./tools/test_preflight_regression.sh
./tools/test_manifest_regression.sh
./tools/test_qt_version_pinning.sh
./scripts/download_qt_frameworks.sh --check
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
./fix_worms_wmd.sh --dry-run
./fix_worms_wmd.sh --verify
./tools/preflight_check.sh --quick
./tools/collect_diagnostics.sh
./tools/launch_worms.sh --check-fix --log-file "$HOME/Library/Logs/WormsWMD-Fix/post-audit-launch.log" --no-crash-report
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
actionlint .github/workflows/*.yml
git diff --check
```

## Progress

- 2026-07-01: Started after post-v1.7.3 adversarial audit findings.
- 2026-07-01: Added failing regressions for GOG verify/dry-run detection,
  noninteractive multiple-install ambiguity, launcher custom `GAME_APP` reapply,
  and rollback of all mutated config files.
- 2026-07-01: Patched installer detection, shared config mutation lists,
  launcher reapply, and release/bootstrap backup documentation.
- 2026-07-01: Compared against the Tamworth harness and added a small `.agents`
  layer, stricter harness marker/line/path gates, required CI regression checks,
  full-SHA GitHub Action pin enforcement, and CODEOWNERS coverage for
  trust-sensitive harness surfaces.
- 2026-07-01: Second adversarial pass found and fixed two follow-up edges:
  empty `GAME_APP` no longer disables auto-detection, and `--verify` now uses
  read-only game validation instead of mutation-path validation.
- 2026-07-01: Reviewed GitHub issues #12, #11, #10, #9, and #8. Added direct
  regression coverage for the #8/#9 optional WebP `libsharpyuv` verifier path.
- 2026-07-01: Reopened for a final comprehensive hardening loop after request
  to fully test, anticipate, and resolve remaining edge cases.
- 2026-07-01: Added mutation-safety regression coverage for malformed critical
  bundle paths and symlinked/hardlinked config files before mutation.
- 2026-07-01: Added bootstrap installer safety coverage for `INSTALL_DIR`
  values that resolve through symlinks or `..` into system paths.
- 2026-07-01: Added logging and launcher path-safety coverage so rejected log
  paths do not create outside directories, hardlinked log files are refused,
  and safe nested log paths under `~/Library/Logs` still work.
- 2026-07-01: Ran a real local Steam `--force` reapply on macOS 27.0, then
  verified the install, ran preflight and diagnostics, and completed a bounded
  launch smoke with no leftover Worms process and no fresh crash report.

## Surprises & Discoveries

- Empty `GAME_APP` was a real edge: the path defaulted, but the explicit flag
  disabled auto-detection. The installer now treats only non-empty `GAME_APP` as
  explicit.
- `--verify` should be read-only validation. It no longer requires
  mutation-safe bundle paths before running verification.
- Recent issue reports cluster around partial runtime installs, GOG detection,
  backup progress, and dependency parsing. Current focused tests now cover each
  cluster directly.
- Creating log directories before validation was a real side-effect bug. The
  final fix validates creatable paths against `~/Library/Logs` before creating
  them, including paths whose safe nested parents do not exist yet.

## Decision Log

- Use regression-first changes for every concrete bug from the audit.
- Keep the Worms harness on execution plans rather than importing Tamworth's
  feature ledger. Port only the agent layer and mechanical gates that fit this
  repo.

## Outcomes & Retrospective

All post-v1.7.3 audit findings were patched with focused regressions. The
second pass found two additional detection/verification edges and both were
fixed. The final hardening loop added bootstrap path safety, mutation safety,
and logging side-effect coverage. The harness now enforces repo-local agent
files, marker sections, line caps, local-path hygiene, required CI checks,
full-SHA GitHub Action pins, and CODEOWNERS coverage for trust-sensitive
surfaces. Local Steam dry-run, forced reapply, verify, preflight, diagnostics,
and launch smoke passed on macOS 27.0. The last five reported GitHub issues
were reviewed and mapped back to regression coverage.
