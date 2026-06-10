#!/bin/bash
#
# 06_fix_info_plist.sh
#
# Fixes missing or incorrect entries in the game's Info.plist:
# - Adds CFBundleIdentifier (required for proper app identity)
# - Adds NSHighResolutionCapable (enables Retina/HiDPI support)
# - Updates LSMinimumSystemVersion to a more reasonable value
#

set -euo pipefail

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
INFO_PLIST="$GAME_APP/Contents/Info.plist"
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
worms_log_init "06_fix_info_plist"
worms_debug_init

if [[ -z "$LOGGING_PRESET" ]]; then
    echo "Log file: $LOG_FILE"
    if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
        echo "Trace log: $TRACE_FILE"
    fi
fi

echo "=== Fixing Info.plist ==="

worms_reject_control_chars "$GAME_APP" "GAME_APP"
worms_validate_game_app_for_mutation "$GAME_APP" || {
    echo "ERROR: Unsafe game bundle mutation path: $GAME_APP"
    exit 1
}

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "ERROR: Info.plist not found at: $INFO_PLIST"
    exit 1
fi
worms_refuse_linked_file_for_mutation "$INFO_PLIST" "Info.plist" || exit 1
worms_path_inside_root "$GAME_APP/Contents" "$INFO_PLIST" || {
    echo "ERROR: Info.plist resolves outside the game bundle: $INFO_PLIST"
    exit 1
}

# Check if we can write to the plist
if [[ ! -w "$INFO_PLIST" ]]; then
    echo "ERROR: Cannot write to Info.plist (check permissions)"
    exit 1
fi

plist_has_key() {
    local key="$1"
    /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" >/dev/null 2>&1
}

plist_set_string() {
    local key="$1"
    local value="$2"

    if plist_has_key "$key"; then
        /usr/libexec/PlistBuddy -c "Set :$key '$value'" "$INFO_PLIST"
    else
        /usr/libexec/PlistBuddy -c "Add :$key string '$value'" "$INFO_PLIST"
    fi
}

plist_set_bool() {
    local key="$1"
    local value="$2"

    if plist_has_key "$key"; then
        /usr/libexec/PlistBuddy -c "Set :$key $value" "$INFO_PLIST"
    else
        /usr/libexec/PlistBuddy -c "Add :$key bool $value" "$INFO_PLIST"
    fi
}

current_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || true)
if [[ -z "$current_id" ]]; then
    echo "Setting CFBundleIdentifier..."
    plist_set_string "CFBundleIdentifier" "com.team17.wormswmd"
else
    echo "CFBundleIdentifier already set: $current_id"
fi

# Add or correct NSHighResolutionCapable
current_hidpi=$(/usr/libexec/PlistBuddy -c "Print :NSHighResolutionCapable" "$INFO_PLIST" 2>/dev/null || true)
if [[ "$current_hidpi" != "true" ]]; then
    echo "Enabling NSHighResolutionCapable..."
    plist_set_bool "NSHighResolutionCapable" "true"
else
    echo "NSHighResolutionCapable already set"
fi

# Add or correct NSSupportsAutomaticGraphicsSwitching for better battery life on laptops
current_graphics_switching=$(/usr/libexec/PlistBuddy -c "Print :NSSupportsAutomaticGraphicsSwitching" "$INFO_PLIST" 2>/dev/null || true)
if [[ "$current_graphics_switching" != "true" ]]; then
    echo "Enabling NSSupportsAutomaticGraphicsSwitching..."
    plist_set_bool "NSSupportsAutomaticGraphicsSwitching" "true"
else
    echo "NSSupportsAutomaticGraphicsSwitching already set"
fi

# Update LSMinimumSystemVersion to 10.13 (High Sierra) - more reasonable minimum
current_min=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST" 2>/dev/null || true)
if [[ -z "$current_min" || "$current_min" == "10.8" ]]; then
    echo "Setting LSMinimumSystemVersion to 10.13..."
    plist_set_string "LSMinimumSystemVersion" "10.13"
else
    echo "LSMinimumSystemVersion: $current_min"
fi

echo ""
echo "Info.plist fixes applied successfully!"
echo ""
echo "Updated entries:"
echo "  CFBundleIdentifier: $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || echo 'not set')"
echo "  NSHighResolutionCapable: $(/usr/libexec/PlistBuddy -c "Print :NSHighResolutionCapable" "$INFO_PLIST" 2>/dev/null || echo 'not set')"
echo "  NSSupportsAutomaticGraphicsSwitching: $(/usr/libexec/PlistBuddy -c "Print :NSSupportsAutomaticGraphicsSwitching" "$INFO_PLIST" 2>/dev/null || echo 'not set')"
echo "  LSMinimumSystemVersion: $(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST" 2>/dev/null || echo 'not set')"
