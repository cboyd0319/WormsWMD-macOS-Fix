#!/bin/bash
#
# 02_replace_qt_frameworks.sh - Replace Qt 5.3 with Qt 5.15
#
# Replaces the outdated Qt 5.3.2 frameworks bundled with the game
# with Qt 5.15 from pre-built package or Intel Homebrew.
#
# Environment Variables:
#   QT_PREFIX   - Path to Qt installation (pre-built cache or Homebrew)
#   QT_SOURCE   - "prebuild" or "homebrew"
#

set -euo pipefail

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
GAME_FRAMEWORKS="$GAME_APP/Contents/Frameworks"
GAME_PLUGINS="$GAME_APP/Contents/PlugIns"
GAME_EXEC="$GAME_APP/Contents/MacOS/Worms W.M.D"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGGING_PRESET="${WORMSWMD_LOGGING_INITIALIZED:-}"

# Determine Qt source location
QT_PREFIX="${QT_PREFIX:-/usr/local/opt/qt@5}"
QT_SOURCE="${QT_SOURCE:-homebrew}"

# Set paths based on source type
if [[ "$QT_SOURCE" == "prebuild" ]]; then
    # Pre-built package structure: Frameworks/ and PlugIns/
    NEW_QT="$QT_PREFIX/Frameworks"
    NEW_QT_PLUGINS="$QT_PREFIX/PlugIns"
else
    # Homebrew structure: lib/ and plugins/
    NEW_QT="$QT_PREFIX/lib"
    NEW_QT_PLUGINS="$QT_PREFIX/plugins"
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/logging.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
worms_log_init "02_replace_qt_frameworks"
worms_debug_init

if [[ -z "$LOGGING_PRESET" ]]; then
    echo "Log file: $LOG_FILE"
    if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
        echo "Trace log: $TRACE_FILE"
    fi
fi

if [[ -z "$GAME_APP" ]] || [[ ! -d "$GAME_APP/Contents" ]] || [[ ! -f "$GAME_EXEC" ]]; then
    echo "ERROR: Invalid GAME_APP: $GAME_APP"
    echo "Expected a Worms W.M.D.app bundle containing: $GAME_EXEC"
    exit 1
fi

mkdir -p "$GAME_FRAMEWORKS" "$GAME_PLUGINS/platforms" "$GAME_PLUGINS/imageformats"

echo "=== Replacing Qt Frameworks ==="
echo "Source: $NEW_QT ($QT_SOURCE)"
echo "Target: $GAME_FRAMEWORKS"
echo ""

# Verify source exists
if [ ! -d "$NEW_QT/QtCore.framework" ]; then
    echo "ERROR: Qt 5 not found at $NEW_QT"
    if [[ "$QT_SOURCE" == "homebrew" ]]; then
        echo "Install with: arch -x86_64 /usr/local/bin/brew install qt@5"
    else
        echo "Pre-built package may be corrupted. Try running with --force to re-download."
    fi
    exit 1
fi

FRAMEWORKS=()

append_unique() {
    local name="$1"
    local item

    for item in "${FRAMEWORKS[@]}"; do
        if [[ "$item" == "$name" ]]; then
            return
        fi
    done

    FRAMEWORKS+=("$name")
}

for fw_dir in "$GAME_FRAMEWORKS"/Qt*.framework; do
    if [ -d "$fw_dir" ]; then
        fw_name=$(basename "$fw_dir" .framework)
        append_unique "$fw_name"
    fi
done

if [ ${#FRAMEWORKS[@]} -eq 0 ]; then
    for fw_name in QtCore QtGui QtWidgets QtOpenGL QtPrintSupport; do
        append_unique "$fw_name"
    done
fi

# QtDBus is required by libqcocoa on modern Qt
append_unique "QtDBus"
# QtSvg is required by the imageformats/libqsvg plugin
append_unique "QtSvg"

for fw in "${FRAMEWORKS[@]}"; do
    if [ ! -d "$NEW_QT/$fw.framework" ]; then
        echo "WARNING: $fw.framework not found in $NEW_QT"
        continue
    fi

    echo "Replacing $fw.framework..."

    # Remove old framework
    rm -rf "$GAME_FRAMEWORKS/$fw.framework"

    # Copy new framework
    cp -R "$NEW_QT/$fw.framework" "$GAME_FRAMEWORKS/"

    # Update install name to use @executable_path
    fw_path="$GAME_FRAMEWORKS/$fw.framework"
    fw_bin=$(worms_framework_binary "$fw_path" "$fw" || true)
    if [ -n "$fw_bin" ]; then
        rel_path="${fw_bin#"$fw_path"/}"
        install_name_tool -id "@executable_path/../Frameworks/$fw.framework/$rel_path" \
            "$fw_bin"
    fi
done

echo ""
echo "=== Replacing Qt Plugins ==="

# Replace platform plugin
echo "Replacing libqcocoa.dylib..."
rm -f "$GAME_PLUGINS/platforms/libqcocoa.dylib"
cp "$NEW_QT_PLUGINS/platforms/libqcocoa.dylib" "$GAME_PLUGINS/platforms/"

# Replace image format plugins
# Copy all plugins from Qt 5.15 to ensure compatibility, as some plugins
# may have been renamed or restructured between Qt 5.3 and 5.15
echo "Replacing image format plugins..."
# First, remove old plugins
rm -f "$GAME_PLUGINS/imageformats/"*.dylib 2>/dev/null || true
# Then copy all new plugins
for plugin in "$NEW_QT_PLUGINS/imageformats/"*.dylib; do
    if [ -f "$plugin" ]; then
        name=$(basename "$plugin")
        echo "  Copying $name..."
        cp "$plugin" "$GAME_PLUGINS/imageformats/"
    fi
done

echo ""
echo "Qt frameworks replaced successfully."
