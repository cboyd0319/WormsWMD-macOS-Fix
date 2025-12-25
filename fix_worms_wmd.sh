#!/bin/bash
#
# fix_worms_wmd.sh - One-click fix for Worms W.M.D on macOS 26+
#
# This script fixes the black screen issue caused by Apple removing
# the AGL framework and the game using outdated Qt libraries.
#
# Usage:
#   ./fix_worms_wmd.sh             # Apply the fix
#   ./fix_worms_wmd.sh --restore   # Restore from backup
#   ./fix_worms_wmd.sh --verify    # Verify installation only
#   ./fix_worms_wmd.sh --dry-run   # Preview changes without applying
#   ./fix_worms_wmd.sh --help      # Show help
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
VERSION="1.1.0"

# Default game location (uses $HOME instead of ~ for reliability)
DEFAULT_GAME_PATH="$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
GAME_APP="${GAME_APP:-$DEFAULT_GAME_PATH}"

# Global state
DRY_RUN=false
BACKUP_DIR=""
CLEANUP_NEEDED=false
BUILD_DIR="/tmp/agl_stub_build"

# Colors for output (with fallback for non-color terminals)
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    DIM=''
    NC=''
fi

# ============================================================
# Output Functions
# ============================================================

print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}     ${GREEN}Worms W.M.D - macOS Tahoe (26.x) Fix${NC}                   ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}                    Version ${VERSION}                            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    if $DRY_RUN; then
        echo -e "                    ${YELLOW}[ DRY RUN MODE ]${NC}"
    fi
    echo ""
}

print_step() {
    echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"
}

print_substep() {
    echo -e "    $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  ${YELLOW}WARNING:${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC}  ${RED}ERROR:${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC}  ${GREEN}SUCCESS:${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC}  $1"
}

print_dry_run() {
    echo -e "${DIM}   [dry-run] $1${NC}"
}

# Spinner for long-running operations
spinner_pid=""

start_spinner() {
    local msg="$1"
    if [[ -t 1 ]] && ! $DRY_RUN; then
        (
            spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
            i=0
            while true; do
                printf "\r    ${CYAN}%s${NC} %s" "${spin:i++%${#spin}:1}" "$msg"
                sleep 0.1
            done
        ) &
        spinner_pid=$!
        disown
    fi
}

stop_spinner() {
    local success="${1:-true}"
    if [[ -n "$spinner_pid" ]]; then
        kill "$spinner_pid" 2>/dev/null || true
        wait "$spinner_pid" 2>/dev/null || true
        spinner_pid=""
        printf "\r\033[K"  # Clear line
    fi
}

# ============================================================
# Cleanup and Error Handling
# ============================================================

cleanup() {
    stop_spinner false

    # Clean up build directory
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR" 2>/dev/null || true
    fi
}

rollback() {
    stop_spinner false

    echo ""
    print_error "An error occurred during the fix process."

    if [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]] && $CLEANUP_NEEDED; then
        echo ""
        print_step "Rolling back changes from backup..."

        if [[ -d "$BACKUP_DIR/Frameworks" ]]; then
            rm -rf "$GAME_APP/Contents/Frameworks" 2>/dev/null || true
            cp -R "$BACKUP_DIR/Frameworks" "$GAME_APP/Contents/" 2>/dev/null || true
        fi

        if [[ -d "$BACKUP_DIR/PlugIns" ]]; then
            rm -rf "$GAME_APP/Contents/PlugIns" 2>/dev/null || true
            cp -R "$BACKUP_DIR/PlugIns" "$GAME_APP/Contents/" 2>/dev/null || true
        fi

        print_success "Rolled back to original state."
        print_info "Backup preserved at: $BACKUP_DIR"
    fi

    cleanup
    echo ""
    print_info "If you need help, please open an issue at:"
    echo "    https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues"
    echo ""
}

# Set up trap for errors
trap rollback ERR
trap cleanup EXIT

# ============================================================
# Detection Functions
# ============================================================

check_already_applied() {
    local game_frameworks="$GAME_APP/Contents/Frameworks"
    local applied=false
    local partial=false

    # Check for AGL stub
    if [[ -f "$game_frameworks/AGL.framework/Versions/A/AGL" ]]; then
        local agl_arch
        agl_arch=$(lipo -archs "$game_frameworks/AGL.framework/Versions/A/AGL" 2>/dev/null || echo "")
        if [[ "$agl_arch" == "x86_64" ]]; then
            # Check if it's our stub (small file size, ~50KB or less)
            local agl_size
            agl_size=$(stat -f%z "$game_frameworks/AGL.framework/Versions/A/AGL" 2>/dev/null || echo "0")
            if [[ "$agl_size" -lt 100000 ]]; then
                applied=true
            fi
        fi
    fi

    # Check for Qt 5.15 (vs original 5.3)
    if [[ -f "$game_frameworks/QtCore.framework/Versions/5/QtCore" ]]; then
        local qt_info
        qt_info=$(otool -L "$game_frameworks/QtCore.framework/Versions/5/QtCore" 2>/dev/null | head -2 || echo "")
        if echo "$qt_info" | grep -q "5.15"; then
            applied=true
        elif echo "$qt_info" | grep -q "5.3"; then
            if $applied; then
                partial=true
                applied=false
            fi
        fi
    fi

    # Check for bundled dependencies
    if [[ -f "$game_frameworks/libglib-2.0.0.dylib" ]]; then
        applied=true
    fi

    if $partial; then
        echo "partial"
    elif $applied; then
        echo "yes"
    else
        echo "no"
    fi
}

# ============================================================
# Help
# ============================================================

show_help() {
    cat << EOF
${BOLD}Worms W.M.D - macOS Tahoe (26.x) Fix v${VERSION}${NC}

${BOLD}USAGE:${NC}
    ./fix_worms_wmd.sh [OPTIONS]

${BOLD}OPTIONS:${NC}
    --help, -h      Show this help message
    --verify, -v    Verify installation without making changes
    --restore, -r   Restore game from backup
    --dry-run, -n   Preview changes without applying them
    --force, -f     Skip confirmation prompts

${BOLD}ENVIRONMENT VARIABLES:${NC}
    GAME_APP        Path to "Worms W.M.D.app" (for non-standard locations)

${BOLD}EXAMPLES:${NC}
    # Apply the fix (default Steam location)
    ./fix_worms_wmd.sh

    # Preview what will happen without making changes
    ./fix_worms_wmd.sh --dry-run

    # Apply fix for game in custom location
    GAME_APP="/path/to/Worms W.M.D.app" ./fix_worms_wmd.sh

    # Verify current installation
    ./fix_worms_wmd.sh --verify

    # Restore from backup
    ./fix_worms_wmd.sh --restore

${BOLD}REQUIREMENTS:${NC}
    1. Intel Homebrew: /usr/local/bin/brew
       Install: arch -x86_64 /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    2. Qt 5 (x86_64):
       Install: arch -x86_64 /usr/local/bin/brew install qt@5

    3. Rosetta 2 (Apple Silicon only):
       Install: softwareupdate --install-rosetta

${BOLD}MORE INFO:${NC}
    Repository: https://github.com/cboyd0319/WormsWMD-macOS-Fix
    Issues:     https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues
EOF
}

# ============================================================
# Restore Function
# ============================================================

do_restore() {
    print_header
    echo "Looking for backups..."
    echo ""

    backups=$(ls -d ~/Documents/WormsWMD-Backup-* 2>/dev/null || true)
    if [[ -z "$backups" ]]; then
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

    if ! $FORCE; then
        read -p "Restore from this backup? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Restore cancelled."
            exit 0
        fi
    fi

    # Check game exists
    if [[ ! -d "$GAME_APP" ]]; then
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
}

# ============================================================
# Verify Function
# ============================================================

do_verify() {
    print_header
    export GAME_APP
    chmod +x "$SCRIPTS_DIR/05_verify_installation.sh"
    "$SCRIPTS_DIR/05_verify_installation.sh"
    exit $?
}

# ============================================================
# Dry Run Function
# ============================================================

do_dry_run() {
    print_header

    print_step "Pre-flight checks..."

    # Check game exists
    if [[ ! -d "$GAME_APP" ]]; then
        print_error "Game not found at: $GAME_APP"
        exit 1
    fi
    print_dry_run "Game found: $GAME_APP"

    # Check macOS version
    local macos_version major_version
    macos_version=$(sw_vers -productVersion)
    major_version=$(echo "$macos_version" | cut -d. -f1)
    print_dry_run "macOS version: $macos_version"

    if [[ "$major_version" -lt 26 ]]; then
        print_dry_run "Note: This fix is designed for macOS 26+, your version may not need it"
    fi

    # Check architecture
    local arch_name
    arch_name=$(uname -m)
    print_dry_run "Architecture: $arch_name"

    if [[ "$arch_name" == "arm64" ]]; then
        if /usr/bin/pgrep -q oahd 2>/dev/null; then
            print_dry_run "Rosetta 2: installed"
        else
            print_error "Rosetta 2 is not running"
            exit 1
        fi
    fi

    # Check Intel Homebrew
    if [[ ! -f "/usr/local/bin/brew" ]]; then
        print_error "Intel Homebrew not found"
        exit 1
    fi
    print_dry_run "Intel Homebrew: found"

    # Check Qt 5
    if [[ ! -d "/usr/local/opt/qt@5/lib/QtCore.framework" ]]; then
        print_error "Qt 5 not found"
        exit 1
    fi
    local qt_version
    qt_version=$(ls /usr/local/Cellar/qt@5/ 2>/dev/null | head -1 || echo "unknown")
    print_dry_run "Qt 5: $qt_version"

    echo ""
    print_step "Changes that would be made..."
    echo ""

    print_dry_run "Create backup at: ~/Documents/WormsWMD-Backup-YYYYMMDD-HHMMSS/"
    echo ""

    print_dry_run "Build AGL stub library (x86_64)"
    print_dry_run "  Source: $SCRIPT_DIR/src/agl_stub.c"
    print_dry_run "  Target: $GAME_APP/Contents/Frameworks/AGL.framework/"
    echo ""

    print_dry_run "Replace Qt frameworks:"
    for fw in QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus; do
        print_dry_run "  $fw.framework (5.3.2 → $qt_version)"
    done
    echo ""

    print_dry_run "Copy dependencies from /usr/local/opt/:"
    local deps="libpcre2-16 libpcre2-8 libzstd libgthread-2.0 libglib-2.0 libintl libpng16 libfreetype libmd4c libjpeg libtiff liblzma libwebp libwebpdemux libwebpmux libsharpyuv"
    for dep in $deps; do
        print_dry_run "  ${dep}.dylib"
    done
    echo ""

    print_dry_run "Update library paths to use @executable_path"
    print_dry_run "Replace platform plugin: libqcocoa.dylib"
    print_dry_run "Update image format plugins"
    echo ""

    print_success "Dry run complete. No changes were made."
    echo ""
    echo "To apply these changes, run:"
    echo "  ./fix_worms_wmd.sh"
    exit 0
}

# ============================================================
# Main Fix Function
# ============================================================

do_fix() {
    print_header

    # ============================================================
    # Check if already applied
    # ============================================================
    print_step "Checking current state..."

    local applied_status
    applied_status=$(check_already_applied)

    if [[ "$applied_status" == "yes" ]]; then
        echo ""
        print_info "This fix appears to have already been applied."
        echo ""
        echo "    The game already has:"
        echo "    • AGL stub framework installed"
        echo "    • Qt 5.15 frameworks"
        echo "    • Bundled dependencies"
        echo ""

        if ! $FORCE; then
            read -p "Re-apply the fix anyway? [y/N] " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo ""
                print_info "To verify the installation, run: ./fix_worms_wmd.sh --verify"
                exit 0
            fi
        fi
        echo ""
    elif [[ "$applied_status" == "partial" ]]; then
        print_warning "A partial fix was detected. Re-applying to ensure completeness."
        echo ""
    fi

    # ============================================================
    # Pre-flight checks
    # ============================================================
    print_step "Running pre-flight checks..."

    # Check game exists
    if [[ ! -d "$GAME_APP" ]]; then
        print_error "Game not found at: $GAME_APP"
        echo ""
        echo "If your game is in a different location, set GAME_APP:"
        echo "  GAME_APP=\"/path/to/Worms W.M.D.app\" ./fix_worms_wmd.sh"
        exit 1
    fi
    print_substep "Game found: $GAME_APP"

    # Check macOS version
    local macos_version major_version
    macos_version=$(sw_vers -productVersion)
    major_version=$(echo "$macos_version" | cut -d. -f1)
    print_substep "macOS version: $macos_version"

    if [[ "$major_version" -lt 26 ]]; then
        echo ""
        print_warning "This fix is designed for macOS 26 (Tahoe) and later."
        echo "         Your version ($macos_version) may not need this fix."
        echo ""
        if ! $FORCE; then
            read -p "Continue anyway? [y/N] " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Fix cancelled."
                exit 0
            fi
        fi
    fi

    # Check architecture
    local arch_name
    arch_name=$(uname -m)
    print_substep "Architecture: $arch_name"

    if [[ "$arch_name" == "arm64" ]]; then
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
    if [[ ! -f "/usr/local/bin/brew" ]]; then
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
    if [[ ! -d "/usr/local/opt/qt@5/lib/QtCore.framework" ]]; then
        echo ""
        print_error "Qt 5 not found"
        echo ""
        echo "Install Qt 5 with:"
        echo "  arch -x86_64 /usr/local/bin/brew install qt@5"
        exit 1
    fi
    local qt_version
    qt_version=$(ls /usr/local/Cellar/qt@5/ 2>/dev/null | head -1 || echo "unknown")
    print_substep "Qt 5: $qt_version"

    # Check disk space (need ~200MB)
    local available_space
    available_space=$(df -m "$GAME_APP" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    if [[ "$available_space" -lt 200 ]]; then
        print_warning "Low disk space (${available_space}MB available, 200MB recommended)"
    fi

    echo ""
    print_success "Pre-flight checks passed!"

    # ============================================================
    # Create backup
    # ============================================================
    echo ""
    print_step "Creating backup..."

    BACKUP_DIR=~/Documents/WormsWMD-Backup-$(date +%Y%m%d-%H%M%S)
    mkdir -p "$BACKUP_DIR"

    start_spinner "Backing up Frameworks..."
    cp -R "$GAME_APP/Contents/Frameworks" "$BACKUP_DIR/"
    stop_spinner

    start_spinner "Backing up PlugIns..."
    cp -R "$GAME_APP/Contents/PlugIns" "$BACKUP_DIR/"
    stop_spinner

    print_substep "Backup created: $BACKUP_DIR"
    CLEANUP_NEEDED=true

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
    start_spinner "Copying frameworks..."
    "$SCRIPTS_DIR/02_replace_qt_frameworks.sh" > /dev/null
    stop_spinner
    print_substep "Qt frameworks replaced (5.3.2 → $qt_version)"

    echo ""
    print_step "Copying dependencies..."
    chmod +x "$SCRIPTS_DIR/03_copy_dependencies.sh"
    start_spinner "Copying libraries..."
    "$SCRIPTS_DIR/03_copy_dependencies.sh" > /dev/null
    stop_spinner
    print_substep "16 libraries bundled"

    echo ""
    print_step "Fixing library paths..."
    chmod +x "$SCRIPTS_DIR/04_fix_library_paths.sh"
    start_spinner "Updating install names..."
    "$SCRIPTS_DIR/04_fix_library_paths.sh" > /dev/null
    stop_spinner
    print_substep "All paths updated to @executable_path"

    CLEANUP_NEEDED=false  # Success - don't rollback on exit

    # ============================================================
    # Verify installation
    # ============================================================
    echo ""
    print_step "Verifying installation..."
    chmod +x "$SCRIPTS_DIR/05_verify_installation.sh"

    # Capture verification output
    local verify_output
    if verify_output=$("$SCRIPTS_DIR/05_verify_installation.sh" 2>&1); then
        print_substep "All checks passed"
    else
        print_warning "Some verification checks had warnings"
        echo "$verify_output" | grep -E "WARNING|ERROR" | head -5 | while read -r line; do
            print_substep "$line"
        done
    fi

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
    echo -e "${DIM}Backup location: $BACKUP_DIR${NC}"
    echo -e "${DIM}To restore:      ./fix_worms_wmd.sh --restore${NC}"
    echo ""
}

# ============================================================
# Argument Parsing
# ============================================================

FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --restore|-r)
            do_restore
            ;;
        --verify|-v)
            do_verify
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            echo ""
            echo "Run './fix_worms_wmd.sh --help' for usage information."
            exit 1
            ;;
    esac
done

# Run the appropriate action
if $DRY_RUN; then
    do_dry_run
else
    do_fix
fi
