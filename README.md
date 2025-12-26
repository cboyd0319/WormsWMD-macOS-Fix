# Worms W.M.D - macOS Tahoe (26.x) Fix

[![CI](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml/badge.svg)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-26.0%2B-blue.svg)](https://www.apple.com/macos/)
[![GitHub release](https://img.shields.io/github/v/release/cboyd0319/WormsWMD-macOS-Fix?include_prereleases)](https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases)

A comprehensive community fix for Worms W.M.D on macOS 26 (Tahoe) and later. Fixes the black screen issue, improves stability, and includes tools for crash reporting, save backups, and more.

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

This is a comprehensive fix that not only makes the game playable, but also improves stability, security, and the overall experience.

### Core Fixes

| Fix | What It Does |
|-----|--------------|
| **AGL Stub Library** | Provides a stub for the removed AGL framework so macOS will launch the game |
| **Qt 5.15 Upgrade** | Replaces outdated Qt 5.3.2 (2014) with Qt 5.15 for modern OpenGL compatibility |
| **Dependency Bundling** | Bundles all required libraries so the game is fully self-contained |
| **Library Path Fixes** | Rewrites all paths to use `@executable_path` for portability |

### Enhancements

| Enhancement | What It Does |
|-------------|--------------|
| **Ad-hoc Code Signing** | Signs the app bundle to reduce Gatekeeper warnings |
| **Quarantine Removal** | Clears macOS quarantine flags that cause "damaged app" dialogs |
| **Info.plist Fixes** | Adds missing CFBundleIdentifier, enables HiDPI/Retina, GPU switching |
| **Config URL Security** | Upgrades HTTP→HTTPS, disables defunct internal Team17 URLs |
| **Universal AGL Stub** | Builds arm64 + x86_64 binary for future macOS compatibility |
| **Pre-built Qt Packages** | No Homebrew required - downloads ready-to-use Qt frameworks |

### Tools Included

| Tool | What It Does |
|------|--------------|
| **Crash Reporter** | Detects crashes and saves diagnostic reports automatically |
| **Steam Update Watcher** | Monitors for Steam updates that overwrite the fix, prompts to reapply |
| **Save Game Backup** | Backup and restore saves, settings, and replays |
| **Update Checker** | Checks GitHub for new versions of this fix |
| **Controller Helper** | Diagnoses controller connectivity, provides configuration tips |
| **Diagnostics Collector** | Gathers system info for bug reports |
| **Enhanced Launcher** | Launch with logging, safe mode, Steam integration |

## Requirements

- macOS 26 (Tahoe) or later
- Worms W.M.D installed via Steam or GOG
- Internet connection

**That's it!** Everything else is installed automatically:
- Rosetta 2 (for Apple Silicon Macs)
- Xcode Command Line Tools (for building components)
- Qt frameworks (downloaded automatically)

## Quick Start

### Option 1: Double-Click Installer (Easiest)

1. **Download** [`Install Fix.command`](https://github.com/cboyd0319/WormsWMD-macOS-Fix/raw/main/Install%20Fix.command)
2. **Double-click** the downloaded file
3. If macOS says it can't be opened: **Right-click** → **Open** → **Open**
4. **Done!** Everything else is automatic

### Option 2: One-Liner (Terminal)

Open Terminal and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash
```

### Option 3: Manual Clone

```bash
git clone https://github.com/cboyd0319/WormsWMD-macOS-Fix.git
cd WormsWMD-macOS-Fix
./fix_worms_wmd.sh
```

The fix automatically:
- Finds your game (Steam, GOG, or custom locations)
- Installs Rosetta 2 if needed (Apple Silicon)
- Installs Xcode tools if needed
- Creates a backup of original files
- Downloads and applies all fixes
- Verifies everything worked

## Detailed Installation

### Step-by-Step Manual Installation

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

### Pre-built Qt download failed (Homebrew fallback)

If the automatic Qt download fails, the fix will try to use Intel Homebrew as a fallback. If you see Homebrew-related errors:

```bash
# Install Intel Homebrew (Apple Silicon)
arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Qt 5
arch -x86_64 /usr/local/bin/brew install qt@5

# If permission errors occur
sudo mkdir -p /usr/local/var/homebrew/locks /usr/local/etc /usr/local/Frameworks
sudo chown -R $(whoami) /usr/local/var /usr/local/etc /usr/local/Frameworks
```

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

**Q: Does this fix require Homebrew?**

A: No! As of v1.4.0, the fix downloads pre-built Qt frameworks automatically. Homebrew is only used as a fallback if the download fails. If you do need the fallback, you'll need Intel Homebrew (`/usr/local/bin/brew`) on Apple Silicon because the game requires x86_64 libraries.

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

A: The fix doesn't modify input handling, but we include a diagnostic tool. Run `./tools/controller_helper.sh` to check controller connectivity and get configuration tips for Xbox, PlayStation, and Switch Pro controllers.

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
| Outdated Qt 5.3.2 | Replace with Qt 5.15 (pre-built or Homebrew) |
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

The fix bundles dylibs required by the Qt frameworks/plugins (detected via
`otool -L` scan). Common libraries include:

- **Regex:** libpcre2-8.0.dylib, libpcre2-16.0.dylib
- **Compression:** libzstd.1.dylib, liblzma.5.dylib
- **GLib:** libglib-2.0.0.dylib, libgthread-2.0.0.dylib, libintl.8.dylib
- **Graphics:** libpng16.16.dylib, libfreetype.6.dylib, libmd4c.0.dylib
- **Images:** libjpeg.8.dylib, libtiff.6.dylib
- **WebP:** libwebp.7.dylib, libwebpdemux.2.dylib, libwebpmux.3.dylib, libsharpyuv.0.dylib

The exact list can vary depending on the Qt version and plugin set.

### Plugins Updated

- `platforms/libqcocoa.dylib` - Cocoa platform integration
- `imageformats/*.dylib` - Image format support (including `libqsvg.dylib`)

### How the AGL Stub Works

The AGL stub (`src/agl_stub.c`) provides empty implementations of all 41 AGL functions. Since Qt 5.15 doesn't actually use AGL (it uses Core OpenGL directly), the stub just needs to exist and return appropriate error values to satisfy the dynamic linker.

### Why Qt 5.15?

- Qt 5.15 is the last version of Qt 5 with long-term support
- It uses modern OpenGL APIs compatible with macOS's OpenGL implementation
- It maintains binary compatibility with Qt 5.3 APIs the game uses
- Pre-built x86_64 frameworks available for easy distribution

## Security

This fix is designed to be transparent, safe, and reversible. Key security features:

- **Open source**: All code is auditable
- **Minimal network access**: One-time download of Qt frameworks from GitHub (~50MB)
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

- **1.5.0** (2025-12-26): **Zero-setup installer!** Double-click installer, auto-install Rosetta/Xcode, auto-detect game location, friendlier error messages
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
