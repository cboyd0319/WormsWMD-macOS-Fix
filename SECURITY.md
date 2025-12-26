# Security Policy

This document explains the security measures, transparency, and safety of the Worms W.M.D macOS Fix.

## Overview

This fix is a community-developed solution to make Worms W.M.D playable on macOS 26 (Tahoe) and later. We understand that running scripts from the internet requires trust, so we've designed this solution to be:

- **Transparent**: All source code is open and auditable
- **Minimal**: Only modifies what's necessary to fix the game
- **Reversible**: Creates backups before any changes
- **Safe**: Minimal network access, no sudo required, no system modifications

---

## What This Fix Does

### Files Modified (Inside Game Bundle Only)

| Location | Action | Purpose |
|----------|--------|---------|
| `Contents/Frameworks/` | Replace Qt frameworks | Upgrade Qt 5.3.2 → 5.15.x |
| `Contents/Frameworks/AGL.framework/` | Add stub library | Satisfy removed AGL dependency |
| `Contents/Frameworks/*.dylib` | Add dependency libraries | Bundle required libraries |
| `Contents/PlugIns/` | Replace Qt plugins | Update platform/image plugins |
| `Contents/Info.plist` | Update metadata | Add bundle ID, HiDPI flags |
| `Contents/Resources/DataOSX/*.txt` | Update URLs | HTTP→HTTPS, disable internal URLs |

### Files Created (Outside Game Bundle)

| Location | Purpose |
|----------|---------|
| `~/Documents/WormsWMD-Backup-*/` | Timestamped backup of original files |
| `~/Documents/WormsWMD-SaveBackups/` | Save game backups (if using backup tool) |
| `~/Library/Logs/WormsWMD-Fix/` | Fix log files for debugging |
| `~/Library/Logs/WormsWMD/` | Game launcher logs and crash reports |
| `~/.cache/wormswmd-fix/` | Downloaded Qt frameworks cache |
| `~/Library/LaunchAgents/com.wormswmd.fix.watcher.plist` | Optional update watcher (only if installed) |
| `/tmp/agl_stub_build/` | Temporary build directory (deleted after use) |

---

## What This Fix Does NOT Do

- **No system modifications**: Does not touch `/System`, `/Library`, or any system files
- **No elevated privileges**: No `sudo` required (Apple installers may prompt for admin approval)
- **No data collection**: Does not collect, transmit, or store any personal data
- **No executables outside game**: Only modifies files inside the game bundle
- **No persistent changes**: Can be fully reversed with `--restore`

### Network Access (Minimal)

The fix makes limited network connections:
- **Qt framework download**: One-time download of pre-built Qt frameworks from the repo dist/ folder (~50MB)
- **Update checker** (optional): Checks GitHub API for new versions
- **One-liner installer**: Downloads from GitHub
- **Rosetta 2 / Xcode CLT** (if needed): Downloads from Apple software update servers

Connections are limited to GitHub and Apple. No third-party servers, no telemetry, no user data transmitted.

### Optional Background Process

The `tools/watch_for_updates.sh --install` command can optionally install a LaunchAgent that monitors for Steam updates. This is:
- **Opt-in only**: Not installed by default
- **Easily removable**: `./tools/watch_for_updates.sh --uninstall`
- **Transparent**: Only checks if the fix is still applied
- **Local only**: No network access

---

## Security Verification

### 1. Review the Code Yourself

All scripts are open source and written in readable Bash. Key files:

```bash
# Main fix script
less fix_worms_wmd.sh

# Individual step scripts
ls -la scripts/

# Additional tools
ls -la tools/

# AGL stub source (C code)
less src/agl_stub.c
```

### 2. Run ShellCheck

Verify scripts follow best practices:

```bash
shellcheck fix_worms_wmd.sh install.sh scripts/*.sh tools/*.sh
```

### 3. Preview Before Applying

Use dry-run mode to see exactly what will happen:

```bash
./fix_worms_wmd.sh --dry-run
```

### 4. Verify After Applying

Check that only expected changes were made:

```bash
./fix_worms_wmd.sh --verify
```

### 5. Inspect the AGL Stub

The AGL stub is compiled from source on your machine. You can verify:

```bash
# View the source
cat src/agl_stub.c

# Check the compiled binary
file "$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app/Contents/Frameworks/AGL.framework/Versions/A/AGL"
# Expected: Mach-O 64-bit dynamically linked shared library x86_64

# Verify it's a small stub (should be ~50KB or less)
ls -la "$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app/Contents/Frameworks/AGL.framework/Versions/A/AGL"
```

---

## Backup and Recovery

### Automatic Backups

Before making any changes, the fix creates a complete backup:

```
~/Documents/WormsWMD-Backup-YYYYMMDD-HHMMSS/
├── Frameworks/      # Original Qt frameworks and libraries
├── PlugIns/         # Original Qt plugins
├── Info.plist       # Original Info.plist
└── DataOSX/         # Original config files
```

### Full Restore

To completely undo the fix:

```bash
./fix_worms_wmd.sh --restore
```

### Manual Restore

If you prefer manual control:

```bash
BACKUP_DIR=~/Documents/WormsWMD-Backup-YYYYMMDD-HHMMSS
GAME_APP="$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"

rm -rf "$GAME_APP/Contents/Frameworks"
rm -rf "$GAME_APP/Contents/PlugIns"
cp -R "$BACKUP_DIR/Frameworks" "$GAME_APP/Contents/"
cp -R "$BACKUP_DIR/PlugIns" "$GAME_APP/Contents/"
cp "$BACKUP_DIR/Info.plist" "$GAME_APP/Contents/Info.plist"
cp "$BACKUP_DIR/DataOSX/"* "$GAME_APP/Contents/Resources/DataOSX/"
```

### Steam Verification

You can also restore via Steam:

1. Right-click Worms W.M.D in Steam
2. Properties → Local Files → Verify integrity of game files
3. Steam will re-download original files

---

## Third-Party Components

This fix uses the following external components:

| Component | Source | Purpose |
|-----------|--------|---------|
| Qt 5.15 | Pre-built package from repo dist/, or Homebrew (`qt@5`) | Replace outdated Qt 5.3.2 |
| GLib, PCRE2, etc. | Bundled with Qt package or from Homebrew | Required by Qt 5.15 |

All components are obtained from:
- **GitHub repository dist/**: Pre-built Qt frameworks hosted in this repository
- **Homebrew** (fallback): Official macOS package manager (https://brew.sh)

The AGL stub is compiled from source on your machine using Apple's Clang compiler.

### Pre-built Qt Package Security

The pre-built Qt package (`qt-frameworks-x86_64-*.tar.gz`) is:
- Built from official Homebrew Qt 5.15
- Packaged using `tools/package_qt_frameworks.sh` (you can inspect this script)
- Hosted in repo dist/ with SHA256 checksums
- Downloaded over HTTPS only
- Verified with checksum before extraction

---

## Code Quality Measures

### Static Analysis

ShellCheck can report warnings (for example, sourced helper files or unused color vars). Run it to review the current set:

```bash
$ shellcheck --severity=warning *.sh scripts/*.sh tools/*.sh
```

### Syntax Validation

All scripts are validated for correct Bash syntax:

```bash
$ bash -n fix_worms_wmd.sh && echo "OK"
OK
```

### Error Handling

- Scripts use `set -e` to stop on errors
- Automatic rollback if fix fails mid-way
- Clear error messages with suggested fixes
- All operations are logged for debugging

---

## Permissions Required

| Permission | Why Needed | How Used |
|------------|------------|----------|
| Read game directory | To backup and verify | Reads existing files |
| Write game directory | To apply fix | Writes new frameworks/plugins |
| Read `/usr/local/` | To copy Qt libraries | Reads Homebrew installations |
| Write `~/Documents/` | To create backups | Creates backup directories |
| Write `~/Library/Logs/` | To write logs | Creates log files |
| Execute compiler | To build AGL stub | Runs `clang` (Xcode CLT) |

**Not Required:**
- No `sudo` required for the fix itself
- No System Preferences changes
- No Keychain access
- No microphone, camera, or location access

---

## Reporting Security Issues

If you find a security vulnerability in this project:

1. **Do NOT open a public issue** for security vulnerabilities
2. Email the maintainer directly (see GitHub profile)
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will respond within 48 hours and work to address the issue promptly.

For non-security bugs, please use [GitHub Issues](https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues).

---

## Frequently Asked Questions

### Is this safe to run?

Yes. The fix only modifies files inside the game bundle and creates backups. It cannot harm your system, access your data, or persist outside the game directory.

### Why did it used to need Intel Homebrew?

The game is x86_64 only (runs via Rosetta 2 on Apple Silicon). It needs x86_64 Qt libraries. Previously, these were installed via Intel Homebrew (`/usr/local/bin/brew`).

**As of v1.4.0, Homebrew is no longer required!** The fix now downloads pre-built Qt frameworks automatically. Homebrew is only used as a fallback if the download fails.

### Can I verify the code myself?

Absolutely. All code is open source. We encourage you to:
1. Read the scripts before running
2. Use `--dry-run` to preview changes
3. Run ShellCheck for static analysis
4. Verify the AGL stub source code

### What if something goes wrong?

1. Use `./fix_worms_wmd.sh --restore` to undo changes
2. Or verify game files in Steam to restore originals
3. Check logs in `~/Library/Logs/WormsWMD-Fix/`
4. Open an issue on GitHub for help

### Is the one-liner installer safe?

The one-liner (`curl ... | bash`) downloads `install.sh` from GitHub and runs it. This is a common pattern but requires trusting the repository. If you're uncomfortable with this:

1. Clone the repo manually: `git clone https://github.com/cboyd0319/WormsWMD-macOS-Fix.git`
2. Review the code: `less fix_worms_wmd.sh`
3. Run manually: `./fix_worms_wmd.sh --dry-run` then `./fix_worms_wmd.sh`

---

## Checksums

You can verify file integrity by comparing checksums:

```bash
# Generate checksums for all scripts
shasum -a 256 fix_worms_wmd.sh install.sh scripts/*.sh tools/*.sh src/*.c

# Compare with known good values (published alongside dist/ tarballs)
```

Checksums are committed alongside the tarball in `dist/`.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

The fix modifies Worms W.M.D, which is property of Team17 Digital Ltd. This fix is not affiliated with or endorsed by Team17.
