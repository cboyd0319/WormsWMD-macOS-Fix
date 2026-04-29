# Worms W.M.D macOS Fix

[![CI](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml/badge.svg)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS 26.0+](https://img.shields.io/badge/macOS-26.0%2B-blue.svg)](https://www.apple.com/macos/)
[![Latest release](https://img.shields.io/github/v/release/cboyd0319/WormsWMD-macOS-Fix?label=release)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases/latest)
[![Security documented](https://img.shields.io/badge/security-documented-brightgreen.svg)](SECURITY.md)
[![Unofficial community fix](https://img.shields.io/badge/Team17-unofficial%20community%20fix-lightgrey.svg)](ATTRIBUTIONS.md)

## Run This First

1. Download the [latest release zip](https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases/latest).
2. Unzip it.
3. Double-click `Worms W.M.D Fix.command`.
4. Press `1`.

If macOS blocks it, right-click `Worms W.M.D Fix.command`, choose **Open**,
then choose **Open** again. If the fix fails, run the same file again and press
`5` to create a support bundle on your Desktop.

---

<div align="center">

<img src="assets/geocities-chaos-banner.svg" alt="Worms W.M.D macOS Fix black screen repair zone" width="100%" />

<marquee behavior="alternate" scrollamount="12">
<b>!!! PRESS 1 TO FIX !!! NO SUDO !!! BACKUPS FIRST !!! QT 5.15 !!! UNOFFICIAL COMMUNITY FIX !!!</b>
</marquee>

</div>

---

## About

Worms W.M.D can open to a black screen on newer macOS because the game expects
older graphics and Qt runtime behavior. This community project applies the
current workaround and keeps restore, verification, and support tools in the
same launcher.

This is an unofficial community fix. It does not include Worms W.M.D game files
or official Team17/Worms artwork.

## Launcher Options

The launcher is just a menu. Option `1` is the main path. The other buttons are
there when you want to preview, check, restore, or ask for help.

<table>
<tr>
<th>Button</th>
<th>What It Does</th>
</tr>
<tr>
<td><code>1</code></td>
<td>Applies the recommended fix.</td>
</tr>
<tr>
<td><code>2</code></td>
<td>Shows what would change before changing anything.</td>
</tr>
<tr>
<td><code>3</code></td>
<td>Checks whether the fix is already installed.</td>
</tr>
<tr>
<td><code>4</code></td>
<td>Restores original files from a backup.</td>
</tr>
<tr>
<td><code>5</code></td>
<td>Creates a sanitized support bundle on your Desktop.</td>
</tr>
<tr>
<td><code>6</code></td>
<td>Opens the simple help file.</td>
</tr>
</table>

## Terminal Install Option

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash
```

Requires `git` (install Xcode Command Line Tools if missing). With no command
line flags and an interactive Terminal, it opens the same launcher menu.

If `curl | bash` makes you uncomfortable, that is reasonable. Use the release
zip at the top of this page, or open `install.sh` in your browser first and read
it before running anything.

## Requirements

- Target: macOS 26 (Tahoe) or later. Earlier macOS versions typically don't
  need the AGL fix, but macOS 15.x users with keyboard input buffering or lag
  may benefit from the Qt 5.15 refresh.
- Worms W.M.D installed via Steam or GOG
- Internet connection
- git (installed by Xcode Command Line Tools)

The script can prompt to install these if needed (you may see system prompts):

- Rosetta 2 (Apple Silicon)
- Xcode Command Line Tools
- Qt frameworks (downloaded from GitHub; Homebrew fallback)

## What The Fix Does

- Adds an AGL stub framework so the game launches on macOS 26+.
- Replaces Qt 5.3.2 with Qt 5.15.
- Verifies pre-built Qt package checksums, metadata, manifests, and x86_64
  slices before use.
- Bundles required dependencies and fixes install names.
- May resolve keyboard input buffering or lag caused by the original Qt 5.3.2
  runtime.
- Updates Info.plist (bundle ID, HiDPI support, minimum version).
- Fixes known HTTP URLs in DataOSX/CommonData config files.
- Comments out internal/staging URLs in DataOSX config files.
- Clears quarantine flags and applies ad-hoc signing.
- Resets incompatible Qt window geometry to fix small window issues.
- Creates restorable backups with manifests for integrity checks.

## Security And Verification

See [SECURITY.md](SECURITY.md) for the threat model, permissions, audit
checklist, and source review commands. The short version:

- The launcher does not require `sudo` or administrator privileges.
- Pre-built Qt packages are checked with metadata, checksums, manifests, and
  x86_64 slice validation before use.
- Game-bundle backups include manifests and restore verification.
- Support bundles are designed to collect diagnostics without game binaries,
  save archives, or private account tokens.

## Pre-Flight Check

Before launching, you can verify your system is ready:

```bash
./tools/preflight_check.sh
```

This checks:

- macOS version and architecture
- Rosetta 2 status (Apple Silicon)
- Game installation and fix status
- Runtime dependencies
- Network connectivity to Team17 and Steam endpoints

Use `--quick` to skip network checks, or `--verbose` for detailed output.

## Documentation

- [Documentation index](docs/README.md) - Complete durable docs map
- [Support](SUPPORT.md) - Issue reporting and support bundles
- [Attributions](ATTRIBUTIONS.md) - Asset and unofficial-project policy
- [Steam post template](STEAM_POST.md) - Copy/paste community support text
- [What this fix improves](docs/IMPROVEMENTS.md) - All fixes and enhancements explained
- [Installation](docs/INSTALL.md) - Manual install and restore options
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Solutions for common problems
- [FAQ](docs/FAQ.md) - Frequently asked questions
- [Tools](docs/TOOLS.md) - Helper utilities reference
- [Technical details](docs/TECHNICAL.md) - How the fix works
- [Agent harness](docs/style/agent-harness.md) - Repo-local agent workflow and validation standard
- [Security](SECURITY.md) - Security information
- [Contributing](CONTRIBUTING.md) - How to contribute
- [Changelog](CHANGELOG.md) - Version history
- [Team17 Developer Report](TEAM17_DEVELOPER_REPORT.md) - Technical report for Team17

## Support

- Issues: https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues
- If a player is stuck, ask them to run `Worms W.M.D Fix.command` and choose
  option `5` to create a sanitized support bundle on the Desktop.

## Credits

- Steam community for reporting the issue
- Qt Project for Qt 5.15
- Original project visuals are included under this repo's license; no official
  Team17/Worms art is bundled.
- Fix developed with AI assistance

## Links

- [Worms W.M.D on Steam](https://store.steampowered.com/app/327030/Worms_WMD/)

Steam discussion threads about this issue:

- [Can't open on macOS Tahoe M2](https://steamcommunity.com/app/327030/discussions/2/594035123771846058/)
- [Black screen on Mac Pro 2019 16](https://steamcommunity.com/app/327030/discussions/2/686363730790074305/)
- [Black screen on macOS](https://steamcommunity.com/app/327030/discussions/2/686365524184117509/)
