#!/bin/bash
#
# 03_copy_dependencies.sh - Copy Qt external dependencies
#
# Qt 5.15 from Homebrew depends on several external libraries.
# This script scans those dependencies and copies them into the game's
# Frameworks folder to keep the app self-contained.
#
# When using pre-built Qt frameworks (QT_SOURCE=prebuild), dependencies
# are already bundled in the package, so this script will verify they
# exist rather than scanning Homebrew paths.
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
QT_SOURCE="${QT_SOURCE:-homebrew}"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/logging.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
worms_log_init "03_copy_dependencies"
worms_debug_init

if [[ -z "$LOGGING_PRESET" ]]; then
    echo "Log file: $LOG_FILE"
    if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
        echo "Trace log: $TRACE_FILE"
    fi
fi

worms_reject_control_chars "$GAME_APP" "GAME_APP"
worms_validate_game_app_for_mutation "$GAME_APP" || {
    echo "ERROR: Unsafe game bundle mutation path: $GAME_APP"
    exit 1
}

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

# When using pre-built package, dependencies are already bundled
# Just verify they exist and report success
if [[ "$QT_SOURCE" == "prebuild" ]]; then
    echo "=== Verifying Bundled Dependencies ==="

    # Count bundled dylibs (excluding Qt frameworks which are separate)
    bundled_count=0
    for dylib in "$GAME_FRAMEWORKS"/*.dylib; do
        if [[ -f "$dylib" ]]; then
            ((++bundled_count))
        fi
    done

    missing_required=0
    for required_lib in \
        libglib-2.0.0.dylib \
        libgthread-2.0.0.dylib \
        libintl.8.dylib \
        libpcre2-16.0.dylib \
        libpcre2-8.0.dylib \
        libzstd.1.dylib \
        libpng16.16.dylib \
        libjpeg.8.dylib \
        libfreetype.6.dylib \
        libmd4c.0.dylib \
        liblzma.5.dylib \
        libtiff.6.dylib; do
        if [[ ! -f "$GAME_FRAMEWORKS/$required_lib" ]]; then
            echo "ERROR: Required bundled dependency missing: $required_lib"
            ((++missing_required))
        fi
    done

    if [[ $missing_required -gt 0 ]]; then
        echo ""
        echo "Pre-built dependency verification failed."
        echo "Re-run the installer with --force to refresh the Qt package, or install the Homebrew fallback."
        echo "COPIED_LIBS=$bundled_count"
        echo "MISSING_LIBS=$missing_required"
        exit 1
    fi

    if [[ $bundled_count -gt 0 ]]; then
        echo "Found $bundled_count bundled dependencies"
        echo ""
        echo "Verified $bundled_count bundled libraries"
        echo "BUNDLED_LIBS=$bundled_count"
        echo "COPIED_LIBS=0"
        echo "MISSING_LIBS=0"
        exit 0
    else
        echo "WARNING: No bundled dependencies found in pre-built package"
        echo "Falling back to Homebrew dependency scanning..."
    fi
fi

echo "=== Copying Qt External Dependencies ==="

declare -a scan_bins=()

for fw_dir in "$GAME_FRAMEWORKS"/*.framework; do
    if [ -d "$fw_dir" ]; then
        fw_bin=$(worms_framework_binary "$fw_dir" || true)
        if [ -n "$fw_bin" ]; then
            scan_bins+=("$fw_bin")
        fi
    fi
done

if [ -f "$GAME_PLUGINS/platforms/libqcocoa.dylib" ]; then
    scan_bins+=("$GAME_PLUGINS/platforms/libqcocoa.dylib")
fi

for plugin in "$GAME_PLUGINS/imageformats/"*.dylib; do
    if [ -f "$plugin" ]; then
        scan_bins+=("$plugin")
    fi
done

if [ ${#scan_bins[@]} -eq 0 ]; then
    echo "ERROR: No Qt binaries found to scan."
    echo "Run scripts/02_replace_qt_frameworks.sh first."
    exit 1
fi

copied=0
missing=0

declare -a scanned_bins=()
declare -a queue=("${scan_bins[@]}")

bin_scanned() {
    local search="$1"
    local item

    for item in "${scanned_bins[@]:-}"; do
        if [[ "$item" == "$search" ]]; then
            return 0
        fi
    done

    return 1
}

resolve_rpath_dep() {
    local name="$1"
    local candidate

    for candidate in /usr/local/opt/*/lib/"$name" /usr/local/Cellar/*/*/lib/"$name" /usr/local/lib/"$name"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

while [ ${#queue[@]} -gt 0 ]; do
    bin="${queue[0]}"
    queue=("${queue[@]:1}")

    if bin_scanned "$bin"; then
        continue
    fi
    scanned_bins+=("$bin")

    if [ ! -f "$bin" ]; then
        continue
    fi

    while IFS= read -r dep; do
        local_path=""

        if [[ "$dep" == /usr/local/* ]]; then
            local_path="$dep"
        elif [[ "$dep" == @rpath/* ]]; then
            name="${dep#@rpath/}"
            if [[ "$name" == *.dylib ]]; then
                local_path=$(resolve_rpath_dep "$name" || true)
            fi
        fi

        if [ -z "$local_path" ]; then
            continue
        fi

        if [[ "$local_path" != *.dylib ]]; then
            continue
        fi

        if [[ "$local_path" == *".framework/"* ]]; then
            continue
        fi

        name=$(basename "$local_path")
        target="$GAME_FRAMEWORKS/$name"

        if [ ! -f "$target" ]; then
            if [ -f "$local_path" ]; then
                echo "Copying $name..."
                cp -L "$local_path" "$target"
                chmod 755 "$target"
                install_name_tool -id "@executable_path/../Frameworks/$name" "$target" 2>/dev/null || true
                ((++copied))
            else
                echo "WARNING: $name not found at $local_path"
                ((++missing))
                continue
            fi
        fi

        queue+=("$target")
    done < <(worms_otool_dependencies "$bin")
done

echo ""
echo "Copied $copied libraries"
if [ $missing -gt 0 ]; then
    echo "WARNING: $missing libraries were not found"
    echo "You may need to install additional Homebrew packages"
fi
echo "COPIED_LIBS=$copied"
echo "MISSING_LIBS=$missing"
