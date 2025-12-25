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

This automatically installs all required dependencies (glib, pcre2, libpng, freetype, etc.)

## Quick Start

### One-Liner Install (Easiest)

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash
```

This will automatically download and run the fix. Add `--dry-run` to preview changes first:

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash -s -- --dry-run
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
```

The script will automatically:
- Verify all prerequisites are met
- Create a backup of original game files
- Apply all necessary fixes
- Verify the installation was successful

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

The fix script automatically creates a timestamped backup before making changes.

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

### Rosetta 2 issues

Ensure Rosetta is installed and working:
```bash
# Check if Rosetta is running
pgrep -q oahd && echo "Rosetta is running" || echo "Rosetta is NOT running"

# Reinstall if needed
softwareupdate --install-rosetta --agree-to-license
```

## Technical Details

### What Gets Modified

| Component | Original | Fixed |
|-----------|----------|-------|
| QtCore.framework | 5.3.2 | 5.15.x |
| QtGui.framework | 5.3.2 | 5.15.x |
| QtWidgets.framework | 5.3.2 | 5.15.x |
| QtOpenGL.framework | 5.3.2 | 5.15.x |
| QtPrintSupport.framework | 5.3.2 | 5.15.x |
| AGL.framework | System (removed) | Stub library |
| QtDBus.framework | Not present | Added (required by plugins) |

### Libraries Added

The fix bundles these libraries from Homebrew:

- **Regex:** libpcre2-8.0.dylib, libpcre2-16.0.dylib
- **Compression:** libzstd.1.dylib, liblzma.5.dylib
- **GLib:** libglib-2.0.0.dylib, libgthread-2.0.0.dylib, libintl.8.dylib
- **Graphics:** libpng16.16.dylib, libfreetype.6.dylib, libmd4c.0.dylib
- **Images:** libjpeg.8.dylib, libtiff.6.dylib
- **WebP:** libwebp.7.dylib, libwebpdemux.2.dylib, libwebpmux.3.dylib, libsharpyuv.0.dylib

### Plugins Updated

- `platforms/libqcocoa.dylib` - Cocoa platform integration
- `imageformats/*.dylib` - Image format support

### How the AGL Stub Works

The AGL stub (`src/agl_stub.c`) provides empty implementations of all 47 AGL functions. Since Qt 5.15 doesn't actually use AGL (it uses Core OpenGL directly), the stub just needs to exist and return appropriate error values to satisfy the dynamic linker.

### Why Qt 5.15?

- Qt 5.15 is the last version of Qt 5 with long-term support
- It uses modern OpenGL APIs compatible with macOS's OpenGL implementation
- It maintains binary compatibility with Qt 5.3 APIs the game uses
- Available via Homebrew for easy installation

## Contributing

Contributions are welcome! If you find issues or have improvements:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on macOS 26+
5. Submit a pull request

Please report issues on the [GitHub Issues](https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues) page.

## Version History

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
