#!/bin/bash
#
# 05_verify_installation.sh - Verify the fix was applied correctly
#
# Checks all libraries for problematic references and verifies
# the game should be able to load all dependencies.
#
# NOTE: This script intentionally does NOT use 'set -e' because it needs
# to continue checking all components even if some fail, and collect
# all errors for a comprehensive report.
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGGING_PRESET="${WORMSWMD_LOGGING_INITIALIZED:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)
            WORMSWMD_VERBOSE=1
            shift
            ;;
        --debug)
            WORMSWMD_DEBUG=1
            WORMSWMD_VERBOSE=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--verbose] [--debug]"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            exit 1
            ;;
    esac
done

source "$SCRIPT_DIR/logging.sh"
worms_log_init "05_verify_installation"
worms_debug_init

if [[ -z "$LOGGING_PRESET" ]]; then
    echo "Log file: $LOG_FILE"
    if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
        echo "Trace log: $TRACE_FILE"
    fi
    if worms_verbose_enabled; then
        echo "Verbose logging: enabled"
    fi
fi

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
GAME_FRAMEWORKS="$GAME_APP/Contents/Frameworks"
GAME_PLUGINS="$GAME_APP/Contents/PlugIns"
GAME_EXEC="$GAME_APP/Contents/MacOS/Worms W.M.D"

if [[ -z "$GAME_APP" ]] || [[ ! -d "$GAME_APP/Contents" ]]; then
    echo "ERROR: Game not found at: $GAME_APP"
    echo "Set GAME_APP to your Worms W.M.D.app bundle and re-run."
    exit 1
fi

echo "=== Worms W.M.D Installation Verification ==="
echo ""
echo "Game location: $GAME_APP"
macos_name=$(sw_vers -productName 2>/dev/null || echo "macOS")
macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
arch_name=$(uname -m 2>/dev/null || echo "unknown")
echo "System: $macos_name $macos_version ($arch_name)"
echo ""

errors=0
warnings=0
VERBOSE=false
if worms_verbose_enabled; then
    VERBOSE=true
fi

framework_binary() {
    local fw_dir="$1"
    local fw_name
    fw_name=$(basename "$fw_dir" .framework)

    if [ -f "$fw_dir/Versions/5/$fw_name" ]; then
        echo "$fw_dir/Versions/5/$fw_name"
        return
    fi
    if [ -f "$fw_dir/Versions/A/$fw_name" ]; then
        echo "$fw_dir/Versions/A/$fw_name"
        return
    fi
    if [ -f "$fw_dir/Versions/Current/$fw_name" ]; then
        echo "$fw_dir/Versions/Current/$fw_name"
        return
    fi
    if [ -f "$fw_dir/$fw_name" ]; then
        echo "$fw_dir/$fw_name"
        return
    fi
}

print_deps() {
    local bin="$1"
    local label="$2"

    if ! $VERBOSE; then
        return
    fi

    echo "Dependencies for $label:"
    otool -L "$bin" 2>/dev/null || true
}

check_arch() {
    local bin="$1"
    local label="$2"
    local archs

    archs=$(lipo -archs "$bin" 2>/dev/null || true)
    if [[ -z "$archs" ]]; then
        echo "WARNING: Unable to read architectures for $label"
        ((warnings++))
        return
    fi

    if ! echo "$archs" | tr ' ' '\n' | grep -q "^x86_64$"; then
        echo "ERROR: $label is not x86_64 (archs: $archs)"
        ((errors++))
        return
    fi

    if $VERBOSE; then
        echo "ARCH: $label -> $archs"
    fi
}

check_missing_deps() {
    local bin="$1"
    local dep
    local resolved
    local bin_dir

    bin_dir=$(dirname "$bin")

    while IFS= read -r dep; do
        resolved=""

        if [[ "$dep" == @executable_path/* ]]; then
            resolved="$GAME_APP/Contents/MacOS${dep#@executable_path}"
        elif [[ "$dep" == @loader_path/* ]]; then
            resolved="$bin_dir${dep#@loader_path}"
        else
            continue
        fi

        if [ ! -f "$resolved" ]; then
            echo "ERROR: Missing dependency for $(basename "$bin"): $dep"
            ((errors++))
        fi
    done < <(otool -L "$bin" 2>/dev/null | awk 'NR>1 {print $1}' || true)
}

# Check main executable
echo "--- Checking main executable ---"
if [ ! -f "$GAME_EXEC" ]; then
    echo "ERROR: Main executable not found!"
    ((errors++))
else
    bad_refs=$(otool -L "$GAME_EXEC" 2>/dev/null | grep -E "@rpath|/usr/local" || true)
    if [ -n "$bad_refs" ]; then
        echo "WARNING: Main executable has unresolved references:"
        echo "$bad_refs"
        ((warnings++))
    else
        echo "OK: Main executable references look good"
    fi
    check_arch "$GAME_EXEC" "Main executable"
    check_missing_deps "$GAME_EXEC"
    print_deps "$GAME_EXEC" "Main executable"
fi

# Check frameworks
echo ""
echo "--- Checking frameworks ---"
framework_found=false
for fw_dir in "$GAME_FRAMEWORKS"/*.framework; do
    if [ -d "$fw_dir" ]; then
        fw_name=$(basename "$fw_dir" .framework)
        if [[ "$fw_name" == "AGL" ]]; then
            continue
        fi

        framework_found=true
        lib=$(framework_binary "$fw_dir")
        if [ -z "$lib" ] || [ ! -f "$lib" ]; then
            echo "ERROR: $fw_name.framework binary not found!"
            ((errors++))
            continue
        fi

        bad_refs=$(otool -L "$lib" 2>/dev/null | grep -E "/usr/local|@rpath" | grep -v "@executable_path" || true)
        if [ -n "$bad_refs" ]; then
            echo "WARNING: $fw_name has unresolved references:"
            echo "$bad_refs"
            ((warnings++))
        else
            echo "OK: $fw_name.framework"
        fi
        check_arch "$lib" "$fw_name.framework"
        check_missing_deps "$lib"
        print_deps "$lib" "$fw_name.framework"
    fi
done

if ! $framework_found; then
    echo "ERROR: No frameworks found in $GAME_FRAMEWORKS"
    ((errors++))
else
    qt_core="$GAME_FRAMEWORKS/QtCore.framework/Versions/Current/QtCore"
    if [ ! -f "$qt_core" ]; then
        qt_core="$GAME_FRAMEWORKS/QtCore.framework/Versions/5/QtCore"
    fi
    if [ -f "$qt_core" ]; then
        qt_info=$(otool -L "$qt_core" 2>/dev/null | head -2 || true)
        if echo "$qt_info" | grep -q "5.15"; then
            echo "OK: QtCore 5.15 detected"
        else
            echo "WARNING: QtCore does not appear to be 5.15"
            ((warnings++))
        fi
    else
        echo "WARNING: QtCore.framework not found for version check"
        ((warnings++))
    fi
fi

# Check AGL stub
echo ""
echo "--- Checking AGL stub ---"
if [ ! -f "$GAME_FRAMEWORKS/AGL.framework/Versions/A/AGL" ]; then
    echo "ERROR: AGL stub not found!"
    ((errors++))
else
    arch=$(lipo -archs "$GAME_FRAMEWORKS/AGL.framework/Versions/A/AGL" 2>/dev/null)
    if [ "$arch" = "x86_64" ]; then
        echo "OK: AGL stub (x86_64)"
    else
        echo "WARNING: AGL stub architecture is $arch (expected x86_64)"
        ((warnings++))
    fi
    print_deps "$GAME_FRAMEWORKS/AGL.framework/Versions/A/AGL" "AGL stub"
fi

# Check dylibs
echo ""
echo "--- Checking library dependencies ---"
for lib in "$GAME_FRAMEWORKS"/*.dylib; do
    if [ -f "$lib" ]; then
        name=$(basename "$lib")
        bad_refs=$(otool -L "$lib" 2>/dev/null | grep -E "/usr/local|@rpath" | grep -v "@executable_path" || true)
        if [ -n "$bad_refs" ]; then
            echo "WARNING: $name has unresolved references:"
            echo "$bad_refs"
            ((warnings++))
        fi
        check_arch "$lib" "$name"
        check_missing_deps "$lib"
        print_deps "$lib" "$name"
    fi
done
echo "OK: Library dependencies checked"

# Check plugins
echo ""
echo "--- Checking plugins ---"
for plugin in "$GAME_PLUGINS/platforms/"*.dylib "$GAME_PLUGINS/imageformats/"*.dylib; do
    if [ -f "$plugin" ]; then
        name=$(basename "$plugin")
        bad_refs=$(otool -L "$plugin" 2>/dev/null | grep -E "/usr/local|@rpath" | grep -v "@executable_path" || true)
        if [ -n "$bad_refs" ]; then
            echo "WARNING: $name has unresolved references:"
            echo "$bad_refs"
            ((warnings++))
        fi
        check_arch "$plugin" "$name"
        check_missing_deps "$plugin"
        print_deps "$plugin" "$name"
    fi
done
echo "OK: Plugins checked"

# Summary
echo ""
echo "=== Verification Summary ==="
if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo "SUCCESS: All checks passed!"
    echo ""
    echo "The game should now work. Try launching it from Steam."
    exit 0
elif [ $errors -eq 0 ]; then
    echo "PASSED with $warnings warning(s)"
    echo ""
    echo "The game may work, but there are some potential issues."
    echo "Try launching it from Steam to verify."
    exit 0
else
    echo "FAILED: $errors error(s), $warnings warning(s)"
    echo ""
    echo "The fix may not have been applied correctly."
    echo "Please review the errors above."
    exit 1
fi
