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
echo ""

errors=0
warnings=0

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
fi

# Check frameworks
echo ""
echo "--- Checking frameworks ---"
for fw in QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus; do
    lib="$GAME_FRAMEWORKS/$fw.framework/Versions/5/$fw"
    if [ ! -f "$lib" ]; then
        echo "ERROR: $fw.framework not found!"
        ((errors++))
    else
        bad_refs=$(otool -L "$lib" 2>/dev/null | grep -E "/usr/local|@rpath" | grep -v "@executable_path" || true)
        if [ -n "$bad_refs" ]; then
            echo "WARNING: $fw has unresolved references:"
            echo "$bad_refs"
            ((warnings++))
        else
            echo "OK: $fw.framework"
        fi
    fi
done

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
