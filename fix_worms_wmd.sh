#!/bin/bash
#
# fix_worms_wmd.sh - One-click fix for Worms W.M.D on macOS 26+
#
# This script fixes the black screen issue caused by Apple removing
# the AGL framework and the game using outdated Qt libraries.
#
# Usage:
#   ./fix_worms_wmd.sh           # Apply the fix
#   ./fix_worms_wmd.sh --restore # Restore from backup
#   ./fix_worms_wmd.sh --verify  # Verify installation only
#
# Requirements:
#   - Intel Homebrew (/usr/local/bin/brew)
#   - Qt 5 (arch -x86_64 /usr/local/bin/brew install qt@5)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# Default game location
GAME_APP="${GAME_APP:-/Users/$USER/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}     ${GREEN}Worms W.M.D - macOS Tahoe (26.x) Fix${NC}                   ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}                    Version 1.0.0                            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

print_success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}

# Check if running with --restore
if [ "$1" = "--restore" ]; then
    print_header
    echo "Looking for backups..."
    echo ""

    backups=$(ls -d ~/Documents/WormsWMD-Backup-* 2>/dev/null || true)
    if [ -z "$backups" ]; then
        print_error "No backups found in ~/Documents/"
        exit 1
    fi

    echo "Available backups:"
    echo "$backups"
    echo ""

    # Use the most recent backup
    latest=$(ls -dt ~/Documents/WormsWMD-Backup-* 2>/dev/null | head -1)
    echo "Using most recent backup: $latest"
    echo ""

    read -p "Restore from this backup? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Restore cancelled."
        exit 0
    fi

    print_step "Restoring Frameworks..."
    rm -rf "$GAME_APP/Contents/Frameworks"
    cp -R "$latest/Frameworks" "$GAME_APP/Contents/"

    print_step "Restoring PlugIns..."
    rm -rf "$GAME_APP/Contents/PlugIns"
    cp -R "$latest/PlugIns" "$GAME_APP/Contents/"

    print_success "Game restored to original state."
    exit 0
fi

# Check if running with --verify
if [ "$1" = "--verify" ]; then
    print_header
    chmod +x "$SCRIPTS_DIR/05_verify_installation.sh"
    "$SCRIPTS_DIR/05_verify_installation.sh"
    exit $?
fi

print_header

# ============================================================
# Pre-flight checks
# ============================================================
print_step "Running pre-flight checks..."

# Check game exists
if [ ! -d "$GAME_APP" ]; then
    print_error "Game not found at: $GAME_APP"
    echo ""
    echo "If your game is in a different location, set GAME_APP:"
    echo "  GAME_APP=\"/path/to/Worms W.M.D.app\" ./fix_worms_wmd.sh"
    exit 1
fi
echo "  Game found: $GAME_APP"

# Check macOS version
macos_version=$(sw_vers -productVersion)
major_version=$(echo "$macos_version" | cut -d. -f1)
echo "  macOS version: $macos_version"

if [ "$major_version" -lt 26 ]; then
    print_warning "This fix is designed for macOS 26 (Tahoe) and later."
    echo "  Your version ($macos_version) may not need this fix."
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Fix cancelled."
        exit 0
    fi
fi

# Check architecture
arch_name=$(uname -m)
echo "  Architecture: $arch_name"

if [ "$arch_name" = "arm64" ]; then
    # Check Rosetta
    if ! /usr/bin/pgrep -q oahd; then
        print_error "Rosetta 2 is not running."
        echo "  Install with: softwareupdate --install-rosetta"
        exit 1
    fi
    echo "  Rosetta 2: installed"
fi

# Check Intel Homebrew
if [ ! -f "/usr/local/bin/brew" ]; then
    print_error "Intel Homebrew not found at /usr/local/bin/brew"
    echo ""
    echo "Install Intel Homebrew with:"
    echo "  arch -x86_64 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi
echo "  Intel Homebrew: found"

# Check Qt 5
if [ ! -d "/usr/local/opt/qt@5/lib/QtCore.framework" ]; then
    print_error "Qt 5 not found"
    echo ""
    echo "Install Qt 5 with:"
    echo "  arch -x86_64 /usr/local/bin/brew install qt@5"
    exit 1
fi
qt_version=$(ls /usr/local/Cellar/qt@5/ 2>/dev/null | head -1)
echo "  Qt 5: $qt_version"

echo ""
print_success "Pre-flight checks passed!"

# ============================================================
# Create backup
# ============================================================
echo ""
print_step "Creating backup..."

BACKUP_DIR=~/Documents/WormsWMD-Backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"

cp -R "$GAME_APP/Contents/Frameworks" "$BACKUP_DIR/"
cp -R "$GAME_APP/Contents/PlugIns" "$BACKUP_DIR/"

echo "  Backup created: $BACKUP_DIR"

# ============================================================
# Apply fixes
# ============================================================
echo ""
print_step "Building AGL stub library..."
chmod +x "$SCRIPTS_DIR/01_build_agl_stub.sh"
"$SCRIPTS_DIR/01_build_agl_stub.sh"

echo ""
print_step "Replacing Qt frameworks..."
chmod +x "$SCRIPTS_DIR/02_replace_qt_frameworks.sh"
export GAME_APP
"$SCRIPTS_DIR/02_replace_qt_frameworks.sh"

echo ""
print_step "Copying dependencies..."
chmod +x "$SCRIPTS_DIR/03_copy_dependencies.sh"
"$SCRIPTS_DIR/03_copy_dependencies.sh"

echo ""
print_step "Fixing library paths..."
chmod +x "$SCRIPTS_DIR/04_fix_library_paths.sh"
"$SCRIPTS_DIR/04_fix_library_paths.sh"

# ============================================================
# Verify installation
# ============================================================
echo ""
print_step "Verifying installation..."
chmod +x "$SCRIPTS_DIR/05_verify_installation.sh"
"$SCRIPTS_DIR/05_verify_installation.sh"

# ============================================================
# Done
# ============================================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                    ${GREEN}FIX COMPLETE!${NC}                            ${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "The fix has been applied. Launch Worms W.M.D from Steam to test."
echo ""
echo "If you need to restore the original files:"
echo "  ./fix_worms_wmd.sh --restore"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
