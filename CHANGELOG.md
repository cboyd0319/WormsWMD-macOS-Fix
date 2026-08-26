# Changelog

Notable changes are listed here. This project follows Keep a Changelog and Semantic Versioning.

## Unreleased

### Changed

- Support bundles now stay bound to the Steam or GOG installation selected in
  the friendly launcher, report Mach-O run-path resolution, label backup source
  metadata, remove ANSI fragments, and include only one copy of identical
  backup manifests.
- The Qt 5.15.19 package now contains 15 actual runtime dependency dylibs
  without duplicate plugin entries or duplicate tar members.
- Optional quarantine removal, ad-hoc signing, and Qt geometry reset now happen
  only after hard runtime verification succeeds.

### Fixed

- Fixed issue #20 verification for GOG executables by resolving `@rpath`
  dependencies through `LC_RPATH` and allowing unresolved weak-load
  dependencies as warnings. Required unresolved dependencies still fail.
- Fixed game-bundle backup and rollback coverage for the main executable and
  existing code-signature resources.
- Bound new backups to their canonical source app and prevented an automatic
  restore from applying a GOG backup to Steam, or a Steam backup to GOG.
- Fixed friendly-launcher option 7 so an interactive Steam or GOG selection is
  used for the actual launch action.
- Made install-name rewrite failures and AGL compiler failures actionable
  instead of suppressing their underlying errors.
- Stopped rollback from claiming success when restored-file verification
  fails.
- Made restore guidance use the recorded Steam or GOG storefront instead of
  always recommending Steam repair.
- Made manifest verification reject unrecorded extra files and Qt archive
  validation reject unreadable archives and duplicate members before extraction.
- Added v2 manifest coverage for symlink paths and target digests while keeping
  existing v1 backups compatible with their legacy guarantees.

## Mainline maintenance after 1.7.5 (2026-08-11)

### Security
- Pinned mainline bootstrap commit verification to the `v1.7.5` tag target.
  This follow-up commit lives on `main` after the `v1.7.5` release tag so
  one-line installers can verify the exact release commit.

## 1.7.5 (2026-08-11)

### Changed
- Updated release, bootstrap, verification, documentation, and issue-template
  surfaces for v1.7.5.
- Kept exact bootstrap commit pins empty in the release-tag commit. Exact
  pinning is recorded in the following mainline maintenance entry.

### Fixed
- Addressed issue #19 installation failures on macOS 26.6 by making copied Qt
  framework binaries writable before updating their install names.

## Mainline maintenance after 1.7.4 (2026-07-01)

### Security
- Pinned mainline bootstrap commit verification to the `v1.7.4` tag target.
  This follow-up commit lives on `main` after the `v1.7.4` release tag so
  one-line installers can verify the exact release commit.

## 1.7.4 (2026-07-01)

### Added
- Added regression coverage for bootstrap install path safety, game-bundle
  mutation boundaries, log-path side effects, hardlinked log refusal, optional
  WebP dependency parsing, GOG discovery, rollback, launch-helper reapply, and
  issue-driven installer failure paths.
- Added a repo-local `.agents` layer and stricter harness validation for agent
  instructions, docs topology, local-path hygiene, CI regression coverage,
  CODEOWNERS coverage, and full-SHA GitHub Actions pins.
- Added a completed post-1.7.3 audit execution plan that records the issue
  review, fixes, live Steam validation, and release-gate evidence.

### Changed
- Updated installer, launcher, README, install, trust, security, runtime
  contract, runbook, tools, harness, and issue-template release surfaces for
  v1.7.4.
- Kept release-tag bootstrap commit pins empty for the v1.7.4 tag commit;
  exact pinning is recorded in the following mainline maintenance entry.
- Shared the config-file inventory used by backup, rollback, URL mutation, and
  verification so the restore contract matches the mutating surface.

### Fixed
- Fixed dry-run and verify game discovery so Steam, GOG, custom `GAME_APP`, and
  empty `GAME_APP` cases behave consistently with the apply path.
- Fixed noninteractive multiple-install discovery so ambiguous installs fail
  with guidance instead of silently choosing a target.
- Fixed launcher `--check-fix` reapply so custom `GAME_APP` paths are preserved.
- Fixed rollback coverage for `DataOSX` and `CommonData` config files,
  including `PcLanConfig.txt`.
- Fixed mutation safety so existing critical bundle paths must be directories
  inside `Contents`, and symlinked or hardlinked config files are refused before
  any URL rewrite.
- Fixed bootstrap installer safety so `INSTALL_DIR` values that resolve through
  symlinks or `..` into system paths are rejected after normalization.
- Fixed logging side effects so rejected `LOG_DIR` and `LOG_FILE` values do not
  create directories outside `~/Library/Logs`.
- Fixed launcher logging so safe nested log files under `~/Library/Logs` still
  work while hardlinked log files are refused.
- Fixed launcher crash-report directory creation so it only happens when
  logging and crash reporting are enabled.

## Mainline maintenance after 1.7.3 (2026-06-29)

### Security
- Pinned mainline bootstrap commit verification to the `v1.7.3` tag target.
  This follow-up commit lives on `main` after the `v1.7.3` release tag so
  one-line installers can verify the exact release commit.

## 1.7.3 (2026-06-29)

### Changed
- Updated installer, launcher, README, install, troubleshooting, trust,
  security, support, and issue-template release surfaces for v1.7.3.
- Kept release-tag bootstrap commit pins empty for the v1.7.3 tag commit; the
  follow-up mainline maintenance commit should pin the exact tag target.

### Fixed
- Fixed issue #12 hardening so required runtime assets supplied by the fixer are
  enforced as installer invariants. If the release artifact, cache, build
  output, or selected Qt source is incomplete, the installer now fails clearly
  instead of continuing toward a partial black-screen state.
- Fixed support-bundle troubleshooting gaps by adding sanitized installer
  history, runtime invariant status, backup integrity status, and required Qt
  archive content checks.
- Fixed default installer log naming so simultaneous runs do not reuse one
  timestamp-only log file.
- Fixed AGL stub building on macOS 27 Apple Silicon Command Line Tools by using
  native `clang -arch x86_64` cross-compilation instead of launching `clang`
  under Rosetta.
- Fixed repeated AGL framework installs so stale nested framework symlinks are
  repaired before backup manifest validation and are not recreated during AGL
  replacement.
- Fixed installer rollback on Bash 3.2 by enabling `ERR` trap inheritance for
  failures inside installer functions.
- Fixed Steam update watcher reapply paths so custom `GAME_APP` locations are
  forwarded and persisted in the LaunchAgent.
- Fixed manually dispatched release-bundle workflow artifact names for branch
  refs containing `/`.
- Fixed save restore semantics so restored backup roots replace stale local save
  files instead of merging over them.

## Mainline maintenance after 1.7.2 (2026-06-22)

### Security
- Pinned mainline bootstrap commit verification to the `v1.7.2` tag target.
  This follow-up commit lives on `main` after the `v1.7.2` release tag so
  one-line installers can verify the exact release commit.

## 1.7.2 (2026-06-22)

### Added
- Added macOS 27 Golden Gate readiness guidance for Apple Silicon users,
  including plain Rosetta instructions and launcher option 3 readiness checks.
- Added diagnostics and support-bundle details for macOS version, Rosetta
  package version, x86_64 execution, `oahd`, and macOS 27 game-support status
  when available.
- Added regression coverage that keeps macOS 26 Tahoe behavior separate from
  macOS 27 Golden Gate behavior.

### Changed
- Updated installer, launcher, README, install, FAQ, troubleshooting, trust,
  support, and issue-template release surfaces for v1.7.2.
- Kept release-tag bootstrap commit pins empty for the v1.7.2 tag commit; the
  follow-up mainline maintenance commit should pin the exact tag target.

### Fixed
- Made installer dry-run mode warn instead of fail when Rosetta is missing, so
  players can preview the fix before installing Rosetta.
- Made Rosetta installation verify actual x86_64 execution before continuing.
- Added a harness guard that fails validation when tracked text contains
  accidental workstation-local paths.

## Mainline maintenance after 1.7.1 (2026-06-22)

### Security
- Pinned mainline bootstrap commit verification to the `v1.7.1` tag target.
  This follow-up commit lives on `main` after the `v1.7.1` release tag so
  one-line installers can verify the exact release commit.

## 1.7.1 (2026-06-22)

### Fixed
- Fixed issue #11 game discovery on macOS Bash 3.2 so the installer no longer
  crashes with an empty detection result under `set -u`.
- Shared Steam/GOG game discovery with diagnostics and preflight checks so GOG
  installs under `$HOME/GOG Games` or the older GOG support path are detected
  consistently when the default Steam path is absent.
- Added the GOG Worms W.M.D product page to optional preflight reachability
  checks and clarified that public endpoint checks are diagnostic only.
- Normalized support-bundle archive ownership metadata so uploaded bundles do
  not expose the local macOS account name through `tar` listings.
- Fixed save backup creation when only local Team17 saves exist and Steam Cloud
  save directories are absent.

## Mainline maintenance after 1.7.0 (2026-06-18)

### Security
- Pinned mainline bootstrap commit verification to the `v1.7.0` tag target.
  This follow-up commit lives on `main` after the `v1.7.0` release tag so
  one-line installers can verify the exact release commit.

## 1.7.0 (2026-06-18)

### Added
- Added a v1.7.0 regression suite for issue #10 and the adjacent bug hunt,
  covering backup progress, restore selection, diagnostics, launcher friction,
  preflight URLs, manifest hashing, support-bundle sanitization, save backups,
  and Qt package version pinning.
- Added `tools/fetch_qt_homebrew_bottles.rb` to rebuild an isolated, checksum-
  locked Homebrew x86_64 bottle prefix for Qt runtime packaging.
- Added `SOURCE_PROVENANCE.tsv` support for Qt archives and committed the
  Homebrew bottle lock used to build the bundled Qt package.
- Added CI coverage for the new regression scripts.
- Added launcher option `7` to start Worms W.M.D directly from the friendly
  menu, plus a post-fix launch prompt after a successful apply.

### Changed
- Updated the bundled Qt runtime archive from 5.15.18 to Qt 5.15.19, the Qt
  5.15.x patch level verified from Homebrew `qt@5` on 2026-06-18.
- Reduced backup friction from issue #10 by showing backup manifest progress
  and batching manifest hashing work.
- Updated preflight network checks to use the public Team17 Worms W.M.D page
  and Steam Worms W.M.D store page.
- Qt package creation now rejects non-5.15.x inputs, embeds source provenance
  when provided, supports isolated dependency prefixes, and prunes framework
  headers from runtime archives.
- Support bundles now write unique archive names instead of overwriting a bundle
  created in the same second.
- Release documentation, support guidance, install examples, issue templates,
  runbooks, and technical docs now reflect v1.7.0 behavior and verification.

### Fixed
- Fixed the apparent hang during backup creation reported in issue #10.
- Fixed restore selection so restore prefers the newest original-looking backup
  instead of a backup that already contains the fix.
- Fixed diagnostics false positives for local Qt checksum and quarantine status.
- Fixed save backup handling for hidden files and copy failures.
- Fixed preflight Qt reporting so it shows the QtCore current version, such as
  5.15.19, instead of the compatibility version.
- Fixed launcher behavior when input is piped and when force mode should avoid
  watcher prompts.
- Fixed restore and backup manifest verification performance by hashing file
  batches instead of invoking one checksum process per file.
- Fixed preflight architecture and current-Qt-version checks used by local
  verification.

### Security
- Sanitized support bundles by default and stopped including raw logs, traces,
  crash logs, save data, game binaries, and private config contents.
- Sanitized diagnostics written to stdout, files, and clipboard by redacting
  home-account paths, external volume paths, temporary paths, email addresses,
  and common secret-like key/value strings.
- Added source-provenance documentation and lockfile-based rebuild steps for
  the bundled Qt runtime closure.
- Updated v1.7.0 bootstrap refs for the release tag and documented the
  follow-up mainline exact-commit pinning step.

## 1.6.6 (2026-06-13)

### Added
- Added GitHub issue templates for installation failures and bug reports.

### Changed
- Updated bootstrap defaults and release verification examples for `v1.6.6`.

### Fixed
- Fixed installation verification failures caused by Mach-O dependency paths
  containing spaces.
- Skipped the optional WebP image plugin from incomplete pre-built Qt packages
  instead of rolling back an otherwise working install.

## 1.6.5 (2026-06-10)

### Fixed
- Fixed main installer completion so verification errors fail the run before the
  success message and keep rollback enabled.
- Added CommonData config files to game-bundle backup and restore coverage.
- Made Info.plist metadata fixes correct existing false or missing values.
- Stopped writing in-bundle `.backup` copies of config files during URL fixes.

### Security
- Hardened bootstrap installers so `INSTALL_DIR` cannot move or overwrite an
  arbitrary non-empty directory or unrelated Git repository.
- Pinned bootstrap installers to release `v1.6.5` by default; non-default refs
  now require explicit developer opt-in.
- Pinned GitHub Actions to latest stable immutable commit SHAs.
- Hardened Qt and save archive handling against unsafe symlinks, hardlinks,
  special files, and mutable remote `dist/` fallback.
- Added game-bundle containment checks before framework, plugin, Info.plist, and
  config mutation.
- Rejected control-character path injection in diagnostics and launcher logging,
  constrained log files to `~/Library/Logs`, and expanded support-bundle path
  redaction.
- Made installation verification fail on external absolute Mach-O dependencies.

## 1.6.4 (2026-04-29)

### Fixed
- Fixed release checksum files so `shasum -a 256 -c` works after downloading
  the zip and `.sha256` file from GitHub Releases.

## 1.6.3 (2026-04-29)

### Added
- Added a friendly double-click launcher with apply, preview, verify, restore,
  support bundle, and help menu actions.
- Added player-facing release bundle tooling with `RELEASE_INFO.txt`,
  `RELEASE_MANIFEST.tsv`, zip output, and SHA-256 checksum output.
- Added a GitHub release workflow for building and publishing release zips from
  version tags.
- Added release SHA-256 verification instructions and GitHub artifact
  attestations for release assets.
- Added `docs/TRUST.md` with a player-readable trust and safety checklist.
- Added `.github/CODEOWNERS` to require maintainer review for trust-sensitive
  project files.
- Added Dependabot checks for GitHub Actions updates.
- Added `README_FIRST.txt`, `SUPPORT.md`, `STEAM_POST.md`,
  `ATTRIBUTIONS.md`, and clearer release-bundle guidance for community support.
- Added manifest creation and verification for game-bundle backups and save-game backup archives.
- Added sanitized diagnostics support bundles for community issue reports.
- Added deterministic Qt package creation controls, including explicit Qt prefix/version support for future Qt 5.15.x refreshes.

### Changed
- `Install Fix.command` and interactive no-argument `install.sh` runs now open
  the friendly launcher when available.
- `install.sh` can pin clones to a tagged release through `INSTALL_REF`.
- GitHub Actions now use current Node 24-compatible official action versions.
- Pre-built Qt package discovery now selects the highest verified semantic version instead of relying on modification time.
- Qt package validation now checks checksums, metadata, required frameworks/plugins, safe archive layout, archive manifests when present, generated cache manifests, and x86_64 Mach-O slices before installer use.
- Restore and rollback now verify backup manifests when present and warn when restoring older legacy backups.

### Security
- Save-game restore now validates archive layout before extraction.
- Diagnostics support bundles redact home paths and email-like values from generated reports.

## 1.6.2 (2026-04-29)

### Fixed
- Fixed dry-run Qt detection so the installer preview accepts the bundled pre-built Qt package before requiring Intel Homebrew.
- Fixed already-applied detection for the universal AGL stub by accepting any library slice list that includes `x86_64`.
- Fixed pre-built Qt preparation failures so the installer only falls back to Homebrew when a valid x86_64 Homebrew Qt install is actually present.

### Changed
- Main installer builds now use a per-run `mktemp` directory with cleanup instead of a shared `/tmp` path.
- One-line and double-click installers now show Git clone and pull progress while preserving the existing guidance flow.
- Diagnostics now report the bundled pre-built Qt package first and treat Intel Homebrew as an optional fallback.
- Documentation now notes a confirmed macOS 15.7.3 keyboard input buffering/lag report resolved after the Qt 5.15 refresh.
- Documentation now matches the current tool flags, AGL stub count, Team17 report notes, and validation command set.

## 1.6.1 (2025-12-27)

### Fixed
- Fixed "dependencies not found" errors when using pre-built Qt frameworks on Apple Silicon Macs without Intel Homebrew (Issue #2).
- Pre-built Qt package now properly copies bundled x86_64 dependency libraries (libpcre2, libzstd, libglib, libintl, libpng, libfreetype, etc.).
- Dependency copy script now skips Homebrew scanning when using pre-built package (dependencies already included).

### Changed
- Added chmod instructions to README and troubleshooting for "Insufficient Privileges" errors (Issue #1).

## 1.6.0 (2025-12-26)

### Added
- Added `tools/preflight_check.sh` for pre-launch verification of system requirements.
- Pre-flight check verifies Rosetta 2 status, game installation, fix status, and network connectivity.
- Added Rosetta 2 optimization hints for Apple Silicon users.
- Extended URL fixes to cover CommonData config files (AnalyticsConfig.txt, HttpConfig.txt).
- Added graceful fallbacks when `otool` or `curl` are unavailable in preflight check.

### Changed
- Redacted exposed API secrets in TEAM17_DEVELOPER_REPORT.md for responsible disclosure.
- Updated SECURITY.md with new mitigations and audit checklist.
- Updated documentation across README, TOOLS, and IMPROVEMENTS to reflect new features.
- Preflight check now uses `printf` for consistent output formatting.
- Preflight network checks enforce HTTPS with TLS 1.2 minimum.

### Fixed
- Fixed small/unresizable window issue by resetting incompatible Qt 5.3 window geometry after applying the fix.

### Security
- Game config secrets are now documented (redacted) rather than published in full.
- Added Game URL security to the security audit checklist.

## 1.5.0 (2025-12-26)

### Added
- Added a double-click installer (`Install Fix.command`).
- Added automatic Rosetta 2 install on Apple Silicon when missing.
- Added automatic Xcode Command Line Tools install prompt when needed.
- Added game auto-detection across Steam, GOG, and custom Steam library paths.
- Added an optional update watcher prompt after a successful fix.
- Added multi-install selection when multiple copies are found.

### Changed
- Redesigned the flow for zero setup.
- Rewrote error messages with clearer next steps.
- Made the default fix path automatic with no manual setup.
- Updated help text for automatic features.
- Reorganized documentation into `docs/` and refreshed style.

## 1.4.0 (2025-12-25)

### Added
- Added prebuilt Qt 5.15 x86_64 frameworks with a Homebrew fallback.
- Added `tools/package_qt_frameworks.sh` for distribution packaging.
- Added a Steam update watcher in `tools/watch_for_updates.sh` with an optional LaunchAgent.
- Added crash detection and reports in `tools/launch_worms.sh`.
- Added Steam launch options integration (`--steam %command%`) and `--check-fix`.
- Added `tools/backup_saves.sh` for backup and restore of saves, settings, and replays.
- Added `tools/check_updates.sh` to check for new fix versions with optional download.
- Added `tools/controller_helper.sh` for controller diagnostics and configuration tips.

### Changed
- The fix script now prefers prebuilt Qt frameworks.
- The Qt replacement script supports both prebuilt and Homebrew sources.
- Crash reports now save to `~/Library/Logs/WormsWMD/crashes/`.

## 1.3.0 (2025-12-25)

### Added
- Added a universal AGL stub (arm64 + x86_64).
- Added ad-hoc code signing to reduce Gatekeeper warnings.
- Added quarantine removal after applying the fix.
- Added `tools/collect_diagnostics.sh` for bug reports.
- Added an expanded FAQ and known limitations documentation.
- Added performance expectations and a compatibility matrix to the Team17 report.
- Added library version analysis for FMOD, libcurl, and the Steam API.

### Changed
- Verification now checks code signing status and quarantine flags.
- AGL stub verification accepts universal binaries.
- The Team17 report expanded to version 2.3.

## 1.2.5 (2025-12-25)

### Changed
- Dry-run output now lists Info.plist and config enhancements for completeness.

## 1.2.4 (2025-12-25)

### Changed
- Verification output now reports a clean Info.plist/config check when no issues are found.

## 1.2.3 (2025-12-25)

### Changed
- Verification now checks Info.plist metadata and config URL hygiene.
- Logging now covers Info.plist and config URL scripts for consistent diagnostics.

## 1.2.2 (2025-12-25)

### Changed
- Option parsing now allows combining `--verify` or `--restore` with `--verbose` or `--debug` in any order.
- Backups now include `Info.plist` and DataOSX config files for full restore coverage.
- Documentation now matches the current scripts and enhancements.

### Fixed
- Restore now reverts Info.plist and config file changes when present.

## 1.2.1 (2025-12-25)

### Changed
- Documentation accuracy pass, including removal of non-existent tools and clearer logging.
- The Team17 report expanded with scope, security and malware assessment, and updated recommendations.

### Fixed
- Corrected version history entries to match shipped features.

## 1.2.0 (2025-12-25)

### Added
- Added the Team17 developer report (`TEAM17_DEVELOPER_REPORT.md`) for official fix guidance.
- Added an Info.plist enhancement script (bundle ID, HiDPI flags, minimum system version update).
- Added a config URL security script (HTTP to HTTPS and internal URL disablement).
- Added verification for missing `@executable_path` and `@loader_path` dependencies.
- Added per-run logs in `~/Library/Logs/WormsWMD-Fix` with a `--log-file` override.
- Added debug tracing (`--debug`) and verbose verification output (`--verbose`).
- Added `QtSvg.framework` when missing (required by the SVG image plugin).
- Added verification of binary architectures for x86_64 compatibility.

### Changed
- Qt framework replacement now targets frameworks present in the game bundle and adjusts install names based on their layout.
- Dependency bundling and install-name fixes now scan bundled binaries instead of a hardcoded list.
- Verification output now includes system info to help diagnose environment-specific failures.

### Fixed
- Resolved ShellCheck warnings (SC2155, SC2295).
- AGL stub now compiles cleanly with stricter warnings enabled.
- Dependency copy no longer fails early under `set -e`.
- Rosetta detection now checks actual x86_64 execution.
- Validation now checks that `GAME_APP` points to a real app bundle before running destructive operations.
- Installer no longer resets or removes existing installs; it backs up and reclones instead.

## 1.1.0 (2025-12-25)

### Added
- Added dry-run mode (`--dry-run`, `-n`) to preview changes without applying them.
- Added force mode (`--force`, `-f`) to skip confirmation prompts.
- Added detection for already-applied fixes and prompts before reapplying.
- Added automatic rollback to restore from backup if the fix fails.
- Added progress spinners for long-running operations.
- Added a disk space check and warnings below 200 MB.
- Added a one-liner installer (`curl -fsSL .../install.sh | bash`).
- Added GitHub Actions CI for ShellCheck and syntax validation.

### Changed
- Version bumped to 1.1.0.
- Improved error messages with an issue tracker link.
- Improved output formatting with status symbols and clear fallbacks for non-TTY terminals.
- Help text now includes all new options.

### Fixed
- Replaced hardcoded Qt and GLib version numbers with dynamic detection.
- Replaced `/Users/$USER` with `$HOME` for portability.
- Trap handlers now clean up `/tmp/agl_stub_build` on exit.

## 1.0.0 (2025-12-25)

### Added
- Initial release.
- Added the AGL stub library for macOS 26 (Tahoe) compatibility.
- Added Qt 5.15 framework replacement (from Qt 5.3.2).
- Added automatic backup creation before modifications.
- Added `--verify` to check installation status.
- Added `--restore` to restore from backup.
- Added `--help` with usage documentation.
- Added the troubleshooting guide and documentation.

### Technical details
- Replaced five Qt frameworks (QtCore, QtGui, QtWidgets, QtOpenGL, QtPrintSupport).
- Added QtDBus.framework (required by libqcocoa.dylib).
- Bundled dependency libraries from Homebrew.
- Fixed all library paths to use `@executable_path`.
