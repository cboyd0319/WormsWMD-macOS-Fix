# Issue 10 Backup Stall

Status: Completed

## Problem

Issue #10 reports that v1.6.6 appears to hang while creating a backup on a
MacBook M1 Pro. The attached support bundle shows one interrupted backup
manifest and later complete manifests, which points to silent manifest hashing
rather than framework copying. The bundle also reports a local Qt checksum
mismatch even though the repository archive verifies from `dist/`.

## Scope and non-goals

In scope:

- Make the backup manifest phase visibly progress.
- Avoid redundant immediate manifest verification in the apply path while
  preserving rollback and restore verification before files are copied back.
- Fix diagnostics so local Qt archive checksums are verified from the archive
  directory.
- Audit adjacent installer, backup, restore, diagnostics, checksum, and support
  bundle paths for concrete edge-case defects.
- Add a focused regression check and CI wiring.

Non-goals:

- No replacement of the Qt archive.
- No privileged operations.
- Real game-bundle mutation is limited to the local Steam install the user made
  available for end-to-end testing.
- No broad backup format redesign.

## Constraints and risks

- Preserve game data, backups, and restore safety.
- Keep rollback and restore manifest verification before destructive copying.
- Keep macOS 26+ behavior and avoid breaking Windows 11 repository inspection.
- Treat user paths and support bundle data as untrusted.

## Milestones

- [x] Inspect issue #10, support bundle, backup manifests, and current backup
  code.
- [x] Add a failing regression check for the observed diagnostics and backup
  progress gaps.
- [x] Implement the smallest code change.
- [x] Update docs and CI wiring.
- [x] Audit adjacent edge cases and patch confirmed defects.
- [x] Run focused verification and record the result.

## Verification

```bash
./tools/test_issue_10_regression.sh
./tools/test_support_bundle_sanitization.sh
./tools/test_backup_saves_regression.sh
./tools/test_launcher_friction.sh
./tools/test_preflight_regression.sh
./tools/test_manifest_regression.sh
./tools/validate_harness.sh
./tools/test_dependency_parsing.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
./fix_worms_wmd.sh --help
./tools/collect_diagnostics.sh --help
./tools/backup_saves.sh --help
./fix_worms_wmd.sh --dry-run
./scripts/download_qt_frameworks.sh --check
./tools/build_release_bundle.sh --version local-smoke --skip-zip
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
./fix_worms_wmd.sh --force
./fix_worms_wmd.sh --verify
./tools/preflight_check.sh --verbose
./tools/watch_for_updates.sh --check
./tools/launch_worms.sh --log --check-fix --no-crash-report
```

## Progress

- 2026-06-18: Confirmed issue #10 was opened on June 17, 2026. The support
  bundle reports macOS 26.5.1, Apple M1 Pro, original Qt 5.3.2 still present,
  and backup directories from repeated attempts.
- 2026-06-18: Found one interrupted manifest ending inside
  `QtCore.framework/Headers` and two complete manifests with plugin entries.
- 2026-06-18: User requested a deeper pass for other potential errors, issues,
  and edge cases before finalizing.
- 2026-06-18: Added support-bundle and normal diagnostics sanitization for
  account names, private paths, external-volume paths with spaces, temporary
  paths, email addresses, and common token/secret assignment patterns.
- 2026-06-18: Fixed adjacent issues found during the deeper pass: same-second
  backup/support-bundle path collisions, hidden save-file omission and masked
  copy failures, brittle `sw_vers` usage on non-macOS hosts, and fragile
  preflight architecture/pipeline handling.
- 2026-06-18: Ran the fix against the local Steam install. The installer
  created a timestamped backup under the user's Documents folder, replaced the
  old Qt frameworks with the verified prebuilt Qt 5.15.18 package, installed the
  AGL stub, bundled dependencies, removed quarantine, signed the bundle, and
  reset Qt geometry.
- 2026-06-18: Generated a post-fix support bundle under `/tmp` and checked the
  archive contents for user paths, synthetic private data, email addresses, and
  common token labels.
- 2026-06-18: Performed a bounded launch smoke. The game process started and
  created the save directory; the process was then terminated. No visual
  gameplay validation was performed.
- 2026-06-18: Reduced post-install friction by adding a launch prompt after
  successful apply, a launcher menu option to launch the game, and
  version-neutral first-read checksum instructions.
- 2026-06-18: Fixed a noisy full-preflight warning where an HTTP 404 from the
  Team17 service host was reported as unreachable even though the host responded.
- 2026-06-18: Reduced backup/restore manifest friction by batching SHA-256
  manifest work instead of launching `shasum` once per file.
- 2026-06-18: Replaced the noisy Team17 service-host preflight probe with the
  public Team17 Worms W.M.D page and Steam Worms W.M.D store page.
- 2026-06-18: Found that repeated force applies can create a newest backup that
  already includes the fix. Restore now prefers the newest original-looking
  backup and warns if all backups appear to be fixed-state backups.
- 2026-06-18: Found and fixed a launcher noninteractive-input bug where fallback
  prompts written to stdout contaminated command-substitution answers and could
  loop forever during piped menu tests.
- 2026-06-18: Timed optimized manifest work against the local 5,098-file
  backup: manifest write completed in 9.70s and manifest verify in 12.22s on
  this machine. Live backup and restore runs used the optimized paths afterward.

## Surprises & Discoveries

- `tools/collect_diagnostics.sh` reports the local Qt checksum as mismatched
  when run from the repository root because `shasum -c` reads a checksum file
  whose filename is relative to `dist/`.
- The previous quarantine diagnostic used `grep -c ... || echo 0`, which could
  produce `0` plus a fallback `0` under `pipefail` and report a false warning.
- Extended diagnostics leaked local ownership data through `ls -la` framework
  listings even when path sanitization was added.
- Restore-side target verification had the same per-file hashing cost as backup
  manifest creation. It was not visible until the full live restore path was
  exercised.
- The friendly launcher was difficult to test noninteractively because prompts
  were written to stdout while their callers captured stdout for the answer.
- Force reapply is useful for repairs, but it can create fixed-state backups.
  Restore must not blindly pick the newest backup when older original backups
  are available.

## Decision Log

- Keep manifest verification in rollback and restore paths. Remove only the
  immediate post-write verification from the normal apply path because it
  duplicates the expensive hash pass and does not protect the later destructive
  restore operations.
- Sanitize diagnostics at emission time so regular diagnostic output, copied
  output, and support bundles follow the same privacy boundary.
- Do not include raw `.log`, `.trace`, save, or private game configuration files
  in support bundles. Keep uploaded support artifacts to generated diagnostics,
  Qt package metadata, and backup manifests.
- Treat public product pages as better preflight connectivity signals than
  implementation-detail service roots.
- Preserve checksum-based manifest safety, but batch checksum work so backup and
  restore scale with bytes hashed instead of process-launch count.
- Prefer original-looking backups for restore because the user-facing restore
  promise is to undo the fix, not to restore the newest fixed reapply state.

## Outcomes & Retrospective

Shipped the issue #10 fix plus adjacent hardening for diagnostics privacy,
support-bundle contents, backup path collisions, save backup fidelity,
macOS/non-macOS diagnostics robustness, preflight network reporting, and
first-run launcher friction, while preserving checksum-based manifest
verification.
Focused regression scripts, harness validation, shell syntax, ShellCheck,
release-bundle smoke, AGL compile smoke, help-path smoke, dry-run, local
restore/reapply cycles, post-fix verify, full preflight, update check,
support-bundle sanitization checks, simulated launcher menu launch, and bounded
real launch smoke all ran successfully. Remaining caveat: the launch smoke
proved process startup and short-lived stability, but did not include manual
visual gameplay validation.
