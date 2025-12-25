#!/bin/bash
#
# 03_copy_dependencies.sh - Copy Qt external dependencies
#
# Qt 5.15 from Homebrew depends on several external libraries.
# This script copies them into the game's Frameworks folder.
#

set -e

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
GAME_FRAMEWORKS="$GAME_APP/Contents/Frameworks"

echo "=== Copying Qt External Dependencies ==="

# All required dependencies
DEPS=(
    # Core Qt dependencies
    "/usr/local/opt/pcre2/lib/libpcre2-16.0.dylib"
    "/usr/local/opt/pcre2/lib/libpcre2-8.0.dylib"
    "/usr/local/opt/zstd/lib/libzstd.1.dylib"
    "/usr/local/opt/glib/lib/libgthread-2.0.0.dylib"
    "/usr/local/opt/glib/lib/libglib-2.0.0.dylib"
    "/usr/local/opt/gettext/lib/libintl.8.dylib"

    # Graphics dependencies
    "/usr/local/opt/libpng/lib/libpng16.16.dylib"
    "/usr/local/opt/freetype/lib/libfreetype.6.dylib"
    "/usr/local/opt/md4c/lib/libmd4c.0.dylib"

    # Image format dependencies
    "/usr/local/opt/jpeg-turbo/lib/libjpeg.8.dylib"
    "/usr/local/opt/libtiff/lib/libtiff.6.dylib"
    "/usr/local/opt/xz/lib/liblzma.5.dylib"

    # WebP dependencies
    "/usr/local/opt/webp/lib/libwebp.7.dylib"
    "/usr/local/opt/webp/lib/libwebpdemux.2.dylib"
    "/usr/local/opt/webp/lib/libwebpmux.3.dylib"
    "/usr/local/opt/webp/lib/libsharpyuv.0.dylib"
)

copied=0
missing=0

for dep in "${DEPS[@]}"; do
    name=$(basename "$dep")
    if [ -f "$dep" ]; then
        echo "Copying $name..."
        cp "$dep" "$GAME_FRAMEWORKS/"
        chmod 755 "$GAME_FRAMEWORKS/$name"
        # Set install name
        install_name_tool -id "@executable_path/../Frameworks/$name" "$GAME_FRAMEWORKS/$name" 2>/dev/null || true
        ((copied++))
    else
        echo "WARNING: $name not found at $dep"
        ((missing++))
    fi
done

echo ""
echo "Copied $copied libraries"
if [ $missing -gt 0 ]; then
    echo "WARNING: $missing libraries were not found"
    echo "You may need to install additional Homebrew packages"
fi
