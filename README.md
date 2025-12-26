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
- [Frequently Asked Questions](#frequently-asked-questions)
- [Known Limitations](#known-limitations)
- [Technical Details](#technical-details)
- [Security](#security)
- [Contributing](#contributing)
- [Additional Tools](#additional-tools)
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

- macOS 26 (Tahoe) or later
- Worms W.M.D installed via Steam or GOG
- Internet connection (for downloading pre-built Qt frameworks, ~50MB one-time download)
- Approximately 200MB free disk space

**Good news:** Homebrew is no longer required! The fix automatically downloads pre-built Qt frameworks. Homebrew is only used as a fallback if the download fails.

### 1. Rosetta 2 (Apple Silicon Macs only)

```bash
softwareupdate --install-rosetta
```

### 2. Intel Homebrew (Optional - Fallback Only)

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

### Collecting diagnostics for bug reports

Use the diagnostics collector to gather system information:

```bash
# Print to terminal
./tools/collect_diagnostics.sh

# Save to file for GitHub issue
./tools/collect_diagnostics.sh --output ~/Desktop/worms-diagnostics.txt

# Copy to clipboard
./tools/collect_diagnostics.sh --copy

# Full diagnostics (includes library details)
./tools/collect_diagnostics.sh --full --output ~/Desktop/worms-full-diagnostics.txt
```

## Frequently Asked Questions

### General

**Q: Does this fix work on macOS 15 (Sequoia) or earlier?**

A: You probably don't need it. This fix is specifically for macOS 26 (Tahoe) where Apple removed the AGL framework. Earlier versions should run the game without modification.

**Q: Will this fix work for the GOG version?**

A: Yes. The fix modifies the app bundle, which is identical between Steam and GOG versions. Just set `GAME_APP` to point to your GOG installation.

**Q: Is this fix safe? Will it harm my computer?**

A: Yes, it's safe. The fix only modifies files inside the game's app bundle, creates a backup first, never requires admin privileges, and is fully open source. See [SECURITY.md](SECURITY.md) for details.

**Q: Can I undo this fix?**

A: Yes. Run `./fix_worms_wmd.sh --restore` to restore from backup, or verify game files in Steam to re-download the original.

### Technical

**Q: Why do I need Intel Homebrew on Apple Silicon?**

A: The game is x86_64-only and runs via Rosetta 2. The Qt frameworks must also be x86_64, which requires Intel Homebrew (`/usr/local/bin/brew`). ARM Homebrew (`/opt/homebrew`) provides arm64 libraries that won't work.

**Q: Why Qt 5.15 instead of Qt 6?**

A: Qt 5.15 maintains binary compatibility with the Qt 5.3 APIs the game uses. Qt 6 changed many APIs and would require source code modifications to the game itself.

**Q: What does the AGL stub actually do?**

A: Nothing, by design. The stub provides empty function implementations that return error codes. The game's binary has a dynamic link to AGL that must be satisfied for macOS to launch it, but the actual game code (via Qt 5.15) never calls these functions.

**Q: Will Apple Silicon native support ever be possible?**

A: Not without source code access. Team17 would need to rebuild the game as a universal binary (x86_64 + arm64). The community fix builds a universal AGL stub for future-proofing, but the main game binary will always require Rosetta 2.

### Performance

**Q: Is performance worse on Apple Silicon compared to Intel?**

A: There's approximately 20-30% overhead from Rosetta 2 translation, but Apple Silicon Macs are fast enough that the game still runs well. Most users report smooth 60 FPS gameplay.

**Q: The game runs slowly on first launch after the fix. Is this normal?**

A: Yes. Rosetta 2 translates x86_64 code on first run and caches it. Subsequent launches will be faster.

**Q: Are there any graphics settings I should change?**

A: The game should work with default settings. If you experience issues, try lowering resolution or disabling some visual effects. The diagnostic launcher has a `--safe-mode` option for troubleshooting.

### Troubleshooting

**Q: I get "app is damaged" or Gatekeeper warnings. What do I do?**

A: This is normal for unsigned apps. Right-click the app and choose "Open", then click "Open" in the dialog. The fix now applies ad-hoc code signing and clears quarantine flags to minimize these warnings.

**Q: Multiplayer/online features don't work. Is this related to the fix?**

A: The fix doesn't modify networking. If online features don't work, it's likely a server-side issue with Team17's infrastructure. Check the Steam community forums for current status.

**Q: My controller doesn't work. Can the fix help?**

A: The fix doesn't modify input handling. Controller support depends on the game's original implementation and macOS controller support. Try using a controller mapping tool like Joystick Doctor.

## Known Limitations

These limitations exist because we don't have access to the game's source code:

### Cannot Be Fixed (Requires Team17)

| Limitation | Impact | Why |
|------------|--------|-----|
| **FMOD uses deprecated runtime** | Audio may break in future macOS | FMOD libs link to removed libstdc++; Rosetta 2 provides shims for now |
| **Steam API uses deprecated runtime** | Networking may break in future macOS | Same as FMOD; needs Steamworks SDK update |
| **No native Apple Silicon** | ~20-30% performance overhead | Requires rebuilding game binary as universal |
| **OpenGL only (deprecated)** | May break if Apple removes OpenGL | Needs Metal renderer implementation |
| **No code signing by Team17** | Gatekeeper warnings | Only Team17 can sign with their Developer ID |

### Workarounds Applied

| Limitation | Our Workaround |
|------------|----------------|
| Gatekeeper warnings | Ad-hoc signing + quarantine removal |
| Missing AGL framework | Stub library that satisfies dynamic linker |
| Outdated Qt 5.3.2 | Replace with Qt 5.15 from Homebrew |
| Missing Qt frameworks | Bundle QtDBus and QtSvg |
| Hardcoded library paths | Rewrite to @executable_path |
| HTTP config URLs | Upgrade to HTTPS |

### What This Fix Does NOT Change

- Game logic, physics, or gameplay mechanics
- Save files or game data
- Steam/GOG DRM or licensing
- Network protocol or server communication
- Audio processing or sound effects
- Original graphics quality or assets

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

## Additional Tools

The fix includes several helpful utilities in the `tools/` directory:

### Save Game Backup
```bash
# Backup your saves before making changes
./tools/backup_saves.sh

# List available backups
./tools/backup_saves.sh --list

# Restore from backup
./tools/backup_saves.sh --restore
```

### Steam Update Watcher
Steam's "Verify Integrity" will overwrite the fix. The watcher monitors for this:
```bash
# Check if fix is still applied
./tools/watch_for_updates.sh --check

# Run watcher in background
./tools/watch_for_updates.sh --daemon &

# Install to run automatically on login
./tools/watch_for_updates.sh --install
```

### Steam Launch Options Integration
Use the enhanced launcher with Steam for crash reporting:
1. Right-click Worms W.M.D in Steam → Properties
2. In "Launch Options", enter:
   ```
   "/path/to/WormsWMD-macOS-Fix/tools/launch_worms.sh" --steam %command%
   ```

### Update Checker
```bash
# Check for new versions
./tools/check_updates.sh

# Silent check (for scripts)
./tools/check_updates.sh --quiet
```

### Controller Helper
```bash
# Diagnose controller issues
./tools/controller_helper.sh

# Show detailed controller info
./tools/controller_helper.sh --info
```

## Version History

- **1.4.0** (2025-12-25): Pre-built Qt (no Homebrew needed), Steam update watcher, crash reporter, save backup, update checker, controller helper
- **1.3.0** (2025-12-25): Universal AGL stub, ad-hoc code signing, quarantine removal, diagnostics tool, expanded FAQ and Known Limitations
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
