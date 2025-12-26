#!/bin/bash
#
# preflight_check.sh - Pre-flight verification for Worms W.M.D
#
# Comprehensive check of system requirements, game installation,
# fix status, and network connectivity before launching the game.
#
# Usage:
#   ./preflight_check.sh [--verbose] [--quick]
#
# Options:
#   --verbose    Show detailed diagnostic information
#   --quick      Skip network checks for faster results
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$REPO_DIR/scripts/ui.sh"
worms_color_init auto

# Default game location
GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"

VERBOSE=false
QUICK=false
ERRORS=0
WARNINGS=0

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
            echo "  --quick, -q      Skip network checks for faster results"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper functions
check_pass() {
    echo "${GREEN}[PASS]${RESET} $1"
}

check_fail() {
    echo "${RED}[FAIL]${RESET} $1"
    ((ERRORS++)) || true
}

check_warn() {
    echo "${YELLOW}[WARN]${RESET} $1"
    ((WARNINGS++)) || true
}

check_info() {
    if $VERBOSE; then
        echo "${BLUE}[INFO]${RESET} $1"
    fi
}

section() {
    echo ""
    echo "${BOLD}=== $1 ===${RESET}"
}

# ============================================================================
# System Checks
# ============================================================================

section "System Requirements"

# Check macOS version
macos_version=$(sw_vers -productVersion)
macos_major=$(echo "$macos_version" | cut -d. -f1)
echo "macOS version: $macos_version"

if [[ "$macos_major" -ge 26 ]]; then
    check_warn "macOS 26 (Tahoe) detected - fix is REQUIRED"
elif [[ "$macos_major" -ge 15 ]]; then
    check_info "macOS 15 (Sequoia) - fix may be needed"
else
    check_pass "macOS version should work without fix"
fi

# Check architecture
arch=$(uname -m)
echo "Architecture: $arch"

if [[ "$arch" == "arm64" ]]; then
    check_info "Apple Silicon detected - Rosetta 2 required"

    # Check Rosetta 2
    if /usr/bin/pgrep -q oahd 2>/dev/null; then
        check_pass "Rosetta 2 is running"
    elif [[ -f "/Library/Apple/usr/libexec/oah/libRosettaRuntime" ]]; then
        check_pass "Rosetta 2 is installed"
    else
        # Try to check via arch command
        if arch -x86_64 /usr/bin/true 2>/dev/null; then
            check_pass "Rosetta 2 is functional"
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
    exec_arch=$(file "$GAME_EXEC" | grep -o 'x86_64\|arm64' | head -1)
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

# Check AGL stub
if [[ -d "$FRAMEWORKS_DIR/AGL.framework" ]]; then
    agl_arch=$(file "$FRAMEWORKS_DIR/AGL.framework/Versions/A/AGL" 2>/dev/null | grep -o 'x86_64\|arm64' | tr '\n' '+' | sed 's/+$//')
    check_pass "AGL stub installed (arch: $agl_arch)"
else
    if [[ "$macos_major" -ge 26 ]]; then
        check_fail "AGL stub NOT installed - game will not launch on macOS 26+"
    else
        check_info "AGL stub not installed (may not be needed)"
    fi
fi

# Check Qt version
if [[ -f "$FRAMEWORKS_DIR/QtCore.framework/Versions/5/QtCore" ]]; then
    qt_version=$(otool -L "$FRAMEWORKS_DIR/QtCore.framework/Versions/5/QtCore" 2>/dev/null | grep "QtCore" | grep -o "5\.[0-9]*\.[0-9]*" | head -1 || echo "unknown")

    if [[ "$qt_version" == "5.15"* ]]; then
        check_pass "Qt version: $qt_version (updated)"
    elif [[ "$qt_version" == "5.3"* ]]; then
        check_warn "Qt version: $qt_version (outdated - fix needed)"
    else
        check_info "Qt version: $qt_version"
    fi
else
    check_fail "QtCore framework not found"
fi

# Check for AGL dependencies in Qt
if otool -L "$FRAMEWORKS_DIR/QtGui.framework/Versions/5/QtGui" 2>/dev/null | grep -q "/System/Library/Frameworks/AGL.framework"; then
    check_warn "QtGui still references system AGL (fix may not be complete)"
else
    check_pass "QtGui does not reference system AGL"
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
# Network Connectivity (optional)
# ============================================================================

if ! $QUICK; then
    section "Network Connectivity"

    # Check Team17 services
    if curl -s --max-time 5 -o /dev/null -w "%{http_code}" "https://ads.t17service.com" 2>/dev/null | grep -q "^[23]"; then
        check_pass "Team17 directory service reachable"
    else
        check_warn "Team17 directory service not reachable (multiplayer may not work)"
    fi

    # Check Steam
    if curl -s --max-time 5 -o /dev/null "https://steamcommunity.com" 2>/dev/null; then
        check_pass "Steam community reachable"
    else
        check_warn "Steam community not reachable"
    fi
else
    check_info "Network checks skipped (--quick mode)"
fi

# ============================================================================
# Rosetta 2 Performance Hints
# ============================================================================

if [[ "$arch" == "arm64" ]]; then
    section "Rosetta 2 Optimization"

    check_info "For best performance on Apple Silicon:"
    echo "       - Close unnecessary apps to free memory"
    echo "       - First launch may be slower (Rosetta translation caching)"
    echo "       - Subsequent launches will be faster"

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
