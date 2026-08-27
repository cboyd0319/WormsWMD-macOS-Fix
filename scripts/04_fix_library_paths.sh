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

set -euo pipefail

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
GAME_FRAMEWORKS="$GAME_APP/Contents/Frameworks"
GAME_PLUGINS="$GAME_APP/Contents/PlugIns"
GAME_EXEC="$GAME_APP/Contents/MacOS/Worms W.M.D"
BUILD_DIR="${BUILD_DIR:-}"
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
LOGGING_PRESET="${WORMSWMD_LOGGING_INITIALIZED:-}"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/logging.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
worms_log_init "04_fix_library_paths"
worms_debug_init

if [[ -z "$LOGGING_PRESET" ]]; then
    echo "Log file: $LOG_FILE"
    if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
        echo "Trace log: $TRACE_FILE"
    fi
fi

echo "=== Fixing Library Path References ==="

worms_reject_control_chars "$GAME_APP" "GAME_APP"
worms_reject_control_chars "$BUILD_DIR" "BUILD_DIR"
if [[ -z "$BUILD_DIR" ]]; then
    echo "ERROR: BUILD_DIR must be set to the AGL stub build directory."
    echo "Run fix_worms_wmd.sh, or export BUILD_DIR from mktemp before running this helper."
    exit 1
fi
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

# Install AGL stub
echo ""
echo "--- Installing AGL stub framework ---"
if [ -f "$BUILD_DIR/AGL" ]; then
    mkdir -p "$GAME_FRAMEWORKS/AGL.framework/Versions/A"
    cp "$BUILD_DIR/AGL" "$GAME_FRAMEWORKS/AGL.framework/Versions/A/AGL"
    mkdir -p "$GAME_FRAMEWORKS/AGL.framework/Versions/A/Resources"
    cat > "$GAME_FRAMEWORKS/AGL.framework/Versions/A/Resources/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.wormswmd.aglstub</string>
    <key>CFBundleName</key>
    <string>AGL</string>
    <key>CFBundleExecutable</key>
    <string>AGL</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
</dict>
</plist>
EOF
    rm -f \
        "$GAME_FRAMEWORKS/AGL.framework/AGL" \
        "$GAME_FRAMEWORKS/AGL.framework/Resources" \
        "$GAME_FRAMEWORKS/AGL.framework/Versions/Current" \
        "$GAME_FRAMEWORKS/AGL.framework/Versions/A/A" \
        "$GAME_FRAMEWORKS/AGL.framework/Versions/A/Resources/Resources"
    ln -sf A "$GAME_FRAMEWORKS/AGL.framework/Versions/Current"
    ln -sf Versions/Current/AGL "$GAME_FRAMEWORKS/AGL.framework/AGL"
    ln -sf Versions/Current/Resources "$GAME_FRAMEWORKS/AGL.framework/Resources"
    echo "AGL stub installed"
else
    echo "ERROR: AGL stub not found at $BUILD_DIR/AGL"
    echo "Run 01_build_agl_stub.sh first."
    exit 1
fi

fw_names=()
fw_ids=()
fw_bins=()

for fw_dir in "$GAME_FRAMEWORKS"/*.framework; do
    if [ -d "$fw_dir" ]; then
        fw_name=$(basename "$fw_dir" .framework)
        fw_bin=$(worms_framework_binary "$fw_dir" || true)
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
    local label="${3:-$(basename "$bin")}"
    local dep
    local dep_id
    local fw_name
    local dep_base
    local resolved
    local tool_output

    if [ ! -f "$bin" ]; then
        return
    fi

    if [ -n "$id" ]; then
        if ! tool_output=$(install_name_tool -id "$id" "$bin" 2>&1); then
            echo "ERROR: Failed to update install ID for $label"
            [[ -n "$tool_output" ]] && echo "$tool_output"
            return 1
        fi
    fi

    while IFS= read -r dep; do
        dep_id=""
        if [[ "$dep" == @executable_path/* ]] || [[ "$dep" == @loader_path/* ]]; then
            resolved=$(worms_expand_macho_path "$dep" "$bin" "$GAME_EXEC" || true)
            if [[ -z "$resolved" ]] \
                || ! worms_path_inside_root "$GAME_APP/Contents" "$resolved"; then
                echo "ERROR: Dependency resolves outside the app bundle in $label: $dep"
                return 1
            fi
            if [[ ! -f "$resolved" ]]; then
                if worms_macho_dependency_is_weak "$bin" "$dep"; then
                    echo "WARNING: Keeping optional missing dependency for $label: $dep"
                else
                    echo "ERROR: Missing dependency in $label: $dep"
                    return 1
                fi
            fi
            continue
        fi

        if [[ "$dep" == *".framework/"* ]]; then
            fw_name=$(basename "${dep%%.framework/*}")
            dep_id=$(fw_id_for "$fw_name" || true)
            if [ -n "$dep_id" ]; then
                if ! tool_output=$(install_name_tool -change "$dep" "$dep_id" "$bin" 2>&1); then
                    echo "ERROR: Failed to update dependency in $label: $dep"
                    [[ -n "$tool_output" ]] && echo "$tool_output"
                    return 1
                fi
            fi
        else
            dep_base=$(basename "$dep")
            dep_id=$(dylib_id_for "$dep_base" || true)
            if [ -n "$dep_id" ]; then
                if ! tool_output=$(install_name_tool -change "$dep" "$dep_id" "$bin" 2>&1); then
                    echo "ERROR: Failed to update dependency in $label: $dep"
                    [[ -n "$tool_output" ]] && echo "$tool_output"
                    return 1
                fi
            fi
        fi

        [[ -n "$dep_id" ]] && continue

        case "$dep" in
            /usr/lib/*|/System/Library/*)
                ;;
            @rpath/*)
                if worms_resolve_macho_rpath_dependency "$bin" "$dep" "$GAME_EXEC" "$GAME_APP" >/dev/null; then
                    echo "Keeping bundled rpath dependency for $label: $dep"
                elif worms_macho_dependency_is_weak "$bin" "$dep"; then
                    echo "WARNING: Keeping optional unresolved dependency for $label: $dep"
                else
                    echo "ERROR: Unresolved dependency in $label: $dep"
                    return 1
                fi
                ;;
            *)
                echo "ERROR: Unportable dependency in $label: $dep"
                return 1
                ;;
        esac
    done < <(worms_otool_dependencies "$bin")
}

echo ""
echo "--- Updating install names ---"

echo "Fixing Worms W.M.D..."
fix_binary "$GAME_EXEC" "" "Worms W.M.D"

for i in "${!fw_bins[@]}"; do
    echo "Fixing ${fw_names[$i]}.framework..."
    fix_binary "${fw_bins[$i]}" "${fw_ids[$i]}" "${fw_names[$i]}.framework"
done

for i in "${!dylib_paths[@]}"; do
    echo "Fixing ${dylib_names[$i]}..."
    fix_binary "${dylib_paths[$i]}" "${dylib_ids[$i]}" "${dylib_names[$i]}"
done

if [ -f "$GAME_PLUGINS/platforms/libqcocoa.dylib" ]; then
    echo "Fixing libqcocoa.dylib..."
    fix_binary "$GAME_PLUGINS/platforms/libqcocoa.dylib" "@executable_path/../PlugIns/platforms/libqcocoa.dylib" "libqcocoa.dylib"
fi

for plugin in "$GAME_PLUGINS/imageformats/"*.dylib; do
    if [ -f "$plugin" ]; then
        name=$(basename "$plugin")
        echo "Fixing $name..."
        fix_binary "$plugin" "@executable_path/../PlugIns/imageformats/$name" "$name"
    fi
done

echo ""
echo "Library path fixes complete."
