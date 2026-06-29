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
echo -e "${BLUE}║${NC}     Supports macOS 26+ and macOS 27 Golden Gate.              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}     The process is fully automatic.                           ${BLUE}║${NC}"
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
INSTALL_REF="v1.7.3"
INSTALL_COMMIT=""

directory_is_empty() {
    local dir="$1"

    [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

repo_remote_matches() {
    local dir="$1"
    local remote

    remote=$(git -C "$dir" config --get remote.origin.url 2>/dev/null || true)
    case "$remote" in
        "$REPO_URL"|"$REPO_URL.git"|git@github.com:cboyd0319/WormsWMD-macOS-Fix.git)
            return 0
            ;;
    esac

    return 1
}

verify_install_commit() {
    local actual_commit

    actual_commit=$(git -C "$INSTALL_DIR" rev-parse HEAD 2>/dev/null || true)
    if [[ "$INSTALL_COMMIT" == PENDING_* ]]; then
        echo -e "${RED}Release commit pin is not finalized for $INSTALL_REF.${NC}"
        echo "Replace INSTALL_COMMIT with the final release commit before publishing."
        read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
        exit 1
    fi
    if [[ -n "$INSTALL_COMMIT" ]] && [[ "$actual_commit" != "$INSTALL_COMMIT" ]]; then
        echo -e "${RED}Pinned release verification failed.${NC}"
        echo "Expected $INSTALL_COMMIT"
        echo "Got ${actual_commit:-unknown}"
        read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
        exit 1
    fi
}

# Clone or update the repository
if [[ -d "$INSTALL_DIR/.git" ]]; then
    if ! repo_remote_matches "$INSTALL_DIR"; then
        echo -e "${RED}$INSTALL_DIR is a Git repository for a different remote.${NC}"
        echo "Move it yourself or choose the Terminal installer with a different INSTALL_DIR."
        read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
        exit 1
    fi
    echo -e "${CYAN}Updating fix scripts...${NC}"
    if git -C "$INSTALL_DIR" fetch --progress --force origin "refs/tags/$INSTALL_REF:refs/tags/$INSTALL_REF" \
        && git -C "$INSTALL_DIR" checkout --detach "$INSTALL_REF"; then
        verify_install_commit
        :
    else
        echo -e "${RED}Update failed. Existing installation was left untouched.${NC}"
        read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
        exit 1
    fi
else
    echo -e "${CYAN}Downloading fix scripts...${NC}"
    if [[ -d "$INSTALL_DIR" ]]; then
        if ! directory_is_empty "$INSTALL_DIR"; then
            echo -e "${RED}$INSTALL_DIR already exists and is not an empty fix checkout.${NC}"
            echo "Move it yourself, then run this installer again."
            read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
            exit 1
        fi
    fi
    if ! git clone --progress --branch "$INSTALL_REF" --depth 1 "$REPO_URL.git" "$INSTALL_DIR"; then
        echo ""
        echo -e "${RED}Failed to download the fix.${NC}"
        echo ""
        echo "Please check your internet connection and try again."
        echo ""
        read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
        exit 1
    fi
    verify_install_commit
fi

echo ""

# Sanity check
if [[ ! -f "$INSTALL_DIR/fix_worms_wmd.sh" ]]; then
    echo -e "${RED}Download incomplete: fix_worms_wmd.sh not found.${NC}"
    read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
    exit 1
fi

cd "$INSTALL_DIR" || exit 1

# Make scripts executable and run the friendly launcher when available.
chmod +x fix_worms_wmd.sh
if [[ -f "Worms W.M.D Fix.command" ]]; then
    chmod +x "Worms W.M.D Fix.command"
fi
if [[ -d scripts ]]; then
    shopt -s nullglob
    script_files=(scripts/*.sh)
    if (( ${#script_files[@]} )); then
        chmod +x "${script_files[@]}"
    fi
    shopt -u nullglob
fi
if [[ -d tools ]]; then
    shopt -s nullglob
    tool_files=(tools/*.sh)
    if (( ${#tool_files[@]} )); then
        chmod +x "${tool_files[@]}"
    fi
    shopt -u nullglob
fi

if [[ -f "Worms W.M.D Fix.command" ]]; then
    ./"Worms W.M.D Fix.command"
else
    ./fix_worms_wmd.sh
fi

# Keep the window open so user can see the result
echo ""
echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
echo ""
echo "You can close this window now."
echo ""
read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
