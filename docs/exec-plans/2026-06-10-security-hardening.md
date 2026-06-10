# Security Hardening

Status: Completed

## Problem

Repository-wide security scan found remaining hardening gaps in archive
extraction, CI action pinning, update downloads, LaunchAgent plist generation,
and standalone temporary build directory handling.

## Scope and non-goals

In scope:

- Shell installer and helper script security hardening.
- GitHub Actions supply-chain pinning.
- Documentation and security notes that describe changed behavior.
- Focused regression checks for archive rejection, update download behavior, and
  existing validation commands.

Out of scope:

- Replacing the bundled Qt archive.
- Adding privileged installers, notarization, or system-wide writes.
- Changing game assets or save data formats beyond safer restore validation.

## Constraints and risks

- Preserve macOS 26+ and Windows 11 repository validation behavior.
- Keep scripts compatible with macOS Bash 3.2.
- Preserve legitimate Qt framework symlinks while rejecting unsafe archive links
  and hardlink/special entries.
- Pin CI actions to immutable SHAs that correspond to latest stable tags.

## Milestones

- [x] Add archive metadata validation for Qt and save restore tarballs.
- [x] Verify update downloads against release checksum assets.
- [x] Pin GitHub Actions to latest stable immutable commit SHAs.
- [x] Harden LaunchAgent plist generation and standalone AGL temp handling.
- [x] Update docs and security notes.
- [x] Run focused and repo validation.

## Verification

```bash
./tools/validate_harness.sh
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
./scripts/download_qt_frameworks.sh --check
./tools/backup_saves.sh --help
./tools/check_updates.sh --help
./tools/build_release_bundle.sh --version local-smoke --skip-zip
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
```

## Progress

- 2026-06-10: Started after user approved subagents for security scan.
- 2026-06-10: Hardened archive validation, update downloads, bootstrap refs,
  symlink-sensitive game-bundle mutations, log paths, diagnostics output, and
  CI action pinning.

## Surprises & Discoveries

- Existing Qt framework archive legitimately contains framework symlinks, so tar
  hardening must validate symlink targets instead of rejecting all symlinks.
- Latest stable action tags were resolved before pinning to immutable SHAs:
  `actions/checkout` `v6.0.3` -> `df4cb1c...`,
  `actions/attest` `v4.1.0` -> `59d89421...`,
  `actions/upload-artifact` `v7.0.1` -> `043fb46d...`,
  `ludeeus/action-shellcheck` `2.0.0` -> `00cae500...`.
- Current bundled Qt archive predates `MANIFEST.txt`, so extraction now writes
  a cache-local manifest after checksum, metadata, layout, link, and Mach-O
  validation. Future package builds still include the manifest inside the
  archive.

## Decision Log

- Use release zip plus matching `.sha256` for update downloads instead of the
  unauthenticated main-branch source snapshot.
- Keep default install pinned to `v1.6.4` and exact commit
  `4456929b241dcff0e2eea483f1ac4d2336be9e3a`; require explicit opt-in for
  unpinned refs.

## Outcomes & Retrospective

Security scan candidates were fixed with focused validation and repository
checks. Remaining live-environment checks require a real Worms W.M.D install on
macOS.
