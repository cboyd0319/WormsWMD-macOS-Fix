# Technical details

## Known limitations

These limitations exist because the game is closed-source.

### Can't be fixed (requires Team17)

| Limitation | Impact | Reason |
|------------|--------|--------|
| FMOD uses deprecated runtime | Audio may break in future macOS | FMOD libs link to removed libstdc++; Rosetta provides shims for now |
| Steam API uses deprecated runtime | Networking may break in future macOS | Same as FMOD; needs Steamworks SDK update |
| No native Apple Silicon | Requires Rosetta on Apple Silicon; performance varies by system | Requires a universal binary |
| OpenGL only (deprecated) | May break if Apple removes OpenGL | Needs a Metal renderer |
| No code signing by Team17 | Gatekeeper warnings | Only Team17 can sign with their Developer ID |

### Workarounds applied

| Limitation | Workaround |
|------------|------------|
| Gatekeeper warnings | Ad-hoc signing and quarantine removal |
| Missing AGL framework | Stub library that satisfies the dynamic linker |
| Outdated Qt 5.3.2 | Replace with Qt 5.15 (pre-built or Homebrew) |
| Missing Qt frameworks | Bundle QtDBus and QtSvg |
| Hardcoded library paths | Rewrite to bundle-relative paths and validate bundled `@rpath` targets |
| HTTP config URLs | Upgrade to HTTPS (DataOSX and CommonData) |

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
| DataOSX configs | HTTP/internal URLs | HTTPS for known URLs; internal URLs commented out |
| CommonData configs | HTTP URLs | HTTPS in AnalyticsConfig.txt and HttpConfig.txt |
| Main executable install names | Original game references | Portable references when a matching bundled framework or dylib exists |

## Libraries added

The fix bundles dylibs required by Qt frameworks and plugins (detected with `otool -L`). Common libraries include:

- **Regex:** libpcre2-8.0.dylib, libpcre2-16.0.dylib
- **Compression:** libzstd.1.dylib, liblzma.5.dylib
- **GLib:** libglib-2.0.0.dylib, libgthread-2.0.0.dylib, libintl.8.dylib
- **Graphics:** libpng16.16.dylib, libfreetype.6.dylib, libmd4c.0.dylib
- **Images:** libjpeg.8.dylib, libtiff.6.dylib
- **WebP:** libwebp.7.dylib, libwebpdemux.2.dylib, libwebpmux.3.dylib, libsharpyuv.0.dylib

The exact list varies by Qt version and plugin set.

The committed Qt 5.15.19 archive contains 15 top-level runtime dependency
dylibs. Qt plugins live only under `PlugIns/`; their Mach-O self install IDs are
not copied again into `Frameworks/`, and archive members are unique.

## Mach-O run-path verification

The verifier parses `LC_RPATH` and dependency load commands with `otool`.
`@executable_path` is expanded from the game executable, `@loader_path` from the
binary being inspected, and resolved `@rpath` targets must remain inside the
selected app bundle. An unresolved `LC_LOAD_WEAK_DYLIB` is optional; an
unresolved strong load remains an installation error.

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
- Qt 5.15.19 is the current final Qt 5.15.x patch level and is the validated
  archive committed in `dist/`.

## Release package

The player-facing release zip is built by `tools/build_release_bundle.sh`. It
contains the friendly `Worms W.M.D Fix.command` launcher, the small bootstrap
installer, the canonical `fix_worms_wmd.sh` engine, support docs, original
visual assets, tools, scripts, source, and the verified `dist/` Qt package.

The release builder writes:

- `RELEASE_INFO.txt` with start-here instructions and build metadata
- `RELEASE_MANIFEST.tsv` with SHA-256, size, and relative path entries
- `WormsWMD-macOS-Fix-VERSION.zip`
- `WormsWMD-macOS-Fix-VERSION.zip.sha256`

The release bundle does not include game binaries, save files, user data,
official game art, or third-party sample assets.

## Qt package distribution

The installer prefers the highest verified `qt-frameworks-x86_64-*.tar.gz`
package in `dist/` with a matching `.sha256` file. Verification checks the
checksum, tar layout, tar entry metadata, symlink targets, metadata, required
Qt frameworks/plugins, any archive manifest, and `x86_64` Mach-O slices before
the package is reported as available. If a legacy archive lacks `MANIFEST.txt`,
the downloader writes and verifies a cache-local manifest before installer use.
Remote fallback uses the pinned release commit for `dist/` contents, not the
mutable default branch.

Maintainers can build a replacement package with:

```bash
./tools/fetch_qt_homebrew_bottles.rb \
  --lock dist/qt-frameworks-x86_64-5.15.19.source-provenance.tsv \
  --output /tmp/wormswmd-qt51519-prefix

SOURCE_DATE_EPOCH=1781740800 \
QT_PREFIX=/tmp/wormswmd-qt51519-prefix/opt/qt@5 \
QT_DEP_PREFIX=/tmp/wormswmd-qt51519-prefix \
QT_PACKAGE_VERSION=5.15.19 \
QT_SOURCE_PROVENANCE_FILE=dist/qt-frameworks-x86_64-5.15.19.source-provenance.tsv \
./tools/package_qt_frameworks.sh --output dist --version 5.15.19
```

Generated packages include `METADATA.txt`, `MANIFEST.txt`, and optional
`SOURCE_PROVENANCE.tsv`, prune framework headers from the runtime archive, and
use deterministic ordering and timestamps from `SOURCE_DATE_EPOCH` where
possible. The packager rejects versions outside Qt 5.15.x and can use
`QT_DEP_PREFIX` when dependency bottles live in an isolated Homebrew-like
prefix. This keeps future Qt 5.15.x refreshes inspectable without changing the
default user install flow.
