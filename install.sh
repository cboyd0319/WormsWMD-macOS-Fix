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

set -e

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

# Check for git or curl
if ! command -v git &>/dev/null && ! command -v curl &>/dev/null; then
    print_error "git or curl is required but not installed."
    exit 1
fi

print_success "Prerequisites OK!"
echo ""

# Download/update the fix
print_step "Downloading fix..."

mkdir -p "$(dirname "$INSTALL_DIR")"

if [[ -d "$INSTALL_DIR/.git" ]] && command -v git &>/dev/null; then
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
    if command -v git &>/dev/null; then
        git clone --quiet "$REPO_URL.git" "$INSTALL_DIR"
    else
        mkdir -p "$INSTALL_DIR"
        curl -fsSL "$REPO_URL/archive/refs/heads/main.tar.gz" | tar -xz -C "$INSTALL_DIR" --strip-components=1
    fi
fi

print_success "Fix downloaded to: $INSTALL_DIR"
echo ""

# Make scripts executable
chmod +x "$INSTALL_DIR/fix_worms_wmd.sh"
chmod +x "$INSTALL_DIR/scripts/"*.sh

# Run the fix
print_step "Running fix..."
echo ""

cd "$INSTALL_DIR"
./fix_worms_wmd.sh "$@"
