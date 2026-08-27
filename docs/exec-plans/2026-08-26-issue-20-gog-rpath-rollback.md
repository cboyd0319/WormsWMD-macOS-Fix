# Issue 20 GOG rpath and rollback hardening

Status: Active

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
- Back up, restore, and verify the complete `Contents/MacOS` tree because deep
  signing mutates both the main executable and GOG's `libGalaxy.dylib`.
- Bind new backups to the canonical source app and prevent cross-install
  automatic restore.
- Keep runtime and signing failures transactional; apply untracked quarantine
  and preference changes only after runtime and strict signature verification.
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
- [x] Milestone 8: Stop release work and reopen the full trust-boundary audit
  after repeated review rounds exposed additional integrity gaps.
- [x] Milestone 9: Add fail-first coverage and fix every material audit finding
  across backup publication/restore, signing, Mach-O verification, archive and
  manifest validation, Qt runtime replacement, and launcher targeting.
- [ ] Milestone 10: Repeat the full adversarial review, live Steam/GOG tests,
  hosted CI, and Copilot review before restoring completed status.

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
- 2026-08-26: Addressed both Copilot review findings with fail-first tests:
  option 7 now launches the interactive selection instead of a stale local
  value, and duplicate-member validation propagates unreadable archive errors.
- 2026-08-26: Addressed the three follow-up Copilot findings with regressions
  for run-path owner expansion, weak install names containing spaces, changed
  symlink targets, and unrecorded symlinks. New manifests are v2; v1 remains a
  compatible legacy format.
- 2026-08-26: Addressed the final three Copilot findings with fail-first
  regressions for linked `Contents/MacOS`, same-path cross-store restore, and
  missing weak `@executable_path` dependencies. Mutation containment now covers
  `Contents/MacOS`, new-backup restore requires path and storefront identity,
  and weak-load handling is consistent across supported Mach-O path tokens.
- 2026-08-26: Reopened the audit and stopped merge/release work after the next
  Copilot pass found unmanifested metadata, special-entry, canonical archive
  alias, and manual-restore gaps. A fresh local adversarial pass also confirmed
  that deep signing changes GOG's `libGalaxy.dylib` even though current backups
  cover only the main executable, and identified additional false-success and
  partial-backup exposure paths. The prior completion verdict is withdrawn
  until the expanded audit and verification milestones pass.
- 2026-08-26: Added fail-first regressions for canonical tar aliases, FIFOs,
  control-character paths, duplicate manifest symlinks, dangling output links,
  save archive aliases, direct Mach-O escapes, relative dependencies, ignored
  GOG libraries, unreadable architectures, stale Qt 5.3 plugins, interrupted
  backup publication, signing rollback, nested app links/hardlinks, and wrong
  storefront launch fallback.
- 2026-08-26: Fixed the confirmed audit defects. Backups now stage and verify
  before publication, cover all `MacOS` files, and keep signing inside rollback.
  Shared tree/archive validation rejects canonical aliases, control paths,
  unsupported entries, duplicate manifest paths, escaping links, and hardlinks.
  Runtime verification covers direct token containment, relative names, GOG
  dylibs, every plugin category, and unreadable Mach-O files.
- 2026-08-26: Rebuilt Qt twice from all 17 checksum-locked provenance bottles.
  Both builds produced SHA-256
  `0fb27b25821fa1034134a575169eea40620fa93240a79041a0933967271521f1`
  with 16 dependency dylibs, `libsharpyuv.0.dylib`, no `.prl` files, and a
  verified dependency closure.
- 2026-08-26: Validated disposable clones of both installed storefronts. GOG
  passed apply, zero-warning post-sign verification, strict signature checking,
  and visual main-menu rendering; restore reproduced all 3,097 recorded
  files/symlink targets and both original executable/Galaxy hashes. Steam passed
  upgrade from the v1.7.5-fixed state, stale-plugin removal, storefront metadata
  binding, verification, and whole-surface restore comparison. Both installed
  source apps remained unchanged.
- 2026-08-26: The final local pass also found that noninteractive multi-install
  auto-detection attempted unusable `/dev/tty`, then silently retained the
  default Steam path. Detection now clears ambiguous targets and dry-run uses a
  safe placeholder instead of `/Contents`; read-only verification failures no
  longer print a mutating-installer rollback error.
- 2026-08-26: The next Copilot pass found four valid residuals. Full C-locale
  control bytes are now rejected; metadata v2 marks complete `MacOS` backups and
  restore uses a staged swap that removes extras; dry-run shows runtime verify,
  sign, then strict signature verify in the actual order; and linked plugin
  entries fail instead of bypassing traversal. Metadata v1 keeps its prior merge
  behavior for compatibility.
- 2026-08-26: Repeated the live GOG apply/restore path with metadata v2 and an
  injected post-fix `MacOS` dylib. The staged swap removed the extra entry and
  again reproduced the 3,097-record baseline plus both original GOG hashes.

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
- Bash subshells inherited the installer's `EXIT` cleanup trap. A command
  substitution or interactive spinner could therefore delete a managed build
  or backup-staging directory owned by the top-level process. Cleanup now runs
  only at `BASH_SUBSHELL=0`.
- `codesign --deep` changes the GOG `libGalaxy.dylib` hash as well as the main
  executable. A disposable probe confirmed both mutations, invalidating the
  earlier main-executable-only rollback claim.
- The earlier 15-dylib archive shipped WebP libraries but omitted their
  `@rpath/libsharpyuv.0.dylib` closure, so the installer skipped all WebP
  components. Packaging now resolves dependency run paths before copying.

## Decision Log

- Resolve `@rpath` generically from the current binary and main executable
  rather than adding a `libGalaxy.dylib` exception.
- Accept unresolved weak dependencies as warnings, but keep unresolved strong
  dependencies and external absolute targets as errors.
- Bind backups to canonical app paths and fail closed on ambiguous legacy
  restores instead of adding a new backup-selection API.
- Move quarantine and preference changes after the rollback boundary rather
  than attempting to serialize recursive xattrs and user preferences.
- Keep ad-hoc signing inside the rollback boundary and require strict signature
  verification. Only quarantine and preference changes remain outside because
  they are not serialized in the game backup.
- Back up existing `_CodeSignature` resources and record their presence so
  manual restore can remove fixer-created signature resources when the original
  app did not have them.

## Outcomes & Retrospective

The release verdict remains open until Milestones 9 and 10 pass. The current Qt
candidate has 98 unique members, 16 runtime dependency dylibs, 21 recorded
framework symlinks, no `.prl` files, and is 11,109,876 bytes. Two independent
builds produced SHA-256
`0fb27b25821fa1034134a575169eea40620fa93240a79041a0933967271521f1`.

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
