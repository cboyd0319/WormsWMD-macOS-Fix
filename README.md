# Worms W.M.D - macOS Tahoe (26.x) Fix

[![CI](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml/badge.svg)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-26.0%2B-blue.svg)](https://www.apple.com/macos/)
[![GitHub release](https://img.shields.io/github/v/release/cboyd0319/WormsWMD-macOS-Fix?include_prereleases)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases)

A comprehensive fix for Worms W.M.D black screen issues on macOS 26 (Tahoe) and later.

## Table of Contents

- [The Problem](#the-problem)
- [The Solution](#the-solution)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Detailed Installation](#detailed-installation)
- [Restoring Original Files](#restoring-original-files)
- [Troubleshooting](#troubleshooting)
- [Technical Details](#technical-details)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

## The Problem

Starting with macOS 26 (Tahoe), Apple removed the AGL (Apple OpenGL) framework that Worms W.M.D depends on. The game also ships with Qt 5.3.2 from 2014, which relies on deprecated `NSOpenGLContext` APIs. This causes the game to display only a black screen on launch.

**Affected Systems:**
- macOS 26.x (Tahoe) and later
- Both Apple Silicon (M1/M2/M3/M4) and Intel Macs
- The game runs via Rosetta 2 on Apple Silicon

**Symptoms:**
- Game launches but shows only a black screen
- No crash, just an unresponsive black window
- Audio may or may not play

## The Solution

This fix:
1. **Creates an AGL stub library** that satisfies the game's AGL dependency
2. **Replaces outdated Qt 5.3.2 frameworks** with Qt 5.15 (which has better OpenGL compatibility)
3. **Bundles all required dependencies** so the game is fully self-contained
4. **Fixes all library path references** to use `@executable_path` for portability

## Requirements

Before running the fix, you need:

### 1. Rosetta 2 (Apple Silicon Macs only)

```bash
softwareupdate --install-rosetta
```

### 2. Intel Homebrew

The fix requires Intel (x86_64) Homebrew to obtain x86_64 Qt libraries. This is separate from ARM Homebrew (`/opt/homebrew`).

**Check if installed:**
```bash
/usr/local/bin/brew --version
```

**If not installed:**
```bash
arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 3. Qt 5.15 (x86_64)

Install Qt 5 using Intel Homebrew:
```bash
arch -x86_64 /usr/local/bin/brew install qt@5
```

This installs required dependencies (glib, pcre2, libpng, freetype, etc.). The fix
scans the Qt frameworks/plugins and bundles any Homebrew dylibs they reference.

## Quick Start

### One-Liner Install (Easiest)

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash
```

This will automatically download and run the fix. Add `--dry-run` to preview changes first:

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash -s -- --dry-run
```

You can customize where the installer clones the repo:

```bash
INSTALL_DIR="$HOME/.wormswmd-fix" curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash
```

### Manual Install

```bash
# Clone the repository
git clone https://github.com/cboyd0319/WormsWMD-macOS-Fix.git
cd WormsWMD-macOS-Fix

# Preview changes (optional)
./fix_worms_wmd.sh --dry-run

# Run the fix
./fix_worms_wmd.sh

# Optional: Verify only
./fix_worms_wmd.sh --verify
```

The script will automatically:
- Verify all prerequisites are met
- Create a backup of original game files
- Apply all necessary fixes
- Verify the installation was successful
- Apply optional Info.plist and config URL enhancements (if scripts are present)

## Detailed Installation

### Option 1: Automatic (Recommended)

```bash
# Clone and run
git clone https://github.com/cboyd0319/WormsWMD-macOS-Fix.git
cd WormsWMD-macOS-Fix
./fix_worms_wmd.sh
```

### Option 2: Manual Installation

If you prefer to run each step manually:

```bash
cd WormsWMD-macOS-Fix

# Step 1: Build the AGL stub library
./scripts/01_build_agl_stub.sh

# Step 2: Replace Qt frameworks
./scripts/02_replace_qt_frameworks.sh

# Step 3: Copy required dependencies
./scripts/03_copy_dependencies.sh

# Step 4: Fix all library path references
./scripts/04_fix_library_paths.sh

# Step 5: Verify the installation
./scripts/05_verify_installation.sh

# Step 6 (optional): Fix Info.plist metadata
./scripts/06_fix_info_plist.sh

# Step 7 (optional): Secure config URLs
./scripts/07_fix_config_urls.sh
```

### Custom Game Location

If your game is installed in a non-standard location:

```bash
GAME_APP="/path/to/Worms W.M.D.app" ./fix_worms_wmd.sh
```

### Verify Only

To check the current state without making changes:

```bash
./fix_worms_wmd.sh --verify
```

## Restoring Original Files

The fix script automatically creates a timestamped backup before making changes
(Frameworks, PlugIns, Info.plist, and key DataOSX config files).

### Automatic Restore

```bash
./fix_worms_wmd.sh --restore
```

This shows available backups and restores from the most recent one.

### Manual Restore

```bash
# Find your backup
ls ~/Documents/WormsWMD-Backup-*

# Restore (replace YYYYMMDD-HHMMSS with your backup timestamp)
BACKUP_DIR=~/Documents/WormsWMD-Backup-YYYYMMDD-HHMMSS
GAME_APP="$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"

rm -rf "$GAME_APP/Contents/Frameworks"
rm -rf "$GAME_APP/Contents/PlugIns"
cp -R "$BACKUP_DIR/Frameworks" "$GAME_APP/Contents/"
cp -R "$BACKUP_DIR/PlugIns" "$GAME_APP/Contents/"

# Restore Info.plist (if backed up)
if [[ -f "$BACKUP_DIR/Info.plist" ]]; then
  cp "$BACKUP_DIR/Info.plist" "$GAME_APP/Contents/Info.plist"
fi

# Restore config files (if backed up)
if [[ -d "$BACKUP_DIR/DataOSX" ]]; then
  cp "$BACKUP_DIR/DataOSX/"* "$GAME_APP/Contents/Resources/DataOSX/" 2>/dev/null || true
fi
```

## Troubleshooting

### "Intel Homebrew not found"

Install Intel Homebrew:
```bash
arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### "Qt 5 not found"

Install Qt 5 via Intel Homebrew:
```bash
arch -x86_64 /usr/local/bin/brew install qt@5
```

### "Permission denied" errors during Homebrew install

Fix directory permissions:
```bash
sudo mkdir -p /usr/local/var/homebrew/locks /usr/local/etc /usr/local/Frameworks
sudo chown -R $(whoami) /usr/local/var /usr/local/etc /usr/local/Frameworks
```

### Game still shows black screen after fix

1. **Verify game files in Steam:**
   - Right-click Worms W.M.D → Properties → Local Files → Verify integrity
   - Re-run the fix script after verification

2. **Check the fix was applied:**
   ```bash
   ./fix_worms_wmd.sh --verify
   ```

3. **Check for crash logs:**
   - Open Console.app
   - Look for entries related to "Worms" in Crash Reports

4. **Try a clean install:**
   - Restore original files: `./fix_worms_wmd.sh --restore`
   - Verify game files in Steam
   - Re-run the fix

### "Library not loaded" errors on launch

Run the verification script to identify missing dependencies:
```bash
./scripts/05_verify_installation.sh
```

### Logging and debugging

The fix now writes a log file for each run:

- Default: `~/Library/Logs/WormsWMD-Fix/`
- Override: `./fix_worms_wmd.sh --log-file /path/to/log.txt`

For deeper diagnostics:

```bash
# Full shell tracing to a .trace log
./fix_worms_wmd.sh --debug

# Show full verification details
./fix_worms_wmd.sh --verify --verbose
```

### Diagnostic game launcher

For advanced troubleshooting, use the diagnostic launcher:

```bash
# Launch with logging
./tools/launch_worms.sh --log

# Safe mode (for graphics issues)
./tools/launch_worms.sh --safe-mode --log

# Full debug mode
./tools/launch_worms.sh --qt-debug --opengl-debug --log --verbose
```

Logs are saved to `~/Library/Logs/WormsWMD/`.

### Rosetta 2 issues

Ensure Rosetta is installed and working:
```bash
# Check if Rosetta is available
/usr/bin/arch -x86_64 /usr/bin/true && echo "Rosetta is available" || echo "Rosetta is NOT available"

# Reinstall if needed
softwareupdate --install-rosetta --agree-to-license
```

If you still see issues, attach the log file when reporting.

## Technical Details

### What Gets Modified

Qt frameworks already bundled with the game are replaced (commonly QtCore, QtGui,
QtWidgets, QtOpenGL, QtPrintSupport).

| Component | Original | Fixed |
|-----------|----------|-------|
| Qt*.framework (bundled) | 5.3.2 | 5.15.x |
| AGL.framework | System (removed) | Stub library |
| QtDBus.framework | Not present (if missing) | Added (required by plugins) |
| QtSvg.framework | Not present (if missing) | Added (required by SVG plugin) |
| Info.plist | Missing identifiers / HiDPI flags | Adds CFBundleIdentifier, HiDPI flags, graphics switching, updates minimum version |
| DataOSX configs | HTTP/internal URLs | HTTPS + internal URLs commented out (with .backup) |

### Libraries Added

The fix bundles any Homebrew dylibs referenced by the Qt frameworks/plugins
(`otool -L` scan of `/usr/local` and `@rpath` entries). Common libraries include:

- **Regex:** libpcre2-8.0.dylib, libpcre2-16.0.dylib
- **Compression:** libzstd.1.dylib, liblzma.5.dylib
- **GLib:** libglib-2.0.0.dylib, libgthread-2.0.0.dylib, libintl.8.dylib
- **Graphics:** libpng16.16.dylib, libfreetype.6.dylib, libmd4c.0.dylib
- **Images:** libjpeg.8.dylib, libtiff.6.dylib
- **WebP:** libwebp.7.dylib, libwebpdemux.2.dylib, libwebpmux.3.dylib, libsharpyuv.0.dylib

The exact list can vary depending on your Homebrew versions and plugin set.

### Plugins Updated

- `platforms/libqcocoa.dylib` - Cocoa platform integration
- `imageformats/*.dylib` - Image format support (including `libqsvg.dylib`)

### How the AGL Stub Works

The AGL stub (`src/agl_stub.c`) provides empty implementations of all 41 AGL functions. Since Qt 5.15 doesn't actually use AGL (it uses Core OpenGL directly), the stub just needs to exist and return appropriate error values to satisfy the dynamic linker.

### Why Qt 5.15?

- Qt 5.15 is the last version of Qt 5 with long-term support
- It uses modern OpenGL APIs compatible with macOS's OpenGL implementation
- It maintains binary compatibility with Qt 5.3 APIs the game uses
- Available via Homebrew for easy installation

## Security

This fix is designed to be transparent, safe, and reversible. Key security features:

- **Open source**: All code is auditable
- **No network access**: Scripts never connect to the internet
- **No elevated privileges**: Never requires `sudo`
- **Reversible**: Full backup created before any changes
- **Minimal scope**: Only modifies files inside the game bundle

For detailed security information, see [SECURITY.md](SECURITY.md).

To verify before running:
```bash
# Preview all changes without applying
./fix_worms_wmd.sh --dry-run

# Run ShellCheck on all scripts
shellcheck fix_worms_wmd.sh scripts/*.sh
```

## Contributing

Contributions are welcome! If you find issues or have improvements:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on macOS 26+
5. Submit a pull request

Please report issues on the [GitHub Issues](https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues) page.

## Version History

- **1.2.5** (2025-12-25): Dry-run output now reflects Info.plist/config enhancements
- **1.2.4** (2025-12-25): Verification output clarity for Info.plist/config checks
- **1.2.3** (2025-12-25): Verification now checks Info.plist/config URLs; logging coverage for new scripts
- **1.2.2** (2025-12-25): Option parsing fixes, backup/restore expanded to Info.plist + config files, docs accuracy pass
- **1.2.1** (2025-12-25): Team17 report expansion and documentation clarity updates
- **1.2.0** (2025-12-25): Dynamic framework scanning, logging/debugging, QtSvg bundling, Info.plist/config enhancements, and Team17 report
- **1.1.0** (2025-12-25): Added dry-run mode, force mode, already-applied detection, automatic rollback, progress spinners, one-liner installer, and CI/CD pipeline
- **1.0.0** (2025-12-25): Initial release for macOS 26 (Tahoe)

## Credits

- Thanks to the [Steam community](https://steamcommunity.com/app/327030/discussions/2/686363730790074305/) for reporting the issue
- [Qt Project](https://www.qt.io/) for Qt 5.15
- Fix developed with assistance from Claude

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Worms W.M.D is property of Team17 Digital Ltd.

## Links

- [Steam Discussion Thread](https://steamcommunity.com/app/327030/discussions/2/686363730790074305/)
- [Worms W.M.D on Steam](https://store.steampowered.com/app/327030/Worms_WMD/)
