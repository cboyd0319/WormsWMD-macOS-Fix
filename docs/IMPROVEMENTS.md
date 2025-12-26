# What this fix improves

This fix does more than just make the game launch. It addresses multiple issues with the original game bundle and adds quality-of-life improvements.

## Core fixes

These changes make the game playable on macOS 26 (Tahoe) and later.

| Issue | What was wrong | What the fix does |
|-------|----------------|-------------------|
| AGL framework removed | macOS 26 removed the AGL (Apple OpenGL) framework that the game requires | Adds a stub AGL.framework that satisfies the dynamic linker |
| Qt 5.3.2 outdated | The bundled Qt frameworks (from 2014) use deprecated APIs that cause a black screen | Replaces with Qt 5.15 LTS which uses modern OpenGL APIs |
| Missing Qt frameworks | QtDBus and QtSvg frameworks are missing but required by plugins | Bundles these frameworks with the game |
| Broken library paths | Some libraries reference `/usr/local` paths that don't exist | Rewrites all paths to use `@executable_path` |

## Security improvements

These changes improve the security posture of the game.

| Issue | What was wrong | What the fix does |
|-------|----------------|-------------------|
| HTTP config URLs | Config files use unencrypted HTTP URLs | Upgrades all URLs to HTTPS |
| Internal URLs exposed | Defunct internal Team17 URLs are in config files | Comments out internal/staging URLs (with backup) |
| No code signing | The game binary is completely unsigned | Applies ad-hoc code signing to reduce warnings |
| Quarantine flags | macOS marks downloaded files as quarantined | Clears quarantine flags to prevent "damaged app" dialogs |

## Display improvements

These changes improve how the game looks and behaves on modern Macs.

| Issue | What was wrong | What the fix does |
|-------|----------------|-------------------|
| No HiDPI support declared | Info.plist lacks `NSHighResolutionCapable` | Adds the flag for proper Retina display support |
| No GPU switching | Info.plist lacks `NSSupportsAutomaticGraphicsSwitching` | Adds the flag so laptops can use integrated graphics and save battery |

## Metadata fixes

These changes fix missing or incorrect metadata in the app bundle.

| Issue | What was wrong | What the fix does |
|-------|----------------|-------------------|
| Missing bundle identifier | `CFBundleIdentifier` is not set | Adds `com.team17.wormswmd` for proper app identity |
| Outdated minimum version | `LSMinimumSystemVersion` is set to 10.8 (2012) | Updates to reflect actual requirements |

## Future-proofing

These changes prepare the game for future macOS versions.

| Issue | Risk | What the fix does |
|-------|------|-------------------|
| x86_64-only AGL stub | If Apple removes Rosetta, the stub wouldn't load | Builds a universal binary (x86_64 + arm64) |
| Self-contained dependencies | Future macOS may remove more libraries | Bundles all required dylibs inside the app |

## Tools included

The fix includes utilities to help manage the game.

| Tool | What it does |
|------|--------------|
| Save game backup | Back up and restore saves, settings, and replays |
| Steam update watcher | Detects when Steam overwrites the fix and alerts you |
| Enhanced launcher | Launch with logging, safe mode, and debug options |
| Crash reporter | Saves crash reports with system information |
| Update checker | Checks for new versions of the fix |
| Controller helper | Diagnoses controller connectivity and provides tips |
| Diagnostics collector | Gathers system info for bug reports |

See [TOOLS.md](TOOLS.md) for usage details.

## What this fix doesn't change

The fix only modifies what's necessary. It doesn't touch:

- Game logic, physics, or gameplay mechanics
- Save files or game data
- Steam/GOG DRM or licensing
- Network protocol or server communication
- Audio processing or sound effects
- Original graphics quality or assets
- Multiplayer functionality

## Known limitations

Some issues can't be fixed without access to the game's source code:

| Limitation | Impact | Why it can't be fixed |
|------------|--------|----------------------|
| No native Apple Silicon | ~20-30% performance overhead via Rosetta | Requires rebuilding the game binary |
| FMOD uses deprecated runtime | Audio may break in future macOS | FMOD libs need updating by Team17 |
| Steam API uses deprecated runtime | Networking may break in future macOS | Steamworks SDK needs updating |
| OpenGL only | May break if Apple removes OpenGL | Requires a Metal renderer |

See [TECHNICAL.md](TECHNICAL.md) for more details.
