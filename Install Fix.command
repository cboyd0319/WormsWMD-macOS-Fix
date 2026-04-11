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
echo -e "${BLUE}║${NC}     ${GREEN}${BOLD}Worms W.M.D - macOS Fix Installer${NC}                        ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}     Fix for macOS 26 (Tahoe) and later                         ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check git
if ! command -v git &>/dev/null; then
    echo -e "${YELLOW}Installing required tools...${NC}"
    xcode-select --install 2>/dev/null || true
    echo ""
    echo "After installation, run this again."
    read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
    exit 0
fi

REPO_URL="https://github.com/cboyd0319/WormsWMD-macOS-Fix"
INSTALL_DIR="$HOME/.wormswmd-fix"

backup_install_dir() {
    local src="$1"
    local backup="${src}.backup.$(date +%s)"

    if mv "$src" "$backup"; then
        echo -e "${CYAN}Backup created: $backup${NC}"
    else
        echo -e "${RED}Backup failed: $src${NC}"
        exit 1
    fi
}

# Clone or update
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo -e "${CYAN}Updating fix scripts...${NC}"
    
    if ! git -C "$INSTALL_DIR" pull --progress --ff-only origin main; then
        echo -e "${YELLOW}Update failed → reinstalling...${NC}"
        backup_install_dir "$INSTALL_DIR"

        echo -e "${CYAN}Cloning repository (this may take time)...${NC}"
        git clone --progress "$REPO_URL.git" "$INSTALL_DIR"
    fi
else
    echo -e "${CYAN}Downloading fix scripts...${NC}"

    if [[ -d "$INSTALL_DIR" ]]; then
        backup_install_dir "$INSTALL_DIR"
    fi

    echo -e "${CYAN}Cloning repository (this may take time, you will see progress)...${NC}"
    
    if ! git clone --progress "$REPO_URL.git" "$INSTALL_DIR"; then
        echo ""
        echo -e "${RED}Download failed.${NC}"
        echo "Check your internet connection."
        read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
        exit 1
    fi
fi

echo ""

# Check
if [[ ! -f "$INSTALL_DIR/fix_worms_wmd.sh" ]]; then
    echo -e "${RED}Error: fix script not found.${NC}"
    read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
    exit 1
fi

cd "$INSTALL_DIR" || exit 1

chmod +x fix_worms_wmd.sh

echo -e "${GREEN}Running fix...${NC}"
echo ""

./fix_worms_wmd.sh

echo ""
echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
echo ""
echo -e "${GREEN}Done!${NC}"
echo "You can close this window."
echo ""

read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
