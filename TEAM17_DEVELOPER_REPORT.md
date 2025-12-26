# Worms W.M.D - macOS Compatibility Report for Team17

**Document Version:** 1.0
**Date:** December 25, 2025
**Prepared for:** Team17 Digital Ltd.
**Platform:** macOS 26 (Tahoe) and later

---

## Executive Summary

Worms W.M.D fails to launch on macOS 26 (Tahoe) and later, displaying only a black screen. This report provides a comprehensive technical analysis of all issues affecting the game, recommended fixes, and suggestions for long-term maintainability.

**Severity:** Critical (Game Unplayable)
**Affected Users:** All macOS 26+ users
**Root Cause:** Deprecated framework dependencies and outdated Qt version

---

## Table of Contents

1. [Critical Issues](#1-critical-issues)
2. [Technical Analysis](#2-technical-analysis)
3. [Required Fixes](#3-required-fixes)
4. [Recommended Improvements](#4-recommended-improvements)
5. [Long-Term Recommendations](#5-long-term-recommendations)
6. [Testing Verification](#6-testing-verification)
7. [Appendix: Technical Details](#7-appendix-technical-details)

---

## 1. Critical Issues

### 1.1 AGL Framework Removal (CRITICAL)

**Issue:** Apple removed the AGL (Apple OpenGL) framework in macOS 26 (Tahoe). The game's executable has a dynamic dependency on AGL.

**Impact:** The game cannot launch at all - the dynamic linker fails to load the executable.

**Evidence:**
```
$ otool -L "Worms W.M.D" | grep AGL
# (Reference to AGL.framework exists in original binary)
```

**Fix Required:** Either:
- Remove all AGL dependencies from the codebase and rebuild, OR
- Bundle a stub AGL.framework that provides no-op implementations of the 41 AGL functions

### 1.2 Outdated Qt 5.3.2 Frameworks (CRITICAL)

**Issue:** The game ships with Qt 5.3.2 (released 2014), which uses deprecated `NSOpenGLContext` APIs that no longer function correctly on modern macOS.

**Impact:** Even if AGL is resolved, the game displays only a black screen due to OpenGL context creation failures.

**Current State:**
| Framework | Shipped Version | Last Compatible |
|-----------|-----------------|-----------------|
| QtCore    | 5.3.2           | Qt 5.15.x       |
| QtGui     | 5.3.2           | Qt 5.15.x       |
| QtWidgets | 5.3.2           | Qt 5.15.x       |
| QtOpenGL  | 5.3.2           | Qt 5.15.x       |
| QtPrintSupport | 5.3.2      | Qt 5.15.x       |

**Fix Required:** Update Qt frameworks to 5.15.x (LTS) or Qt 6.x

---

## 2. Technical Analysis

### 2.1 AGL Framework Dependencies

The game references AGL functions through the dynamic linker. In macOS 26, Apple completed the removal of legacy OpenGL frameworks that began with the deprecation of OpenGL in macOS 10.14 (2018).

**AGL Functions Referenced (likely):**
- `aglChoosePixelFormat`
- `aglCreateContext`
- `aglSetDrawable`
- `aglSetCurrentContext`
- `aglSwapBuffers`
- Various other context management functions

**Analysis:** Based on Qt 5.15's architecture, Qt no longer uses AGL for OpenGL rendering - it uses CGL (Core OpenGL) directly. The AGL dependency likely comes from:
1. Legacy code paths in the game engine
2. Third-party libraries compiled against older macOS SDKs
3. Historical Qt integration code

### 2.2 Qt Framework Analysis

The shipped Qt 5.3.2 frameworks have several critical issues:

1. **OpenGL Context Creation:** Uses deprecated `NSOpenGLContext` APIs that fail silently on macOS 26
2. **Missing Frameworks:** `QtDBus.framework` is required by the Cocoa platform plugin but not bundled
3. **Plugin Compatibility:** `libqcocoa.dylib` platform plugin expects newer Qt internal APIs
4. **Dependency Resolution:** Absolute paths to `/usr/local` that don't exist on end-user systems

### 2.3 Library Path Issues

The current build has hardcoded library paths:
```
@rpath/QtCore.framework/Versions/5/QtCore
/usr/local/opt/qt@5/lib/...
```

These fail on systems without development tools installed.

---

## 3. Required Fixes

### 3.1 Fix 1: AGL Framework (Choose One)

#### Option A: Rebuild Without AGL (Recommended)
Remove AGL dependencies from the codebase entirely. Modern Qt 5.15+ uses CGL directly and does not require AGL.

**Steps:**
1. Audit codebase for `#include <AGL/agl.h>` or AGL function calls
2. Replace with CGL equivalents or remove if unused
3. Rebuild against macOS 12+ SDK

#### Option B: Bundle AGL Stub (Quick Fix)
Provide a stub framework that satisfies the dynamic linker:

```c
// All 41 AGL functions return appropriate error values
AGLContext aglCreateContext(AGLPixelFormat pix, AGLContext share) {
    return NULL;  // Always fail - Qt 5.15 won't actually use this
}
```

### 3.2 Fix 2: Update Qt Frameworks

**Minimum Required:** Qt 5.15.x LTS
**Recommended:** Qt 6.5+ LTS (for Metal support)

**Frameworks to Update:**
- QtCore.framework → 5.15.x
- QtGui.framework → 5.15.x
- QtWidgets.framework → 5.15.x
- QtOpenGL.framework → 5.15.x
- QtPrintSupport.framework → 5.15.x

**Frameworks to Add:**
- QtDBus.framework (required by libqcocoa.dylib)
- QtSvg.framework (required by SVG image plugin)

### 3.3 Fix 3: Update Platform Plugins

Replace bundled plugins with Qt 5.15.x versions:

- `PlugIns/platforms/libqcocoa.dylib`
- `PlugIns/imageformats/*.dylib`

### 3.4 Fix 4: Bundle Dependencies

The Qt 5.15 frameworks from Homebrew require these libraries:

| Library | Purpose |
|---------|---------|
| libpcre2-8.0.dylib | Regular expressions |
| libpcre2-16.0.dylib | Unicode regex |
| libglib-2.0.0.dylib | GLib core |
| libgthread-2.0.0.dylib | Threading |
| libintl.8.dylib | Internationalization |
| libpng16.16.dylib | PNG support |
| libfreetype.6.dylib | Font rendering |
| libjpeg.8.dylib | JPEG support |
| libtiff.6.dylib | TIFF support |
| libwebp.7.dylib | WebP support |
| libzstd.1.dylib | Compression |
| liblzma.5.dylib | Compression |
| libmd4c.0.dylib | Markdown |

### 3.5 Fix 5: Update Library Paths

All library references must use `@executable_path` relative paths:

**Before:**
```
/usr/local/opt/qt@5/lib/QtCore.framework/...
@rpath/QtCore.framework/...
```

**After:**
```
@executable_path/../Frameworks/QtCore.framework/...
```

Use `install_name_tool` to update all references:
```bash
install_name_tool -change "/old/path" "@executable_path/../Frameworks/lib.dylib" binary
```

---

## 4. Recommended Improvements

### 4.1 Code Signing

**Current State:** The game binary is not code signed.

**Recommendation:** Sign the app bundle with a valid Developer ID certificate to:
- Avoid Gatekeeper warnings
- Enable notarization
- Improve user trust

```bash
codesign --deep --force --sign "Developer ID Application: Team17" "Worms W.M.D.app"
xcrun notarytool submit "Worms W.M.D.app" --apple-id ... --team-id ...
```

### 4.2 Notarization

Apple requires notarization for apps distributed outside the App Store. Without notarization, macOS displays security warnings.

### 4.3 Universal Binary Support

**Current State:** x86_64 only (runs via Rosetta 2 on Apple Silicon)

**Recommendation:** Build universal binary (x86_64 + arm64) for:
- Native performance on Apple Silicon
- Reduced battery consumption
- Future-proofing against Rosetta deprecation

```bash
clang -arch x86_64 -arch arm64 ...
```

### 4.4 Metal Rendering Backend

**Current State:** OpenGL only (deprecated since macOS 10.14)

**Recommendation:** Add Metal rendering backend:
- OpenGL is deprecated and may be removed in future macOS
- Metal provides better performance on Apple hardware
- Qt 6 has built-in Metal support via RHI

### 4.5 Steam Runtime Updates

Consider updating the Steam integration:
- Current `libsteam_api.dylib` may be outdated
- Newer Steam SDK versions have better macOS support

---

## 5. Long-Term Recommendations

### 5.1 Port to Qt 6

Qt 5.15 is end-of-life. Qt 6 provides:
- Native Metal rendering
- Better Apple Silicon support
- Modern C++17 codebase
- Active security updates

### 5.2 Regular macOS Testing

Establish a testing process for each major macOS beta:
- WWDC beta releases (June)
- Public betas (July-September)
- Final releases (October)

### 5.3 Minimum macOS Version Policy

Consider updating minimum macOS version to:
- macOS 12 (Monterey) minimum for Qt 5.15
- macOS 13 (Ventura) minimum for Qt 6

This ensures users have adequate framework support.

### 5.4 Automated CI/CD Pipeline

Implement automated builds and tests:
```yaml
# Example GitHub Actions workflow
on: [push]
jobs:
  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: make macos
      - name: Test
        run: ./run_tests.sh
      - name: Sign & Notarize
        run: ./sign_and_notarize.sh
```

---

## 6. Testing Verification

### 6.1 Test Matrix

| Configuration | Status | Notes |
|--------------|--------|-------|
| macOS 26.2 (arm64) | PASS | After fix applied |
| macOS 26.2 (x86_64 via Rosetta) | PASS | After fix applied |
| macOS 26.0 | Expected PASS | Same fixes required |
| macOS 15.x | Expected PASS | Fixes not required |
| macOS 14.x | Expected PASS | Fixes not required |

### 6.2 Verification Commands

```bash
# Check executable architecture
file "Worms W.M.D"  # Should show x86_64

# Check library dependencies
otool -L "Worms W.M.D" | grep -E "@rpath|/usr/local"  # Should be empty

# Check Qt version
otool -L "Contents/Frameworks/QtCore.framework/Versions/5/QtCore" | head -2
# Should show 5.15.x

# Check AGL stub exists
ls "Contents/Frameworks/AGL.framework/Versions/A/AGL"
```

---

## 7. Appendix: Technical Details

### 7.1 AGL Stub Implementation

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

### 7.2 Required Dependency Versions (Homebrew Reference)

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

### 7.3 Complete Library Path Fix Script

See `scripts/04_fix_library_paths.sh` for the complete implementation that:
1. Scans all frameworks and dylibs
2. Builds lookup tables for @executable_path references
3. Updates all dependencies using install_name_tool

### 7.4 Original Game Frameworks

The original game bundle includes:
```
QtCore.framework (5.3.2)
QtGui.framework (5.3.2)
QtWidgets.framework (5.3.2)
QtOpenGL.framework (5.3.2)
QtPrintSupport.framework (5.3.2)
libQtSolutions_PropertyBrowser-head.1.0.0.dylib
libfmodevent.dylib
libfmodex.dylib
libcurl.4.dylib
libsteam_api.dylib
```

---

## Contact

For questions about this report or the community fix:

**Repository:** https://github.com/cboyd0319/WormsWMD-macOS-Fix
**Issues:** https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues

---

*This report was prepared based on analysis of Worms W.M.D version distributed via Steam as of December 2025.*
