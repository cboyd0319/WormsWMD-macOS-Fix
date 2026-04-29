# Worms W.M.D macOS Fix

[![CI](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml/badge.svg)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS 26.0+](https://img.shields.io/badge/macOS-26.0%2B-blue.svg)](https://www.apple.com/macos/)
[![Latest release](https://img.shields.io/github/v/release/cboyd0319/WormsWMD-macOS-Fix?label=release)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases/latest)
[![Security documented](https://img.shields.io/badge/security-documented-brightgreen.svg)](SECURITY.md)
[![Unofficial community fix](https://img.shields.io/badge/Team17-unofficial%20community%20fix-lightgrey.svg)](ATTRIBUTIONS.md)

Community compatibility fix for Worms W.M.D on newer macOS versions. It is
intended for players who see a black screen, broken window sizing, keyboard lag,
or related launch issues caused by the older runtime shipped with the game.

This is an unofficial community project. It does not include Worms W.M.D game
files or official Team17/Worms artwork.

## Quick Start

For most players, this is the only section you need.

1. Download the [latest release zip](https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases/latest).
2. Unzip it.
3. Double-click `Worms W.M.D Fix.command`.
4. Press `1` to apply the recommended fix.
5. Launch Worms W.M.D normally from Steam or GOG.

If macOS blocks the launcher, right-click `Worms W.M.D Fix.command`, choose
**Open**, then choose **Open** again.

If the fix fails, run `Worms W.M.D Fix.command` again and press `5`. This
creates a sanitized support bundle on your Desktop that can be attached to a
GitHub issue.

## Verify The Download

The release page includes a `.zip.sha256` checksum next to the zip file. To
verify the `v1.6.4` release before unzipping it:

```bash
cd ~/Downloads
shasum -a 256 -c WormsWMD-macOS-Fix-v1.6.4.zip.sha256
```

Terminal should print `WormsWMD-macOS-Fix-v1.6.4.zip: OK`.

For stronger provenance checking, GitHub CLI users can also verify the release
attestation:

```bash
gh attestation verify WormsWMD-macOS-Fix-v1.6.4.zip --repo cboyd0319/WormsWMD-macOS-Fix
```

## Launcher Options

The launcher is a simple numbered menu:

| Option | Purpose |
| --- | --- |
| `1` | Apply the recommended fix. |
| `2` | Preview what would change before changing anything. |
| `3` | Check whether the fix is already installed. |
| `4` | Restore original game files from a backup. |
| `5` | Create a sanitized support bundle on your Desktop. |
| `6` | Open the help file. |

## Requirements

- macOS 26 (Tahoe) or later for the black-screen AGL fix.
- Worms W.M.D installed through Steam or GOG.
- Internet connection.
- `git`, usually installed by the Xcode Command Line Tools.

Earlier macOS versions usually do not need the AGL fix, but macOS 15.x players
with keyboard buffering or lag may still benefit from the Qt 5.15 runtime
refresh.

The launcher can prompt for these system components when needed:

- Rosetta 2 on Apple Silicon Macs.
- Xcode Command Line Tools.
- Qt frameworks downloaded from this repository's GitHub releases, with a
  Homebrew fallback.

## What The Fix Changes

- Adds an AGL stub framework so the game can launch on macOS 26+.
- Replaces the bundled Qt 5.3.2 runtime with Qt 5.15.
- Verifies pre-built Qt package checksums, metadata, manifests, and x86_64
  slices before use.
- Bundles required dependencies and fixes install names.
- Updates Info.plist values for bundle identity, HiDPI support, and minimum
  macOS version.
- Fixes known HTTP URLs in `DataOSX/CommonData` config files.
- Comments out internal or staging URLs in `DataOSX` config files.
- Clears quarantine flags and applies ad-hoc signing.
- Resets incompatible Qt window geometry that can cause small-window issues.
- Creates restorable backups with manifests for integrity checks.

## Safety And Verification

This project is designed so players can inspect what it does before running it:

- The launcher does not require `sudo` or administrator privileges.
- Option `2` previews planned changes without modifying game files.
- Option `4` restores original files from backup.
- Release zips include SHA-256 checksums and GitHub artifact attestations.
- Support bundles are designed to collect diagnostics without game binaries,
  save archives, or private account tokens.
- The security model, review checklist, and source-audit commands are documented
  in [SECURITY.md](SECURITY.md).
- A plain-English trust guide is available in [docs/TRUST.md](docs/TRUST.md).

You can also review the installer script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/v1.6.4/install.sh
```

## Terminal Install Option

Use the release zip above unless you specifically prefer Terminal.

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/v1.6.4/install.sh | INSTALL_REF=v1.6.4 bash
```

With no command-line flags and an interactive Terminal, this opens the same
launcher menu as the release zip. The `INSTALL_REF=v1.6.4` part makes the
bootstrap clone the tagged release instead of whatever is currently on `main`.

## Pre-Flight Check

Before launching the game, you can verify that your system is ready:

```bash
./tools/preflight_check.sh
```

This checks:

- macOS version and architecture.
- Rosetta 2 status on Apple Silicon.
- Game installation and fix status.
- Runtime dependencies.
- Network connectivity to Team17 and Steam endpoints.

Use `--quick` to skip network checks, or `--verbose` for detailed output.

## Troubleshooting

- If macOS says the launcher cannot be opened, right-click it and choose
  **Open**.
- If the game was updated or reinstalled, run option `1` again.
- If you want to undo the fix, run option `4`.
- If you need help, run option `5` and attach the generated support bundle to a
  GitHub issue.

## Documentation

- [Documentation index](docs/README.md) - Complete docs map.
- [Installation](docs/INSTALL.md) - Manual install and restore options.
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Solutions for common problems.
- [FAQ](docs/FAQ.md) - Frequently asked questions.
- [Security](SECURITY.md) - Threat model, review checklist, and audit commands.
- [Trust and safety](docs/TRUST.md) - How to verify the download before running
  it.
- [Support](SUPPORT.md) - Issue reporting and support bundles.
- [Tools](docs/TOOLS.md) - Helper utilities reference.
- [Technical details](docs/TECHNICAL.md) - How the fix works.
- [What this fix improves](docs/IMPROVEMENTS.md) - Fixes and enhancements.
- [Attributions](ATTRIBUTIONS.md) - Asset and unofficial-project policy.
- [Contributing](CONTRIBUTING.md) - How to contribute.
- [Changelog](CHANGELOG.md) - Version history.
- [Team17 Developer Report](TEAM17_DEVELOPER_REPORT.md) - Technical report for
  Team17.
- [Steam post template](STEAM_POST.md) - Copy/paste community support text.

## Support

- Issues: https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues
- If a player is stuck, ask them to run `Worms W.M.D Fix.command` and choose
  option `5` to create a sanitized support bundle on the Desktop.

## Credits

- Steam community members who reported the macOS issue and tested fixes.
- Qt Project for Qt 5.15.
- This repository uses original project files only; no official Team17/Worms
  art is bundled.
- Fix developed with AI assistance.

## Links

- [Worms W.M.D on Steam](https://store.steampowered.com/app/327030/Worms_WMD/)

Steam discussion threads about this issue:

- [Can't open on macOS Tahoe M2](https://steamcommunity.com/app/327030/discussions/2/594035123771846058/)
- [Black screen on Mac Pro 2019 16](https://steamcommunity.com/app/327030/discussions/2/686363730790074305/)
- [Black screen on macOS](https://steamcommunity.com/app/327030/discussions/2/686365524184117509/)
