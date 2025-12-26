# Worms W.M.D - macOS Tahoe (26.x) Fix

[![CI](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml/badge.svg)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-26.0%2B-blue.svg)](https://www.apple.com/macos/)

Fix the black screen on macOS 26 (Tahoe) and later by restoring AGL compatibility and replacing the bundled Qt frameworks. The repo also includes tools for diagnostics, backups, and updates.

## Quick start

### Option 1: Double-click installer

1. Download [`Install Fix.command`](https://github.com/cboyd0319/WormsWMD-macOS-Fix/raw/main/Install%20Fix.command).
2. Double-click the file.
3. If macOS blocks it, right-click and select **Open**.

### Option 2: One-liner (Terminal)

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash
```

### Option 3: Manual clone

```bash
git clone https://github.com/cboyd0319/WormsWMD-macOS-Fix.git
cd WormsWMD-macOS-Fix
./fix_worms_wmd.sh
```

Preview changes without applying:

```bash
./fix_worms_wmd.sh --dry-run
```

## Requirements

- macOS 26 (Tahoe) or later
- Worms W.M.D installed via Steam or GOG
- Internet connection

The script installs these if needed (you may see system prompts):
- Rosetta 2 (Apple Silicon)
- Xcode Command Line Tools
- Qt frameworks (downloaded from GitHub; Homebrew fallback)

## What the fix does

- Adds an AGL stub framework so the game launches on macOS 26+.
- Replaces Qt 5.3.2 with Qt 5.15.
- Bundles required dependencies and fixes install names.
- Updates Info.plist and config URLs.
- Clears quarantine flags and applies ad-hoc signing to reduce Gatekeeper warnings.

## Documentation

- `docs/INSTALL.md`
- `docs/TROUBLESHOOTING.md`
- `docs/FAQ.md`
- `docs/TECHNICAL.md`
- `docs/TOOLS.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `TEAM17_DEVELOPER_REPORT.md`
- `CHANGELOG.md`
- `LICENSE`

## Support

- Issues: https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues

## Credits

- Steam community for reporting the issue
- Qt Project for Qt 5.15
- Fix developed with assistance from Claude

## Links

- Steam discussion thread: https://steamcommunity.com/app/327030/discussions/2/686363730790074305/
- Worms W.M.D on Steam: https://store.steampowered.com/app/327030/Worms_WMD/
