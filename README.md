# Worms W.M.D - macOS Tahoe (26.x) Fix

[![CI](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml/badge.svg)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-26.0%2B-blue.svg)](https://www.apple.com/macos/)

Fix the black screen on macOS 26 (Tahoe) and later by restoring AGL compatibility and replacing the bundled Qt frameworks. The repo also includes tools for diagnostics, backups, and updates.

## Quick start

### Option 1: Double-click installer

1. Download [`Install Fix.command`](https://github.com/cboyd0319/WormsWMD-macOS-Fix/raw/main/Install%20Fix.command).
2. Double-click the file.
3. If macOS blocks it, right-click → **Open** → **Open** again.
4. If it still won't run, see [Troubleshooting](docs/TROUBLESHOOTING.md#install-fixcommand-wont-run).

### Option 2: One-liner (Terminal)

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash
```

Requires `git` (Xcode Command Line Tools installs it if missing).

### Option 3: Manual / advanced

See `docs/INSTALL.md` for manual install, dry-run, and restore steps.

## Requirements

- macOS 26 (Tahoe) or later
- Worms W.M.D installed via Steam or GOG
- Internet connection
- git (installed by Xcode Command Line Tools)

The script installs these if needed (you may see system prompts):
- Rosetta 2 (Apple Silicon)
- Xcode Command Line Tools
- Qt frameworks (downloaded from GitHub; Homebrew fallback)

## What the fix does

- Adds an AGL stub framework so the game launches on macOS 26+.
- Replaces Qt 5.3.2 with Qt 5.15.
- Bundles required dependencies and fixes install names.
- Updates Info.plist (bundle ID, HiDPI support, minimum version).
- Fixes HTTP URLs to HTTPS in config files.
- Comments out internal/staging URLs that shouldn't be in retail builds.
- Clears quarantine flags and applies ad-hoc signing.

## Pre-flight check

Before launching, you can verify your system is ready:

```bash
./tools/preflight_check.sh
```

This checks:
- macOS version and architecture
- Rosetta 2 status (Apple Silicon)
- Game installation and fix status
- Runtime dependencies
- Network connectivity to Team17 services

Use `--quick` to skip network checks, or `--verbose` for detailed output.

## Documentation

- [What this fix improves](docs/IMPROVEMENTS.md) - All fixes and enhancements explained
- [Installation](docs/INSTALL.md) - Manual install and restore options
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Solutions for common problems
- [FAQ](docs/FAQ.md) - Frequently asked questions
- [Tools](docs/TOOLS.md) - Helper utilities reference
- [Technical details](docs/TECHNICAL.md) - How the fix works
- [Security](SECURITY.md) - Security information
- [Contributing](CONTRIBUTING.md) - How to contribute
- [Changelog](CHANGELOG.md) - Version history
- [Team17 Developer Report](TEAM17_DEVELOPER_REPORT.md) - Technical report for Team17

## Support

- Issues: https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues

## Credits

- Steam community for reporting the issue
- Qt Project for Qt 5.15
- Fix developed with assistance from Claude

## Links

- [Worms W.M.D on Steam](https://store.steampowered.com/app/327030/Worms_WMD/)

Steam discussion threads about this issue:

- [Can't open on macOS Tahoe M2](https://steamcommunity.com/app/327030/discussions/2/594035123771846058/)
- [Black screen on Mac Pro 2019 16](https://steamcommunity.com/app/327030/discussions/2/686363730790074305/)
- [Black screen on macOS](https://steamcommunity.com/app/327030/discussions/2/686365524184117509/)
