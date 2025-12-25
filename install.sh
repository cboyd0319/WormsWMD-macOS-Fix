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
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

print_step() { echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"; }
print_error() { echo -e "${RED}✗${NC}  ${RED}ERROR:${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC}  ${GREEN}SUCCESS:${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC}  $1"; }

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

# Check architecture and Rosetta
arch_name=$(uname -m)
if [[ "$arch_name" == "arm64" ]]; then
    if ! /usr/bin/pgrep -q oahd 2>/dev/null; then
        echo ""
        print_error "Rosetta 2 is required but not installed."
        echo ""
        echo "Install Rosetta 2 with:"
        echo "  softwareupdate --install-rosetta"
        echo ""
        echo "Then run this installer again."
        exit 1
    fi
    print_info "Rosetta 2: installed"
fi

# Check Intel Homebrew
if [[ ! -f "/usr/local/bin/brew" ]]; then
    echo ""
    print_error "Intel Homebrew is required but not installed."
    echo ""
    echo "Install Intel Homebrew with:"
    echo "  arch -x86_64 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    echo ""
    echo "Then run this installer again."
    exit 1
fi
print_info "Intel Homebrew: found"

# Check Qt 5
if [[ ! -d "/usr/local/opt/qt@5/lib/QtCore.framework" ]]; then
    echo ""
    print_info "Qt 5 not found. Installing..."
    echo ""
    arch -x86_64 /usr/local/bin/brew install qt@5
    echo ""
fi
print_info "Qt 5: installed"

print_success "Prerequisites OK!"
echo ""

# Download/update the fix
print_step "Downloading fix..."

if [[ -d "$INSTALL_DIR/.git" ]]; then
    # Update existing installation
    print_info "Updating existing installation..."
    cd "$INSTALL_DIR"
    git pull --quiet origin main
else
    # Fresh clone
    rm -rf "$INSTALL_DIR"
    if command -v git &>/dev/null; then
        git clone --quiet "$REPO_URL.git" "$INSTALL_DIR"
    else
        # Fallback to curl + tar
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
