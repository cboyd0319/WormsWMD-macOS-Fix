# Security

This document describes the security model for the Worms W.M.D macOS fix.

## Overview

The fix is designed to be transparent, minimal, and reversible.

Key points:
- Open source and auditable
- Modifies only the game bundle
- Creates backups before changes
- Does not require `sudo`

## What the fix changes

### Files modified inside the game bundle

| Location | Action | Purpose |
|----------|--------|---------|
| `Contents/Frameworks/` | Replace Qt frameworks | Upgrade Qt 5.3.2 to 5.15.x |
| `Contents/Frameworks/AGL.framework/` | Add stub library | Satisfy removed AGL dependency |
| `Contents/Frameworks/*.dylib` | Add dependency libraries | Bundle required libraries |
| `Contents/PlugIns/` | Replace Qt plugins | Update platform and image plugins |
| `Contents/Info.plist` | Update metadata | Add bundle ID and HiDPI flags |
| `Contents/Resources/DataOSX/*.txt` | Update URLs | Use HTTPS and disable internal URLs |

### Files created outside the game bundle

| Location | Purpose |
|----------|---------|
| `~/Documents/WormsWMD-Backup-*/` | Backups of original files |
| `~/Documents/WormsWMD-SaveBackups/` | Save game backups (if you use the tool) |
| `~/Library/Logs/WormsWMD-Fix/` | Fix logs |
| `~/Library/Logs/WormsWMD/` | Launcher logs and crash reports |
| `~/.cache/wormswmd-fix/` | Cached Qt frameworks |
| `~/Library/LaunchAgents/com.wormswmd.fix.watcher.plist` | Optional update watcher |
| `/tmp/agl_stub_build/` | Temporary build directory |

## What the fix does not do

- It does not modify system files.
- It does not collect or transmit personal data.
- It does not require `sudo`.
- It does not install background services unless you opt in.

## Network access

The fix uses limited network access:
- Qt framework download from the repo `dist/` directory
- Optional update checks against GitHub
- Installer download from GitHub
- Apple software update servers for Rosetta 2 or Xcode CLT, if needed

No third-party servers or telemetry are used.

## Optional background process

The update watcher (`tools/watch_for_updates.sh --install`) can install a LaunchAgent.
It runs locally and does not use network access.

## Verify the fix

### Review the code

```bash
less fix_worms_wmd.sh
ls -la scripts/
ls -la tools/
less src/agl_stub.c
```

### Run ShellCheck

```bash
shellcheck fix_worms_wmd.sh install.sh scripts/*.sh tools/*.sh
```

### Preview changes

```bash
./fix_worms_wmd.sh --dry-run
```

### Verify after applying

```bash
./fix_worms_wmd.sh --verify
```

### Inspect the AGL stub

```bash
cat src/agl_stub.c
file "$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app/Contents/Frameworks/AGL.framework/Versions/A/AGL"
ls -la "$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app/Contents/Frameworks/AGL.framework/Versions/A/AGL"
```

## Backups and recovery

The fix creates a backup before making changes:

Backup contents:
- Frameworks/
- PlugIns/
- Info.plist
- DataOSX/

Restore automatically:

```bash
./fix_worms_wmd.sh --restore
```

## Third-party components

| Component | Source | Purpose |
|-----------|--------|---------|
| Qt 5.15 | Pre-built package in repo `dist/`, or Homebrew (`qt@5`) | Replace Qt 5.3.2 |
| GLib, PCRE2, and others | Bundled with Qt package or Homebrew | Qt 5.15 dependencies |

Pre-built Qt packages:
- Built from Homebrew Qt 5.15
- Packaged with `tools/package_qt_frameworks.sh`
- Stored in repo `dist/` with SHA256 checksums
- Downloaded over HTTPS

Checksums are committed alongside the tarball in `dist/`.

## Permissions

The fix needs these permissions:

| Permission | Why needed |
|------------|------------|
| Read game directory | Back up and verify |
| Write game directory | Apply the fix |
| Read `/usr/local/` | Copy Qt libraries (Homebrew fallback) |
| Write `~/Documents/` | Create backups |
| Write `~/Library/Logs/` | Write logs |
| Run compiler | Build the AGL stub |

## Report a security issue

Do not open a public issue for security problems. Email the maintainer instead.
Include a description, steps to reproduce, impact, and a suggested fix.
