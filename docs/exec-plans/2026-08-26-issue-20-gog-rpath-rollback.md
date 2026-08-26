# Issue 20 GOG rpath and rollback hardening

Status: Completed

## Problem

Issue #20 reports that the v1.7.5 fix reaches final verification on a GOG
installation but rejects `@rpath/libGalaxy.dylib`. The attached support bundle
also exposed incomplete rollback coverage, backups that are not bound to their
source app, diagnostics that inspect Steam after a GOG failure, misleading
dependency/path success messages, and unnecessarily noisy support/package
metadata.

## Scope and non-goals

In scope:

- Resolve bundled `@rpath` dependencies using Mach-O load commands and treat
  unresolved weak dependencies as optional.
- Make install-name rewriting fail clearly when an intended mutation fails.
- Back up, restore, and verify the main executable.
- Bind new backups to the canonical source app and prevent cross-install
  automatic restore.
- Keep pre-verification failures transactional by applying optional signing,
  quarantine, and preference changes only after hard runtime verification.
- Preserve the selected game path through friendly-launcher diagnostics.
- Improve sanitized dependency evidence, failure summaries, manifest mapping,
  ANSI removal, and duplicate-manifest handling.
- Stop packaging plugin self-references as framework dependencies and reconcile
  the committed Qt archive metadata/checksum if the staged archive validates.
- Update regression checks and user/runtime documentation with the behavior.

Non-goals:

- Bundle GOG Galaxy binaries or change the game executable beyond existing
  install-name and ad-hoc-signing behavior.
- Modify either locally installed Worms W.M.D app during automated validation.
- Publish a release, push the branch, or mutate issue #20 without a separate
  request.

## Constraints and risks

- Preserve Bash 3.2 compatibility and quoted paths with spaces.
- Keep backup restore fail-closed; legacy backups remain usable only when their
  target is unambiguous.
- Do not accept `@rpath` targets outside the selected app bundle as portable.
- Do not weaken checksum, archive-layout, symlink, or executable validation.
- The committed Qt archive may change only with a new checksum, manifest,
  deterministic packaging, and extraction-layout verification.
- The real GOG executable is a strong Galaxy load with both
  `@executable_path/../Frameworks` and `@executable_path` run paths. The latter
  resolves `Contents/MacOS/libGalaxy.dylib`.

## Milestones

- [x] Milestone 1: Add fail-first regressions for resolvable and weak
  `@rpath`, explicit path-rewrite failures, executable rollback, and
  cross-install restore rejection.
- [x] Milestone 2: Implement shared Mach-O dependency resolution and truthful
  dependency/path verification in `scripts/common.sh`,
  `scripts/03_copy_dependencies.sh`, `scripts/04_fix_library_paths.sh`, and
  `scripts/05_verify_installation.sh`.
- [x] Milestone 3: Extend backup metadata/manifest coverage and transaction
  ordering in `fix_worms_wmd.sh`; update rollback regression coverage.
- [x] Milestone 4: Preserve launcher game selection and improve
  `tools/collect_diagnostics.sh` evidence, sanitization, and manifest packaging;
  update support/launcher regressions.
- [x] Milestone 5: Remove plugin self-dependencies from future Qt packages and,
  if reproducibly validated, repair the committed archive and checksum.
- [x] Milestone 6: Update runtime contracts, troubleshooting, changelog, and
  documentation indexes.
- [x] Milestone 7: Run focused red-green checks, full shell syntax/ShellCheck,
  harness validation, package validation, and non-mutating live metadata probes.

## Verification

Focused checks:

```bash
./tools/test_dependency_parsing.sh
./tools/test_installer_rollback_regression.sh
./tools/test_support_bundle_sanitization.sh
./tools/test_launcher_friction.sh
./tools/test_manifest_regression.sh
./tools/test_qt_version_pinning.sh
```

Broad gates:

```bash
./tools/validate_harness.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
./scripts/download_qt_frameworks.sh --check
./fix_worms_wmd.sh --help
./fix_worms_wmd.sh --dry-run
git diff --check
```

Live validation is read-only against installed game metadata unless an explicit
disposable copy is created first.

## Progress

- 2026-08-26: Audited issue #20 and every support-bundle file. Confirmed three
  identical final-verification failures, two earlier AGL failures, wrong-target
  diagnostics, byte-identical valid backups, and the rollback/restore gaps.
- 2026-08-26: Created branch `fix/issue-20-gog-rpath-rollback` and started this
  plan.
- 2026-08-26: Added red-green regressions for resolved and weak `@rpath`
  dependencies, missing strong loads, path rewrite failures, executable
  rollback, failed rollback verification, cross-install restore, multi-install
  support selection, ANSI removal, manifest deduplication, actionable AGL
  errors, plugin self-dependencies, and duplicate tar members.
- 2026-08-26: Repacked the verified Qt 5.15.19 archive from the existing
  provenance-locked payload. It now contains 15 dependency dylibs, 104 unique
  archive entries, a regenerated manifest, normalized timestamps, and an
  updated checksum.
- 2026-08-26: The adversarial pass added boundary regressions for tab-delimited
  paths, escaping rpath symlinks, unmanifested and invalid backup metadata,
  custom-path legacy ambiguity, signature-resource restoration, duplicate
  archive members, and unrecorded manifest files.
- 2026-08-26: Installed the entitled GOG macOS build and tested a disposable
  APFS copy. The full fix and verbose post-sign verification passed, the intro
  and main menu rendered, and restore recovered the exact original executable
  hash, Qt 5.3.2 files, and unsigned signature state.

## Surprises & Discoveries

- The diagnostics inventory contains Steam's `libsteam_api.dylib`, while every
  failed-run backup manifest omits it, proving the reports cover different app
  installations.
- All five support-bundle manifests are identical and valid, but omit the main
  executable even though the installer modifies and signs it.
- The prebuilt package's reported 27 dependencies include 12 duplicate Qt
  plugin self-references; the installer's count of 16 is otherwise consistent
  with three intentionally skipped WebP libraries and four original game
  dylibs.
- The package tar list recursively expanded directory entries and then archived
  the explicitly listed children again. Adding `--no-recursion` reduced the
  archive from about 48 MB to about 11 MB with no required runtime file loss.
- Shared manifest verification checked recorded files but did not reject extra
  unrecorded files, even though restore copies directory trees. Verification now
  fails closed on extras across game, save, Qt, and release manifests.

## Decision Log

- Resolve `@rpath` generically from the current binary and main executable
  rather than adding a `libGalaxy.dylib` exception.
- Accept unresolved weak dependencies as warnings, but keep unresolved strong
  dependencies and external absolute targets as errors.
- Bind backups to canonical app paths and fail closed on ambiguous legacy
  restores instead of adding a new backup-selection API.
- Move optional finishing touches after hard runtime verification rather than
  attempting to serialize and restore recursive xattrs and user preferences.
- Back up existing `_CodeSignature` resources and record their presence so
  manual restore can remove fixer-created signature resources when the original
  app did not have them.

## Outcomes & Retrospective

Issue #20 is fixed without a `libGalaxy.dylib` special case. Mach-O verification
now resolves bundled run paths and recognizes weak loads, while required missing
dependencies still fail. Rollback covers the executable and signature resources,
new backups are bound to their source app, ambiguous and untrusted restore state
fails before mutation, and finishing touches occur after the hard verification
boundary. Diagnostics retain the selected Steam or GOG target and produce
smaller, clearer support bundles.

The Qt archive was deterministically repaired from the existing verified,
provenance-locked payload. Its checksum passes; it contains 104 unique members,
15 runtime dependency dylibs, no duplicate plugin copies, and is 11,102,001
bytes. A second independent repack produced the same SHA-256.

Fresh completion evidence:

- All 13 repository regression scripts passed.
- Full `bash -n`, ShellCheck, `git diff --check`, and
  `./tools/validate_harness.sh` passed.
- `./scripts/download_qt_frameworks.sh --check` returned `available`.
- The installed Steam app passed `./fix_worms_wmd.sh --verify`; quick preflight
  and sanitized diagnostics also completed successfully.
- A disposable real Mach-O executable resolved a strong
  `@rpath/libGalaxy.dylib` through `LC_RPATH` and classified an absent
  `LC_LOAD_WEAK_DYLIB` Galaxy dependency as optional.
- A disposable copy of the actual GOG app completed apply and post-sign verify,
  rendered the main menu on macOS 27.0, and restored the original executable
  SHA-256 `119b2bde18871423e0ffad74548cfa8f07b0f7f08b3f2c86ab313eb44fcccb05`.
- `./tools/build_release_bundle.sh --version local-smoke --skip-zip` and an
  x86_64 AGL compilation smoke passed; generated smoke artifacts were removed.

The installed GOG app remained unchanged; all mutations occurred on a disposable
copy. Release publication remains outside this implementation pass.
