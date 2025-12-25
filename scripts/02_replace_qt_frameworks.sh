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

# Frameworks to replace
FRAMEWORKS="QtCore QtGui QtWidgets QtOpenGL QtPrintSupport"

for fw in $FRAMEWORKS; do
    echo "Replacing $fw.framework..."

    # Remove old framework
    rm -rf "$GAME_FRAMEWORKS/$fw.framework"

    # Copy new framework
    cp -R "$NEW_QT/$fw.framework" "$GAME_FRAMEWORKS/"

    # Update install name to use @executable_path
    install_name_tool -id "@executable_path/../Frameworks/$fw.framework/Versions/5/$fw" \
        "$GAME_FRAMEWORKS/$fw.framework/Versions/5/$fw"
done

# Add QtDBus (required by libqcocoa)
echo "Adding QtDBus.framework..."
rm -rf "$GAME_FRAMEWORKS/QtDBus.framework"
cp -R "$NEW_QT/QtDBus.framework" "$GAME_FRAMEWORKS/"
install_name_tool -id "@executable_path/../Frameworks/QtDBus.framework/Versions/5/QtDBus" \
    "$GAME_FRAMEWORKS/QtDBus.framework/Versions/5/QtDBus"

echo ""
echo "=== Replacing Qt Plugins ==="

# Replace platform plugin
echo "Replacing libqcocoa.dylib..."
rm -f "$GAME_PLUGINS/platforms/libqcocoa.dylib"
cp "$NEW_QT_PLUGINS/platforms/libqcocoa.dylib" "$GAME_PLUGINS/platforms/"

# Replace image format plugins (only those that exist in the game)
echo "Replacing image format plugins..."
for plugin in "$NEW_QT_PLUGINS/imageformats/"*.dylib; do
    name=$(basename "$plugin")
    if [ -f "$GAME_PLUGINS/imageformats/$name" ]; then
        echo "  Replacing $name..."
        rm -f "$GAME_PLUGINS/imageformats/$name"
        cp "$plugin" "$GAME_PLUGINS/imageformats/"
    fi
done

echo ""
echo "Qt frameworks replaced successfully."
