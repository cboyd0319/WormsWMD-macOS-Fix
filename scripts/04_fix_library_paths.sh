#!/bin/bash
#
# 04_fix_library_paths.sh - Fix all library path references
#
# Updates all library references to use @executable_path instead
# of absolute paths like /usr/local/opt/...
#
# This script dynamically detects installed library versions to handle
# different Homebrew package versions across systems.
#

set -e

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
GAME_FRAMEWORKS="$GAME_APP/Contents/Frameworks"
GAME_PLUGINS="$GAME_APP/Contents/PlugIns"
GAME_EXEC="$GAME_APP/Contents/MacOS/Worms W.M.D"
BUILD_DIR="/tmp/agl_stub_build"

echo "=== Fixing Library Path References ==="

# Dynamically detect installed versions
QT_VERSION=$(ls /usr/local/Cellar/qt@5/ 2>/dev/null | head -1 || echo "")
GLIB_VERSION=$(ls /usr/local/Cellar/glib/ 2>/dev/null | head -1 || echo "")

# Build list of prefixes dynamically
PREFIXES="/usr/local/opt/qt@5/lib"
if [ -n "$QT_VERSION" ]; then
    PREFIXES="$PREFIXES /usr/local/Cellar/qt@5/$QT_VERSION/lib"
fi
PREFIXES="$PREFIXES /usr/local/opt/pcre2/lib /usr/local/opt/zstd/lib /usr/local/opt/glib/lib"
if [ -n "$GLIB_VERSION" ]; then
    PREFIXES="$PREFIXES /usr/local/Cellar/glib/$GLIB_VERSION/lib"
fi
PREFIXES="$PREFIXES /usr/local/opt/gettext/lib /usr/local/opt/libpng/lib /usr/local/opt/md4c/lib /usr/local/opt/freetype/lib /usr/local/opt/jpeg-turbo/lib /usr/local/opt/libtiff/lib /usr/local/opt/xz/lib /usr/local/opt/webp/lib"

echo "Detected Qt version: ${QT_VERSION:-unknown}"
echo "Detected GLib version: ${GLIB_VERSION:-unknown}"

# Install AGL stub
echo ""
echo "--- Installing AGL stub framework ---"
if [ -f "$BUILD_DIR/AGL" ]; then
    mkdir -p "$GAME_FRAMEWORKS/AGL.framework/Versions/A"
    cp "$BUILD_DIR/AGL" "$GAME_FRAMEWORKS/AGL.framework/Versions/A/AGL"
    ln -sf A "$GAME_FRAMEWORKS/AGL.framework/Versions/Current"
    ln -sf Versions/Current/AGL "$GAME_FRAMEWORKS/AGL.framework/AGL"
    echo "AGL stub installed"
else
    echo "WARNING: AGL stub not found at $BUILD_DIR/AGL"
    echo "Run 01_build_agl_stub.sh first"
fi

# Fix main executable
echo ""
echo "--- Fixing main executable ---"
install_name_tool -change \
    "@rpath/libcurl.4.dylib" \
    "@executable_path/../Frameworks/libcurl.4.dylib" \
    "$GAME_EXEC" 2>/dev/null || true

install_name_tool -id \
    "@executable_path/../Frameworks/libcurl.4.dylib" \
    "$GAME_FRAMEWORKS/libcurl.4.dylib" 2>/dev/null || true

# Framework list
FRAMEWORKS="QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus"

# Dylib dependencies
DYLIBS="libpcre2-16.0.dylib libpcre2-8.0.dylib libzstd.1.dylib libgthread-2.0.0.dylib libglib-2.0.0.dylib libintl.8.dylib libpng16.16.dylib libmd4c.0.dylib libfreetype.6.dylib libjpeg.8.dylib libtiff.6.dylib liblzma.5.dylib libwebp.7.dylib libwebpdemux.2.dylib libwebpmux.3.dylib libsharpyuv.0.dylib"

echo ""
echo "--- Fixing Qt framework references ---"
for fw in $FRAMEWORKS; do
    lib="$GAME_FRAMEWORKS/$fw.framework/Versions/5/$fw"
    if [ -f "$lib" ]; then
        echo "Fixing $fw..."

        # Fix references to other Qt frameworks
        for dep_fw in $FRAMEWORKS; do
            for prefix in $PREFIXES; do
                install_name_tool -change \
                    "$prefix/$dep_fw.framework/Versions/5/$dep_fw" \
                    "@executable_path/../Frameworks/$dep_fw.framework/Versions/5/$dep_fw" \
                    "$lib" 2>/dev/null || true
            done
        done

        # Fix references to dylibs
        for dylib in $DYLIBS; do
            for prefix in $PREFIXES; do
                install_name_tool -change \
                    "$prefix/$dylib" \
                    "@executable_path/../Frameworks/$dylib" \
                    "$lib" 2>/dev/null || true
            done
        done
    fi
done

echo ""
echo "--- Fixing copied library references ---"

# Fix libfreetype
install_name_tool -change \
    "/usr/local/opt/libpng/lib/libpng16.16.dylib" \
    "@executable_path/../Frameworks/libpng16.16.dylib" \
    "$GAME_FRAMEWORKS/libfreetype.6.dylib" 2>/dev/null || true

# Fix libglib
install_name_tool -change \
    "/usr/local/opt/gettext/lib/libintl.8.dylib" \
    "@executable_path/../Frameworks/libintl.8.dylib" \
    "$GAME_FRAMEWORKS/libglib-2.0.0.dylib" 2>/dev/null || true
install_name_tool -change \
    "/usr/local/opt/pcre2/lib/libpcre2-8.0.dylib" \
    "@executable_path/../Frameworks/libpcre2-8.0.dylib" \
    "$GAME_FRAMEWORKS/libglib-2.0.0.dylib" 2>/dev/null || true

# Fix libgthread - handle any glib version
install_name_tool -change \
    "/usr/local/opt/glib/lib/libglib-2.0.0.dylib" \
    "@executable_path/../Frameworks/libglib-2.0.0.dylib" \
    "$GAME_FRAMEWORKS/libgthread-2.0.0.dylib" 2>/dev/null || true

if [ -n "$GLIB_VERSION" ]; then
    install_name_tool -change \
        "/usr/local/Cellar/glib/$GLIB_VERSION/lib/libglib-2.0.0.dylib" \
        "@executable_path/../Frameworks/libglib-2.0.0.dylib" \
        "$GAME_FRAMEWORKS/libgthread-2.0.0.dylib" 2>/dev/null || true
fi

# Fix libtiff
install_name_tool -change \
    "/usr/local/opt/zstd/lib/libzstd.1.dylib" \
    "@executable_path/../Frameworks/libzstd.1.dylib" \
    "$GAME_FRAMEWORKS/libtiff.6.dylib" 2>/dev/null || true
install_name_tool -change \
    "/usr/local/opt/xz/lib/liblzma.5.dylib" \
    "@executable_path/../Frameworks/liblzma.5.dylib" \
    "$GAME_FRAMEWORKS/libtiff.6.dylib" 2>/dev/null || true
install_name_tool -change \
    "/usr/local/opt/jpeg-turbo/lib/libjpeg.8.dylib" \
    "@executable_path/../Frameworks/libjpeg.8.dylib" \
    "$GAME_FRAMEWORKS/libtiff.6.dylib" 2>/dev/null || true

# Fix webp libraries
install_name_tool -change "@rpath/libsharpyuv.0.dylib" "@executable_path/../Frameworks/libsharpyuv.0.dylib" "$GAME_FRAMEWORKS/libwebp.7.dylib" 2>/dev/null || true
install_name_tool -change "@rpath/libwebp.7.dylib" "@executable_path/../Frameworks/libwebp.7.dylib" "$GAME_FRAMEWORKS/libwebpdemux.2.dylib" 2>/dev/null || true
install_name_tool -change "@rpath/libsharpyuv.0.dylib" "@executable_path/../Frameworks/libsharpyuv.0.dylib" "$GAME_FRAMEWORKS/libwebpdemux.2.dylib" 2>/dev/null || true
install_name_tool -change "@rpath/libwebp.7.dylib" "@executable_path/../Frameworks/libwebp.7.dylib" "$GAME_FRAMEWORKS/libwebpmux.3.dylib" 2>/dev/null || true
install_name_tool -change "@rpath/libsharpyuv.0.dylib" "@executable_path/../Frameworks/libsharpyuv.0.dylib" "$GAME_FRAMEWORKS/libwebpmux.3.dylib" 2>/dev/null || true

echo ""
echo "--- Fixing plugins ---"

# Fix platform plugin
if [ -f "$GAME_PLUGINS/platforms/libqcocoa.dylib" ]; then
    echo "Fixing libqcocoa.dylib..."
    install_name_tool -id "@executable_path/../PlugIns/platforms/libqcocoa.dylib" \
        "$GAME_PLUGINS/platforms/libqcocoa.dylib" 2>/dev/null || true

    install_name_tool -change \
        "/usr/local/opt/qt@5/plugins/platforms/libqcocoa.dylib" \
        "@executable_path/../PlugIns/platforms/libqcocoa.dylib" \
        "$GAME_PLUGINS/platforms/libqcocoa.dylib" 2>/dev/null || true

    for fw in $FRAMEWORKS; do
        for prefix in $PREFIXES; do
            install_name_tool -change \
                "$prefix/$fw.framework/Versions/5/$fw" \
                "@executable_path/../Frameworks/$fw.framework/Versions/5/$fw" \
                "$GAME_PLUGINS/platforms/libqcocoa.dylib" 2>/dev/null || true
        done
    done

    install_name_tool -change \
        "/usr/local/opt/freetype/lib/libfreetype.6.dylib" \
        "@executable_path/../Frameworks/libfreetype.6.dylib" \
        "$GAME_PLUGINS/platforms/libqcocoa.dylib" 2>/dev/null || true
fi

# Fix image format plugins
for plugin in "$GAME_PLUGINS/imageformats/"*.dylib; do
    if [ -f "$plugin" ]; then
        name=$(basename "$plugin")
        echo "Fixing $name..."

        install_name_tool -id "@executable_path/../PlugIns/imageformats/$name" "$plugin" 2>/dev/null || true

        install_name_tool -change \
            "/usr/local/opt/qt@5/plugins/imageformats/$name" \
            "@executable_path/../PlugIns/imageformats/$name" \
            "$plugin" 2>/dev/null || true

        for fw in $FRAMEWORKS; do
            for prefix in $PREFIXES; do
                install_name_tool -change \
                    "$prefix/$fw.framework/Versions/5/$fw" \
                    "@executable_path/../Frameworks/$fw.framework/Versions/5/$fw" \
                    "$plugin" 2>/dev/null || true
            done
        done

        # Fix external library references
        install_name_tool -change "/usr/local/opt/jpeg-turbo/lib/libjpeg.8.dylib" "@executable_path/../Frameworks/libjpeg.8.dylib" "$plugin" 2>/dev/null || true
        install_name_tool -change "/usr/local/opt/libtiff/lib/libtiff.6.dylib" "@executable_path/../Frameworks/libtiff.6.dylib" "$plugin" 2>/dev/null || true
        install_name_tool -change "/usr/local/opt/webp/lib/libwebpmux.3.dylib" "@executable_path/../Frameworks/libwebpmux.3.dylib" "$plugin" 2>/dev/null || true
        install_name_tool -change "/usr/local/opt/webp/lib/libwebpdemux.2.dylib" "@executable_path/../Frameworks/libwebpdemux.2.dylib" "$plugin" 2>/dev/null || true
        install_name_tool -change "/usr/local/opt/webp/lib/libwebp.7.dylib" "@executable_path/../Frameworks/libwebp.7.dylib" "$plugin" 2>/dev/null || true
    fi
done

# Fix AGL references in all libraries that might need it
echo ""
echo "--- Fixing AGL references ---"
OLD_AGL="/System/Library/Frameworks/AGL.framework/Versions/A/AGL"
NEW_AGL="@executable_path/../Frameworks/AGL.framework/Versions/A/AGL"

for lib in "$GAME_FRAMEWORKS"/*.dylib; do
    install_name_tool -change "$OLD_AGL" "$NEW_AGL" "$lib" 2>/dev/null || true
done

for fw in $FRAMEWORKS; do
    lib="$GAME_FRAMEWORKS/$fw.framework/Versions/5/$fw"
    if [ -f "$lib" ]; then
        install_name_tool -change "$OLD_AGL" "$NEW_AGL" "$lib" 2>/dev/null || true
    fi
done

echo ""
echo "Library path fixes complete."
