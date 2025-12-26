#!/bin/bash
#
# check_updates.sh - Check for fix updates on GitHub
#
# Compares the installed version with the latest release on GitHub
# and notifies if an update is available.
#
# Usage:
#   ./check_updates.sh              # Check and show result
#   ./check_updates.sh --quiet      # Silent, exit code only
#   ./check_updates.sh --download   # Download latest if available
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
GITHUB_REPO="cboyd0319/WormsWMD-macOS-Fix"
API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

QUIET=false
DOWNLOAD=false

print_help() {
    cat << 'EOF'
Worms W.M.D Fix - Update Checker

Checks for new versions of the fix on GitHub.

USAGE:
    ./check_updates.sh [OPTIONS]

OPTIONS:
    --quiet, -q     Silent mode (exit code only: 0=up to date, 1=update available)
    --download, -d  Download latest version if available
    --help, -h      Show this help

EXIT CODES:
    0   Up to date (or update downloaded successfully)
    1   Update available
    2   Error (network, parsing, etc.)

EXAMPLES:
    # Check for updates
    ./check_updates.sh

    # Silent check (for scripts)
    if ./check_updates.sh --quiet; then
        echo "Up to date"
    else
        echo "Update available"
    fi

EOF
}

# Get current version from fix script
get_current_version() {
    if [[ -f "$REPO_DIR/fix_worms_wmd.sh" ]]; then
        grep -m1 'VERSION=' "$REPO_DIR/fix_worms_wmd.sh" | cut -d'"' -f2
    else
        echo "unknown"
    fi
}

# Get latest version from GitHub
get_latest_version() {
    local response
    response=$(curl -sf "$API_URL" 2>/dev/null) || return 1

    # Extract tag_name (e.g., "v1.3.0")
    echo "$response" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//'
}

# Get download URL for latest release
get_download_url() {
    local response
    response=$(curl -sf "$API_URL" 2>/dev/null) || return 1

    # Get the zipball URL
    echo "$response" | grep -o '"zipball_url": *"[^"]*"' | head -1 | cut -d'"' -f4
}

# Compare versions (returns 0 if v1 >= v2, 1 if v1 < v2)
version_compare() {
    local v1="$1"
    local v2="$2"

    # Convert to comparable numbers
    local v1_parts v2_parts
    IFS='.' read -ra v1_parts <<< "$v1"
    IFS='.' read -ra v2_parts <<< "$v2"

    for i in 0 1 2; do
        local p1="${v1_parts[$i]:-0}"
        local p2="${v2_parts[$i]:-0}"

        if [[ "$p1" -gt "$p2" ]]; then
            return 0
        elif [[ "$p1" -lt "$p2" ]]; then
            return 1
        fi
    done

    return 0  # Equal
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet|-q)
            QUIET=true
            shift
            ;;
        --download|-d)
            DOWNLOAD=true
            shift
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 2
            ;;
    esac
done

# Get versions
current=$(get_current_version)
latest=$(get_latest_version)

if [[ -z "$latest" ]] || [[ "$latest" == "null" ]]; then
    if ! $QUIET; then
        echo -e "${RED}Could not check for updates (network error?)${NC}"
    fi
    exit 2
fi

if $QUIET; then
    if version_compare "$current" "$latest"; then
        exit 0  # Up to date
    else
        exit 1  # Update available
    fi
fi

# Verbose output
echo -e "${BLUE}Worms W.M.D Fix - Update Check${NC}"
echo ""
echo "Current version: $current"
echo "Latest version:  $latest"
echo ""

if version_compare "$current" "$latest"; then
    echo -e "${GREEN}You're up to date!${NC}"
    exit 0
else
    echo -e "${YELLOW}Update available!${NC}"
    echo ""
    echo "Release page: https://github.com/${GITHUB_REPO}/releases/latest"
    echo ""

    if $DOWNLOAD; then
        echo "Downloading latest version..."

        local download_url
        download_url=$(get_download_url)

        if [[ -z "$download_url" ]]; then
            echo -e "${RED}Could not get download URL${NC}"
            exit 2
        fi

        local download_file="$HOME/Downloads/WormsWMD-Fix-${latest}.zip"
        if curl -L -o "$download_file" "$download_url"; then
            echo -e "${GREEN}Downloaded: $download_file${NC}"
            echo ""
            echo "To install:"
            echo "  1. Extract the zip file"
            echo "  2. Replace your current fix folder"
            echo "  3. Run ./fix_worms_wmd.sh"
        else
            echo -e "${RED}Download failed${NC}"
            exit 2
        fi
    else
        echo "To update:"
        echo "  git -C \"$REPO_DIR\" pull"
        echo ""
        echo "Or download: ./check_updates.sh --download"
    fi

    exit 1
fi
