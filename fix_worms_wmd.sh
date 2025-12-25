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
#   ./fix_worms_wmd.sh --help    # Show help
#
# Environment Variables:
#   GAME_APP - Path to Worms W.M.D.app (if non-standard location)
#
# Requirements:
#   - Intel Homebrew (/usr/local/bin/brew)
#   - Qt 5 (arch -x86_64 /usr/local/bin/brew install qt@5)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
VERSION="1.0.0"

# Default game location (uses $HOME instead of ~ for reliability)
DEFAULT_GAME_PATH="$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
GAME_APP="${GAME_APP:-$DEFAULT_GAME_PATH}"

# Colors for output (with fallback for non-color terminals)
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}     ${GREEN}Worms W.M.D - macOS Tahoe (26.x) Fix${NC}                   ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}                    Version ${VERSION}                            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"
}

print_substep() {
    echo -e "    $1"
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

show_help() {
    cat << EOF
Worms W.M.D - macOS Tahoe (26.x) Fix v${VERSION}

USAGE:
    ./fix_worms_wmd.sh [OPTIONS]

OPTIONS:
    --help, -h      Show this help message
    --verify, -v    Verify installation without making changes
    --restore, -r   Restore game from backup

ENVIRONMENT VARIABLES:
    GAME_APP        Path to "Worms W.M.D.app" (for non-standard locations)

EXAMPLES:
    # Apply the fix (default Steam location)
    ./fix_worms_wmd.sh

    # Apply fix for game in custom location
    GAME_APP="/path/to/Worms W.M.D.app" ./fix_worms_wmd.sh

    # Verify current installation
    ./fix_worms_wmd.sh --verify

    # Restore from backup
    ./fix_worms_wmd.sh --restore

REQUIREMENTS:
    1. Intel Homebrew: /usr/local/bin/brew
       Install: arch -x86_64 /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    2. Qt 5 (x86_64):
       Install: arch -x86_64 /usr/local/bin/brew install qt@5

    3. Rosetta 2 (Apple Silicon only):
       Install: softwareupdate --install-rosetta

For more information, see: https://github.com/cboyd0319/WormsWMD-macOS-Fix
EOF
}

# Parse arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --restore|-r)
        print_header
        echo "Looking for backups..."
        echo ""

        backups=$(ls -d ~/Documents/WormsWMD-Backup-* 2>/dev/null || true)
        if [ -z "$backups" ]; then
            print_error "No backups found in ~/Documents/"
            echo ""
            echo "Backups are created automatically when running the fix."
            echo "If you haven't run the fix yet, there's nothing to restore."
            exit 1
        fi

        echo "Available backups:"
        echo "$backups"
        echo ""

        # Use the most recent backup
        latest=$(ls -dt ~/Documents/WormsWMD-Backup-* 2>/dev/null | head -1)
        echo "Most recent backup: $latest"
        echo ""

        read -p "Restore from this backup? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Restore cancelled."
            exit 0
        fi

        # Check game exists
        if [ ! -d "$GAME_APP" ]; then
            print_error "Game not found at: $GAME_APP"
            echo ""
            echo "Set GAME_APP if your game is in a different location:"
            echo "  GAME_APP=\"/path/to/Worms W.M.D.app\" ./fix_worms_wmd.sh --restore"
            exit 1
        fi

        print_step "Restoring Frameworks..."
        rm -rf "$GAME_APP/Contents/Frameworks"
        cp -R "$latest/Frameworks" "$GAME_APP/Contents/"

        print_step "Restoring PlugIns..."
        rm -rf "$GAME_APP/Contents/PlugIns"
        cp -R "$latest/PlugIns" "$GAME_APP/Contents/"

        echo ""
        print_success "Game restored to original state."
        echo ""
        echo "You may want to verify game files in Steam:"
        echo "  Right-click Worms W.M.D → Properties → Local Files → Verify integrity"
        exit 0
        ;;
    --verify|-v)
        print_header
        export GAME_APP
        chmod +x "$SCRIPTS_DIR/05_verify_installation.sh"
        "$SCRIPTS_DIR/05_verify_installation.sh"
        exit $?
        ;;
    "")
        # No argument - continue with fix
        ;;
    *)
        print_error "Unknown option: $1"
        echo ""
        echo "Run './fix_worms_wmd.sh --help' for usage information."
        exit 1
        ;;
esac

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
print_substep "Game found: $GAME_APP"

# Check macOS version
macos_version=$(sw_vers -productVersion)
major_version=$(echo "$macos_version" | cut -d. -f1)
print_substep "macOS version: $macos_version"

if [ "$major_version" -lt 26 ]; then
    echo ""
    print_warning "This fix is designed for macOS 26 (Tahoe) and later."
    echo "         Your version ($macos_version) may not need this fix."
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Fix cancelled."
        exit 0
    fi
fi

# Check architecture
arch_name=$(uname -m)
print_substep "Architecture: $arch_name"

if [ "$arch_name" = "arm64" ]; then
    # Check Rosetta
    if ! /usr/bin/pgrep -q oahd; then
        echo ""
        print_error "Rosetta 2 is not running."
        echo ""
        echo "Rosetta 2 is required to run x86_64 applications on Apple Silicon."
        echo "Install with: softwareupdate --install-rosetta"
        exit 1
    fi
    print_substep "Rosetta 2: installed"
fi

# Check Intel Homebrew
if [ ! -f "/usr/local/bin/brew" ]; then
    echo ""
    print_error "Intel Homebrew not found at /usr/local/bin/brew"
    echo ""
    echo "This fix requires Intel (x86_64) Homebrew to obtain Qt libraries."
    echo ""
    echo "Install Intel Homebrew with:"
    echo "  arch -x86_64 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi
print_substep "Intel Homebrew: found"

# Check Qt 5
if [ ! -d "/usr/local/opt/qt@5/lib/QtCore.framework" ]; then
    echo ""
    print_error "Qt 5 not found"
    echo ""
    echo "Install Qt 5 with:"
    echo "  arch -x86_64 /usr/local/bin/brew install qt@5"
    exit 1
fi
qt_version=$(ls /usr/local/Cellar/qt@5/ 2>/dev/null | head -1 || echo "unknown")
print_substep "Qt 5: $qt_version"

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

print_substep "Backup created: $BACKUP_DIR"

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
