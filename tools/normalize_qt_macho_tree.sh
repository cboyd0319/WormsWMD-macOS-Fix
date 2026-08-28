#!/bin/bash
# Normalize or validate Qt package Mach-O IDs, imports, rpaths, and UUIDs.

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

canonical_packaged_macho_id() {
    local tree_root="$1"
    local binary="$2"
    local rel framework_name

    rel=${binary#"$tree_root"/}
    [[ "$rel" != "$binary" ]] || return 1
    case "$rel" in
        Frameworks/*.framework/Versions/5/*)
            framework_name=${rel#Frameworks/}
            framework_name=${framework_name%%.framework/*}
            [[ "$(basename "$binary")" == "$framework_name" ]] || return 1
            printf '@rpath/%s.framework/Versions/5/%s\n' \
                "$framework_name" "$framework_name"
            ;;
        Frameworks/*.dylib|PlugIns/*/*.dylib)
            printf '@rpath/%s\n' "$(basename "$binary")"
            ;;
        *)
            return 1
            ;;
    esac
}

canonical_packaged_dependency() {
    local tree_root="$1"
    local dependency="$2"
    local framework_name dependency_name target

    case "$dependency" in
        /usr/lib/*|/System/Library/*)
            printf '%s\n' "$dependency"
            return 0
            ;;
        *'.framework/Versions/5/'*)
            framework_name=${dependency%%.framework/Versions/5/*}
            framework_name=$(basename "$framework_name")
            target="$tree_root/Frameworks/$framework_name.framework/Versions/5/$framework_name"
            [[ -f "$target" ]] && [[ ! -L "$target" ]] || return 1
            printf '@rpath/%s.framework/Versions/5/%s\n' \
                "$framework_name" "$framework_name"
            ;;
        *.dylib)
            dependency_name=$(basename "$dependency")
            target="$tree_root/Frameworks/$dependency_name"
            [[ -f "$target" ]] && [[ ! -L "$target" ]] || return 1
            printf '@rpath/%s\n' "$dependency_name"
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_packaged_macho_tree() {
    local tree_root="$1"
    local binary old_id dependency canonical rpath new_id tool_output macho_count=0

    while IFS= read -r -d '' binary; do
        file "$binary" 2>/dev/null | grep -Fq 'Mach-O' || continue
        macho_count=$((macho_count + 1))
        chmod u+w "$binary" || return 1
        old_id=$(worms_macho_install_id "$binary" || true)
        while IFS= read -r dependency; do
            [[ -n "$dependency" ]] || continue
            [[ -n "$old_id" ]] && [[ "$dependency" == "$old_id" ]] && continue
            canonical=$(canonical_packaged_dependency \
                "$tree_root" "$dependency" || true)
            [[ -n "$canonical" ]] || {
                echo "ERROR: Unexpected packaged dependency: $binary -> $dependency" >&2
                return 1
            }
            [[ "$dependency" == "$canonical" ]] && continue
            if ! tool_output=$(install_name_tool -change \
                "$dependency" "$canonical" "$binary" 2>&1); then
                echo "ERROR: Could not normalize dependency: $binary -> $dependency" >&2
                [[ -z "$tool_output" ]] || echo "$tool_output" >&2
                return 1
            fi
        done < <(worms_otool_dependencies "$binary")
        while IFS= read -r rpath; do
            [[ -n "$rpath" ]] || continue
            if ! tool_output=$(install_name_tool -delete_rpath \
                "$rpath" "$binary" 2>&1); then
                echo "ERROR: Could not remove packaged rpath: $binary -> $rpath" >&2
                [[ -z "$tool_output" ]] || echo "$tool_output" >&2
                return 1
            fi
        done < <(worms_macho_rpaths "$binary" | LC_ALL=C sort -u)
        [[ -n "$old_id" ]] || continue
        new_id=$(canonical_packaged_macho_id "$tree_root" "$binary" || true)
        [[ -n "$new_id" ]] || {
            echo "ERROR: Could not classify packaged Mach-O ID: $binary" >&2
            return 1
        }
        if [[ "$old_id" != "$new_id" ]] \
            && ! install_name_tool -id "$new_id" "$binary"; then
            echo "ERROR: Could not normalize packaged Mach-O ID: $binary" >&2
            return 1
        fi
        /usr/bin/python3 "$ROOT_DIR/tools/normalize_macho_uuid.py" "$binary" \
            || return 1
    done < <(find "$tree_root/Frameworks" "$tree_root/PlugIns" -type f -print0)
    [[ "$macho_count" -gt 0 ]] || {
        echo "ERROR: Qt package contains no Mach-O files to normalize" >&2
        return 1
    }
}

validate_normalized_macho_tree() {
    local tree_root="$1"
    local binary install_id expected_id dependency expected_dependency rpath macho_count=0

    while IFS= read -r -d '' binary; do
        file "$binary" 2>/dev/null | grep -Fq 'Mach-O' || continue
        macho_count=$((macho_count + 1))
        install_id=$(worms_macho_install_id "$binary" || true)
        if [[ -n "$install_id" ]]; then
            expected_id=$(canonical_packaged_macho_id \
                "$tree_root" "$binary" || true)
            [[ -n "$expected_id" ]] && [[ "$install_id" == "$expected_id" ]] || {
                echo "ERROR: Noncanonical packaged Mach-O ID: $binary -> $install_id" >&2
                return 1
            }
        fi
        while IFS= read -r dependency; do
            [[ -n "$dependency" ]] || continue
            [[ -n "$install_id" ]] && [[ "$dependency" == "$install_id" ]] && continue
            expected_dependency=$(canonical_packaged_dependency \
                "$tree_root" "$dependency" || true)
            [[ -n "$expected_dependency" ]] \
                && [[ "$dependency" == "$expected_dependency" ]] || {
                echo "ERROR: Noncanonical packaged dependency: $binary -> $dependency" >&2
                return 1
            }
        done < <(worms_otool_dependencies "$binary")
        rpath=$(worms_macho_rpaths "$binary" | head -1 || true)
        [[ -z "$rpath" ]] || {
            echo "ERROR: Unexpected packaged LC_RPATH: $binary -> $rpath" >&2
            return 1
        }
        /usr/bin/python3 "$ROOT_DIR/tools/normalize_macho_uuid.py" \
            --check "$binary" || return 1
    done < <(find "$tree_root/Frameworks" "$tree_root/PlugIns" -type f -print0)
    [[ "$macho_count" -gt 0 ]] || {
        echo "ERROR: Qt package contains no Mach-O files to validate" >&2
        return 1
    }
}

usage() {
    echo "Usage: $0 [--check] EXTRACTED_QT_ROOT"
}

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
    shift
fi
[[ $# -eq 1 ]] || { usage >&2; exit 2; }
TREE_ROOT="$1"
worms_reject_control_chars "$TREE_ROOT" "Qt Mach-O tree"
[[ -d "$TREE_ROOT/Frameworks" ]] && [[ -d "$TREE_ROOT/PlugIns" ]] \
    && [[ ! -L "$TREE_ROOT" ]] || {
    echo "ERROR: Expected a real extracted Qt package root: $TREE_ROOT" >&2
    exit 1
}
for required_command in file find install_name_tool otool sort; do
    command -v "$required_command" >/dev/null 2>&1 \
        || { echo "ERROR: Missing command: $required_command" >&2; exit 1; }
done
[[ -x /usr/bin/python3 ]] || { echo "ERROR: /usr/bin/python3 is required" >&2; exit 1; }

if $CHECK_ONLY; then
    validate_normalized_macho_tree "$TREE_ROOT"
else
    normalize_packaged_macho_tree "$TREE_ROOT"
    validate_normalized_macho_tree "$TREE_ROOT"
fi
