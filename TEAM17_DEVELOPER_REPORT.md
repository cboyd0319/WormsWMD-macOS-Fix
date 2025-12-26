# Worms W.M.D macOS compatibility report for Team17

Document version: 2.5
Date: 2025-12-26
Prepared for: Team17 Digital Ltd.
Platform: macOS 26 (Tahoe) and later

## Executive summary

Worms W.M.D does not launch on macOS 26 (Tahoe) and later. It shows a black screen. This report summarizes the issues, required fixes, and recommendations.

Severity: critical (game does not launch)
Affected users: macOS 26+ players
Root causes: deprecated framework dependencies, outdated libraries, legacy build settings, and missing platform compliance updates (signing, notarization, diagnostics)

Verified on this machine: macOS 26.2 (Apple Silicon M4 Max via Rosetta 2) with community fix v1.5.0 applied and verification passing

Community fix status: v1.5.0 provides a zero-setup experience with auto install for Rosetta 2 and Xcode CLT, plus game detection

### Issue summary

| Category | Severity | Key issues |
|----------|----------|------------|
| Framework dependencies | Critical | AGL removal, Qt 5.3.2, missing QtDBus/QtSvg |
| Audio libraries | High | FMOD and Steamworks linked to removed libstdc++/libgcc |
| Build configuration | Medium | Ancient SDK/Xcode, missing CFBundleIdentifier |
| Security and compliance | Medium | Unsigned app, no hardened runtime, HTTP endpoints |
| Platform and performance | Medium | OpenGL-only, no Apple Silicon native binary |
| Diagnostics and observability | Medium | No structured logging or crash reporting |

---

## Scope and evidence

- Static analysis of the shipped macOS app bundle (Steam build) on macOS 26.2
- Dynamic dependency inspection (`otool -L`, `lipo`, `codesign`)
- Community fix verification logs (AGL stub + Qt 5.15 + dependency bundling)
- No access to original game source code; all code-level recommendations are based on binary and packaging behavior

---

## Table of contents

1. [Critical issues](#1-critical-issues)
2. [High priority issues](#2-high-priority-issues)
3. [Medium priority issues](#3-medium-priority-issues)
4. [Technical analysis](#4-technical-analysis)
5. [Required fixes](#5-required-fixes)
6. [Recommended improvements](#6-recommended-improvements)
7. [Long-term recommendations](#7-long-term-recommendations)
8. [Security and malware assessment](#8-security-and-malware-assessment)
9. [Testing verification](#9-testing-verification)
10. [Performance expectations](#10-performance-expectations)
11. [Appendix: technical details](#11-appendix-technical-details)

---

## 1. Critical issues

### 1.1 AGL framework removal (critical)

Issue: Apple removed the AGL (Apple OpenGL) framework in macOS 26 (Tahoe). The game's executable has a dynamic dependency on AGL.

Impact: The game cannot launch at all - the dynamic linker fails to load the executable.

Fix required: Do one of these options:
- Remove all AGL dependencies from the codebase and rebuild, OR
- Bundle a stub AGL.framework that provides no-op implementations of the 41 AGL functions

### 1.2 Outdated Qt 5.3.2 frameworks (critical)

Issue: The game ships with Qt 5.3.2 (released 2014), which uses deprecated `NSOpenGLContext` APIs that no longer function correctly on modern macOS.

Impact: Even if AGL is resolved, the game displays only a black screen due to OpenGL context creation failures.

Current state:

| Framework | Shipped Version | Required Version |
|-----------|-----------------|------------------|
| QtCore    | 5.3.2 (2014)    | 5.15.x or 6.x    |
| QtGui     | 5.3.2           | 5.15.x or 6.x    |
| QtWidgets | 5.3.2           | 5.15.x or 6.x    |
| QtOpenGL  | 5.3.2           | 5.15.x or 6.x    |
| QtPrintSupport | 5.3.2      | 5.15.x or 6.x    |

Fix required: Update Qt frameworks to 5.15.x (LTS) or Qt 6.x

### 1.3 Missing Qt frameworks (critical)

Issue: The game bundle is missing required Qt frameworks that modern Qt plugins depend on.

Missing frameworks:
- `QtDBus.framework` - Required by libqcocoa.dylib platform plugin
- `QtSvg.framework` - Required by libqsvg.dylib image format plugin

Fix required: Bundle these frameworks with the game.

---

## 2. High priority issues

### 2.1 FMOD audio libraries use deprecated runtime (high)

Issue: The bundled FMOD audio libraries (`libfmodevent.dylib`, `libfmodex.dylib`) link against deprecated GNU C++ runtime libraries that are no longer present on macOS 26.

Dependencies (missing on macOS 26):
```
/usr/lib/libstdc++.6.dylib    (removed from macOS)
/usr/lib/libgcc_s.1.dylib     (removed from macOS)
```

Verified: Both libraries are absent on macOS 26.2 (`/usr/lib`).

Current workaround: Rosetta 2 appears to provide compatibility shims for these libraries, but this is undocumented and unreliable.

Impact: Potential audio failures or crashes, especially in future macOS versions.

Fix required: Update FMOD to a modern version that uses libc++ instead of libstdc++.

Current FMOD analysis:
- Version: Very old (built against Mac OS X 10.6 era SDKs)
- Architecture: Universal (i386 + x86_64) - 32-bit code is unnecessary
- Carbon Framework dependency: Deprecated

### 2.2 Steam API library outdated (high)

Issue: The bundled `libsteam_api.dylib` uses the same deprecated runtime:
```
/usr/lib/libstdc++.6.dylib    (removed from macOS)
/usr/lib/libgcc_s.1.dylib     (removed from macOS)
```

Fix required: Update to current Steamworks SDK, which uses modern libc++.

---

## 3. Medium priority issues

### 3.1 Ancient build configuration

Current build environment (from Info.plist):

| Property | Current value | Recommended |
|----------|--------------|-------------|
| DTSDKName | macosx10.11 | macosx14.0+ |
| DTXcode | 0731 (Xcode 7.3.1) | 15.0+ |
| DTXcodeBuild | 7D1014 | Current |
| BuildMachineOSBuild | 16G1618 (macOS 10.12.6) | Current |
| LSMinimumSystemVersion | 10.8 | 12.0+ |

Issues:
1. Built with 9-year-old SDK (macOS 10.11 El Capitan, 2015)
2. Built with Xcode 7.3.1 (2016)
3. Minimum system version set to macOS 10.8 (2012)
4. No modern macOS APIs or optimizations available

### 3.2 No code signing (security)

Issue: The game binary is completely unsigned.

```bash
$ codesign -dv "Worms W.M.D.app"
code object is not signed at all
```

Impact:
- Gatekeeper warnings on first launch
- Cannot be notarized (current state)
- Reduced user trust
- May be blocked by enterprise security policies

### 3.3 No hardened runtime (security)

Issue: The game does not use Apple's Hardened Runtime, which is required for notarization.

Missing entitlements:
- `com.apple.security.cs.allow-unsigned-executable-memory`
- `com.apple.security.cs.disable-library-validation`
- Other entitlements required for games

### 3.4 Bundled libcurl may have vulnerabilities (security)

Issue: The game bundles `libcurl.4.dylib` which may contain security vulnerabilities if not updated regularly.

Current version: Unknown (no version string visible)

Recommendation: Do one of these options:
- Use system libcurl (`/usr/lib/libcurl.4.dylib`)
- Bundle and regularly update libcurl
- Document the specific version for security audits

### 3.5 Carbon framework usage (deprecated)

Issue: Both the game and FMOD libraries link against the Carbon framework:

```
/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon
```

Status: Carbon has been deprecated since macOS 10.8 (2012) and fully deprecated since macOS 10.14 (2018).

Impact: May cause issues in future macOS versions as Apple continues removing legacy APIs.

### 3.6 32-bit code in universal binaries (obsolete)

Issue: FMOD and Steam API libraries contain 32-bit (i386) code:

```bash
$ file libfmodex.dylib
Mach-O universal binary with 2 architectures: [i386:...] [x86_64:...]
```

Impact:
- Unnecessary file size increase
- 32-bit support was removed in macOS 10.15 Catalina (2019)
- No functional benefit

### 3.7 No apple silicon native binary (performance)

Issue: The macOS build is x86_64 only and runs under Rosetta 2 on Apple Silicon.

Impact:
- Performance and battery penalties (often 2x+ slower)
- Increased risk of incompatibility if Rosetta is deprecated in a future macOS

Fix required: Provide universal binaries (x86_64 + arm64).

### 3.8 OpenGL-only renderer (deprecated)

Issue: Rendering relies on OpenGL, which is deprecated on macOS and may be removed in a future release.

Impact:
- Future compatibility risk
- Performance limitations compared to Metal

Fix required: Provide a Metal backend (direct Metal or via Qt 6 RHI).

### 3.9 Limited diagnostic logging (medium)

Issue: There is no documented, user-accessible logging for startup failures or rendering issues.

Impact: Support and QA cannot reliably reproduce or diagnose failures, especially black-screen or crash-on-startup cases.

Fix required: Add structured logging with configurable verbosity and file output (see section 6.8).

### 3.10 No crash reporting / symbolication pipeline (medium)

Issue: Crash logs are not symbolicated and there is no integrated crash reporting pipeline.

Impact: High MTTR (mean time to resolution) for regressions and platform-specific issues.

Fix required: Ship dSYMs and integrate crash reporting (see section 7.6).

### 3.11 Insecure HTTP endpoints in config (security)

Issue: Configuration files reference HTTP endpoints:
- `http://www.team17.com/wormsrevolution/`
- `http://xom.team17.com/revolutiontest/` (internal)

Impact:
- Mixed-content and MITM risk
- Internal endpoints should not ship in public builds

Fix required: Update to HTTPS and remove internal/staging URLs from retail builds.

### 3.12 Missing bundle identifier (compliance)

Issue: `CFBundleIdentifier` is missing in the Info.plist.

Impact:
- App identity and preferences are not properly namespaced
- Complicates notarization, signing, and crash symbolication

Fix required: Set a stable bundle identifier (e.g., `com.team17.wormswmd`).

---

## 4. Technical analysis

### 4.1 Complete dependency analysis

Main Executable Dependencies:
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
/System/Library/Frameworks/Carbon.framework          (deprecated)
/System/Library/Frameworks/Cocoa.framework
/System/Library/Frameworks/OpenGL.framework          (deprecated)
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

### 4.2 FMOD library analysis

libfmodex.dylib Dependencies:
```
/System/Library/Frameworks/Carbon.framework          (deprecated)
/System/Library/Frameworks/AudioUnit.framework
/System/Library/Frameworks/CoreAudio.framework
/usr/lib/libstdc++.6.dylib                           (missing on macOS 26)
/usr/lib/libgcc_s.1.dylib                            (missing on macOS 26)
/usr/lib/libSystem.B.dylib
/System/Library/Frameworks/CoreServices.framework
/System/Library/Frameworks/CoreFoundation.framework
```

libfmodevent.dylib Dependencies:
```
/System/Library/Frameworks/Carbon.framework          (deprecated)
@executable_path/../Frameworks/libfmodex.dylib
/System/Library/Frameworks/CoreAudio.framework
/usr/lib/libstdc++.6.dylib                           (missing on macOS 26)
/usr/lib/libgcc_s.1.dylib                            (missing on macOS 26)
/usr/lib/libSystem.B.dylib
/System/Library/Frameworks/CoreFoundation.framework
```

### 4.3 Qt framework analysis

The shipped Qt 5.3.2 frameworks have several critical issues:

1. OpenGL context creation: Uses deprecated `NSOpenGLContext` APIs that fail silently on macOS 26
2. Missing frameworks: `QtDBus.framework` is required by the Cocoa platform plugin but not bundled
3. Plugin compatibility: `libqcocoa.dylib` platform plugin expects newer Qt internal APIs
4. Dependency resolution: Absolute paths to `/usr/local` that do not exist on end-user systems

### 4.4 Game data locations

Save Data: `~/Library/Application Support/Team17/Save/`
Preferences: Not using standard NSUserDefaults (no plist files found)
DLC Content: `steamapps/common/WormsWMD/DLC/`

---

## 5. Required fixes

### 5.1 Fix 1: AGL framework (choose one)

#### Option a: rebuild without AGL (recommended)
Remove AGL dependencies from the codebase entirely. Modern Qt 5.15+ uses CGL directly.

Steps:
1. Audit codebase for `#include <AGL/agl.h>` or AGL function calls
2. Replace with CGL equivalents or remove if unused
3. Rebuild against macOS 12+ SDK

#### Option b: bundle AGL stub (quick fix)
Provide a stub framework that satisfies the dynamic linker. See `src/agl_stub.c` in the community fix for a complete implementation.

### 5.2 Fix 2: update Qt frameworks

Minimum required: Qt 5.15.x LTS
Recommended: Qt 6.5+ LTS (for Metal support)

Frameworks to update:
- QtCore.framework to 5.15.x+
- QtGui.framework to 5.15.x+
- QtWidgets.framework to 5.15.x+
- QtOpenGL.framework to 5.15.x+
- QtPrintSupport.framework to 5.15.x+

Frameworks to add:
- QtDBus.framework (required by libqcocoa.dylib)
- QtSvg.framework (required by SVG image plugin)

### 5.3 Fix 3: update FMOD

Current version: Unknown (very old, ~2010 era)
Required: FMOD 2.x or FMOD Core

Changes needed:
- Replace libfmodevent.dylib and libfmodex.dylib
- Update to libc++ runtime (not libstdc++)
- Remove Carbon framework dependency
- Build x86_64 only (or universal x86_64 + arm64)

### 5.4 Fix 4: update Steam SDK

Current version: Very old (uses libstdc++).
Required: Current Steamworks SDK.

### 5.5 Fix 5: update platform plugins

Replace bundled plugins with Qt 5.15.x versions:
- `PlugIns/platforms/libqcocoa.dylib`
- `PlugIns/imageformats/*.dylib`

### 5.6 Fix 6: update library paths

All library references must use `@executable_path` relative paths:

```bash
install_name_tool -change "/old/path" "@executable_path/../Frameworks/lib.dylib" binary
```

---

## 6. Recommended improvements

### 6.1 Code signing and notarization

Current state: No code signing
Recommendation: Implement a full code signing and notarization pipeline.

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

Required entitlements (entitlements.plist):
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

Current state: x86_64 only (runs via Rosetta 2 on Apple Silicon)

Recommendation: Build a universal binary (x86_64 + arm64).

Benefits:
- Native performance on Apple Silicon (2-3x faster)
- Reduced battery consumption (up to 50% better)
- Future-proofing against Rosetta deprecation
- Better user experience

```bash
clang -arch x86_64 -arch arm64 -mmacosx-version-min=12.0 ...
```

### 6.3 Metal rendering backend

Current state: OpenGL only (deprecated since macOS 10.14)

Recommendation: Add a Metal rendering backend.

Benefits:
- OpenGL is deprecated and may be removed
- Metal provides 2-10x better performance
- Better battery life on laptops
- Qt 6 has built-in Metal support via RHI

### 6.4 Update minimum macOS version

Current minimum: 10.8 (Mountain Lion, 2012)
Recommended minimum: 12.0 (Monterey, 2021)

Benefits:
- Access to modern APIs
- Better security features
- Smaller test matrix
- Users on older macOS are increasingly rare

### 6.5 Update libcurl

Current: Unknown bundled version
Options:
1. Use system libcurl (recommended for security)
2. Bundle current libcurl and update regularly
3. Switch to NSURLSession for networking

### 6.6 Retina/HiDPI display support

Verify: Ensure `NSHighResolutionCapable` is set in Info.plist:
```xml
<key>NSHighResolutionCapable</key>
<true/>
```

### 6.7 Full screen support

Verify: Use modern full-screen support with:
```xml
<key>LSUIPresentationMode</key>
<integer>3</integer>
```

### 6.8 Diagnostic logging and supportability

Recommendation: Add a configurable logging system with file output and log levels:
- Default log location: `~/Library/Logs/Team17/WormsWMD/`
- Launch arguments: `-log-level`, `-log-file`, `-safe-mode`
- Capture Qt plugin loading, OpenGL/Metal initialization, and Steamworks init status

Benefit: Faster support triage and reproducible diagnostics.

### 6.9 Crash reporting and symbolication

Recommendation: Ship dSYMs and integrate crash reporting:
- Centralized symbol server for each release build
- Automatic crash submission (opt-in) with privacy controls

Benefit: Reduces time to diagnose macOS-specific regressions.

### 6.10 Secure networking and ATS compliance

Recommendation:
- Remove HTTP endpoints from retail builds
- Enforce HTTPS and update ATS exceptions only if required
- Audit network calls for TLS 1.2+ compatibility

### 6.11 Safe mode and fallback rendering

Recommendation: Add a safe-mode option that:
- Disables hardware acceleration
- Forces a compatibility renderer
- Resets graphics settings to defaults

Benefit: Provides a recovery path for graphics initialization failures.

---

## 7. Long-term recommendations

### 7.1 Port to Qt 6

Qt 5.15 is end-of-life. Qt 6 provides:
- Native Metal rendering via RHI (Rendering Hardware Interface)
- Better Apple Silicon support
- Modern C++17/20 codebase
- Active security updates
- Better HiDPI support

### 7.2 Replace OpenGL with Metal

Timeline: Apple may remove OpenGL entirely in a future macOS version.

Options:
1. Qt 6 RHI (easiest - abstracts Metal/OpenGL/Vulkan)
2. MoltenVK (Vulkan over Metal)
3. Direct Metal port (best performance)
4. SDL2/3 with Metal backend

### 7.3 Regular macOS testing

Establish a testing process:
- WWDC beta releases (June) - immediate testing
- Public betas (July-September) - regression testing
- Final releases (October) - validation
- Point releases - quick verification

### 7.4 Automated CI/CD pipeline

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

### 7.5 Dependency management

Implement automated dependency updates:
- Qt version tracking
- FMOD version tracking
- libcurl security updates
- Steam SDK updates

### 7.6 Crash reporting

Implement crash reporting to catch issues early:
- Apple's built-in crash reporter
- Third-party services (Sentry, Crashlytics)
- Steam's built-in crash handling

---

## 8. Security and malware assessment

Scope: Static inspection of the installed macOS app bundle and configuration files on macOS 26.2. No source code was available for review.

Findings (static):
- No LaunchAgents/Daemons or autostart entries found (only `Contents/Info.plist` exists).
- No script files with valid shebangs were detected; occurrences of `#!` are within binary data files (false positives).
- URL strings are limited to expected Team17 endpoints in `DataOSX/SteamConfig.txt` and `DataOSX/GOGConfig.txt` (HTTP, not HTTPS) plus icon metadata.
- Binaries are unsigned (confirmed via `codesign`), which is a distribution/security concern but not evidence of malware.

Conclusion: No obvious indicators of malicious payloads were found in the static scan performed on this machine. This does not rule out runtime-only behaviors.

Recommended additional checks (for Team17):
- Runtime network monitoring (e.g., `lsof -i`, Little Snitch) to validate outbound connections.
- Binary scanning with internal security tooling and reproducible build verification.
- Dependency SBOM and provenance checks for Qt, FMOD, Steamworks, and bundled third-party libraries.

---

## 9. Testing verification

### 9.1 Compatibility matrix

#### Fix required

| macOS version | Code name | Fix required | Status | Notes |
|--------------|-----------|--------------|--------|-------|
| macOS 26.x | Tahoe | Yes | Verified | AGL removed, Qt 5.3.2 broken |
| macOS 15.x | Sequoia | Likely no | Untested | AGL still present |
| macOS 14.x | Sonoma | No | Expected | Should work without fix |
| macOS 13.x | Ventura | No | Expected | Should work without fix |
| macOS 12.x | Monterey | No | Expected | Should work without fix |

#### Hardware compatibility

| Hardware | Status | Notes |
|----------|--------|-------|
| Apple Silicon (M1/M2/M3/M4) | Verified | Runs via Rosetta 2 |
| Intel Mac (2016+) | Expected | Native x86_64 |
| Intel Mac (pre-2016) | Unknown | May lack required Metal support |

#### Tested configurations

| System | macOS | Hardware | GPU | Status |
|--------|-------|----------|-----|--------|
| Mac (Apple Silicon) | 26.2 | M4 Max | Integrated | Pass |

Note: Please report additional tested configurations via GitHub issues.

### 9.2 Verification commands

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

# Check QtSvg and QtDBus presence
test -d "Contents/Frameworks/QtSvg.framework" && echo "QtSvg present"
test -d "Contents/Frameworks/QtDBus.framework" && echo "QtDBus present"

# Check AGL stub
file "Contents/Frameworks/AGL.framework/Versions/A/AGL"
# Expected: Mach-O 64-bit dynamically linked shared library x86_64

# Check code signing
codesign -dv --verbose=4 "Worms W.M.D.app"
# Expected: valid signature with Developer ID

# Verify entitlements
codesign -d --entitlements - "Worms W.M.D.app"
# Expected: required entitlements present

# (If implemented) Verify log file creation
ls ~/Library/Logs/Team17/WormsWMD/ 2>/dev/null || true
```

### 9.3 Runtime testing

1. Launch test: Game launches without black screen
2. Audio test: Sound effects and music play correctly
3. Graphics test: No rendering glitches
4. Input test: Keyboard, mouse, controller all work
5. Network test: Multiplayer connectivity works
6. Save test: Game saves and loads correctly
7. Steam test: Achievements, cloud saves work
8. Full screen test: Resolution switching works
9. Performance test: Acceptable frame rates

---

## 10. Performance expectations

### 10.1 Expected performance

With the community fix applied, users can expect:

| Metric | Apple Silicon (Rosetta 2) | Intel Mac |
|--------|---------------------------|-----------|
| Launch Time | 3-8 seconds | 2-5 seconds |
| Menu Navigation | Smooth | Smooth |
| Gameplay (1v1) | 60 FPS | 60 FPS |
| Gameplay (4+ players) | 30-60 FPS | 45-60 FPS |
| Complex explosions | May dip to 20-30 FPS | 30-45 FPS |

### 10.2 Performance overhead

| Factor | Overhead | Notes |
|--------|----------|-------|
| Rosetta 2 translation | ~20-30% | One-time translation cached |
| OpenGL (vs native Metal) | ~10-20% | macOS OpenGL is a wrapper |
| Qt 5.15 (vs Qt 5.3) | Negligible | May actually improve |
| AGL stub | None | Stub is never actually called |

### 10.3 Known performance issues

1. First launch after fix: May be slower as Rosetta 2 translates new binaries
2. Large maps with many objects: May experience frame drops
3. Extended sessions: Memory usage may increase over time
4. Background apps: Close resource-intensive apps for best performance

### 10.4 Optimization recommendations for Team17

If source code access is available, these would significantly improve performance:

1. Native Apple Silicon build: Would eliminate ~25-30% Rosetta overhead
2. Metal renderer: Would provide 2-10x rendering performance improvement
3. Modern Qt 6 with RHI: Built-in Metal support with better GPU utilization
4. Memory optimization: Profile and fix any memory leaks

---

## 11. Appendix: technical details

### 11.1 AGL stub implementation

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

The community fix now builds a universal binary (x86_64 + arm64) for future-proofing.

### 11.2 Bundled library version analysis

#### FMOD audio libraries

| Library | Architecture | Runtime | Estimated Version | Notes |
|---------|--------------|---------|-------------------|-------|
| libfmodex.dylib | i386 + x86_64 | libstdc++.6 | FMOD Ex 4.x (~2010-2012) | Deprecated runtime |
| libfmodevent.dylib | i386 + x86_64 | libstdc++.6 | FMOD Event (~2010-2012) | Deprecated runtime |

Analysis Method:
```bash
# Check architecture
lipo -info libfmodex.dylib
# Output: Architectures in the fat file: libfmodex.dylib are: i386 x86_64

# Check dependencies
otool -L libfmodex.dylib | grep -E "libstdc|libgcc"
# Output: /usr/lib/libstdc++.6.dylib, /usr/lib/libgcc_s.1.dylib
```

Version Indicators:
- Presence of both i386 and x86_64 suggests pre-2015 build (before Apple moved to 64-bit only)
- Use of libstdc++.6 indicates pre-2013 toolchain (before libc++ became default)
- FMOD Ex (not FMOD Studio) was the product name until ~2014
- File sizes and export symbols match FMOD Ex 4.x series

Recommended update: FMOD Studio 2.02.x or later (uses libc++, supports arm64)

#### Libcurl

| Library | Architecture | Estimated Version | Notes |
|---------|--------------|-------------------|-------|
| libcurl.4.dylib | x86_64 | 7.x (unknown minor) | Bundled, version unverifiable |

Analysis method:
```bash
# Check for version string
strings libcurl.4.dylib | grep -i "libcurl\|curl/"
# No clear version string found

# Check dependencies
otool -L libcurl.4.dylib
# Links against system libraries (libc++, libz, etc.)
```

Security recommendation:
- Current version is unknown; may contain unpatched CVEs
- Option 1: Use system libcurl (`/usr/lib/libcurl.4.dylib`) - automatically updated by Apple
- Option 2: Bundle latest libcurl 8.x and maintain update schedule
- Option 3: Migrate to NSURLSession for modern Apple networking

#### Steam API

| Library | Architecture | Runtime | Estimated Version | Notes |
|---------|--------------|---------|-------------------|-------|
| libsteam_api.dylib | i386 + x86_64 | libstdc++.6 | Steamworks SDK ~1.3x (2015-2016) | Deprecated runtime |

Recommended update: Steamworks SDK 1.57+ (uses libc++, supports notarization)

### 11.3 Qt property browser library

The game bundles `libQtSolutions_PropertyBrowser-head.1.0.0.dylib`, a third-party Qt component for property editing UI. This is from the Qt Solutions archive and appears compatible with Qt 5.15.

### 11.4 Complete build information

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
NSHumanReadableCopyright: Copyright (c) 2016 Team17
NSMainNibFile: MainMenu
NSPrincipalClass: NSApplication
BuildMachineOSBuild: 16G1618
```

### 11.5 Required dependency versions

For the community fix (pre-built package or Homebrew fallback):

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

Note: As of community fix v1.5.0, pre-built Qt frameworks are automatically downloaded, Rosetta 2 and Xcode CLT are auto-installed, and the game is auto-detected - eliminating all manual setup for most users.

### 11.6 Original game bundle contents

Frameworks:
- QtCore.framework (5.3.2)
- QtGui.framework (5.3.2)
- QtWidgets.framework (5.3.2)
- QtOpenGL.framework (5.3.2)
- QtPrintSupport.framework (5.3.2)
- libQtSolutions_PropertyBrowser-head.1.0.0.dylib
- libfmodevent.dylib (universal i386+x86_64, libstdc++)
- libfmodex.dylib (universal i386+x86_64, libstdc++)
- libcurl.4.dylib
- libsteam_api.dylib (universal i386+x86_64, libstdc++)

PlugIns:
- platforms/libqcocoa.dylib
- imageformats/*.dylib

### 11.7 Deprecated apis summary

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

Repository: https://github.com/cboyd0319/WormsWMD-macOS-Fix
Issues: https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues

---

*This report was prepared based on comprehensive analysis of Worms W.M.D version distributed via Steam as of December 2025, tested on macOS 26.2 (Tahoe) on Apple Silicon (M4 Max). Community fix v1.5.0 verified.*
