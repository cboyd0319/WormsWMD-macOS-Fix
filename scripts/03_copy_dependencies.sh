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
QT_PREFIX="${QT_PREFIX:-/usr/local/opt/qt@5}"
QT_DEP_PREFIX="${QT_DEP_PREFIX:-}"

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

declare -a dependency_roots=()
declare -a scanned_bins=()
declare -a queue=("${scan_bins[@]}")
DEPENDENCY_SOURCE_RECORDS=$(mktemp "${TMPDIR:-/tmp}/wormswmd-dependency-sources.XXXXXX")
trap 'rm -f "$DEPENDENCY_SOURCE_RECORDS"' EXIT

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

initialize_dependency_roots() {
    local qt_prefix_real dependency_prefix_real cellar_real

    worms_reject_control_chars "$QT_PREFIX" "QT_PREFIX"
    worms_reject_control_chars "$QT_DEP_PREFIX" "QT_DEP_PREFIX"
    [[ -d "$QT_PREFIX" ]] || {
        echo "ERROR: Qt dependency source prefix not found: $QT_PREFIX"
        return 1
    }
    qt_prefix_real=$(worms_real_dir "$QT_PREFIX") || return 1

    if [[ "$QT_PREFIX" == "/usr/local/opt/qt@5" ]]; then
        cellar_real=$(worms_real_dir /usr/local/Cellar) || {
            echo "ERROR: Standard Intel Homebrew Cellar is unavailable."
            return 1
        }
        worms_path_inside_root "$cellar_real" "$qt_prefix_real" || {
            echo "ERROR: /usr/local/opt/qt@5 resolves outside /usr/local/Cellar."
            return 1
        }
        dependency_roots+=("$cellar_real")
    else
        worms_bool_true "${WORMSWMD_ALLOW_CUSTOM_QT_PREFIX:-}" || {
            echo "ERROR: Custom QT_PREFIX requires WORMSWMD_ALLOW_CUSTOM_QT_PREFIX=1"
            return 1
        }
        dependency_roots+=("$qt_prefix_real")
    fi

    if [[ -n "$QT_DEP_PREFIX" ]]; then
        [[ -d "$QT_DEP_PREFIX" ]] && [[ ! -L "$QT_DEP_PREFIX" ]] || {
            echo "ERROR: QT_DEP_PREFIX must be a real directory: $QT_DEP_PREFIX"
            return 1
        }
        dependency_prefix_real=$(worms_real_dir "$QT_DEP_PREFIX") || return 1
        dependency_roots+=("$dependency_prefix_real")
    fi
}

validate_bundled_dependency_target() {
    local target="$1"
    local target_real archs

    [[ -f "$target" ]] && [[ ! -L "$target" ]] \
        && [[ "$(worms_file_link_count "$target")" -eq 1 ]] || return 1
    target_real=$(realpath "$target" 2>/dev/null || true)
    [[ -n "$target_real" ]] \
        && worms_path_inside_root "$GAME_FRAMEWORKS" "$target_real" || return 1
    archs=$(lipo -archs "$target_real" 2>/dev/null || true)
    printf '%s\n' "$archs" | tr ' ' '\n' | grep -qx x86_64
}

initialize_dependency_roots || exit 1

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

    binary_id=$(worms_macho_install_id "$bin" || true)
    while IFS= read -r dep; do
        [[ -n "$dep" ]] || continue
        [[ "$dep" == "$binary_id" ]] && continue
        case "$dep" in
            /usr/lib/*|/System/Library/*|*".framework/"*)
                continue
                ;;
        esac
        [[ "$dep" == *.dylib ]] || continue
        if worms_has_control_chars "$dep" \
            || worms_macho_path_has_parent_component "$dep"; then
            echo "ERROR: Unsafe dependency path: $dep ($bin)"
            ((++missing))
            continue
        fi
        case "$dep" in
            @rpath/*|@executable_path/*|@loader_path/*|/*)
                ;;
            *)
                echo "ERROR: Unsupported relative dependency: $dep ($bin)"
                ((++missing))
                continue
                ;;
        esac

        name=$(basename "$dep")
        target="$GAME_FRAMEWORKS/$name"
        local_path=""
        resolve_status=0
        if local_path=$(worms_resolve_macho_dependency_source \
            "$bin" "$dep" "$GAME_EXEC" "${dependency_roots[@]}" 2>&1); then
            resolve_status=0
        else
            resolve_status=$?
            local_path=""
        fi

        if [[ -n "$local_path" ]]; then
            if ! worms_record_dependency_source \
                "$DEPENDENCY_SOURCE_RECORDS" "$name" "$local_path"; then
                ((++missing))
                continue
            fi
        fi

        if [[ -f "$target" ]]; then
            if ! validate_bundled_dependency_target "$target"; then
                echo "ERROR: Existing bundled dependency is unsafe: $target"
                ((++missing))
                continue
            fi
            queue+=("$target")
            continue
        fi

        if [[ -z "$local_path" ]]; then
            if worms_macho_dependency_is_weak "$bin" "$dep"; then
                echo "WARNING: Optional dependency unavailable: $dep"
                continue
            fi
            if [[ "$resolve_status" -eq 2 ]]; then
                echo "ERROR: Ambiguous dependency source: $dep ($bin)"
            else
                echo "ERROR: Could not resolve dependency source: $dep ($bin)"
            fi
            ((++missing))
            continue
        fi

        echo "Copying $name..."
        cp "$local_path" "$target"
        chmod 755 "$target"
        if ! install_name_tool -id \
            "@executable_path/../Frameworks/$name" "$target"; then
            echo "ERROR: Failed to update copied dependency ID: $target"
            ((++missing))
            continue
        fi
        ((++copied))

        queue+=("$target")
    done < <(worms_otool_dependencies "$bin")
done

echo ""
echo "Copied $copied libraries"
if [ $missing -gt 0 ]; then
    echo "ERROR: $missing required dependency source(s) failed validation"
fi
echo "COPIED_LIBS=$copied"
echo "MISSING_LIBS=$missing"
[[ "$missing" -eq 0 ]]
