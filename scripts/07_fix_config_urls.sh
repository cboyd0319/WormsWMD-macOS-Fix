#!/bin/bash
#
# 07_fix_config_urls.sh
#
# Fixes security issues in game configuration files:
# - Updates HTTP URLs to HTTPS where possible
# - Removes/comments out internal staging URLs that shouldn't be in retail builds
# - Fixes URLs in both DataOSX and CommonData directories
#

set -euo pipefail

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
DATA_OSX_DIR="$GAME_APP/Contents/Resources/DataOSX"
COMMON_DATA_DIR="$GAME_APP/Contents/Resources/CommonData"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGGING_PRESET="${WORMSWMD_LOGGING_INITIALIZED:-}"

# shellcheck disable=SC1091
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

fix_count=0

# Function to fix a single config file
fix_config_file() {
    local config_path="$1"
    local config_name
    config_name="$(basename "$config_path")"

    if [[ ! -f "$config_path" ]]; then
        return 0
    fi

    echo "Processing $config_name..."

    # Create backup
    if [[ ! -f "${config_path}.backup" ]]; then
        cp "$config_path" "${config_path}.backup"
    fi

    # Fix HTTP to HTTPS for external Team17 URL
    if grep -q 'http://www\.team17\.com' "$config_path"; then
        echo "  Updating Team17 URL to HTTPS..."
        sed -i '' 's|http://www\.team17\.com|https://www.team17.com|g' "$config_path"
        ((fix_count++)) || true
    fi

    # Comment out internal/staging URLs (these shouldn't be in retail builds)
    if grep -q 'URL_Internal.*xom\.team17\.com' "$config_path"; then
        echo "  Commenting out internal staging URL..."
        sed -i '' 's|^\([[:space:]]*URL_Internal.*xom\.team17\.com.*\)$|// DISABLED: \1|g' "$config_path"
        ((fix_count++)) || true
    fi

    # Fix HTTP to HTTPS for Google Analytics (in comments/examples)
    if grep -q 'http://www\.google-analytics\.com' "$config_path"; then
        echo "  Updating Google Analytics URL to HTTPS..."
        sed -i '' 's|http://www\.google-analytics\.com|https://www.google-analytics.com|g' "$config_path"
        ((fix_count++)) || true
    fi

    # Fix MainUrl in AnalyticsConfig if it uses HTTP
    if grep -q 'MainUrl.*=.*"http://' "$config_path"; then
        echo "  Updating MainUrl to HTTPS..."
        sed -i '' 's|MainUrl[[:space:]]*=[[:space:]]*"http://|MainUrl = "https://|g' "$config_path"
        ((fix_count++)) || true
    fi
}

# Fix DataOSX config files
if [[ -d "$DATA_OSX_DIR" ]]; then
    echo ""
    echo "--- DataOSX Directory ---"
    for config_file in "SteamConfig.txt" "SteamConfigDemo.txt" "GOGConfig.txt" "PcLanConfig.txt" "SwitchConfig.txt" "SwitchConfigGOG.txt"; do
        fix_config_file "$DATA_OSX_DIR/$config_file"
    done
else
    echo "WARNING: DataOSX directory not found at: $DATA_OSX_DIR"
fi

# Fix CommonData config files
if [[ -d "$COMMON_DATA_DIR" ]]; then
    echo ""
    echo "--- CommonData Directory ---"
    for config_file in "AnalyticsConfig.txt" "HttpConfig.txt"; do
        fix_config_file "$COMMON_DATA_DIR/$config_file"
    done
else
    echo "WARNING: CommonData directory not found at: $COMMON_DATA_DIR"
fi

echo ""
if [[ $fix_count -gt 0 ]]; then
    echo "Fixed $fix_count URL issues in configuration files."
else
    echo "No URL fixes needed (already fixed or not present)."
fi
echo ""
echo "Backups saved with .backup extension"
