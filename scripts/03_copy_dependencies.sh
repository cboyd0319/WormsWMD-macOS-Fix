#!/bin/bash
#
# 03_copy_dependencies.sh - Copy Qt external dependencies
#
# Qt 5.15 from Homebrew depends on several external libraries.
# This script scans those dependencies and copies them into the game's
# Frameworks folder to keep the app self-contained.
#

set -euo pipefail

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
GAME_FRAMEWORKS="$GAME_APP/Contents/Frameworks"
GAME_PLUGINS="$GAME_APP/Contents/PlugIns"
GAME_EXEC="$GAME_APP/Contents/MacOS/Worms W.M.D"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGGING_PRESET="${WORMSWMD_LOGGING_INITIALIZED:-}"

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

if [[ -z "$GAME_APP" ]] || [[ ! -d "$GAME_APP/Contents" ]] || [[ ! -f "$GAME_EXEC" ]]; then
    echo "ERROR: Invalid GAME_APP: $GAME_APP"
    echo "Expected a Worms W.M.D.app bundle containing: $GAME_EXEC"
    exit 1
fi

mkdir -p "$GAME_FRAMEWORKS" "$GAME_PLUGINS/platforms" "$GAME_PLUGINS/imageformats"

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
    done < <(otool -L "$bin" 2>/dev/null | awk 'NR>1 {print $1}' || true)
done

echo ""
echo "Copied $copied libraries"
if [ $missing -gt 0 ]; then
    echo "WARNING: $missing libraries were not found"
    echo "You may need to install additional Homebrew packages"
fi
echo "COPIED_LIBS=$copied"
echo "MISSING_LIBS=$missing"
