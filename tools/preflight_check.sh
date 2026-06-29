#!/bin/bash
#
# preflight_check.sh - Pre-flight verification for Worms W.M.D
#
# Comprehensive check of system requirements, game installation,
# fix status, and optional public endpoint reachability before launching the game.
#
# Usage:
#   ./preflight_check.sh [--verbose] [--quick]
#
# Options:
#   --verbose    Show detailed diagnostic information
#   --quick      Skip public endpoint checks for faster results
#

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$REPO_DIR/scripts/ui.sh"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/common.sh"
worms_color_init auto

# Default game location
DEFAULT_GAME_PATH="$(worms_default_game_app)"
GAME_APP="${GAME_APP:-$DEFAULT_GAME_PATH}"

VERBOSE=false
QUICK=false
ERRORS=0
WARNINGS=0
CURL_BASE=(--proto '=https' --tlsv1.2 --max-time 5 --silent)
INTEL_TRANSLATION_AVAILABLE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --quick|-q)
            QUICK=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--verbose] [--quick]"
            echo ""
            echo "Pre-flight verification for Worms W.M.D on macOS."
            echo ""
            echo "Options:"
            echo "  --verbose, -v    Show detailed diagnostic information"
            echo "  --quick, -q      Skip public endpoint checks for faster results"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ "$GAME_APP" == "$DEFAULT_GAME_PATH" ]] && [[ ! -d "$GAME_APP" ]]; then
    detected_game=$(worms_first_detected_game_app || true)
    if [[ -n "$detected_game" ]]; then
        GAME_APP="$detected_game"
    fi
fi

# Helper functions
check_pass() {
    printf '%b\n' "${GREEN}[PASS]${RESET} $1"
}

check_fail() {
    printf '%b\n' "${RED}[FAIL]${RESET} $1"
    ((ERRORS++)) || true
}

check_warn() {
    printf '%b\n' "${YELLOW}[WARN]${RESET} $1"
    ((WARNINGS++)) || true
}

check_info() {
    if $VERBOSE; then
        printf '%b\n' "${BLUE}[INFO]${RESET} $1"
    fi
}

binary_archs() {
    local bin="$1"
    local archs

    archs=$(lipo -archs "$bin" 2>/dev/null || true)
    if [[ -n "$archs" ]]; then
        printf '%s\n' "$archs"
        return 0
    fi

    archs=$(file "$bin" 2>/dev/null | grep -o 'x86_64\|arm64' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//' || true)
    printf '%s\n' "${archs:-unknown}"
}

http_status() {
    local url="$1"
    local status

    status=$(curl "${CURL_BASE[@]}" -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
    printf '%s\n' "${status:-000}"
}

section() {
    echo ""
    printf '%b\n' "${BOLD}=== $1 ===${RESET}"
}

# ============================================================================
# System Checks
# ============================================================================

section "System Requirements"

# Check required tools
HAVE_OTOOL=true
if ! command -v otool >/dev/null 2>&1; then
    HAVE_OTOOL=false
    check_warn "otool not available - skipping Qt/AGL library checks"
fi

if ! $QUICK; then
    if ! command -v curl >/dev/null 2>&1; then
        check_warn "curl not available - skipping public endpoint checks"
        QUICK=true
    fi
fi

# Check macOS version
macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
macos_major=$(echo "$macos_version" | cut -d. -f1)
echo "macOS version: $macos_version"

if [[ "$macos_major" =~ ^[0-9]+$ ]] && [[ "$macos_major" -ge 27 ]]; then
    check_warn "macOS 27 (Golden Gate) detected - fix is REQUIRED and Intel game support is transitional"
elif [[ "$macos_major" =~ ^[0-9]+$ ]] && [[ "$macos_major" -ge 26 ]]; then
    check_warn "macOS 26 (Tahoe) detected - fix is REQUIRED"
elif [[ "$macos_major" =~ ^[0-9]+$ ]] && [[ "$macos_major" -ge 15 ]]; then
    check_info "macOS 15 (Sequoia) - fix may be needed"
else
    check_pass "macOS version should work without fix"
fi

# Check architecture
arch=$(uname -m)
echo "Architecture: $arch"

if [[ "$arch" == "arm64" ]]; then
    check_info "Apple Silicon detected - Rosetta required"

    # Check Rosetta 2
    if /usr/bin/pgrep -q oahd 2>/dev/null; then
        INTEL_TRANSLATION_AVAILABLE=true
        check_pass "Rosetta 2 is running"
    elif [[ -f "/Library/Apple/usr/libexec/oah/libRosettaRuntime" ]]; then
        INTEL_TRANSLATION_AVAILABLE=true
        check_pass "Rosetta 2 is installed"
    else
        # Try to check via arch command
        if arch -x86_64 /usr/bin/true 2>/dev/null; then
            INTEL_TRANSLATION_AVAILABLE=true
            check_pass "Rosetta 2 is functional"
        elif [[ "$macos_major" =~ ^[0-9]+$ ]] && [[ "$macos_major" -ge 27 ]]; then
            check_fail "Rosetta is required but unavailable"
            echo "       Worms W.M.D is an older Intel Mac game."
            echo "       macOS 27 may need Rosetta reinstalled after upgrading."
            echo "       Install Rosetta, then run the launcher again and choose option 3:"
            echo "       softwareupdate --install-rosetta --agree-to-license"
        else
            check_fail "Rosetta 2 not installed - run: softwareupdate --install-rosetta"
        fi
    fi

    # Check Rosetta runtime libraries
    if [[ -f "/Library/Apple/usr/lib/libRosettaAot.dylib" ]]; then
        check_pass "Rosetta runtime libraries present"
    else
        check_warn "Rosetta runtime libraries not found in expected location"
    fi
else
    check_pass "Intel Mac - native execution"
fi

# Check Xcode Command Line Tools (needed for fix)
if xcode-select -p &>/dev/null; then
    check_pass "Xcode Command Line Tools installed"
else
    check_warn "Xcode CLT not installed - needed to apply fix"
fi

# ============================================================================
# Game Installation Checks
# ============================================================================

section "Game Installation"

if [[ -d "$GAME_APP" ]]; then
    check_pass "Game found at: $GAME_APP"
else
    check_fail "Game not found at: $GAME_APP"
    if [[ "$GAME_APP" == "$DEFAULT_GAME_PATH" ]]; then
        echo "       Searched common Steam, GOG, Applications, and Games folders"
    fi
    echo "       Install via Steam or set GAME_APP environment variable"
    # Can't continue without game
    section "Summary"
    echo "Errors: $ERRORS, Warnings: $WARNINGS"
    exit 1
fi

# Check main executable
GAME_EXEC="$GAME_APP/Contents/MacOS/Worms W.M.D"
if [[ -x "$GAME_EXEC" ]]; then
    check_pass "Main executable found and executable"

    # Check architecture
    exec_arch=$(binary_archs "$GAME_EXEC")
    check_info "Executable architecture: $exec_arch"
else
    check_fail "Main executable not found or not executable"
fi

# Check bundle size
bundle_size=$(du -sh "$GAME_APP" 2>/dev/null | cut -f1)
check_info "Bundle size: $bundle_size"

# ============================================================================
# Fix Status Checks
# ============================================================================

section "Fix Status"

FRAMEWORKS_DIR="$GAME_APP/Contents/Frameworks"
PLUGINS_DIR="$GAME_APP/Contents/PlugIns"

# Check AGL stub
agl_stub="$FRAMEWORKS_DIR/AGL.framework/Versions/A/AGL"
if [[ -f "$agl_stub" ]]; then
    agl_arch=$(binary_archs "$agl_stub")
    if echo "$agl_arch" | tr ' ' '\n' | grep -qx "x86_64"; then
        check_pass "AGL stub installed (arch: $agl_arch)"
    else
        check_fail "AGL stub does not include x86_64 architecture (arch: $agl_arch)"
    fi
else
    if [[ "$macos_major" =~ ^[0-9]+$ ]] && [[ "$macos_major" -ge 26 ]]; then
        check_fail "AGL stub binary NOT installed - game will not launch on macOS 26+"
    else
        check_info "AGL stub not installed (may not be needed)"
    fi
fi

# Check Qt version
if [[ -f "$FRAMEWORKS_DIR/QtCore.framework/Versions/5/QtCore" ]]; then
    if $HAVE_OTOOL; then
        qt_version=$(otool -L "$FRAMEWORKS_DIR/QtCore.framework/Versions/5/QtCore" 2>/dev/null \
            | sed -n '/QtCore.*current version/ {
                s/.*current version \([0-9][0-9.]*\)).*/\1/p
                q
            }' || true)
        if [[ -z "$qt_version" ]]; then
            qt_version=$(otool -L "$FRAMEWORKS_DIR/QtCore.framework/Versions/5/QtCore" 2>/dev/null | grep "QtCore" | grep -o "5\.[0-9]*\.[0-9]*" | head -1 || echo "unknown")
        fi

        if [[ "$qt_version" == "5.15"* ]]; then
            check_pass "Qt version: $qt_version (updated)"
        elif [[ "$qt_version" == "5.3"* ]]; then
            check_warn "Qt version: $qt_version (outdated - fix needed)"
        else
            check_info "Qt version: $qt_version"
        fi
    else
        check_warn "QtCore present but version could not be checked (otool missing)"
    fi
else
    check_fail "QtCore framework not found"
fi

for required_fw in QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus QtSvg; do
    if [[ -d "$FRAMEWORKS_DIR/$required_fw.framework" ]]; then
        check_pass "$required_fw.framework present"
    else
        check_fail "$required_fw.framework not found"
    fi
done

# Check for AGL dependencies in Qt
if [[ -f "$FRAMEWORKS_DIR/QtGui.framework/Versions/5/QtGui" ]]; then
    if $HAVE_OTOOL; then
        if otool -L "$FRAMEWORKS_DIR/QtGui.framework/Versions/5/QtGui" 2>/dev/null | grep -q "/System/Library/Frameworks/AGL.framework"; then
            check_warn "QtGui still references system AGL (fix may not be complete)"
        else
            check_pass "QtGui does not reference system AGL"
        fi
    else
        check_warn "QtGui present but AGL reference check skipped (otool missing)"
    fi
else
    check_warn "QtGui framework not found"
fi

if [[ -f "$PLUGINS_DIR/platforms/libqcocoa.dylib" ]]; then
    check_pass "Qt platform plugin present"
else
    check_fail "Qt platform plugin not found"
fi

if [[ -f "$PLUGINS_DIR/imageformats/libqsvg.dylib" ]]; then
    check_pass "Qt SVG image plugin present"
else
    check_fail "Qt SVG image plugin not found"
fi

# Check code signing
sign_status=$(codesign -dv "$GAME_APP" 2>&1 || true)
if echo "$sign_status" | grep -q "not signed"; then
    check_warn "App is not signed (may trigger Gatekeeper warnings)"
elif echo "$sign_status" | grep -q "adhoc"; then
    check_pass "App has ad-hoc signature"
else
    check_pass "App is signed"
fi

# ============================================================================
# Runtime Dependencies
# ============================================================================

section "Runtime Dependencies"

# Check FMOD libraries
if [[ -f "$FRAMEWORKS_DIR/libfmodex.dylib" ]]; then
    fmod_deps=$(otool -L "$FRAMEWORKS_DIR/libfmodex.dylib" 2>/dev/null | grep -cE "libstdc\+\+|libgcc_s" || true)
    if [[ "$fmod_deps" -gt 0 ]]; then
        check_warn "FMOD uses deprecated runtime (relies on Rosetta 2 compatibility)"
    else
        check_pass "FMOD libraries present"
    fi
else
    check_fail "FMOD libraries not found"
fi

# Check Steam API
if [[ -f "$FRAMEWORKS_DIR/libsteam_api.dylib" ]]; then
    check_pass "Steam API library present"
else
    check_warn "Steam API library not found"
fi

# Check libcurl
if [[ -f "$FRAMEWORKS_DIR/libcurl.4.dylib" ]]; then
    check_pass "libcurl present"
else
    check_warn "libcurl not found"
fi

# ============================================================================
# Public Endpoint Reachability (optional)
# ============================================================================

if ! $QUICK; then
    section "Public Endpoint Reachability"

    team17_status=$(http_status "https://www.team17.com/games/worms-w-m-d")
    if [[ "$team17_status" == 2* || "$team17_status" == 3* ]]; then
        check_pass "Team17 Worms W.M.D page reachable"
    else
        check_warn "Team17 Worms W.M.D page not reachable (HTTP $team17_status)"
    fi

    steam_status=$(http_status "https://store.steampowered.com/app/327030/Worms_WMD/")
    if [[ "$steam_status" == 2* || "$steam_status" == 3* ]]; then
        check_pass "Steam Worms W.M.D store page reachable"
    else
        check_warn "Steam Worms W.M.D store page not reachable (HTTP $steam_status)"
    fi

    gog_status=$(http_status "https://www.gog.com/en/game/worms_wmd")
    if [[ "$gog_status" == 2* || "$gog_status" == 3* ]]; then
        check_pass "GOG Worms W.M.D store page reachable"
    else
        check_warn "GOG Worms W.M.D store page not reachable (HTTP $gog_status)"
    fi
else
    check_info "Public endpoint checks skipped (--quick mode)"
fi

# ============================================================================
# Rosetta Notes
# ============================================================================

if [[ "$arch" == "arm64" ]]; then
    section "Rosetta Notes"

    if $INTEL_TRANSLATION_AVAILABLE; then
        check_info "For best performance on Apple Silicon:"
        echo "       - Close unnecessary apps to free memory"
        echo "       - First launch may be slower (translation caching)"
        echo "       - Subsequent launches will be faster"
    else
        echo "       - Install Rosetta, then run the launcher again and choose option 3"
        echo "       - If it still fails, choose option 5 to create a support bundle"
    fi

    # Check if ROSETTA_ADVERTISE_AVX is set
    if [[ -n "${ROSETTA_ADVERTISE_AVX:-}" ]]; then
        check_info "ROSETTA_ADVERTISE_AVX is set: $ROSETTA_ADVERTISE_AVX"
    fi
fi

# ============================================================================
# Summary
# ============================================================================

section "Summary"

if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo "${GREEN}${BOLD}All checks passed!${RESET} The game should launch successfully."
elif [[ $ERRORS -eq 0 ]]; then
    echo "${YELLOW}${BOLD}$WARNINGS warning(s)${RESET} - game may work but some issues detected."
else
    echo "${RED}${BOLD}$ERRORS error(s), $WARNINGS warning(s)${RESET} - fix required before launching."
fi

echo ""

# Exit with appropriate code
if [[ $ERRORS -gt 0 ]]; then
    exit 1
else
    exit 0
fi
