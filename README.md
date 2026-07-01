# Worms W.M.D macOS Fix

[![CI](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml/badge.svg)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS 26.0+](https://img.shields.io/badge/macOS-26.0%2B-blue.svg)](https://www.apple.com/macos/)
[![Latest release](https://img.shields.io/github/v/release/cboyd0319/WormsWMD-macOS-Fix?label=release)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases/latest)
[![Security documented](https://img.shields.io/badge/security-documented-brightgreen.svg)](SECURITY.md)
[![Unofficial community fix](https://img.shields.io/badge/Team17-unofficial%20community%20fix-lightgrey.svg)](ATTRIBUTIONS.md)

Community compatibility fix for Worms W.M.D on newer macOS versions. It helps
with black screens, broken window sizing, keyboard lag, and related launch
issues caused by the older runtime shipped with the game.

This is an unofficial community project. It does not include Worms W.M.D game
files or official Team17/Worms artwork.

## Start Here

For most players:

1. Open the [latest release page](https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases/latest) and download
   `WormsWMD-macOS-Fix-v1.7.4.zip`.
2. Unzip it.
3. Double-click `Worms W.M.D Fix.command`.
4. Press `1`.

| Goal | What to do |
| --- | --- |
| Install | Press `1` in the launcher. |
| Preview first | Open `Worms W.M.D Fix.command` and press `2`. |
| Check launch readiness | Open `Worms W.M.D Fix.command` and press `3`. |
| Undo the fix | Open `Worms W.M.D Fix.command` and press `4`. |
| Ask for help | Open `Worms W.M.D Fix.command` and press `5` to create a sanitized support bundle. |
| Launch the game | Launch when prompted after applying the fix, or press `7` later. |

If macOS blocks the launcher, right-click `Worms W.M.D Fix.command`, choose
**Open**, then choose **Open** again.

## v1.7.4 At A Glance

| Area | What changed |
| --- | --- |
| Detection | Steam, GOG, custom `GAME_APP`, dry-run, verify, diagnostics, and launcher paths use consistent game discovery. |
| Rollback | Every config file the fixer can mutate is backed up, restored, and verified through the same shared list. |
| Mutation safety | The fixer refuses malformed bundle paths plus symlinked or hardlinked config files before writing. |
| Bootstrap safety | Terminal and double-click bootstraps are pinned to `v1.7.4` and reject install directories that resolve into system paths. |
| Log hygiene | Rejected log paths do not create directories outside `~/Library/Logs`, hardlinked log files are refused, and safe nested log paths still work. |
| Harness | CI and repo-local harness rules now enforce the release regression suite, CODEOWNERS coverage, full-SHA GitHub Actions pins, explicit runner labels, and a pinned ShellCheck binary. |

## Requirements

| Requirement | Notes |
| --- | --- |
| macOS | macOS 26 Tahoe or later for the black-screen AGL fix. macOS 27 Golden Gate also needs Rosetta on Apple Silicon. |
| Game install | Worms W.M.D installed through Steam or GOG. |
| Apple Silicon | Rosetta 2 is required and can be installed by macOS when prompted. |
| Developer tools | `git`, usually provided by the Xcode Command Line Tools. |
| Internet | Needed for the one-line installer, updates, and optional checks. |

This release targets macOS 26 Tahoe and later. Earlier macOS versions usually
do not need the AGL fix. There is one confirmed macOS 15.7.3 report that the Qt
5.15 refresh improved keyboard buffering or lag, but macOS 15.x is not a
validated support target for v1.7.4.

On macOS 27 Golden Gate, Rosetta may need to be installed again after an
upgrade. The preview command reports this without changing your Mac; the game
needs Rosetta before it can launch on Apple Silicon.

## Verify The Download

The release page includes a `.zip.sha256` checksum next to the zip file.

```bash
cd ~/Downloads
shasum -a 256 -c WormsWMD-macOS-Fix-v1.7.4.zip.sha256
```

Expected output:

```text
WormsWMD-macOS-Fix-v1.7.4.zip: OK
```

GitHub CLI users can also verify the release attestation:

```bash
gh attestation verify WormsWMD-macOS-Fix-v1.7.4.zip --repo cboyd0319/WormsWMD-macOS-Fix
```

## Launcher Menu

| Option | Purpose |
| --- | --- |
| `1` | Apply the recommended fix. |
| `2` | Preview what would change before changing anything. |
| `3` | Check whether the game is ready to launch. |
| `4` | Restore original game files from a backup. |
| `5` | Create a sanitized support bundle on your Desktop. |
| `6` | Open the help file. |
| `7` | Launch Worms W.M.D. |

## What The Fix Changes

| Component | Change |
| --- | --- |
| AGL | Adds a compatibility stub framework so the game can launch on macOS 26+. |
| Qt | Replaces the bundled Qt 5.3.2 runtime with Qt 5.15.x. |
| Dependencies | Bundles required dylibs and fixes install names. |
| App metadata | Updates Info.plist bundle identity, HiDPI, and minimum macOS values. |
| Config URLs | Converts known HTTP URLs to HTTPS and comments out internal/staging URLs. |
| Signing | Clears quarantine flags and applies ad-hoc signing. |
| Window state | Resets incompatible Qt window geometry that can cause small windows. |
| Backups | Creates restorable game-bundle backups with manifests for integrity checks. |

## Safety Model

| Safety feature | What it means |
| --- | --- |
| No `sudo` | The launcher does not require administrator privileges. |
| Preview mode | Option `2` shows planned changes without modifying game files. |
| Restore path | Option `4` restores original game files from backup. |
| Verified releases | Release zips include SHA-256 checksums and GitHub artifact attestations. |
| Sanitized support | Support bundles avoid game binaries, save archives, raw logs, and private config contents. |
| Documented security | See [SECURITY.md](SECURITY.md) and [docs/TRUST.md](docs/TRUST.md). |

Review the installer script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/v1.7.4/install.sh
```

## Terminal Install

Use the release zip unless you specifically prefer Terminal.

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/v1.7.4/install.sh | bash
```

With no command-line flags and an interactive Terminal, this opens the same
launcher menu as the release zip. The bootstrap is pinned to release `v1.7.4`
by default. The `v1.7.4` raw tag bootstrap pins the release tag, and the
mainline maintenance bootstrap verifies the exact `v1.7.4` tag target commit.

## Pre-Flight Check

```bash
./tools/preflight_check.sh
```

| Check | Covers |
| --- | --- |
| System | macOS version, architecture, Rosetta, Xcode Command Line Tools. |
| Game | App location and executable presence. |
| Fix status | AGL stub, Qt version, QtGui references, signing state. |
| Runtime | FMOD, Steam API, and libcurl. |
| Public endpoints | Team17, Steam, and GOG Worms W.M.D pages for optional reachability checks. |

Use `--quick` to skip public endpoint checks, or `--verbose` for detailed
output. These checks are diagnostic only; they are not required to apply the fix
and do not prove multiplayer service health.

## Troubleshooting Fast Paths

| Symptom | First action |
| --- | --- |
| macOS blocks the launcher | Right-click `Worms W.M.D Fix.command`, choose **Open**, then choose **Open** again. |
| Steam updated or verified the game | Run option `1` again. |
| You want to undo the fix | Run option `4`. |
| The fix failed | Run option `5` and attach the sanitized support bundle to a GitHub issue. |
| You want a deeper check | Run `./tools/preflight_check.sh`. |

## Documentation Map

| Need | Link |
| --- | --- |
| Full docs index | [docs/README.md](docs/README.md) |
| Manual install and restore | [docs/INSTALL.md](docs/INSTALL.md) |
| Common failures | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |
| Frequently asked questions | [docs/FAQ.md](docs/FAQ.md) |
| Security model | [SECURITY.md](SECURITY.md) |
| Trust and verification | [docs/TRUST.md](docs/TRUST.md) |
| Support flow | [SUPPORT.md](SUPPORT.md) |
| Helper tools | [docs/TOOLS.md](docs/TOOLS.md) |
| Technical details | [docs/TECHNICAL.md](docs/TECHNICAL.md) |
| Version history | [CHANGELOG.md](CHANGELOG.md) |
| Vendor-facing report | [TEAM17_DEVELOPER_REPORT.md](TEAM17_DEVELOPER_REPORT.md) |
| Community post template | [STEAM_POST.md](STEAM_POST.md) |

## Support

| Channel | Use |
| --- | --- |
| GitHub issues | https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues |
| Support bundle | Launcher option `5`; attach the generated `.tar.gz` to the issue. |

Do not upload raw `.log` or `.trace` files, save archives, game binaries, or
private config files. Use the support bundle unless a maintainer asks for
something more specific.

## Credits And Links

- Steam community members who reported the macOS issue and tested fixes.
- Qt Project for Qt 5.15.
- [Worms W.M.D on Steam](https://store.steampowered.com/app/327030/Worms_WMD/)

Steam discussion threads about this issue:

- [Can't open on macOS Tahoe M2](https://steamcommunity.com/app/327030/discussions/2/594035123771846058/)
- [Black screen on Mac Pro 2019 16](https://steamcommunity.com/app/327030/discussions/2/686363730790074305/)
- [Black screen on macOS](https://steamcommunity.com/app/327030/discussions/2/686365524184117509/)
