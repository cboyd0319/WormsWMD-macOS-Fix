#!/bin/bash
#
# 07_fix_config_urls.sh
#
# Fixes security issues in game configuration files:
# - Updates HTTP URLs to HTTPS where possible
# - Removes/comments out internal staging URLs that shouldn't be in retail builds
#

set -e

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
DATA_DIR="$GAME_APP/Contents/Resources/DataOSX"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGGING_PRESET="${WORMSWMD_LOGGING_INITIALIZED:-}"

source "$SCRIPT_DIR/logging.sh"
worms_log_init "07_fix_config_urls"
worms_debug_init

if [[ -z "$LOGGING_PRESET" ]]; then
    echo "Log file: $LOG_FILE"
    if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
        echo "Trace log: $TRACE_FILE"
    fi
fi

echo "=== Fixing Configuration URLs ==="

if [[ ! -d "$DATA_DIR" ]]; then
    echo "ERROR: DataOSX directory not found at: $DATA_DIR"
    exit 1
fi

# List of config files to fix
CONFIG_FILES=(
    "SteamConfig.txt"
    "SteamConfigDemo.txt"
    "GOGConfig.txt"
)

fix_count=0

for config_file in "${CONFIG_FILES[@]}"; do
    config_path="$DATA_DIR/$config_file"

    if [[ ! -f "$config_path" ]]; then
        echo "Skipping $config_file (not found)"
        continue
    fi

    echo "Processing $config_file..."

    # Create backup
    if [[ ! -f "${config_path}.backup" ]]; then
        cp "$config_path" "${config_path}.backup"
    fi

    # Fix HTTP to HTTPS for external Team17 URL
    if grep -q 'http://www.team17.com' "$config_path"; then
        echo "  Updating Team17 URL to HTTPS..."
        sed -i '' 's|http://www\.team17\.com|https://www.team17.com|g' "$config_path"
        ((fix_count++)) || true
    fi

    # Comment out internal/staging URLs (these shouldn't be in retail builds)
    # We comment rather than delete to preserve the structure
    if grep -q 'URL_Internal.*xom\.team17\.com' "$config_path"; then
        echo "  Commenting out internal staging URL..."
        sed -i '' 's|^\([[:space:]]*URL_Internal.*xom\.team17\.com.*\)$|// DISABLED: \1|g' "$config_path"
        ((fix_count++)) || true
    fi
done

echo ""
if [[ $fix_count -gt 0 ]]; then
    echo "Fixed $fix_count URL issues in configuration files."
else
    echo "No URL fixes needed (already fixed or not present)."
fi
echo ""
echo "Backups saved with .backup extension"
