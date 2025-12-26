# Worms W.M.D - macOS Compatibility Report for Team17

**Document Version:** 2.0
**Date:** December 25, 2025
**Prepared for:** Team17 Digital Ltd.
**Platform:** macOS 26 (Tahoe) and later

---

## Executive Summary

Worms W.M.D fails to launch on macOS 26 (Tahoe) and later, displaying only a black screen. This report provides a comprehensive technical analysis of **all issues** affecting the game, required fixes, recommended improvements, and suggestions for long-term maintainability.

**Severity:** Critical (Game Unplayable)
**Affected Users:** All macOS 26+ users
**Root Causes:** Multiple deprecated framework dependencies, outdated libraries, and legacy build configuration

### Issue Summary

| Category | Issues Found | Severity |
|----------|--------------|----------|
| Framework Dependencies | 3 | Critical |
| Audio Libraries | 2 | High |
| Build Configuration | 4 | Medium |
| Security | 3 | Medium |
| Performance | 2 | Low |

---

## Table of Contents

1. [Critical Issues](#1-critical-issues)
2. [High Priority Issues](#2-high-priority-issues)
3. [Medium Priority Issues](#3-medium-priority-issues)
4. [Technical Analysis](#4-technical-analysis)
5. [Required Fixes](#5-required-fixes)
6. [Recommended Improvements](#6-recommended-improvements)
7. [Long-Term Recommendations](#7-long-term-recommendations)
8. [Testing Verification](#8-testing-verification)
9. [Appendix: Technical Details](#9-appendix-technical-details)

---

## 1. Critical Issues

### 1.1 AGL Framework Removal (CRITICAL)

**Issue:** Apple removed the AGL (Apple OpenGL) framework in macOS 26 (Tahoe). The game's executable has a dynamic dependency on AGL.

**Impact:** The game cannot launch at all - the dynamic linker fails to load the executable.

**Fix Required:** Either:
- Remove all AGL dependencies from the codebase and rebuild, OR
- Bundle a stub AGL.framework that provides no-op implementations of the 41 AGL functions

### 1.2 Outdated Qt 5.3.2 Frameworks (CRITICAL)

**Issue:** The game ships with Qt 5.3.2 (released 2014), which uses deprecated `NSOpenGLContext` APIs that no longer function correctly on modern macOS.

**Impact:** Even if AGL is resolved, the game displays only a black screen due to OpenGL context creation failures.

**Current State:**

| Framework | Shipped Version | Required Version |
|-----------|-----------------|------------------|
| QtCore    | 5.3.2 (2014)    | 5.15.x or 6.x    |
| QtGui     | 5.3.2           | 5.15.x or 6.x    |
| QtWidgets | 5.3.2           | 5.15.x or 6.x    |
| QtOpenGL  | 5.3.2           | 5.15.x or 6.x    |
| QtPrintSupport | 5.3.2      | 5.15.x or 6.x    |

**Fix Required:** Update Qt frameworks to 5.15.x (LTS) or Qt 6.x

### 1.3 Missing Qt Frameworks (CRITICAL)

**Issue:** The game bundle is missing required Qt frameworks that modern Qt plugins depend on.

**Missing Frameworks:**
- `QtDBus.framework` - Required by libqcocoa.dylib platform plugin
- `QtSvg.framework` - Required by libqsvg.dylib image format plugin

**Fix Required:** Bundle these frameworks with the game.

---

## 2. High Priority Issues

### 2.1 FMOD Audio Libraries Use Deprecated Runtime (HIGH)

**Issue:** The bundled FMOD audio libraries (`libfmodevent.dylib`, `libfmodex.dylib`) link against deprecated GNU C++ runtime libraries that are **no longer present** on macOS 26.

**Dependencies (MISSING on macOS 26):**
```
/usr/lib/libstdc++.6.dylib    ← REMOVED from macOS
/usr/lib/libgcc_s.1.dylib     ← REMOVED from macOS
```

**Current Workaround:** Rosetta 2 appears to provide compatibility shims for these libraries, but this is undocumented and unreliable.

**Impact:** Potential audio failures or crashes, especially in future macOS versions.

**Fix Required:** Update FMOD to a modern version that uses libc++ instead of libstdc++.

**Current FMOD Analysis:**
- Version: Very old (built against Mac OS X 10.6 era SDKs)
- Architecture: Universal (i386 + x86_64) - 32-bit code is unnecessary
- Carbon Framework dependency: Deprecated

### 2.2 Steam API Library Outdated (HIGH)

**Issue:** The bundled `libsteam_api.dylib` uses the same deprecated runtime:
```
/usr/lib/libstdc++.6.dylib    ← REMOVED from macOS
/usr/lib/libgcc_s.1.dylib     ← REMOVED from macOS
```

**Fix Required:** Update to current Steamworks SDK, which uses modern libc++.

---

## 3. Medium Priority Issues

### 3.1 Ancient Build Configuration

**Current Build Environment (from Info.plist):**

| Property | Current Value | Recommended |
|----------|--------------|-------------|
| DTSDKName | macosx10.11 | macosx14.0+ |
| DTXcode | 0731 (Xcode 7.3.1) | 15.0+ |
| DTXcodeBuild | 7D1014 | Current |
| BuildMachineOSBuild | 16G1618 (macOS 10.12.6) | Current |
| LSMinimumSystemVersion | 10.8 | 12.0+ |

**Issues:**
1. Built with 9-year-old SDK (macOS 10.11 El Capitan, 2015)
2. Built with Xcode 7.3.1 (2016)
3. Minimum system version set to macOS 10.8 (2012)
4. No modern macOS APIs or optimizations available

### 3.2 No Code Signing (SECURITY)

**Issue:** The game binary is completely unsigned.

```bash
$ codesign -dv "Worms W.M.D.app"
code object is not signed at all
```

**Impact:**
- Gatekeeper warnings on first launch
- Cannot be notarized
- Reduced user trust
- May be blocked by enterprise security policies

### 3.3 No Hardened Runtime (SECURITY)

**Issue:** The game does not use Apple's Hardened Runtime, which is required for notarization.

**Missing Entitlements:**
- `com.apple.security.cs.allow-unsigned-executable-memory`
- `com.apple.security.cs.disable-library-validation`
- Other required entitlements for games

### 3.4 Bundled libcurl May Have Vulnerabilities (SECURITY)

**Issue:** The game bundles `libcurl.4.dylib` which may contain security vulnerabilities if not updated regularly.

**Current Version:** Unknown (no version string visible)

**Recommendation:** Either:
- Use system libcurl (`/usr/lib/libcurl.4.dylib`)
- Bundle and regularly update libcurl
- Document the specific version for security audits

### 3.5 Carbon Framework Usage (DEPRECATED)

**Issue:** Both the game and FMOD libraries link against the Carbon framework:

```
/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon
```

**Status:** Carbon has been deprecated since macOS 10.8 (2012) and fully deprecated since macOS 10.14 (2018).

**Impact:** May cause issues in future macOS versions as Apple continues removing legacy APIs.

### 3.6 32-bit Code in Universal Binaries (OBSOLETE)

**Issue:** FMOD and Steam API libraries contain 32-bit (i386) code:

```bash
$ file libfmodex.dylib
Mach-O universal binary with 2 architectures: [i386:...] [x86_64:...]
```

**Impact:**
- Unnecessary file size increase
- 32-bit support was removed in macOS 10.15 Catalina (2019)
- No functional benefit

---

## 4. Technical Analysis

### 4.1 Complete Dependency Analysis

**Main Executable Dependencies:**
```
@executable_path/../Frameworks/libfmodevent.dylib
@executable_path/../Frameworks/libfmodex.dylib
@executable_path/../Frameworks/libQtSolutions_PropertyBrowser-head.1.0.0.dylib
@executable_path/../Frameworks/QtCore.framework/Versions/5/QtCore
@executable_path/../Frameworks/QtWidgets.framework/Versions/5/QtWidgets
@executable_path/../Frameworks/QtGui.framework/Versions/5/QtGui
@executable_path/../Frameworks/QtOpenGL.framework/Versions/5/QtOpenGL
@executable_path/../Frameworks/libcurl.4.dylib
@executable_path/../Frameworks/libsteam_api.dylib
/System/Library/Frameworks/AVFoundation.framework
/System/Library/Frameworks/Security.framework
/System/Library/Frameworks/IOKit.framework
/System/Library/Frameworks/Foundation.framework
/System/Library/Frameworks/QuartzCore.framework
/System/Library/Frameworks/IOSurface.framework
/System/Library/Frameworks/CoreMedia.framework
/System/Library/Frameworks/CoreVideo.framework
/System/Library/Frameworks/Carbon.framework          ← DEPRECATED
/System/Library/Frameworks/Cocoa.framework
/System/Library/Frameworks/OpenGL.framework          ← DEPRECATED
/System/Library/Frameworks/CoreGraphics.framework
/System/Library/Frameworks/AppKit.framework
/System/Library/Frameworks/CFNetwork.framework
/System/Library/Frameworks/CoreFoundation.framework
/System/Library/Frameworks/CoreServices.framework
/usr/lib/libz.1.dylib
/usr/lib/libresolv.9.dylib
/usr/lib/libobjc.A.dylib
/usr/lib/libc++.1.dylib
/usr/lib/libSystem.B.dylib
```

### 4.2 FMOD Library Analysis

**libfmodex.dylib Dependencies:**
```
/System/Library/Frameworks/Carbon.framework          ← DEPRECATED
/System/Library/Frameworks/AudioUnit.framework
/System/Library/Frameworks/CoreAudio.framework
/usr/lib/libstdc++.6.dylib                           ← MISSING on macOS 26
/usr/lib/libgcc_s.1.dylib                            ← MISSING on macOS 26
/usr/lib/libSystem.B.dylib
/System/Library/Frameworks/CoreServices.framework
/System/Library/Frameworks/CoreFoundation.framework
```

**libfmodevent.dylib Dependencies:**
```
/System/Library/Frameworks/Carbon.framework          ← DEPRECATED
@executable_path/../Frameworks/libfmodex.dylib
/System/Library/Frameworks/CoreAudio.framework
/usr/lib/libstdc++.6.dylib                           ← MISSING on macOS 26
/usr/lib/libgcc_s.1.dylib                            ← MISSING on macOS 26
/usr/lib/libSystem.B.dylib
/System/Library/Frameworks/CoreFoundation.framework
```

### 4.3 Qt Framework Analysis

The shipped Qt 5.3.2 frameworks have several critical issues:

1. **OpenGL Context Creation:** Uses deprecated `NSOpenGLContext` APIs that fail silently on macOS 26
2. **Missing Frameworks:** `QtDBus.framework` is required by the Cocoa platform plugin but not bundled
3. **Plugin Compatibility:** `libqcocoa.dylib` platform plugin expects newer Qt internal APIs
4. **Dependency Resolution:** Absolute paths to `/usr/local` that don't exist on end-user systems

### 4.4 Game Data Locations

**Save Data:** `~/Library/Application Support/Team17/Save/`
**Preferences:** Not using standard NSUserDefaults (no plist files found)
**DLC Content:** `steamapps/common/WormsWMD/DLC/`

---

## 5. Required Fixes

### 5.1 Fix 1: AGL Framework (Choose One)

#### Option A: Rebuild Without AGL (Recommended)
Remove AGL dependencies from the codebase entirely. Modern Qt 5.15+ uses CGL directly.

**Steps:**
1. Audit codebase for `#include <AGL/agl.h>` or AGL function calls
2. Replace with CGL equivalents or remove if unused
3. Rebuild against macOS 12+ SDK

#### Option B: Bundle AGL Stub (Quick Fix)
Provide a stub framework that satisfies the dynamic linker. See `src/agl_stub.c` in the community fix for a complete implementation.

### 5.2 Fix 2: Update Qt Frameworks

**Minimum Required:** Qt 5.15.x LTS
**Recommended:** Qt 6.5+ LTS (for Metal support)

**Frameworks to Update:**
- QtCore.framework → 5.15.x+
- QtGui.framework → 5.15.x+
- QtWidgets.framework → 5.15.x+
- QtOpenGL.framework → 5.15.x+
- QtPrintSupport.framework → 5.15.x+

**Frameworks to Add:**
- QtDBus.framework (required by libqcocoa.dylib)
- QtSvg.framework (required by SVG image plugin)

### 5.3 Fix 3: Update FMOD

**Current Version:** Unknown (very old, ~2010 era)
**Required:** FMOD 2.x or FMOD Core

**Changes Needed:**
- Replace libfmodevent.dylib and libfmodex.dylib
- Update to libc++ runtime (not libstdc++)
- Remove Carbon framework dependency
- Build x86_64 only (or universal x86_64 + arm64)

### 5.4 Fix 4: Update Steam SDK

**Current:** Very old version using libstdc++
**Required:** Current Steamworks SDK

### 5.5 Fix 5: Update Platform Plugins

Replace bundled plugins with Qt 5.15.x versions:
- `PlugIns/platforms/libqcocoa.dylib`
- `PlugIns/imageformats/*.dylib`

### 5.6 Fix 6: Update Library Paths

All library references must use `@executable_path` relative paths:

```bash
install_name_tool -change "/old/path" "@executable_path/../Frameworks/lib.dylib" binary
```

---

## 6. Recommended Improvements

### 6.1 Code Signing and Notarization

**Current State:** No code signing
**Recommendation:** Full code signing and notarization pipeline

```bash
# Sign all frameworks and the app
codesign --deep --force --options runtime \
  --sign "Developer ID Application: Team17 Digital Limited" \
  --entitlements entitlements.plist \
  "Worms W.M.D.app"

# Notarize
xcrun notarytool submit "Worms W.M.D.app" \
  --apple-id developer@team17.com \
  --team-id XXXXXXXXXX \
  --password @keychain:AC_PASSWORD

# Staple
xcrun stapler staple "Worms W.M.D.app"
```

**Required Entitlements (entitlements.plist):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

### 6.2 Universal Binary Support

**Current State:** x86_64 only (runs via Rosetta 2 on Apple Silicon)

**Recommendation:** Build universal binary (x86_64 + arm64)

**Benefits:**
- Native performance on Apple Silicon (2-3x faster)
- Reduced battery consumption (up to 50% better)
- Future-proofing against Rosetta deprecation
- Better user experience

```bash
clang -arch x86_64 -arch arm64 -mmacosx-version-min=12.0 ...
```

### 6.3 Metal Rendering Backend

**Current State:** OpenGL only (deprecated since macOS 10.14)

**Recommendation:** Add Metal rendering backend

**Benefits:**
- OpenGL is deprecated and may be removed
- Metal provides 2-10x better performance
- Better battery life on laptops
- Qt 6 has built-in Metal support via RHI

### 6.4 Update Minimum macOS Version

**Current:** 10.8 (Mountain Lion, 2012)
**Recommended:** 12.0 (Monterey, 2021)

**Benefits:**
- Access to modern APIs
- Better security features
- Smaller test matrix
- Users on older macOS are increasingly rare

### 6.5 Update libcurl

**Current:** Unknown bundled version
**Options:**
1. Use system libcurl (recommended for security)
2. Bundle current libcurl and update regularly
3. Switch to NSURLSession for networking

### 6.6 Retina/HiDPI Display Support

**Verify:** Ensure `NSHighResolutionCapable` is set in Info.plist:
```xml
<key>NSHighResolutionCapable</key>
<true/>
```

### 6.7 Full Screen Support

**Verify:** Modern full screen support via:
```xml
<key>LSUIPresentationMode</key>
<integer>3</integer>
```

---

## 7. Long-Term Recommendations

### 7.1 Port to Qt 6

Qt 5.15 is end-of-life. Qt 6 provides:
- Native Metal rendering via RHI (Rendering Hardware Interface)
- Better Apple Silicon support
- Modern C++17/20 codebase
- Active security updates
- Better High DPI support

### 7.2 Replace OpenGL with Metal

**Timeline:** Apple may remove OpenGL entirely in a future macOS version.

**Options:**
1. Qt 6 RHI (easiest - abstracts Metal/OpenGL/Vulkan)
2. MoltenVK (Vulkan over Metal)
3. Direct Metal port (best performance)
4. SDL2/3 with Metal backend

### 7.3 Regular macOS Testing

Establish a testing process:
- WWDC beta releases (June) - immediate testing
- Public betas (July-September) - regression testing
- Final releases (October) - validation
- Point releases - quick verification

### 7.4 Automated CI/CD Pipeline

```yaml
# GitHub Actions example
name: macOS Build
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-14  # Sonoma with Xcode 15
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: |
          xcodebuild -project WormsWMD.xcodeproj \
            -scheme "Worms WMD" \
            -configuration Release \
            -arch x86_64 -arch arm64
      - name: Sign
        run: ./scripts/sign.sh
      - name: Notarize
        run: ./scripts/notarize.sh
      - name: Upload
        uses: actions/upload-artifact@v4
        with:
          name: WormsWMD-macOS
          path: build/Release/*.app
```

### 7.5 Dependency Management

Implement automated dependency updates:
- Qt version tracking
- FMOD version tracking
- libcurl security updates
- Steam SDK updates

### 7.6 Crash Reporting

Implement crash reporting to catch issues early:
- Apple's built-in crash reporter
- Third-party services (Sentry, Crashlytics)
- Steam's built-in crash handling

---

## 8. Testing Verification

### 8.1 Test Matrix

| Configuration | Status | Notes |
|--------------|--------|-------|
| macOS 26.2 (arm64 via Rosetta) | PASS | Community fix applied |
| macOS 26.0 (arm64 via Rosetta) | Expected PASS | Same fixes required |
| macOS 15.x (Sequoia) | Needs Testing | May work without fixes |
| macOS 14.x (Sonoma) | Expected PASS | Fixes may not be required |
| macOS 13.x (Ventura) | Expected PASS | Fixes may not be required |

### 8.2 Verification Commands

```bash
# Check executable architecture
file "Contents/MacOS/Worms W.M.D"
# Expected: Mach-O 64-bit executable x86_64

# Check for unresolved references
otool -L "Contents/MacOS/Worms W.M.D" | grep -E "@rpath|/usr/local"
# Expected: (empty output)

# Check Qt version
otool -L "Contents/Frameworks/QtCore.framework/Versions/5/QtCore" | head -2
# Expected: 5.15.x

# Check AGL stub
file "Contents/Frameworks/AGL.framework/Versions/A/AGL"
# Expected: Mach-O 64-bit dynamically linked shared library x86_64

# Check code signing
codesign -dv --verbose=4 "Worms W.M.D.app"
# Expected: valid signature with Developer ID

# Verify entitlements
codesign -d --entitlements - "Worms W.M.D.app"
# Expected: required entitlements present
```

### 8.3 Runtime Testing

1. **Launch test:** Game launches without black screen
2. **Audio test:** Sound effects and music play correctly
3. **Graphics test:** No rendering glitches
4. **Input test:** Keyboard, mouse, controller all work
5. **Network test:** Multiplayer connectivity works
6. **Save test:** Game saves and loads correctly
7. **Steam test:** Achievements, cloud saves work
8. **Full screen test:** Resolution switching works
9. **Performance test:** Acceptable frame rates

---

## 9. Appendix: Technical Details

### 9.1 AGL Stub Implementation

A complete AGL stub implementation is provided in `src/agl_stub.c`. This provides no-op implementations of all 41 AGL functions:

- Pixel format functions (5)
- Renderer info functions (4)
- Context functions (8)
- Drawable functions (3)
- Virtual screen functions (2)
- Offscreen rendering functions (2)
- Option functions (5)
- Font functions (1)
- Error functions (2)
- Buffer management (1)
- Display functions (2)
- PBuffer functions (6)

### 9.2 Complete Build Information

From the current game bundle:

```
CFBundleExecutable: Worms W.M.D
CFBundleIdentifier: (not set - should be com.team17.wormswmd)
CFBundleName: Worms W.M.D
CFBundleShortVersionString: 1.0
CFBundleVersion: 1
DTCompiler: com.apple.compilers.llvm.clang.1_0
DTPlatformBuild: 7D1014
DTPlatformVersion: GM
DTSDKBuild: 15E60
DTSDKName: macosx10.11
DTXcode: 0731
DTXcodeBuild: 7D1014
LSMinimumSystemVersion: 10.8
NSHumanReadableCopyright: Copyright © 2016 Team17
NSMainNibFile: MainMenu
NSPrincipalClass: NSApplication
BuildMachineOSBuild: 16G1618
```

### 9.3 Required Dependency Versions

For the community fix (Homebrew reference):

```
qt@5: 5.15.18
glib: 2.82.x
pcre2: 10.44
libpng: 1.6.x
freetype: 2.13.x
libjpeg: 9e
libtiff: 4.5.x
webp: 1.3.x
zstd: 1.5.x
xz: 5.4.x
```

### 9.4 Original Game Bundle Contents

```
Frameworks/
├── QtCore.framework (5.3.2)
├── QtGui.framework (5.3.2)
├── QtWidgets.framework (5.3.2)
├── QtOpenGL.framework (5.3.2)
├── QtPrintSupport.framework (5.3.2)
├── libQtSolutions_PropertyBrowser-head.1.0.0.dylib
├── libfmodevent.dylib (universal i386+x86_64, libstdc++)
├── libfmodex.dylib (universal i386+x86_64, libstdc++)
├── libcurl.4.dylib
└── libsteam_api.dylib (universal i386+x86_64, libstdc++)

PlugIns/
├── platforms/
│   └── libqcocoa.dylib
└── imageformats/
    └── *.dylib
```

### 9.5 Deprecated APIs Summary

| API/Framework | Deprecated | Notes |
|--------------|------------|-------|
| AGL.framework | macOS 10.5 | Removed in macOS 26 |
| OpenGL.framework | macOS 10.14 | Still present, may be removed |
| Carbon.framework | macOS 10.8 | Still present, avoid using |
| libstdc++.6.dylib | macOS 10.9 | Removed in recent macOS |
| libgcc_s.1.dylib | macOS 10.9 | Removed in recent macOS |
| NSOpenGLContext | macOS 10.14 | Still works but deprecated |
| 32-bit (i386) | macOS 10.14 | Removed in macOS 10.15 |

---

## Contact

For questions about this report or the community fix:

**Repository:** https://github.com/cboyd0319/WormsWMD-macOS-Fix
**Issues:** https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues

---

*This report was prepared based on comprehensive analysis of Worms W.M.D version distributed via Steam as of December 2025, tested on macOS 26.2 (Tahoe) on Apple Silicon.*
