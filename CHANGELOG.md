# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive Team17 developer report (`TEAM17_DEVELOPER_REPORT.md`) for official fix guidance
- **Info.plist enhancements**: Adds CFBundleIdentifier, NSHighResolutionCapable (Retina support), NSSupportsAutomaticGraphicsSwitching
- **Config security fixes**: HTTP→HTTPS for Team17 URLs, internal staging URLs commented out
- **Diagnostic game launcher** (`tools/launch_worms.sh`): Logging, safe-mode, Qt/OpenGL debugging
- Verification now reports missing `@executable_path`/`@loader_path` dependencies
- Per-run log files in `~/Library/Logs/WormsWMD-Fix` with `--log-file` override
- Debug tracing (`--debug`) and verbose verification output (`--verbose`)
- QtSvg.framework is bundled when missing (required by SVG image plugin)
- Verification now checks binary architectures for x86_64 compatibility
- Team17 report expanded with security/malware assessment and additional improvements

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

[Unreleased]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases/tag/v1.0.0
