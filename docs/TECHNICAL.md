# Technical details

## Known limitations

These limitations exist because the game is closed-source.

### Can't be fixed (requires Team17)

| Limitation | Impact | Reason |
|------------|--------|--------|
| FMOD uses deprecated runtime | Audio may break in future macOS | FMOD libs link to removed libstdc++; Rosetta provides shims for now |
| Steam API uses deprecated runtime | Networking may break in future macOS | Same as FMOD; needs Steamworks SDK update |
| No native Apple Silicon | ~20-30% performance overhead | Requires a universal binary |
| OpenGL only (deprecated) | May break if Apple removes OpenGL | Needs a Metal renderer |
| No code signing by Team17 | Gatekeeper warnings | Only Team17 can sign with their Developer ID |

### Workarounds applied

| Limitation | Workaround |
|------------|------------|
| Gatekeeper warnings | Ad-hoc signing and quarantine removal |
| Missing AGL framework | Stub library that satisfies the dynamic linker |
| Outdated Qt 5.3.2 | Replace with Qt 5.15 (pre-built or Homebrew) |
| Missing Qt frameworks | Bundle QtDBus and QtSvg |
| Hardcoded library paths | Rewrite to @executable_path |
| HTTP config URLs | Upgrade to HTTPS |

### What this fix doesn't change

- Game logic, physics, or gameplay mechanics
- Save files or game data
- Steam/GOG DRM or licensing
- Network protocol or server communication
- Audio processing or sound effects
- Original graphics quality or assets

## What gets modified

The fix replaces Qt frameworks bundled with the game (commonly QtCore, QtGui, QtWidgets, QtOpenGL, QtPrintSupport).

| Component | Original | Fixed |
|-----------|----------|-------|
| Qt*.framework (bundled) | 5.3.2 | 5.15.x |
| AGL.framework | System (removed) | Stub library |
| QtDBus.framework | Not present (if missing) | Added (required by plugins) |
| QtSvg.framework | Not present (if missing) | Added (required by SVG plugin) |
| Info.plist | Missing identifiers and HiDPI flags | Adds CFBundleIdentifier, HiDPI flags, graphics switching, updates minimum version |
| DataOSX configs | HTTP/internal URLs | HTTPS; internal URLs commented out (with .backup) |

## Libraries added

The fix bundles dylibs required by Qt frameworks and plugins (detected with `otool -L`). Common libraries include:

- **Regex:** libpcre2-8.0.dylib, libpcre2-16.0.dylib
- **Compression:** libzstd.1.dylib, liblzma.5.dylib
- **GLib:** libglib-2.0.0.dylib, libgthread-2.0.0.dylib, libintl.8.dylib
- **Graphics:** libpng16.16.dylib, libfreetype.6.dylib, libmd4c.0.dylib
- **Images:** libjpeg.8.dylib, libtiff.6.dylib
- **WebP:** libwebp.7.dylib, libwebpdemux.2.dylib, libwebpmux.3.dylib, libsharpyuv.0.dylib

The exact list varies by Qt version and plugin set.

## Plugins updated

- `platforms/libqcocoa.dylib` - Cocoa platform integration
- `imageformats/*.dylib` - Image format support (including libqsvg.dylib)

## How the AGL stub works

The AGL stub (`src/agl_stub.c`) provides empty implementations of all 41 AGL functions. Qt 5.15 doesn't use AGL (it uses Core OpenGL directly), so the stub only needs to exist to satisfy the dynamic linker.

## Why Qt 5.15

- Qt 5.15 is the last Qt 5 release with long-term support.
- It uses OpenGL APIs compatible with macOS.
- It preserves binary compatibility with the Qt 5.3 APIs the game uses.
- Pre-built x86_64 frameworks are available for distribution.
