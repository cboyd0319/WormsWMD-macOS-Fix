# Issue 12 AGL Stub Install Failure

Status: Completed

## Problem

Issue #12 reports a release-zip launcher install on macOS 26.0.1 where the
game still launches to a black screen and diagnostics show `AGL stub NOT
installed`. The attached diagnostics also show the game bundle can be left in a
partially fixed state.

## Scope and non-goals

In scope:

- Inspect the AGL build/install path in `fix_worms_wmd.sh` and
  `scripts/04_fix_library_paths.sh`.
- Inspect the required Qt framework replacement path in
  `scripts/02_replace_qt_frameworks.sh`.
- Add the smallest regression checks that catch missing built AGL stubs during
  install-name repair, missing required Qt framework/plugin source during
  replacement, non-x86_64 AGL stubs, and incomplete prebuilt dependency copies.
- Update troubleshooting or support text if the user-facing recovery path is
  unclear.

Out of scope:

- Replacing the Qt archive in `dist/`.
- Changing game discovery, backup format, release packaging, or launcher menu
  structure.
- Adding privileged operations or new dependencies.

## Constraints and risks

- Preserve user game data and the existing backup/rollback path.
- Keep behavior portable across the repo's shell/documentation checks and
  preserve macOS 26+ runtime behavior. macOS-specific runtime checks may be
  named if not live-run.
- Treat `GAME_APP` and `BUILD_DIR` as untrusted input and keep all paths quoted.
- Do not make a missing AGL stub look successful. The fixer is responsible for
  supplying the AGL/Qt runtime assets; if a release artifact, cache, build
  output, or selected Qt source cannot supply them, the install must fail
  clearly and allow rollback.

## Milestones

- [x] Milestone 1: Inspect issue #12, current docs, active plans, and the AGL
  build/install scripts.
- [x] Milestone 2: Patch the minimal failure paths so missing `$BUILD_DIR/AGL`,
  missing required Qt source, missing Qt plugins, non-x86_64 AGL stubs, and
  incomplete prebuilt dependencies abort instead of continuing.
- [x] Milestone 3: Add focused regression checks and necessary user-facing
  recovery notes.
- [x] Milestone 4: Run targeted verification and record the evidence.

## Verification

Focused checks:

```bash
./tools/test_issue_12_agl_install_failure.sh
bash -n scripts/02_replace_qt_frameworks.sh scripts/03_copy_dependencies.sh scripts/04_fix_library_paths.sh scripts/05_verify_installation.sh tools/test_issue_12_agl_install_failure.sh
```

Broader checks if shell or docs behavior changes:

```bash
./tools/validate_harness.sh
shellcheck scripts/02_replace_qt_frameworks.sh scripts/03_copy_dependencies.sh scripts/04_fix_library_paths.sh scripts/05_verify_installation.sh tools/test_issue_12_agl_install_failure.sh
```

## Progress

- 2026-06-29: Created plan after issue triage. Issue #12 diagnostics show
  missing AGL, missing QtDBus/QtSvg, and one backup directory on an M1 macOS
  26.0.1 Steam install.
- 2026-06-29: Patched `scripts/04_fix_library_paths.sh`, added
  `tools/test_issue_12_agl_install_failure.sh`, updated validation indexes, and
  added troubleshooting guidance for the missing AGL diagnostic.
- 2026-06-29: Added the issue #12 regression check to the CI workflow.
- 2026-06-29: Extended the root-cause fix to
  `scripts/02_replace_qt_frameworks.sh` so missing required Qt framework source
  also fails before the install can continue.
- 2026-06-29: Extended the regression to required Qt plugins, prebuilt
  dependency completeness, verifier-required plugins, and AGL x86_64
  architecture checks.
- 2026-06-29: Real macOS 27 forced reapply found that `arch -x86_64 clang`
  cannot load arm64-only Command Line Tools `libxcrun`; switched the AGL build
  script to native `clang -arch x86_64` cross-compilation.
- 2026-06-29: Re-ran real forced install after the AGL build patch; install,
  verification, diagnostics, and bounded launch testing passed against the
  local Steam game install.
- 2026-06-29: Release-zip artifact testing found repeated installs could leave
  stale nested AGL framework symlinks that failed backup manifest validation.
  Patched AGL symlink replacement and backup-copy self-heal, then reran the
  packaged forced install successfully.

## Surprises & Discoveries

- `scripts/04_fix_library_paths.sh` validates that `BUILD_DIR` is set, but if
  `$BUILD_DIR/AGL` is absent it only prints a warning and continues.
- `scripts/02_replace_qt_frameworks.sh` previously printed a warning and
  continued when required Qt frameworks such as `QtDBus` or `QtSvg` were absent
  from the selected Qt source.
- Required Qt plugin source and prebuilt dependency completeness were also part
  of the same partial-install failure class.
- The AGL build step itself must not run `clang` under Rosetta. Native clang can
  cross-compile the required x86_64 slice without requiring x86_64 `libxcrun`.
- Repeated AGL installs must remove existing framework symlinks before
  recreating them; `ln -sf` is not enough on macOS when the destination is an
  existing symlink to a directory.

## Decision Log

- Use a hard failure for a missing built AGL stub during library-path fixing.
  The build step is responsible for supplying it; absence means the installer
  invariant is broken and rollback should restore the pre-fix bundle.
- Use a hard failure for missing required Qt framework source during
  replacement. The release artifact or selected Qt source is responsible for
  supplying it; a missing Qt runtime component is not optional for the current
  fix contract.
- Treat missing `libqcocoa.dylib`, missing `libqsvg.dylib`, missing required
  bundled dylibs, and AGL binaries without an x86_64 slice as install blockers.
- Build AGL slices with native `clang -arch ...`; reserve Rosetta for running
  the Intel game, not for running Apple developer tooling.
- Repair stale AGL framework symlinks in backup copies before manifest
  validation so users affected by older repeated installs can self-heal by
  rerunning the latest fixer.

## Outcomes & Retrospective

The library path fixer now exits with an error when `$BUILD_DIR/AGL` is missing
instead of continuing to a partial install. The Qt replacement script now exits
with an error when required framework source such as `QtSvg.framework` or
required plugin source such as `libqcocoa.dylib`/`libqsvg.dylib` is missing. The
dependency copy step now verifies the required prebuilt dylib set, and
verification/preflight treat non-x86_64 AGL stubs and missing required plugins
as installer invariant failures. The issue #12 regression check creates fake
game bundles for these cases and verifies the scripts fail before claiming the
install step is complete. It also checks repeated AGL framework replacement
does not create nested framework symlinks. CI now runs that check with the
other repository regression scripts.

Verification passed on 2026-06-29:

```bash
./tools/test_issue_12_agl_install_failure.sh
bash -n scripts/02_replace_qt_frameworks.sh scripts/03_copy_dependencies.sh scripts/04_fix_library_paths.sh scripts/05_verify_installation.sh tools/test_issue_12_agl_install_failure.sh
./tools/validate_harness.sh
shellcheck scripts/02_replace_qt_frameworks.sh scripts/03_copy_dependencies.sh scripts/04_fix_library_paths.sh scripts/05_verify_installation.sh tools/test_issue_12_agl_install_failure.sh
./tools/test_qt_version_pinning.sh
./scripts/download_qt_frameworks.sh --check
tar -tzf dist/qt-frameworks-x86_64-5.15.19.tar.gz | rg -q '^Frameworks/QtDBus\.framework/' && tar -tzf dist/qt-frameworks-x86_64-5.15.19.tar.gz | rg -q '^Frameworks/QtSvg\.framework/'
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
```

Real installed-game validation also passed on 2026-06-29:

```bash
./tools/preflight_check.sh --quick
./fix_worms_wmd.sh --verify --verbose
./tools/collect_diagnostics.sh --output /tmp/wormswmd-real-validation-diagnostics.txt
./fix_worms_wmd.sh --force
./fix_worms_wmd.sh --verify
./tools/preflight_check.sh
./tools/collect_diagnostics.sh --output /tmp/wormswmd-real-validation-postfix-diagnostics.txt
LOG_FILE=/tmp/wormswmd-real-launch.log ./tools/launch_worms.sh --check-fix --log --no-crash-report
```

The bounded launch test observed a live Worms process after Steam handoff,
found no recent Worms crash report, and terminated the test-launched process.
