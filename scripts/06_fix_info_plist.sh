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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGGING_PRESET="${WORMSWMD_LOGGING_INITIALIZED:-}"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/logging.sh"
worms_log_init "06_fix_info_plist"
worms_debug_init

if [[ -z "$LOGGING_PRESET" ]]; then
    echo "Log file: $LOG_FILE"
    if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
        echo "Trace log: $TRACE_FILE"
    fi
fi

echo "=== Fixing Info.plist ==="

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "ERROR: Info.plist not found at: $INFO_PLIST"
    exit 1
fi

# Check if we can write to the plist
if [[ ! -w "$INFO_PLIST" ]]; then
    echo "ERROR: Cannot write to Info.plist (check permissions)"
    exit 1
fi

# Add CFBundleIdentifier if missing
if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" &>/dev/null; then
    echo "Adding CFBundleIdentifier..."
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string 'com.team17.wormswmd'" "$INFO_PLIST"
else
    current_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || echo "")
    if [[ -z "$current_id" || "$current_id" == "" ]]; then
        echo "Setting CFBundleIdentifier..."
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier 'com.team17.wormswmd'" "$INFO_PLIST"
    else
        echo "CFBundleIdentifier already set: $current_id"
    fi
fi

# Add NSHighResolutionCapable if missing
if ! /usr/libexec/PlistBuddy -c "Print :NSHighResolutionCapable" "$INFO_PLIST" &>/dev/null; then
    echo "Adding NSHighResolutionCapable..."
    /usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$INFO_PLIST"
else
    echo "NSHighResolutionCapable already set"
fi

# Add NSSupportsAutomaticGraphicsSwitching for better battery life on laptops
if ! /usr/libexec/PlistBuddy -c "Print :NSSupportsAutomaticGraphicsSwitching" "$INFO_PLIST" &>/dev/null; then
    echo "Adding NSSupportsAutomaticGraphicsSwitching..."
    /usr/libexec/PlistBuddy -c "Add :NSSupportsAutomaticGraphicsSwitching bool true" "$INFO_PLIST"
else
    echo "NSSupportsAutomaticGraphicsSwitching already set"
fi

# Update LSMinimumSystemVersion to 10.13 (High Sierra) - more reasonable minimum
current_min=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST" 2>/dev/null || echo "10.8")
if [[ "$current_min" == "10.8" ]]; then
    echo "Updating LSMinimumSystemVersion from 10.8 to 10.13..."
    /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion '10.13'" "$INFO_PLIST"
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
