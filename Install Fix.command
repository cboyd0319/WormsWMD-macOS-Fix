#!/bin/bash
#
# Worms W.M.D - macOS Fix Installer
#
# INSTRUCTIONS:
#   1. Download this file
#   2. Double-click to run
#   3. If macOS says the file can't be opened, right-click it and choose "Open"
#   4. Click "Open" in the dialog that appears
#
# Everything else is automatic!
#

set -euo pipefail

# Move to a sensible directory (in case we're in Downloads or somewhere weird)
cd "$HOME" || exit 1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}                                                                ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}     ${GREEN}${BOLD}Worms W.M.D - macOS Fix Installer${NC}                        ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                                ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}     This will fix Worms W.M.D to work on macOS 26 (Tahoe)     ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}     and later. The process is fully automatic.                ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                                ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if git is available
if ! command -v git &>/dev/null; then
    echo -e "${YELLOW}Installing required tools...${NC}"
    echo ""
    echo "A dialog will appear asking to install developer tools."
    echo "Click 'Install' to continue."
    echo ""
    xcode-select --install 2>/dev/null || true
    echo ""
    echo "Please wait for the installation to complete, then run this installer again."
    echo ""
    read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
    exit 0
fi

REPO_URL="https://github.com/cboyd0319/WormsWMD-macOS-Fix"
INSTALL_DIR="$HOME/.wormswmd-fix"

backup_install_dir() {
    local src="$1"
    local backup
    backup="${src}.backup.$(date +%s)"

    if mv "$src" "$backup"; then
        echo -e "${CYAN}Existing install backed up to: $backup${NC}"
    else
        echo -e "${RED}Failed to back up existing install at: $src${NC}"
        exit 1
    fi
}

# Clone or update the repository
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo -e "${CYAN}Updating fix scripts...${NC}"
    if git -C "$INSTALL_DIR" pull --quiet --ff-only origin main 2>/dev/null; then
        :
    else
        echo -e "${YELLOW}Update failed; reinstalling...${NC}"
        backup_install_dir "$INSTALL_DIR"
        git clone --quiet "$REPO_URL.git" "$INSTALL_DIR"
    fi
else
    echo -e "${CYAN}Downloading fix scripts...${NC}"
    if [[ -d "$INSTALL_DIR" ]]; then
        backup_install_dir "$INSTALL_DIR"
    fi
    if ! git clone --quiet "$REPO_URL.git" "$INSTALL_DIR" 2>/dev/null; then
        echo ""
        echo -e "${RED}Failed to download the fix.${NC}"
        echo ""
        echo "Please check your internet connection and try again."
        echo ""
        read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
        exit 1
    fi
fi

echo ""

# Sanity check
if [[ ! -f "$INSTALL_DIR/fix_worms_wmd.sh" ]]; then
    echo -e "${RED}Download incomplete: fix_worms_wmd.sh not found.${NC}"
    read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
    exit 1
fi

cd "$INSTALL_DIR" || exit 1

# Make the fix script executable and run it
chmod +x fix_worms_wmd.sh
./fix_worms_wmd.sh

# Keep the window open so user can see the result
echo ""
echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
echo ""
echo "You can close this window now."
echo ""
read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
