#!/bin/bash
#
# 02_replace_qt_frameworks.sh - Replace Qt 5.3 with Qt 5.15
#
# Replaces the outdated Qt 5.3.2 frameworks bundled with the game
# with Qt 5.15 from Intel Homebrew.
#

set -e

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
GAME_FRAMEWORKS="$GAME_APP/Contents/Frameworks"
NEW_QT="${NEW_QT:-/usr/local/opt/qt@5/lib}"
NEW_QT_PLUGINS="${NEW_QT_PLUGINS:-/usr/local/opt/qt@5/plugins}"
GAME_PLUGINS="$GAME_APP/Contents/PlugIns"
GAME_EXEC="$GAME_APP/Contents/MacOS/Worms W.M.D"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGGING_PRESET="${WORMSWMD_LOGGING_INITIALIZED:-}"

source "$SCRIPT_DIR/logging.sh"
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
echo "Source: $NEW_QT"
echo "Target: $GAME_FRAMEWORKS"
echo ""

# Verify source exists
if [ ! -d "$NEW_QT/QtCore.framework" ]; then
    echo "ERROR: Qt 5 not found at $NEW_QT"
    echo "Install with: arch -x86_64 /usr/local/bin/brew install qt@5"
    exit 1
fi

framework_binary() {
    local fw_dir="$1"
    local fw_name="$2"

    if [ -f "$fw_dir/Versions/5/$fw_name" ]; then
        echo "$fw_dir/Versions/5/$fw_name"
        return
    fi
    if [ -f "$fw_dir/Versions/Current/$fw_name" ]; then
        echo "$fw_dir/Versions/Current/$fw_name"
        return
    fi
    if [ -f "$fw_dir/Versions/A/$fw_name" ]; then
        echo "$fw_dir/Versions/A/$fw_name"
        return
    fi
    if [ -f "$fw_dir/$fw_name" ]; then
        echo "$fw_dir/$fw_name"
        return
    fi
}

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
    fw_bin=$(framework_binary "$fw_path" "$fw")
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
