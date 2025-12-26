#!/bin/bash
#
# 04_fix_library_paths.sh - Fix all library path references
#
# Updates all library references to use @executable_path instead
# of absolute paths like /usr/local/opt/...
#
# This script scans the bundled frameworks and libraries, then rewrites
# any matching dependency paths to @executable_path for portability.
#

set -e

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
GAME_FRAMEWORKS="$GAME_APP/Contents/Frameworks"
GAME_PLUGINS="$GAME_APP/Contents/PlugIns"
GAME_EXEC="$GAME_APP/Contents/MacOS/Worms W.M.D"
BUILD_DIR="/tmp/agl_stub_build"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGGING_PRESET="${WORMSWMD_LOGGING_INITIALIZED:-}"

source "$SCRIPT_DIR/logging.sh"
worms_log_init "04_fix_library_paths"
worms_debug_init

if [[ -z "$LOGGING_PRESET" ]]; then
    echo "Log file: $LOG_FILE"
    if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
        echo "Trace log: $TRACE_FILE"
    fi
fi

echo "=== Fixing Library Path References ==="

if [[ -z "$GAME_APP" ]] || [[ ! -d "$GAME_APP/Contents" ]] || [[ ! -f "$GAME_EXEC" ]]; then
    echo "ERROR: Invalid GAME_APP: $GAME_APP"
    echo "Expected a Worms W.M.D.app bundle containing: $GAME_EXEC"
    exit 1
fi

mkdir -p "$GAME_FRAMEWORKS" "$GAME_PLUGINS/platforms" "$GAME_PLUGINS/imageformats"

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

fw_names=()
fw_ids=()
fw_bins=()

for fw_dir in "$GAME_FRAMEWORKS"/*.framework; do
    if [ -d "$fw_dir" ]; then
        fw_name=$(basename "$fw_dir" .framework)
        fw_bin=$(framework_binary "$fw_dir")
        if [ -n "$fw_bin" ]; then
            rel_path="${fw_bin#"$fw_dir"/}"
            fw_id="@executable_path/../Frameworks/$fw_name.framework/$rel_path"
            fw_names+=("$fw_name")
            fw_ids+=("$fw_id")
            fw_bins+=("$fw_bin")
        fi
    fi
done

dylib_names=()
dylib_ids=()
dylib_paths=()

for dylib in "$GAME_FRAMEWORKS"/*.dylib; do
    if [ -f "$dylib" ]; then
        name=$(basename "$dylib")
        id="@executable_path/../Frameworks/$name"
        dylib_names+=("$name")
        dylib_ids+=("$id")
        dylib_paths+=("$dylib")
    fi
done

fw_id_for() {
    local name="$1"
    local i

    for i in "${!fw_names[@]}"; do
        if [[ "${fw_names[$i]}" == "$name" ]]; then
            echo "${fw_ids[$i]}"
            return 0
        fi
    done

    return 1
}

dylib_id_for() {
    local name="$1"
    local i

    for i in "${!dylib_names[@]}"; do
        if [[ "${dylib_names[$i]}" == "$name" ]]; then
            echo "${dylib_ids[$i]}"
            return 0
        fi
    done

    return 1
}

fix_binary() {
    local bin="$1"
    local id="$2"
    local dep
    local dep_id
    local fw_name
    local dep_base

    if [ ! -f "$bin" ]; then
        return
    fi

    if [ -n "$id" ]; then
        install_name_tool -id "$id" "$bin" 2>/dev/null || true
    fi

    while IFS= read -r dep; do
        if [[ "$dep" == @executable_path/* ]] || [[ "$dep" == @loader_path/* ]]; then
            continue
        fi

        if [[ "$dep" == *".framework/"* ]]; then
            fw_name=$(basename "${dep%%.framework/*}")
            dep_id=$(fw_id_for "$fw_name" || true)
            if [ -n "$dep_id" ]; then
                install_name_tool -change "$dep" "$dep_id" "$bin" 2>/dev/null || true
            fi
            continue
        fi

        dep_base=$(basename "$dep")
        dep_id=$(dylib_id_for "$dep_base" || true)
        if [ -n "$dep_id" ]; then
            install_name_tool -change "$dep" "$dep_id" "$bin" 2>/dev/null || true
        fi
    done < <(otool -L "$bin" 2>/dev/null | awk 'NR>1 {print $1}' || true)
}

echo ""
echo "--- Updating install names ---"

echo "Fixing Worms W.M.D..."
fix_binary "$GAME_EXEC" ""

for i in "${!fw_bins[@]}"; do
    echo "Fixing ${fw_names[$i]}.framework..."
    fix_binary "${fw_bins[$i]}" "${fw_ids[$i]}"
done

for i in "${!dylib_paths[@]}"; do
    echo "Fixing ${dylib_names[$i]}..."
    fix_binary "${dylib_paths[$i]}" "${dylib_ids[$i]}"
done

if [ -f "$GAME_PLUGINS/platforms/libqcocoa.dylib" ]; then
    echo "Fixing libqcocoa.dylib..."
    fix_binary "$GAME_PLUGINS/platforms/libqcocoa.dylib" "@executable_path/../PlugIns/platforms/libqcocoa.dylib"
fi

for plugin in "$GAME_PLUGINS/imageformats/"*.dylib; do
    if [ -f "$plugin" ]; then
        name=$(basename "$plugin")
        echo "Fixing $name..."
        fix_binary "$plugin" "@executable_path/../PlugIns/imageformats/$name"
    fi
done

echo ""
echo "Library path fixes complete."
