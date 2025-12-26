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
    read -n 1 -s -r -p "Press any key to exit..."
    exit 0
fi

INSTALL_DIR="$HOME/.wormswmd-fix"

# Clone or update the repository
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo -e "${CYAN}Updating fix scripts...${NC}"
    cd "$INSTALL_DIR" || exit 1
    git pull --quiet 2>/dev/null || true
else
    echo -e "${CYAN}Downloading fix scripts...${NC}"
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    if ! git clone --quiet https://github.com/cboyd0319/WormsWMD-macOS-Fix.git "$INSTALL_DIR" 2>/dev/null; then
        echo ""
        echo -e "${RED}Failed to download the fix.${NC}"
        echo ""
        echo "Please check your internet connection and try again."
        echo ""
        read -n 1 -s -r -p "Press any key to exit..."
        exit 1
    fi
    cd "$INSTALL_DIR" || exit 1
fi

echo ""

# Make the fix script executable and run it
chmod +x fix_worms_wmd.sh
./fix_worms_wmd.sh

# Keep the window open so user can see the result
echo ""
echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
echo ""
echo "You can close this window now."
echo ""
read -n 1 -s -r -p "Press any key to exit..."
