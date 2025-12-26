# Changelog

Notable changes are listed here. This project follows Keep a Changelog and Semantic Versioning.

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
