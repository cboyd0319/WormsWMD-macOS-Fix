# Full Repository Deep Audit

Status: Completed

## Problem

A new issue exposed a partial-install failure class, but the deeper risk is
repo-wide: other installer, launcher, diagnostics, backup, release, CI, or docs
paths may still have swallowed failures, misleading success states, rollback
gaps, privacy leaks, unsafe file handling, platform regressions, or untested
assumptions. This audit reviews all high-risk surfaces, not just issue #12.

## Scope and non-goals

In scope:

- `install.sh`, `Install Fix.command`, `Worms W.M.D Fix.command`, and
  `fix_worms_wmd.sh`.
- `scripts/*.sh`, `tools/*.sh`, CI workflows, release packaging, Qt package
  handling, AGL build/install, dependency copying, install-name rewriting,
  verification, restore, backup, diagnostics, preflight, update checks, support
  bundle privacy, docs/runtime contracts, and issue templates.
- Current uncommitted changes from the issue #12 pass.
- Requested specialist agents:
  `adversarial-reviewer`, `shell-expert`, and `code-reviewer`.
- Code, test, docs, and plan updates for material findings.

Out of scope:

- Publishing a release, pushing commits, closing GitHub issues, or changing
  cloud/vendor state without maintainer approval.
- Replacing the Qt archive in `dist/` unless the audit proves it is actually
  invalid.
- Broad refactors or new dependencies that are not needed to fix concrete
  findings.

## Constraints and risks

- Preserve user game data and the existing backup/rollback story.
- Keep downloads HTTPS-only and checksum-verified for executable code,
  frameworks, libraries, and archives.
- Treat `GAME_APP`, `INSTALL_DIR`, `INSTALL_REF`, `LOG_FILE`, and `QT_PREFIX`
  as untrusted input.
- Keep paths quoted and compatible with `Worms W.M.D.app`.
- Preserve macOS 26+ runtime behavior and name unavailable macOS/game-source
  validation gaps when not live-checked.
- Do not overclaim live-game verification when a real Worms W.M.D installation
  is not available in this session.

## Milestones

- [x] Milestone 1: Load requested skills and redirect requested specialist
  agents to full-repo scope.
- [x] Milestone 2: Locally map high-risk workflows and failure surfaces.
- [x] Milestone 3: Reconcile specialist findings and patch material gaps.
- [x] Milestone 4: Run focused and broader verification, then record evidence.

## Verification

Focused checks will depend on findings. Baseline checks:

```bash
./tools/validate_harness.sh
./tools/test_dependency_parsing.sh
./tools/test_issue_10_regression.sh
./tools/test_issue_11_game_detection.sh
./tools/test_issue_12_agl_install_failure.sh
./tools/test_installer_rollback_regression.sh
./tools/test_support_bundle_sanitization.sh
./tools/test_backup_saves_regression.sh
./tools/test_launcher_friction.sh
./tools/test_preflight_regression.sh
./tools/test_manifest_regression.sh
./tools/test_qt_version_pinning.sh
./scripts/download_qt_frameworks.sh --check
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
```

Runtime checks to name if still unavailable:

```bash
./fix_worms_wmd.sh --verify
./tools/preflight_check.sh
./tools/collect_diagnostics.sh
```

## Progress

- 2026-06-29: User expanded scope from issue #12 to all repo behavior.
- 2026-06-29: Loaded `adversarial-review`, `shell`, `debug-session`, and
  `code-review` skills plus shell/debug/code-review references.
- 2026-06-29: Interrupted and redirected read-only `adversarial-reviewer`,
  `shell-expert`, and `code-reviewer` agents to full-repo audit scope.
- 2026-06-29: Reconciled specialist findings. Material blockers were false
  success on partial Qt/AGL runtime installs, Bash 3.2 rollback trap inheritance,
  incomplete prebuilt dependency checks, helper failures hidden as success,
  watcher reapply losing custom `GAME_APP`, and save restore merging stale files.
- 2026-06-29: Patched runtime preflight/verification, top-level rollback,
  dependency verification, watcher LaunchAgent path persistence, save restore,
  diagnostics, and manual install docs. Added regression coverage for rollback,
  required plugins/dependencies, AGL architecture, custom watcher paths, and exact
  save restore.
- 2026-06-29: Ran focused and broader validation before real-machine testing.
- 2026-06-29: Real `./fix_worms_wmd.sh --force` against the installed game on
  macOS 27 initially failed while building the x86_64 AGL stub because
  `arch -x86_64 clang` could not load the arm64-only Command Line Tools
  `libxcrun`. Rollback restored the app cleanly. Patched
  `scripts/01_build_agl_stub.sh` to use native `clang -arch x86_64`
  cross-compilation and added coverage to the issue #12 regression.
- 2026-06-29: Re-ran real `./fix_worms_wmd.sh --force`; it completed
  successfully, created `~/Documents/WormsWMD-Backup-20260629-152601`,
  verified the app, launched the game through `tools/launch_worms.sh --check-fix
  --log --no-crash-report`, observed a live Worms process, found no recent
  Worms crash report, and terminated the test-launched process.
- 2026-06-29: Built a real local release zip, verified its `.sha256`, extracted
  it, and ran the packaged installer against the live Steam game. The first
  artifact run exposed stale nested AGL framework symlinks from repeated
  installs. Added AGL symlink replacement and backup-copy self-heal coverage,
  rebuilt the zip, and confirmed packaged forced install, diagnostics, launcher
  readiness, LaunchAgent install/check/uninstall, endpoint checks, and bounded
  launch all pass.
- 2026-06-29: Reviewed the issue #12 pasted support bundle for missing future
  troubleshooting evidence. Added sanitized support-bundle sections for
  installer history, runtime invariant status, backup integrity status, and
  required Qt archive contents so future reports show both the immediate error
  and whether the fixer-supplied runtime assets were present.
- 2026-06-29: Real support-bundle smoke testing exposed that simultaneous
  installer commands could reuse a timestamp-only log path and mix timelines.
  Added process-specific default log names with collision suffixing and
  regression coverage.

## Surprises & Discoveries

- `ERR` traps in Bash 3.2 do not fire inside functions unless errtrace is
  enabled. The installer did almost all mutating work inside `do_fix()`.
- The original root-cause class was broader than missing AGL: required runtime
  assets supplied by the fixer were not consistently enforced as invariants, so
  an incomplete artifact, cache, build output, or selected Qt source could still
  produce misleading readiness or completion signals.
- The documented manual helper-by-helper install path bypassed the canonical
  backup/rollback engine.
- Save restore needed exact restore semantics, not merge semantics, to remove
  corrupt or newer files absent from the selected backup.
- On macOS 27 Apple Silicon, Command Line Tools can cross-compile x86_64 with
  native `clang -arch x86_64`; forcing the compiler itself through Rosetta can
  fail because `libxcrun` is not available as x86_64.
- Repeated AGL framework installs need to remove existing framework symlinks
  before recreating them. On macOS, `ln -sf` can follow an existing symlink to a
  directory and create nested links such as `Versions/A/A` or
  `Versions/A/Resources/Resources`.

## Decision Log

- Keep specialists read-only. Integration and final judgment stay local so
  findings are verified against the live repo before edits.
- Treat issue #12 as a symptom and regression seed, not the audit boundary.
- Preserve the canonical installer as the user recovery path. Manual docs should
  drive `fix_worms_wmd.sh`, not direct mutating helper scripts.
- Prefer hard failure plus rollback for required runtime completeness and safety
  helper failures. Optional signing/quarantine friction can remain warnings.
- Save restore should copy into a temporary tree first, then replace backed-up
  save roots and verify stale files did not survive.
- Repair stale AGL framework symlinks in the backup copy before manifest
  validation. This preserves backup validation while giving users a self-heal
  path from older repeated installs.

## Outcomes & Retrospective

The audit found and fixed the broader root-cause class behind issue #12:
misleading success states after incomplete runtime installation or failed
recovery paths. The installer now inherits `ERR` traps inside functions so
post-backup failures roll back on Bash 3.2, required Qt framework/plugin source
is validated before destructive replacement, prebuilt dependency copies require
the expected dylib set, AGL readiness requires an x86_64 binary, and incomplete
fixer-supplied runtime assets are treated as installer invariant violations.
Optional helper failures no longer print false success. Watcher reapply preserves custom
`GAME_APP`, save restore replaces backed-up roots from a temporary copy and
checks for stale files, and manual docs now route users through the canonical
rollback-aware engine.

The artifact validation pass also found and fixed a repeated-install AGL
framework layout bug: stale framework symlinks are now removed before they are
recreated, and backup manifest creation repairs the fixer's own stale AGL
symlinks in the backup copy before validation.

The support-bundle follow-up closes an observability gap from issue #12. Future
bundles now include sanitized install-log summaries, the selected fix version or
commit, a runtime invariant matrix for AGL, Qt frameworks, Qt plugins, bundled
dylibs, backup integrity status, and required Qt archive content checks without
copying raw logs, saves, game binaries, or private config contents.
Default installer logs now include the process ID plus a suffix on collision, so
same-second verify/dry-run/apply invocations do not mix into one log file.

Verification passed on 2026-06-29:

```bash
./tools/validate_harness.sh
./tools/test_dependency_parsing.sh
./tools/test_issue_10_regression.sh
./tools/test_issue_11_game_detection.sh
./tools/test_issue_12_agl_install_failure.sh
./tools/test_installer_rollback_regression.sh
./tools/test_support_bundle_sanitization.sh
./tools/test_backup_saves_regression.sh
./tools/test_launcher_friction.sh
./tools/test_preflight_regression.sh
./tools/test_manifest_regression.sh
./tools/test_qt_version_pinning.sh
./scripts/download_qt_frameworks.sh --check
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
./tools/build_release_bundle.sh --version local-audit --skip-zip
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
./fix_worms_wmd.sh --help
./fix_worms_wmd.sh --dry-run
git diff --check
```

`./tools/build_release_bundle.sh --version local-audit --skip-zip` generated
`build/release/WormsWMD-macOS-Fix-local-audit`; that local artifact was removed
after verification. Later real-machine validation found and fixed the AGL build
issue above. Real installed-game verification, forced reapply, diagnostics, and
bounded launch testing passed. A later packaged artifact pass ran:

```bash
./tools/build_release_bundle.sh --version local-live
shasum -a 256 -c WormsWMD-macOS-Fix-local-live.zip.sha256
unzip -q WormsWMD-macOS-Fix-local-live.zip
./fix_worms_wmd.sh --force
./fix_worms_wmd.sh --verify --verbose
./tools/preflight_check.sh
./tools/collect_diagnostics.sh --output /tmp/wormswmd-after-release-artifact-diagnostics.txt
printf '3\n\nq\n' | ./Worms\ W.M.D\ Fix.command
./tools/watch_for_updates.sh --install
./tools/watch_for_updates.sh --check
./tools/watch_for_updates.sh --uninstall
LOG_FILE=/tmp/wormswmd-release-artifact-launch.log ./tools/launch_worms.sh --check-fix --log --no-crash-report
```

The LaunchAgent was installed in the real user session for the test and then
uninstalled. No real GOG install, macOS 26.0.1 M1 Air, or Intel Homebrew Qt
fallback was available on this machine.
