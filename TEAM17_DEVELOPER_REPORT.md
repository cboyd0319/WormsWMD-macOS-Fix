# Worms W.M.D macOS compatibility report for Team17

Document version: 3.0
Date: 2025-12-26
Prepared for: Team17 Digital Ltd.
Platform: macOS 26 (Tahoe) and later

## Executive summary

Worms W.M.D does not launch on macOS 26 (Tahoe) and later. The game displays a black screen and fails to initialize due to deprecated framework dependencies. This report is based on direct inspection of a Steam bundle captured on 2025-12-26. If a community fix has ever been applied, a full uninstall/reinstall is required to validate a pristine stock state (Steam integrity verification does not remove extra files).

**Severity**: Critical (game does not launch on macOS 26+)

**Root causes**:
1. AGL framework removed from macOS 26
2. Qt 5.3.2 frameworks use deprecated OpenGL APIs
3. FMOD and Steamworks libraries link to removed runtime libraries

**Security findings**: Multiple exposed API secrets discovered in shipped configuration files (see Section 8).

**Verified environment (at time of analysis)**:
- Steam bundle at `~/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app`
- macOS 26.2 (Tahoe) on Apple Silicon (M4 Max)
- Stock state assumed; re-verify with a clean reinstall if prior fixes were applied

---

## Issue summary matrix

| Category | Issue | Severity | Fix available |
|----------|-------|----------|---------------|
| Framework dependencies | AGL.framework removed in macOS 26 | Critical | Community fix provides stub |
| Framework dependencies | Qt 5.3.2 OpenGL context failures | Critical | Community fix replaces Qt |
| Audio libraries | FMOD links to removed libstdc++/libgcc | High | No fix (Rosetta 2 workaround) |
| Steam integration | libsteam_api links to removed runtime | High | No fix (Rosetta 2 workaround) |
| Security | Exposed API secrets in config files | High | Team17 action required |
| Build configuration | Ancient SDK (macOS 10.11, Xcode 7.3.1) | Medium | Partial fix available |
| Security/Compliance | Unsigned app bundle | Medium | Community fix adds ad-hoc signature |
| Platform support | x86_64 only (no Apple Silicon native) | Medium | No fix |
| Graphics | OpenGL-only renderer (deprecated) | Medium | No fix |

---

## Table of contents

1. [Critical issues](#1-critical-issues)
2. [High priority issues](#2-high-priority-issues)
3. [Medium priority issues](#3-medium-priority-issues)
4. [Technical analysis](#4-technical-analysis)
5. [Required fixes](#5-required-fixes)
6. [Recommended improvements](#6-recommended-improvements)
7. [Long-term recommendations](#7-long-term-recommendations)
8. [Security assessment](#8-security-assessment)
9. [Testing verification](#9-testing-verification)
10. [Performance expectations](#10-performance-expectations)
11. [Appendix: technical details](#11-appendix-technical-details)

---

## 1. Critical issues

### 1.1 AGL framework removal (critical)

**Issue**: Apple removed the AGL (Apple OpenGL) framework in macOS 26 (Tahoe).

**Impact**: The game cannot launch - the dynamic linker fails immediately.

**Affected binaries** (confirmed via `otool -L`):

| Binary | AGL dependency |
|--------|----------------|
| QtGui.framework | `/System/Library/Frameworks/AGL.framework/Versions/A/AGL` |
| QtWidgets.framework | `/System/Library/Frameworks/AGL.framework/Versions/A/AGL` |
| QtOpenGL.framework | `/System/Library/Frameworks/AGL.framework/Versions/A/AGL` |
| QtPrintSupport.framework | `/System/Library/Frameworks/AGL.framework/Versions/A/AGL` |
| libQtSolutions_PropertyBrowser | `/System/Library/Frameworks/AGL.framework/Versions/A/AGL` |
| libqcocoa.dylib (platform plugin) | `/System/Library/Frameworks/AGL.framework/Versions/A/AGL` |
| All 11 imageformat plugins | `/System/Library/Frameworks/AGL.framework/Versions/A/AGL` |
| libcocoaprintersupport.dylib | `/System/Library/Frameworks/AGL.framework/Versions/A/AGL` |
| libqtaccessiblewidgets.dylib | `/System/Library/Frameworks/AGL.framework/Versions/A/AGL` |

**Total**: 19 binaries depend on AGL.framework

**Fix options**:
1. Remove AGL dependencies from codebase and rebuild (recommended)
2. Bundle a stub AGL.framework with no-op implementations (community fix approach)

### 1.2 Outdated Qt 5.3.2 frameworks (critical)

**Issue**: The game ships with Qt 5.3.2 (released June 2014), which uses deprecated `NSOpenGLContext` APIs that fail on modern macOS.

**Impact**: Even with AGL resolved, the game displays a black screen.

**Shipped Qt versions** (observed in inspected bundle):

| Framework | Version | Release date |
|-----------|---------|--------------|
| QtCore | 5.3.2 | June 2014 |
| QtGui | 5.3.2 | June 2014 |
| QtWidgets | 5.3.2 | June 2014 |
| QtOpenGL | 5.3.2 | June 2014 |
| QtPrintSupport | 5.3.2 | June 2014 |

**Additional Qt issues**:
- All Qt frameworks link to `/usr/lib/libstdc++.6.dylib` (removed from macOS)
- All Qt plugins also link to AGL.framework and libstdc++.6

**Fix required**: Update Qt frameworks to 5.15.x LTS or Qt 6.x

---

## 2. High priority issues

### 2.1 FMOD audio libraries use deprecated runtime (high)

**Issue**: The bundled FMOD libraries link against GNU C++ runtime libraries removed from macOS.

**Library analysis**:

| Library | Architecture | Size | Deprecated dependencies |
|---------|--------------|------|------------------------|
| libfmodex.dylib | i386 + x86_64 | 2.2 MB | libstdc++.6, libgcc_s.1, Carbon |
| libfmodevent.dylib | i386 + x86_64 | 785 KB | libstdc++.6, libgcc_s.1, Carbon |

**Estimated version**: FMOD Ex 4.x (~2010-2012 era)
- Contains unnecessary 32-bit (i386) code
- Uses deprecated Carbon framework
- Built against Mac OS X 10.6 SDK

**Current workaround**: Rosetta 2 appears to provide compatibility shims, but this is undocumented and may break in future macOS versions.

**Fix required**: Update to FMOD Studio 2.x (uses libc++, supports arm64)

### 2.2 Steam API library outdated (high)

**Issue**: The bundled `libsteam_api.dylib` uses the same deprecated runtime.

**Library analysis**:

| Library | Architecture | Size | Deprecated dependencies |
|---------|--------------|------|------------------------|
| libsteam_api.dylib | i386 + x86_64 | 92 KB | libstdc++.6, libgcc_s.1 |

**Estimated version**: Steamworks SDK ~1.3x (2015-2016)

**Fix required**: Update to current Steamworks SDK (1.57+)

---

## 3. Medium priority issues

### 3.1 Ancient build configuration

**Build environment** (from Info.plist):

| Property | Current value | Age | Recommended |
|----------|--------------|-----|-------------|
| DTSDKName | macosx10.11 | 9 years | macosx14.0+ |
| DTXcode | 0731 (Xcode 7.3.1) | 9 years | 15.0+ |
| DTXcodeBuild | 7D1014 | 9 years | Current |
| BuildMachineOSBuild | 16G1618 (macOS 10.12.6) | 8 years | Current |
| LSMinimumSystemVersion | 10.8 | 12 years | 12.0+ |
| CFBundleIdentifier | (not set) | N/A | com.team17.wormswmd |
| NSHighResolutionCapable | (not set) | N/A | true |

### 3.2 No code signing

**Status**: The game bundle is completely unsigned.

```bash
$ codesign -dv "Worms W.M.D.app"
code object is not signed at all
```

**Impact**:
- Gatekeeper warnings on launch
- Cannot be notarized
- May be blocked by enterprise security policies

### 3.3 Bundled libcurl

| Library | Architecture | Size | Version |
|---------|--------------|------|---------|
| libcurl.4.dylib | x86_64 | 3.3 MB | Unknown |

**Dependencies**: Only links to `/usr/lib/libSystem.B.dylib` (modern)

**Recommendation**: Use system libcurl or update to latest version for security patches.

### 3.4 Carbon framework usage

Both the main executable and FMOD link to Carbon:
```
/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon
```

**Status**: Carbon deprecated since macOS 10.8 (2012).

### 3.5 No Apple Silicon native binary

**Current**: x86_64 only (34 MB executable)
**Impact**: Runs via Rosetta 2 with performance overhead that varies by system and workload

### 3.6 OpenGL-only renderer

OpenGL is deprecated on macOS since 10.14 and may be removed in a future version.

---

## 4. Technical analysis

### 4.1 Game bundle structure

**Total size**: 4.9 GB

```
Worms W.M.D.app/Contents/
├── MacOS/
│   └── Worms W.M.D (34 MB, x86_64)
├── Frameworks/
│   ├── QtCore.framework (5.3.2)
│   ├── QtGui.framework (5.3.2)
│   ├── QtWidgets.framework (5.3.2)
│   ├── QtOpenGL.framework (5.3.2)
│   ├── QtPrintSupport.framework (5.3.2)
│   ├── libQtSolutions_PropertyBrowser-head.1.0.0.dylib
│   ├── libfmodevent.dylib (universal i386+x86_64)
│   ├── libfmodex.dylib (universal i386+x86_64)
│   ├── libcurl.4.dylib (x86_64)
│   └── libsteam_api.dylib (universal i386+x86_64)
├── PlugIns/
│   ├── accessible/libqtaccessiblewidgets.dylib
│   ├── imageformats/ (11 plugins)
│   ├── platforms/libqcocoa.dylib
│   └── printsupport/libcocoaprintersupport.dylib
├── Resources/
│   ├── Audio/PC/ (audio banks)
│   ├── CommonData/ (game data, configs)
│   ├── DataOSX/ (platform-specific configs)
│   ├── wads/ (3.0 GB game assets)
│   └── ...
├── Info.plist
└── PkgInfo
```

### 4.2 Main executable dependencies

```
@executable_path/../Frameworks/libfmodevent.dylib
@executable_path/../Frameworks/libfmodex.dylib
@executable_path/../Frameworks/libQtSolutions_PropertyBrowser-head.1.0.0.dylib
@executable_path/../Frameworks/QtCore.framework/Versions/5/QtCore
@executable_path/../Frameworks/QtWidgets.framework/Versions/5/QtWidgets
@executable_path/../Frameworks/QtGui.framework/Versions/5/QtGui
@executable_path/../Frameworks/QtOpenGL.framework/Versions/5/QtOpenGL
@rpath/libcurl.4.dylib
@executable_path/../Frameworks/libsteam_api.dylib

System frameworks:
/System/Library/Frameworks/AVFoundation.framework
/System/Library/Frameworks/Security.framework
/System/Library/Frameworks/IOKit.framework
/System/Library/Frameworks/Foundation.framework
/System/Library/Frameworks/QuartzCore.framework
/System/Library/Frameworks/IOSurface.framework
/System/Library/Frameworks/CoreMedia.framework
/System/Library/Frameworks/CoreVideo.framework
/System/Library/Frameworks/Carbon.framework           (deprecated)
/System/Library/Frameworks/Cocoa.framework
/System/Library/Frameworks/OpenGL.framework           (deprecated)
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

### 4.3 Qt plugin details

All 14 Qt plugins shipped in the game:

| Plugin | Location | AGL dependency | libstdc++ dependency |
|--------|----------|----------------|---------------------|
| libqcocoa.dylib | platforms/ | Yes | Yes |
| libcocoaprintersupport.dylib | printsupport/ | Yes | Yes |
| libqtaccessiblewidgets.dylib | accessible/ | Yes | Yes |
| libqdds.dylib | imageformats/ | Yes | Yes |
| libqgif.dylib | imageformats/ | Yes | Yes |
| libqicns.dylib | imageformats/ | Yes | Yes |
| libqico.dylib | imageformats/ | Yes | Yes |
| libqjp2.dylib | imageformats/ | Yes | Yes |
| libqjpeg.dylib | imageformats/ | Yes | Yes |
| libqmng.dylib | imageformats/ | Yes | Yes |
| libqtga.dylib | imageformats/ | Yes | Yes |
| libqtiff.dylib | imageformats/ | Yes | Yes |
| libqwbmp.dylib | imageformats/ | Yes | Yes |
| libqwebp.dylib | imageformats/ | Yes | Yes |

---

## 5. Required fixes

### 5.1 Fix 1: AGL framework

**Option A (Recommended)**: Rebuild without AGL
1. Remove `#include <AGL/agl.h>` from codebase
2. Replace AGL calls with CGL equivalents
3. Rebuild against macOS 12+ SDK
4. Update Qt to 5.15+ (which doesn't use AGL)

**Option B (Quick fix)**: Bundle AGL stub
- Provide stub framework at `Contents/Frameworks/AGL.framework`
- Implement all 41 AGL functions as no-ops
- See community fix `src/agl_stub.c` for reference

### 5.2 Fix 2: Update Qt frameworks

**Minimum**: Qt 5.15.x LTS
**Recommended**: Qt 6.5+ LTS

Frameworks to replace:
- QtCore.framework: 5.3.2 → 5.15.x+
- QtGui.framework: 5.3.2 → 5.15.x+
- QtWidgets.framework: 5.3.2 → 5.15.x+
- QtOpenGL.framework: 5.3.2 → 5.15.x+
- QtPrintSupport.framework: 5.3.2 → 5.15.x+

Additional frameworks to bundle:
- QtDBus.framework (required by libqcocoa.dylib in Qt 5.15+)
- QtSvg.framework (required by SVG image plugin)

### 5.3 Fix 3: Update FMOD

**Estimated current**: FMOD Ex 4.x (~2010)
**Required**: FMOD Studio 2.02+ or FMOD Core

Requirements:
- Use libc++ instead of libstdc++
- Remove Carbon dependency
- Build x86_64 only (or universal x86_64 + arm64)

### 5.4 Fix 4: Update Steamworks SDK

**Estimated current**: ~1.3x (2015-2016)
**Required**: 1.57+

Requirements:
- Use libc++ instead of libstdc++
- Build x86_64 only (or universal)

### 5.5 Fix 5: Update Qt plugins

Replace all 14 plugins with Qt 5.15.x versions matching the frameworks.

### 5.6 Fix 6: Update library paths

Ensure all libraries use `@executable_path` or `@loader_path`:
```bash
install_name_tool -change "/old/path" "@executable_path/../Frameworks/lib.dylib" binary
```

---

## 6. Recommended improvements

### 6.1 Code signing and notarization

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

Required entitlements:
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

### 6.2 Universal binary support

Build for both architectures:
```bash
clang -arch x86_64 -arch arm64 -mmacosx-version-min=12.0 ...
```

Benefits:
- Native Apple Silicon performance (2-3x faster)
- Reduced battery consumption
- Future-proofing

### 6.3 Metal rendering backend

Current: OpenGL only (deprecated)
Recommendation: Add Metal via Qt 6 RHI or direct port

### 6.4 Update minimum macOS version

Current: 10.8 (2012)
Recommended: 12.0 (2021)

### 6.5 Add bundle identifier

Add to Info.plist:
```xml
<key>CFBundleIdentifier</key>
<string>com.team17.wormswmd</string>
```

### 6.6 Enable HiDPI support

Add to Info.plist:
```xml
<key>NSHighResolutionCapable</key>
<true/>
```

### 6.7 Diagnostic logging

Add structured logging with:
- Default log location: `~/Library/Logs/Team17/WormsWMD/`
- Launch arguments: `-log-level`, `-log-file`, `-safe-mode`
- Capture Qt plugin loading, OpenGL init, Steam init status

### 6.8 Crash reporting

- Ship dSYMs for symbolication
- Integrate crash reporting (Sentry, Crashlytics, or Apple's built-in)

---

## 7. Long-term recommendations

### 7.1 Port to Qt 6

Qt 5.15 is end-of-life. Qt 6 provides:
- Native Metal rendering via RHI
- Better Apple Silicon support
- Modern C++17/20 codebase
- Active security updates

### 7.2 Replace OpenGL with Metal

Options:
1. Qt 6 RHI (abstracts Metal/OpenGL/Vulkan)
2. MoltenVK (Vulkan over Metal)
3. Direct Metal port
4. SDL2/3 with Metal backend

### 7.3 Regular macOS testing

Establish testing schedule:
- WWDC beta releases (June)
- Public betas (July-September)
- Final releases (October)
- Point releases

### 7.4 Automated CI/CD pipeline

```yaml
name: macOS Build
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: xcodebuild -arch x86_64 -arch arm64
      - name: Sign
        run: ./scripts/sign.sh
      - name: Notarize
        run: ./scripts/notarize.sh
```

---

## 8. Security assessment

### 8.1 Exposed API credentials (HIGH SEVERITY)

**CRITICAL**: The shipped game contains confirmed API secrets in plaintext configuration files.

*Note: Actual secret values are redacted from this public report. Presence was confirmed by direct inspection of the game bundle.*

#### GOGConfig.txt
```
GOGClientIDString = "[REDACTED - 17 digits]"
GOGClientID = [REDACTED - 17 digits]
GOGClientSec = "[REDACTED - 64 char hex string]"
SteamAppID = 270910
SteamPrivateKey = "[REDACTED - 64 char hex string]"
```

#### SteamConfig.txt and GOGConfig.txt
```
TwitchClientID = "[REDACTED - 30 chars]"
TwitchClientSec = "[REDACTED - 30 chars]"
```

#### HttpConfig.txt (platform-specific HMAC secrets)

The following platforms have exposed HMAC client credentials:

| Platform | ClientId | ClientSecret |
|----------|----------|--------------|
| PS4 | [REDACTED - 20 chars] | [REDACTED - 32 chars] |
| Xbox One | [REDACTED - 20 chars] | [REDACTED - 32 chars] |
| Windows | [REDACTED - 20 chars] | [REDACTED - 32 chars] |
| Windows GOG | (same as Windows) | (same as Windows) |
| macOS | [REDACTED - 20 chars] | [REDACTED - 32 chars] |
| Linux | (same as macOS) | (same as macOS) |
| Nintendo Switch | (same as PS4) | (same as PS4) |

**Recommendation**: These secrets should be immediately rotated and removed from shipped builds. Use secure credential storage or server-side authentication.

### 8.2 Internal/staging URLs exposed

**SteamConfig.txt and GOGConfig.txt**:
```
URL_Internal = "http://xom.team17.com/revolutiontest/";
```

This internal staging URL should not be in production builds.

### 8.3 Development paths exposed

**WorldSystemPathsOSX.txt**:
```
[ROOT] <PAUL> D:\Projects\t17proj4\Main\Code\Game\EditorWorkspace\
```

This Windows development path should not be in production builds.

### 8.4 Insecure HTTP endpoints

Config files reference HTTP (not HTTPS) endpoints:
```
URL_External = "http://www.team17.com/wormsrevolution/";
URL_Internal = "http://xom.team17.com/revolutiontest/";
```

**Recommendation**: Update all URLs to HTTPS.

### 8.5 Analytics configuration

**AnalyticsConfig.txt**:
```
AppID = "UA-62971458-2";  // Google Analytics tracking ID
```

This is public information but should be documented.

### 8.6 Unsigned application

The game bundle is completely unsigned, which:
- Triggers Gatekeeper warnings
- Prevents notarization
- May be blocked by enterprise policies
- Reduces user trust

### 8.7 Security recommendations summary

| Issue | Severity | Action required |
|-------|----------|-----------------|
| Exposed GOG client secrets | Critical | Rotate immediately |
| Exposed Steam private key | Critical | Rotate immediately |
| Exposed Twitch client secrets | Critical | Rotate immediately |
| Exposed HMAC secrets (PS4/XB1/Win/macOS/Linux/Switch) | Critical | Rotate immediately |
| Internal staging URLs | Medium | Remove from retail builds |
| Development paths | Low | Remove from retail builds |
| HTTP endpoints | Medium | Update to HTTPS |
| Unsigned app | Medium | Implement code signing |

---

## 9. Testing verification

### 9.1 Compatibility matrix

| macOS version | Code name | Fix required | Notes |
|--------------|-----------|--------------|-------|
| macOS 26.x | Tahoe | Yes | AGL removed, Qt 5.3.2 broken |
| macOS 15.x | Sequoia | Unknown | Not verified; AGL still present |
| macOS 14.x | Sonoma | Unknown | Not verified |
| macOS 13.x | Ventura | Unknown | Not verified |
| macOS 12.x | Monterey | Unknown | Not verified |

### 9.2 Hardware compatibility

| Hardware | Status | Notes |
|----------|--------|-------|
| Apple Silicon (M1/M2/M3/M4) | Works with fix | Via Rosetta 2 |
| Intel Mac (2016+) | Works with fix | Native x86_64 |
| Intel Mac (pre-2016) | Unknown | May lack Metal |

### 9.3 Verification commands

```bash
# Check executable architecture
file "Contents/MacOS/Worms W.M.D"
# Expected: Mach-O 64-bit executable x86_64

# Check Qt version
otool -L "Contents/Frameworks/QtCore.framework/Versions/5/QtCore" | head -2
# Stock shows: 5.3.2

# Check for AGL dependencies
otool -L "Contents/Frameworks/QtGui.framework/Versions/5/QtGui" | grep AGL
# Stock shows: /System/Library/Frameworks/AGL.framework/Versions/A/AGL

# Check code signing
codesign -dv "Worms W.M.D.app"
# Stock: not signed at all

# Check for deprecated runtime
otool -L "Contents/Frameworks/libfmodex.dylib" | grep -E "libstdc|libgcc"
# Shows: /usr/lib/libstdc++.6.dylib, /usr/lib/libgcc_s.1.dylib
```

---

## 10. Performance expectations

### 10.1 Performance (not benchmarked in this analysis)

No quantitative benchmarks were collected during this analysis. Measure performance on target hardware with repeatable in-game scenarios if precise numbers are required.

### 10.2 Performance factors (qualitative)

Factors that can influence performance:
- Rosetta 2 translation on Apple Silicon
- OpenGL renderer vs a native Metal backend
- Qt version and plugin compatibility

### 10.3 Optimization recommendations

For native performance improvements:
1. Universal binary (arm64 + x86_64): Eliminates Rosetta overhead
2. Metal renderer: 2-10x rendering improvement
3. Qt 6 with RHI: Built-in Metal support

---

## 11. Appendix: technical details

### 11.1 Complete Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>BuildMachineOSBuild</key>
    <string>16G1618</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Worms W.M.D</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Worms W.M.D</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>DTCompiler</key>
    <string>com.apple.compilers.llvm.clang.1_0</string>
    <key>DTPlatformBuild</key>
    <string>7D1014</string>
    <key>DTPlatformVersion</key>
    <string>GM</string>
    <key>DTSDKBuild</key>
    <string>15E60</string>
    <key>DTSDKName</key>
    <string>macosx10.11</string>
    <key>DTXcode</key>
    <string>0731</string>
    <key>DTXcodeBuild</key>
    <string>7D1014</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.8</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright (c) 2016 Team17. All rights reserved.</string>
    <key>NSMainNibFile</key>
    <string>MainMenu</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

**Missing keys that should be added**:
- `CFBundleIdentifier`: com.team17.wormswmd
- `NSHighResolutionCapable`: true
- `NSSupportsAutomaticGraphicsSwitching`: true
- `LSApplicationCategoryType`: public.app-category.games

### 11.2 Deprecated APIs summary

| API/Framework | Deprecated | Removed | Status in game |
|--------------|------------|---------|----------------|
| AGL.framework | macOS 10.5 | macOS 26 | Critical blocker |
| libstdc++.6.dylib | macOS 10.9 | macOS 10.15+ | High risk |
| libgcc_s.1.dylib | macOS 10.9 | macOS 10.15+ | High risk |
| Carbon.framework | macOS 10.8 | Still present | Medium risk |
| OpenGL.framework | macOS 10.14 | Still present | Medium risk |
| 32-bit (i386) | macOS 10.14 | macOS 10.15 | Unnecessary |

### 11.3 Bundle size analysis (approximate)

| Component | Size |
|-----------|------|
| Main executable | 34 MB |
| Qt frameworks | ~15 MB |
| FMOD libraries | ~3 MB |
| Other libraries | ~5 MB |
| Resources/wads | ~3.0 GB |
| Resources/Audio | ~600 MB |
| Other resources | ~1.2 GB |
| **Total** | **~4.9 GB** |

*Note: Sizes were estimated from the inspected bundle on 2025-12-26 and will vary by build and platform.*

### 11.4 Configuration files analyzed

| File | Location | Contains |
|------|----------|----------|
| SteamConfig.txt | DataOSX/ | Steam app ID, Twitch secrets |
| GOGConfig.txt | DataOSX/ | GOG secrets, Steam key |
| PcLanConfig.txt | DataOSX/ | LAN network config |
| SwitchConfig.txt | DataOSX/ | Network switching config |
| HttpConfig.txt | CommonData/ | HMAC secrets for all platforms |
| AnalyticsConfig.txt | CommonData/ | Google Analytics config |
| ServerDataConfig.txt | CommonData/ | API endpoint paths |
| WorldSystemPathsOSX.txt | Resources/ | File system paths |

### 11.5 Community fix components

The community fix (v1.6.1) addresses the critical issues by:

1. **AGL stub**: Provides `AGL.framework` with no-op implementations
2. **Qt 5.15**: Replaces all Qt frameworks and plugins
3. **Additional dependencies**: Bundles required Qt dependencies (glib, pcre2, freetype, etc.)
4. **Info.plist updates**: Adds CFBundleIdentifier, NSHighResolutionCapable, updates LSMinimumSystemVersion
5. **Ad-hoc signing**: Applies code signature to the modified bundle
6. **HTTPS URLs**: Updates config files to use HTTPS

**Not addressed by community fix**:
- FMOD library update
- Steamworks SDK update
- Apple Silicon native binary
- Metal renderer
- Exposed API secrets

---

## Contact

For questions about this report or the community fix:

Repository: https://github.com/cboyd0319/WormsWMD-macOS-Fix
Issues: https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues

---

*This report was prepared from a Steam bundle inspected on macOS 26.2 (Tahoe) on Apple Silicon (M4 Max), captured on 2025-12-26. If the bundle had ever been modified by a fix, reinstall to confirm a pristine stock state before re-validating these findings.*
