# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2025-12-26

### Added
- **Double-click installer**: `Install Fix.command` - download and double-click, that's it!
- **Auto-install Rosetta 2**: Automatically installs Rosetta on Apple Silicon if missing
- **Auto-install Xcode CLT**: Automatically prompts to install Xcode Command Line Tools if needed
- **Auto-detect game location**: Searches Steam, GOG, and custom Steam library paths
- **Steam watcher prompt**: Offers to install the update watcher after successful fix
- **Multiple installation support**: If multiple game copies found, lets user choose which to fix

### Changed
- Completely redesigned for zero technical knowledge users
- All error messages rewritten to be human-friendly with clear next steps
- Fix now requires zero manual setup - everything is automatic
- Help text updated to reflect automatic features

## [1.4.0] - 2025-12-25

### Added
- **Pre-built Qt frameworks**: Eliminates Homebrew requirement for most users
  - Automatic download of pre-packaged Qt 5.15 x86_64 frameworks
  - Falls back to Homebrew if pre-built not available
  - `tools/package_qt_frameworks.sh` for creating distribution packages
- **Steam update watcher**: `tools/watch_for_updates.sh`
  - Monitors for Steam updates that overwrite the fix
  - Optional LaunchAgent for automatic monitoring on login
  - Prompts to reapply fix when needed
- **Enhanced game launcher**: `tools/launch_worms.sh` improvements
  - Crash detection and automatic crash reports
  - Steam launch options integration (`--steam %command%`)
  - Fix verification before launch (`--check-fix`)
- **Save game backup tool**: `tools/backup_saves.sh`
  - Backup and restore save games, settings, replays
  - Supports both Steam Cloud and local saves
- **Update checker**: `tools/check_updates.sh`
  - Checks GitHub for new fix versions
  - Optional automatic download of updates
- **Controller helper**: `tools/controller_helper.sh`
  - Diagnoses controller connectivity issues
  - Configuration tips for Xbox, PlayStation, Switch Pro controllers
  - Steam Input configuration guidance

### Changed
- Fix script now prefers pre-built Qt (no Homebrew needed)
- Qt replacement script supports both pre-built and Homebrew sources
- Crash reports saved to `~/Library/Logs/WormsWMD/crashes/`

## [1.3.0] - 2025-12-25

### Added
- **Universal AGL stub**: Now builds arm64 + x86_64 for future-proofing
- **Ad-hoc code signing**: Automatically signs app bundle to reduce Gatekeeper friction
- **Quarantine removal**: Clears macOS quarantine flags after fix
- **System diagnostics tool**: `tools/collect_diagnostics.sh` for bug reports
- **Expanded FAQ**: Comprehensive Q&A section in README
- **Known Limitations section**: Clear documentation of what can/cannot be fixed
- **Performance expectations**: Documented in Team17 developer report
- **Compatibility matrix**: Detailed testing matrix in Team17 developer report
- **Library version analysis**: FMOD, libcurl, Steam API version identification

### Changed
- Verification now checks code signing status and quarantine flags
- AGL stub verification accepts universal binaries
- Team17 developer report expanded to version 2.3

## [1.2.5] - 2025-12-25

### Changed
- Dry-run output now lists Info.plist/config enhancements for completeness

## [1.2.4] - 2025-12-25

### Changed
- Verification output now reports a clean Info.plist/config check when no issues are found

## [1.2.3] - 2025-12-25

### Changed
- Verification now checks Info.plist metadata and config URL hygiene
- Logging now covers Info.plist and config URL scripts for consistent diagnostics

## [1.2.2] - 2025-12-25

### Changed
- Option parsing now allows combining `--verify`/`--restore` with `--verbose`/`--debug` in any order
- Backups include `Info.plist` and DataOSX config files for full restore coverage
- Documentation aligned with current scripts and enhancements

### Fixed
- Restore/rollback now reverts Info.plist and config file changes when present

## [1.2.1] - 2025-12-25

### Changed
- Documentation accuracy pass (removed references to non-existent tools, clarified logging/verification)
- Team17 developer report expanded with scope, security/malware assessment, and updated recommendations

### Fixed
- Corrected version history entries to match shipped features

## [1.2.0] - 2025-12-25

### Added
- Comprehensive Team17 developer report (`TEAM17_DEVELOPER_REPORT.md`) for official fix guidance
- Info.plist enhancement script (CFBundleIdentifier, HiDPI flags, minimum system version update)
- Config URL security script (HTTP→HTTPS and internal URL disablement)
- Verification now reports missing `@executable_path`/`@loader_path` dependencies
- Per-run log files in `~/Library/Logs/WormsWMD-Fix` with `--log-file` override
- Debug tracing (`--debug`) and verbose verification output (`--verbose`)
- QtSvg.framework is bundled when missing (required by SVG image plugin)
- Verification now checks binary architectures for x86_64 compatibility

### Changed
- Qt framework replacement now targets the frameworks present in the game bundle and adjusts install names based on their layout
- Dependency bundling and install-name fixes now scan bundled binaries instead of relying on a hardcoded list
- Verification output includes system info to help diagnose environment-specific failures

### Fixed
- ShellCheck warnings resolved (SC2155, SC2295)
- AGL stub now compiles cleanly with stricter warnings enabled
- Dependency copy step no longer fails early under `set -e`
- More reliable Rosetta detection (checks actual x86_64 execution)
- Stronger validation that `GAME_APP` points to a real app bundle before running destructive operations
- Installer no longer resets or removes existing installs; it backs up and re-clones instead

## [1.1.0] - 2025-12-25

### Added
- **Dry-run mode** (`--dry-run`, `-n`): Preview all changes without applying them
- **Force mode** (`--force`, `-f`): Skip all confirmation prompts
- **Already-applied detection**: Detects if fix was previously applied and prompts before re-applying
- **Automatic rollback**: If an error occurs during the fix, automatically restores from backup
- **Progress spinners**: Visual feedback during long-running operations
- **Disk space check**: Warns if less than 200MB available
- **One-liner installer**: `curl -fsSL .../install.sh | bash` support
- **GitHub Actions CI**: Automated shellcheck and syntax validation
- **GitHub Releases**: Pre-built AGL stub binaries and release archives

### Changed
- Version bumped to 1.1.0
- Improved error messages with issue tracker link
- Better output formatting with icons (✓, ✗, ⚠, ℹ)
- Color output gracefully degrades on non-TTY terminals
- Help text now includes all new options

### Fixed
- Hardcoded Qt/GLib version numbers now dynamically detected
- Changed `/Users/$USER` to `$HOME` for better portability
- Trap handlers properly clean up `/tmp/agl_stub_build` on exit

## [1.0.0] - 2025-12-25

### Added
- Initial release
- AGL stub library for macOS 26 (Tahoe) compatibility
- Qt 5.15 framework replacement (from Qt 5.3.2)
- Automatic backup creation before modifications
- `--verify` flag to check installation status
- `--restore` flag to restore from backup
- `--help` flag with usage documentation
- Comprehensive README with troubleshooting guide

### Technical Details
- Replaces 5 Qt frameworks (QtCore, QtGui, QtWidgets, QtOpenGL, QtPrintSupport)
- Adds QtDBus.framework (required by libqcocoa.dylib)
- Bundles dependency libraries from Homebrew
- Fixes all library paths to use `@executable_path`

[1.5.0]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.2.5...v1.3.0
[1.2.5]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.2.4...v1.2.5
[1.2.4]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases/tag/v1.0.0
