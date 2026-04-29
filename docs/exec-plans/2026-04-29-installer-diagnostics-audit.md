# Installer Diagnostics Audit

Status: Completed

## Problem

The deep repo audit found drift between the installer preview, the primary
pre-built Qt path, diagnostics, and documentation. Dry-run mode still treated
Intel Homebrew Qt as mandatory even though normal installs prefer the bundled
pre-built Qt package, and already-applied detection did not recognize the
universal AGL stub produced by the installer.

## Scope and non-goals

In scope:

- Main installer flow in `fix_worms_wmd.sh`.
- Installer entrypoints in `install.sh` and `Install Fix.command`.
- Script build-directory defaults in `scripts/`.
- Diagnostics in `tools/collect_diagnostics.sh`.
- User-facing docs, security docs, changelog, and agent runbooks affected by
  the behavior changes.

Out of scope:

- Applying the fix to the local Worms W.M.D installation.
- Replacing the bundled Qt archive in `dist/`.
- Changing the game save backup or restore format.

## Constraints and risks

- Do not require Intel Homebrew when the bundled pre-built Qt package is
  available and passes its checksum check.
- Do not continue after a pre-built Qt preparation failure unless Homebrew Qt is
  actually available as a fallback.
- Keep build artifacts in per-run temporary directories for the main installer.
- Preserve existing backups, logging, restore behavior, and code-signing flow.

## Milestones

- [x] Inspect repo health, open GitHub issues, and open pull requests.
- [x] Fix installer Qt source detection, temporary build directory handling, and
  already-applied detection.
- [x] Update diagnostics and installer bootstrap progress output.
- [x] Update user-facing docs, security docs, changelog, and runbooks.
- [x] Run validation and record the result.

## Verification

Completed commands:

```bash
./tools/validate_harness.sh
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
./fix_worms_wmd.sh --help
./fix_worms_wmd.sh --dry-run
./scripts/download_qt_frameworks.sh --check
./tools/collect_diagnostics.sh --help
./tools/collect_diagnostics.sh
./tools/check_updates.sh --quiet
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
git diff --check
```

## Progress

- 2026-04-29: Confirmed open Issue #4 and PR #5, with no outstanding comments
  or reviews.
- 2026-04-29: Reproduced dry-run failure on a machine where the bundled Qt
  package is available but Intel Homebrew Qt is not.
- 2026-04-29: Implemented installer and diagnostics fixes.
- 2026-04-29: Validation passed for the harness, shell syntax, ShellCheck, dry
  run, Qt package availability, diagnostics help/output, update check, native
  AGL compile probe, and whitespace checks.

## Surprises & Discoveries

- Dry-run mode had a different Qt requirement path than the real installer.
- A universal AGL stub was treated as partial because detection expected the
  architecture output to equal exactly `x86_64`.
- The diagnostics report treated missing Intel Homebrew as a failure even though
  the pre-built Qt package is the primary path.

## Decision Log

- Prefer the pre-built Qt package wherever possible, and keep Homebrew Qt as an
  explicit fallback.
- Use per-run temporary build directories in the main installer while leaving
  standalone helper scripts with their documented fallback defaults.
- Incorporate PR #5's visible Git progress behavior without removing the
  existing installer guidance.

## Outcomes & Retrospective

The installer preview now uses the same preferred Qt source model as the real
installer: pre-built Qt first, Homebrew only as a fallback. The main installer
uses a per-run temporary build directory, recognizes universal AGL stubs as
already applied, and exits before replacing Qt frameworks if pre-built
preparation fails and no Homebrew fallback is available.

Diagnostics now reports the pre-built Qt package first and treats missing
Homebrew Qt as a fallback warning. Documentation and runbooks were updated to
cover the changed validation command set, macOS 15.7.3 input buffering report,
and installer behavior.

`./tools/preflight_check.sh --quick` and `./fix_worms_wmd.sh --verify` were also
run on this machine. Both returned failure because the local Worms W.M.D app
bundle is currently unfixed; that result was expected and no game files were
modified.
