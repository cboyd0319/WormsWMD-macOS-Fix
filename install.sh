#!/bin/bash
#
# install.sh - One-liner installer for Worms W.M.D macOS Fix
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash
#
# Or with options:
#   curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash -s -- --dry-run
#

set -euo pipefail

REPO_URL="https://github.com/cboyd0319/WormsWMD-macOS-Fix"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.wormswmd-fix}"

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' BLUE='' BOLD='' NC=''
fi

print_step() { echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"; }
print_error() { echo -e "${RED}✗${NC}  ${RED}ERROR:${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC}  ${GREEN}SUCCESS:${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC}  $1"; }

backup_install_dir() {
    local src="$1"
    local backup
    backup="${src}.backup.$(date +%s)"

    if mv "$src" "$backup"; then
        print_info "Existing install backed up to: $backup"
    else
        print_error "Failed to back up existing install at: $src"
        exit 1
    fi
}

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}     ${GREEN}Worms W.M.D - macOS Tahoe Fix Installer${NC}                 ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
print_step "Checking prerequisites..."

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    print_error "This fix is only for macOS."
    exit 1
fi

# Check for prerequisites
if ! command -v git &>/dev/null; then
    print_error "git is required but not installed."
    exit 1
fi

if ! command -v curl &>/dev/null; then
    print_error "curl is required but not installed."
    exit 1
fi

print_success "Prerequisites OK!"
echo ""

# Download/update the fix
print_step "Downloading fix..."

if [[ -f "$INSTALL_DIR" ]]; then
    print_error "INSTALL_DIR points to a file: $INSTALL_DIR"
    exit 1
fi

mkdir -p "$(dirname "$INSTALL_DIR")"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    print_info "Updating existing installation..."
    # Try fast-forward pull first
    if git -C "$INSTALL_DIR" pull --quiet --ff-only origin main 2>/dev/null; then
        : # Success
    else
        print_info "Update failed; reinstalling..."
        backup_install_dir "$INSTALL_DIR"
        git clone --quiet "$REPO_URL.git" "$INSTALL_DIR"
    fi
else
    # Fresh installation
    if [[ -d "$INSTALL_DIR" ]]; then
        backup_install_dir "$INSTALL_DIR"
    fi
    git clone --quiet "$REPO_URL.git" "$INSTALL_DIR"
fi

print_success "Fix downloaded to: $INSTALL_DIR"
echo ""

# Sanity check
if [[ ! -f "$INSTALL_DIR/fix_worms_wmd.sh" ]]; then
    print_error "Download incomplete: fix_worms_wmd.sh not found."
    exit 1
fi

# Make scripts executable
chmod +x "$INSTALL_DIR/fix_worms_wmd.sh"
if [[ -d "$INSTALL_DIR/scripts" ]]; then
    shopt -s nullglob
    script_files=("$INSTALL_DIR/scripts/"*.sh)
    if (( ${#script_files[@]} )); then
        chmod +x "${script_files[@]}"
    fi
    shopt -u nullglob
fi

# Run the fix
print_step "Running fix..."
echo ""

cd "$INSTALL_DIR"
./fix_worms_wmd.sh "$@"
