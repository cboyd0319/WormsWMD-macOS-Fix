# Worms W.M.D - macOS Tahoe (26.x) Fix

A comprehensive fix for Worms W.M.D black screen issues on macOS 26 (Tahoe) and later.

## The Problem

Starting with macOS 26 (Tahoe), Apple removed the AGL (Apple OpenGL) framework that Worms W.M.D depends on. The game also uses Qt 5.3.2 from 2014, which relies on deprecated `NSOpenGLContext` APIs. This causes the game to display only a black screen on launch.

**Affected Systems:**
- macOS 26.x (Tahoe) and later
- Both Apple Silicon (M1/M2/M3/M4) and Intel Macs
- Game runs via Rosetta 2 on Apple Silicon

## The Solution

This fix:
1. Creates an AGL stub library that satisfies the game's AGL dependency
2. Replaces the outdated Qt 5.3.2 frameworks with Qt 5.15 (which has better OpenGL compatibility)
3. Bundles all required dependencies so the game is fully self-contained
4. Fixes all library path references to use `@executable_path`

## Prerequisites

### 1. Rosetta 2 (Apple Silicon only)
If you're on Apple Silicon, ensure Rosetta 2 is installed:
```bash
softwareupdate --install-rosetta
```

### 2. Intel Homebrew
This fix requires Intel (x86_64) Homebrew to obtain x86_64 Qt libraries.

**Check if Intel Homebrew is installed:**
```bash
ls /usr/local/bin/brew
```

**If not installed, install it:**
```bash
arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 3. Qt 5.15 (x86_64)
Install Qt 5 using Intel Homebrew:
```bash
arch -x86_64 /usr/local/bin/brew install qt@5
```

This will also install all required dependencies (glib, pcre2, libpng, freetype, etc.)

## Installation

### Quick Install (Recommended)
```bash
cd ~/Documents/WormsWMD-macOS-Fix
chmod +x fix_worms_wmd.sh
./fix_worms_wmd.sh
```

The script will:
- Verify all prerequisites
- Create a backup of original files
- Apply all fixes
- Verify the installation

### Manual Install
If you prefer to run steps manually, see the `scripts/` directory:
1. `01_build_agl_stub.sh` - Builds the AGL stub library
2. `02_replace_qt_frameworks.sh` - Replaces Qt frameworks
3. `03_copy_dependencies.sh` - Copies all required dependencies
4. `04_fix_library_paths.sh` - Fixes all library path references
5. `05_verify_installation.sh` - Verifies the fix

## Restoring Original Files

A backup is created at:
```
~/Documents/WormsWMD-Backup-YYYYMMDD-HHMMSS/
```

To restore:
```bash
./fix_worms_wmd.sh --restore
```

Or manually:
```bash
BACKUP_DIR=~/Documents/WormsWMD-Backup-XXXXXXXX-XXXXXX
GAME_APP="/Users/$USER/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
rm -rf "$GAME_APP/Contents/Frameworks"
rm -rf "$GAME_APP/Contents/PlugIns"
cp -R "$BACKUP_DIR/Frameworks" "$GAME_APP/Contents/"
cp -R "$BACKUP_DIR/PlugIns" "$GAME_APP/Contents/"
```

## Troubleshooting

### "Qt libraries not found"
Ensure Intel Homebrew Qt is installed:
```bash
arch -x86_64 /usr/local/bin/brew install qt@5
```

### "Permission denied" errors
You may need to fix Homebrew directory permissions:
```bash
sudo mkdir -p /usr/local/var/homebrew/locks /usr/local/etc /usr/local/Frameworks
sudo chown -R $(whoami) /usr/local/var /usr/local/etc /usr/local/Frameworks
```

### Game still shows black screen
1. Verify Steam game files: Right-click game > Properties > Local Files > Verify integrity
2. Re-run the fix script
3. Check Console.app for crash logs

### "Library not loaded" errors on launch
Run the verification script:
```bash
./scripts/05_verify_installation.sh
```

## Technical Details

### What Gets Modified

**Frameworks replaced:**
- QtCore.framework (5.3.2 → 5.15.x)
- QtGui.framework (5.3.2 → 5.15.x)
- QtWidgets.framework (5.3.2 → 5.15.x)
- QtOpenGL.framework (5.3.2 → 5.15.x)
- QtPrintSupport.framework (5.3.2 → 5.15.x)

**Frameworks added:**
- AGL.framework (stub library)
- QtDBus.framework (required by platform plugin)

**Libraries added:**
- libpcre2-8.0.dylib, libpcre2-16.0.dylib (regex)
- libzstd.1.dylib (compression)
- libglib-2.0.0.dylib, libgthread-2.0.0.dylib, libintl.8.dylib (glib)
- libpng16.16.dylib, libfreetype.6.dylib (graphics)
- libmd4c.0.dylib (markdown)
- libjpeg.8.dylib, libtiff.6.dylib, liblzma.5.dylib (images)
- libwebp.7.dylib, libwebpdemux.2.dylib, libwebpmux.3.dylib, libsharpyuv.0.dylib (webp)

**Plugins updated:**
- platforms/libqcocoa.dylib
- imageformats/*.dylib

### AGL Stub Library

The AGL stub (`src/agl_stub.c`) provides empty implementations of all 47 AGL functions. Since modern Qt doesn't actually use AGL (it uses Core OpenGL directly), the stub just needs to exist and return appropriate error values.

## Version History

- **1.0.0** (2025-12-25): Initial release for macOS 26 (Tahoe)

## Credits

- Fix developed with Claude Code
- Thanks to the Steam community for reporting the issue
- Qt Project for Qt 5.15

## License

This fix is provided as-is for personal use. Worms W.M.D is property of Team17.

## Links

- [Steam Discussion Thread](https://steamcommunity.com/app/327030/discussions/2/686363730790074305/)
- [Worms W.M.D on Steam](https://store.steampowered.com/app/327030/Worms_WMD/)
