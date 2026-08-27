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
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
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

validate_qt_prefix() {
    case "$QT_SOURCE" in
        prebuild|homebrew)
            ;;
        *)
            echo "ERROR: Invalid QT_SOURCE: $QT_SOURCE"
            exit 1
            ;;
    esac

    worms_reject_control_chars "$QT_PREFIX" "QT_PREFIX"

    if worms_path_inside_root "$GAME_APP" "$QT_PREFIX" \
        || worms_path_inside_root "$QT_PREFIX" "$GAME_APP"; then
        echo "ERROR: QT_PREFIX and GAME_APP must be separate directory trees."
        exit 1
    fi

    if [[ "$QT_SOURCE" == "homebrew" ]] && [[ "$QT_PREFIX" != "/usr/local/opt/qt@5" ]]; then
        if ! worms_bool_true "${WORMSWMD_ALLOW_CUSTOM_QT_PREFIX:-}"; then
            echo "ERROR: Refusing custom Homebrew QT_PREFIX without WORMSWMD_ALLOW_CUSTOM_QT_PREFIX=1"
            exit 1
        fi
    fi

    if [[ "$QT_SOURCE" == "prebuild" ]]; then
        if [[ ! -f "$QT_PREFIX/METADATA.txt" ]] || [[ ! -f "$QT_PREFIX/MANIFEST.txt" ]]; then
            echo "ERROR: Pre-built QT_PREFIX is missing METADATA.txt or MANIFEST.txt: $QT_PREFIX"
            exit 1
        fi
        worms_validate_tree_symlinks "$QT_PREFIX" || {
            echo "ERROR: Pre-built QT_PREFIX contains unsafe symlinks: $QT_PREFIX"
            exit 1
        }
        if [[ -f "$QT_PREFIX/.wormswmd-qt-cache-v1" ]]; then
            worms_verify_manifest_with_extras "$QT_PREFIX" \
                "$QT_PREFIX/MANIFEST.txt" .wormswmd-qt-cache-v1
        else
            worms_verify_manifest "$QT_PREFIX" "$QT_PREFIX/MANIFEST.txt"
        fi || {
            echo "ERROR: Pre-built QT_PREFIX manifest verification failed: $QT_PREFIX"
            exit 1
        }
    fi
}

prebuilt_webp_supported() {
    [[ "$QT_SOURCE" != "prebuild" ]] || [[ -f "$NEW_QT/libsharpyuv.0.dylib" ]]
}

worms_reject_control_chars "$GAME_APP" "GAME_APP"
worms_validate_game_app_for_mutation "$GAME_APP" || {
    echo "ERROR: Unsafe game bundle mutation path: $GAME_APP"
    exit 1
}
validate_qt_prefix

if [[ -z "$GAME_APP" ]] || [[ ! -d "$GAME_APP/Contents" ]] || [[ ! -f "$GAME_EXEC" ]]; then
    echo "ERROR: Invalid GAME_APP: $GAME_APP"
    echo "Expected a Worms W.M.D.app bundle containing: $GAME_EXEC"
    exit 1
fi

mkdir -p "$GAME_FRAMEWORKS" "$GAME_PLUGINS/platforms" "$GAME_PLUGINS/imageformats"
worms_validate_game_app_for_mutation "$GAME_APP" || {
    echo "ERROR: Unsafe game bundle mutation path: $GAME_APP"
    exit 1
}

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

declare -a FRAMEWORKS=()

append_unique() {
    local name="$1"
    local item

    for item in "${FRAMEWORKS[@]:-}"; do
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
    source_fw="$NEW_QT/$fw.framework"
    if [ ! -d "$source_fw" ]; then
        echo "ERROR: Required Qt framework missing from source: $source_fw"
        exit 1
    fi

    source_fw_bin=$(worms_framework_binary "$source_fw" "$fw" || true)
    if [ -z "$source_fw_bin" ] || [ ! -f "$source_fw_bin" ]; then
        echo "ERROR: Required Qt framework binary missing from source: $source_fw"
        exit 1
    fi
done

if [ ! -f "$NEW_QT_PLUGINS/platforms/libqcocoa.dylib" ]; then
    echo "ERROR: Required Qt platform plugin missing from source: $NEW_QT_PLUGINS/platforms/libqcocoa.dylib"
    exit 1
fi

if [ ! -f "$NEW_QT_PLUGINS/imageformats/libqsvg.dylib" ]; then
    echo "ERROR: Required Qt image plugin missing from source: $NEW_QT_PLUGINS/imageformats/libqsvg.dylib"
    exit 1
fi

for fw in "${FRAMEWORKS[@]}"; do
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
        # Packaged framework binaries may be read-only, but this copy is mutable.
        chmod u+w "$fw_bin"
        install_name_tool -id "@executable_path/../Frameworks/$fw.framework/$rel_path" \
            "$fw_bin"
    fi
done

echo ""

# Copy bundled dependencies from pre-built package
# These are x86_64 libraries that Qt depends on (pcre2, glib, zstd, etc.)
# Plugins (libq*.dylib) are handled separately in the plugins section below
if [[ "$QT_SOURCE" == "prebuild" ]]; then
    echo "=== Copying Bundled Dependencies ==="
    dep_count=0
    for dylib in "$NEW_QT"/*.dylib; do
        if [[ -f "$dylib" ]]; then
            name=$(basename "$dylib")
            # Skip plugins (they start with libq and are copied from PlugIns/)
            if [[ "$name" == libq*.dylib ]]; then
                continue
            fi
            if ! prebuilt_webp_supported && [[ "$name" == libwebp*.dylib ]]; then
                echo "Skipping optional $name (libsharpyuv.0.dylib unavailable)"
                rm -f "$GAME_FRAMEWORKS/$name"
                continue
            fi
            echo "Copying $name..."
            cp "$dylib" "$GAME_FRAMEWORKS/"
            chmod 755 "$GAME_FRAMEWORKS/$name"
            install_name_tool -id "@executable_path/../Frameworks/$name" "$GAME_FRAMEWORKS/$name" 2>/dev/null || true
            ((++dep_count))
        fi
    done
    echo "Copied $dep_count dependency libraries"
    echo ""
fi

echo "=== Replacing Qt Plugins ==="

# Qt 5.15 no longer ships these Qt 5.3 plugin categories. Remove only the
# known legacy directories so unrelated game or user plugin directories remain.
rm -rf "$GAME_PLUGINS/accessible" "$GAME_PLUGINS/printsupport"

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
        if ! prebuilt_webp_supported && [[ "$name" == "libqwebp.dylib" ]]; then
            echo "  Skipping optional $name (libsharpyuv.0.dylib unavailable)"
            continue
        fi
        echo "  Copying $name..."
        cp "$plugin" "$GAME_PLUGINS/imageformats/"
    fi
done

echo ""
echo "Qt frameworks replaced successfully."
