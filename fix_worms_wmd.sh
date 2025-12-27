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
#   - Rosetta 2 on Apple Silicon (auto-installed if missing)
#   - Xcode Command Line Tools (auto-installed if missing)
#   - Pre-built Qt frameworks are downloaded automatically
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
VERSION="1.6.1"
LOG_FILE="${LOG_FILE:-}"
TRACE_FILE="${TRACE_FILE:-}"
WORMSWMD_DEBUG="${WORMSWMD_DEBUG:-false}"
WORMSWMD_VERBOSE="${WORMSWMD_VERBOSE:-false}"

# shellcheck source=./scripts/logging.sh
source "$SCRIPTS_DIR/logging.sh"
# shellcheck source=./scripts/common.sh
source "$SCRIPTS_DIR/common.sh"

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

init_logging() {
    local script_name="$1"
    local was_logging="${WORMSWMD_LOGGING_INITIALIZED:-}"

    worms_log_init "$script_name"
    worms_debug_init
    export WORMSWMD_DEBUG WORMSWMD_VERBOSE TRACE_FILE

    if [[ -z "$was_logging" ]]; then
        print_info "Log file: $LOG_FILE"
        if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
            print_info "Trace log: $TRACE_FILE"
        fi
        if worms_verbose_enabled; then
            print_info "Verbose logging: enabled"
        fi
    fi
}

# Spinner for long-running operations
spinner_pid=""

start_spinner() {
    local msg="$1"
    if [[ -t 1 ]] && ! $DRY_RUN; then
        (
            frames=("|" "/" "-" "\\")
            i=0
            while true; do
                printf "\r    ${CYAN}%s${NC} %s" "${frames[i]}" "$msg"
                i=$(( (i + 1) % ${#frames[@]} ))
                sleep 0.1
            done
        ) &
        spinner_pid=$!
        disown 2>/dev/null || true
    fi
}

stop_spinner() {
    if [[ -n "$spinner_pid" ]]; then
        kill "$spinner_pid" 2>/dev/null || true
        wait "$spinner_pid" 2>/dev/null || true
        spinner_pid=""
        printf "\r\033[K"  # Clear line
    fi
}

# ============================================================
# Auto-Detection and Auto-Install Functions
# ============================================================

# Search for game in common locations
auto_detect_game() {
    local found_games=()
    local search_paths=(
        "$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
        "/Applications/Worms W.M.D.app"
        "$HOME/Applications/Worms W.M.D.app"
        "$HOME/Games/Worms W.M.D.app"
        "$HOME/Library/Application Support/GOG.com/Games/Worms W.M.D/Worms W.M.D.app"
    )

    # Also check for custom Steam library locations
    local steam_config="$HOME/Library/Application Support/Steam/steamapps/libraryfolders.vdf"
    if [[ -f "$steam_config" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ \"path\"[[:space:]]*\"([^\"]+)\" ]]; then
                local lib_path="${BASH_REMATCH[1]}"
                if [[ -d "$lib_path" ]]; then
                    search_paths+=("$lib_path/steamapps/common/WormsWMD/Worms W.M.D.app")
                fi
            fi
        done < "$steam_config"
    fi

    # Search all paths
    for path in "${search_paths[@]}"; do
        if [[ -d "$path" ]] && [[ -f "$path/Contents/MacOS/Worms W.M.D" ]]; then
            found_games+=("$path")
        fi
    done

    # Remove duplicates using associative array
    local -A seen_games
    local unique_games=()
    for game in "${found_games[@]}"; do
        if [[ -z "${seen_games[$game]:-}" ]]; then
            unique_games+=("$game")
            seen_games[$game]=1
        fi
    done

    if [[ ${#unique_games[@]} -eq 0 ]]; then
        echo ""
    elif [[ ${#unique_games[@]} -eq 1 ]]; then
        echo "${unique_games[0]}"
    else
        # Multiple installations found - let user choose
        echo ""
        print_info "Multiple game installations found:"
        echo ""
        local i=1
        for game in "${unique_games[@]}"; do
            echo "    $i) $game"
            ((i++))
        done
        echo ""

        while true; do
            read -r -p "Which installation do you want to fix? [1-${#unique_games[@]}] " choice < /dev/tty
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#unique_games[@]} ]]; then
                echo "${unique_games[$((choice-1))]}"
                return
            fi
            echo "Please enter a number between 1 and ${#unique_games[@]}"
        done
    fi
}

# Check and install Rosetta 2 if needed (Apple Silicon only)
ensure_rosetta() {
    local arch_name
    arch_name=$(uname -m)

    if [[ "$arch_name" != "arm64" ]]; then
        return 0  # Not Apple Silicon, no Rosetta needed
    fi

    # Check if Rosetta is already installed
    if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
        return 0  # Rosetta is available
    fi

    echo ""
    print_info "Rosetta 2 is required to run this game on Apple Silicon."
    echo ""
    echo "    Rosetta 2 is Apple's translation layer that allows Intel apps"
    echo "    to run on M1/M2/M3/M4 Macs. It's safe, free, and made by Apple."
    echo ""

    if $FORCE; then
        echo "Installing Rosetta 2..."
    else
        read -p "Install Rosetta 2 now? [Y/n] " -n 1 -r < /dev/tty
        echo ""
        if [[ "${REPLY:-}" =~ ^[Nn]$ ]]; then
            print_error "Rosetta 2 is required. Cannot continue without it."
            exit 1
        fi
    fi

    echo ""
    start_spinner "Installing Rosetta 2 (this may take a minute)..."

    if softwareupdate --install-rosetta --agree-to-license 2>/dev/null; then
        stop_spinner
        print_success "Rosetta 2 installed successfully!"
        echo ""
    else
        stop_spinner false
        print_error "Failed to install Rosetta 2."
        echo ""
        echo "Please try installing manually:"
        echo "    softwareupdate --install-rosetta"
        exit 1
    fi
}

# Check and install Xcode Command Line Tools if needed
ensure_xcode_clt() {
    # Check if clang is available
    if command -v clang &>/dev/null; then
        return 0  # Already installed
    fi

    # Check if xcode-select path exists
    if xcode-select -p &>/dev/null; then
        return 0  # CLT installed but maybe not in PATH
    fi

    echo ""
    print_info "Xcode Command Line Tools are required to build a component."
    echo ""
    echo "    These are free developer tools from Apple that include the"
    echo "    compiler needed to build the AGL compatibility library."
    echo ""

    if $FORCE; then
        echo "Installing Xcode Command Line Tools..."
    else
        read -p "Install Xcode Command Line Tools now? [Y/n] " -n 1 -r < /dev/tty
        echo ""
        if [[ "${REPLY:-}" =~ ^[Nn]$ ]]; then
            print_error "Xcode Command Line Tools are required. Cannot continue without them."
            exit 1
        fi
    fi

    echo ""
    print_info "A system dialog will appear. Click 'Install' to continue."
    echo "    (This download is about 130MB and may take a few minutes)"
    echo ""

    # Trigger the install dialog
    xcode-select --install 2>/dev/null || true

    echo ""
    echo "Waiting for installation to complete..."
    echo "(Press any key once the installation dialog has finished)"
    echo ""

    # Wait for user to complete the installation
    if [[ -t 0 ]]; then
        read -n 1 -s -r < /dev/tty
    else
        print_warning "Non-interactive session detected. Re-run after CLT installation completes."
        exit 1
    fi

    # Verify installation
    if ! command -v clang &>/dev/null; then
        if ! xcode-select -p &>/dev/null; then
            print_error "Xcode Command Line Tools installation was not completed."
            echo ""
            echo "Please complete the installation dialog, then run this fix again."
            exit 1
        fi
    fi

    print_success "Xcode Command Line Tools installed!"
    echo ""
}

# Offer to install Steam update watcher
offer_steam_watcher() {
    local watcher_script="$SCRIPT_DIR/tools/watch_for_updates.sh"

    if [[ ! -f "$watcher_script" ]]; then
        return 0  # Watcher script doesn't exist
    fi

    # Check if already installed
    if [[ -f "$HOME/Library/LaunchAgents/com.wormswmd.fix.watcher.plist" ]]; then
        return 0  # Already installed
    fi

    echo ""
    print_info "Would you like to be notified when Steam updates overwrite this fix?"
    echo ""
    echo "    Steam's 'Verify Integrity' feature will restore original files,"
    echo "    which means you'll need to re-run this fix after verification."
    echo ""
    echo "    The update watcher runs in the background and notifies you"
    echo "    if the fix needs to be re-applied."
    echo ""

    if $FORCE; then
        return 0  # Don't auto-install in force mode
    fi

    read -p "Install the Steam update watcher? [y/N] " -n 1 -r < /dev/tty
    echo ""

    if [[ "${REPLY:-}" =~ ^[Yy]$ ]]; then
        chmod +x "$watcher_script"
        if "$watcher_script" --install 2>/dev/null; then
            print_success "Steam update watcher installed!"
            echo "    You'll be notified if the fix needs to be re-applied."
        else
            print_warning "Could not install watcher (game will still work fine)"
        fi
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

        if [[ -f "$BACKUP_DIR/Info.plist" ]]; then
            cp "$BACKUP_DIR/Info.plist" "$GAME_APP/Contents/Info.plist" 2>/dev/null || true
        fi

        if [[ -d "$BACKUP_DIR/DataOSX" ]] && [[ -d "$GAME_APP/Contents/Resources/DataOSX" ]]; then
            cp "$BACKUP_DIR/DataOSX/"* "$GAME_APP/Contents/Resources/DataOSX/" 2>/dev/null || true
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

validate_game_app() {
    # If GAME_APP wasn't explicitly set, try auto-detection
    if [[ "$GAME_APP" == "$DEFAULT_GAME_PATH" ]] && [[ ! -d "$GAME_APP" ]]; then
        print_step "Looking for Worms W.M.D..."
        local detected_game
        detected_game=$(auto_detect_game)

        if [[ -n "$detected_game" ]]; then
            GAME_APP="$detected_game"
            print_substep "Found: $GAME_APP"
        fi
    fi

    if [[ -z "${GAME_APP:-}" ]]; then
        print_error "Could not find Worms W.M.D"
        echo ""
        echo "The game was not found in any of the usual locations."
        echo ""
        echo "Please make sure the game is installed, then either:"
        echo "  1. Drag the game app onto this Terminal window and press Enter"
        echo "  2. Set the path manually:"
        echo "     GAME_APP=\"/path/to/Worms W.M.D.app\" ./fix_worms_wmd.sh"
        exit 1
    fi

    if [[ ! -d "$GAME_APP" ]] || [[ ! -d "$GAME_APP/Contents" ]]; then
        print_error "Game not found at: $GAME_APP"
        echo ""
        echo "This location doesn't contain Worms W.M.D."
        echo ""
        echo "Please check that the game is installed, then try again."
        echo "You can also set the path manually:"
        echo "  GAME_APP=\"/path/to/Worms W.M.D.app\" ./fix_worms_wmd.sh"
        exit 1
    fi

    local game_exec="$GAME_APP/Contents/MacOS/Worms W.M.D"
    if [[ ! -f "$game_exec" ]]; then
        print_error "This doesn't look like Worms W.M.D"
        echo ""
        echo "The folder exists but doesn't contain the game executable."
        echo "Location: $GAME_APP"
        echo ""
        echo "Try reinstalling the game through Steam or GOG, then run this fix again."
        exit 1
    fi
}

check_already_applied() {
    local game_frameworks="$GAME_APP/Contents/Frameworks"
    local has_agl=false
    local has_qt=false
    local has_deps=false

    # Check for AGL stub
    if [[ -f "$game_frameworks/AGL.framework/Versions/A/AGL" ]]; then
        local agl_arch
        agl_arch=$(lipo -archs "$game_frameworks/AGL.framework/Versions/A/AGL" 2>/dev/null || echo "")
        if [[ "$agl_arch" == "x86_64" ]]; then
            local agl_size
            agl_size=$(stat -f%z "$game_frameworks/AGL.framework/Versions/A/AGL" 2>/dev/null || echo "0")
            if [[ "$agl_size" -lt 100000 ]]; then
                has_agl=true
            fi
        fi
    fi

    # Check for Qt 5.15 (vs original 5.3)
    local qt_core="$game_frameworks/QtCore.framework/Versions/Current/QtCore"
    if [[ ! -f "$qt_core" ]]; then
        qt_core="$game_frameworks/QtCore.framework/Versions/5/QtCore"
    fi
    if [[ -f "$qt_core" ]]; then
        local qt_info
        qt_info=$(otool -L "$qt_core" 2>/dev/null | head -2 || echo "")
        if echo "$qt_info" | grep -q "5.15"; then
            has_qt=true
        fi
    fi

    # Check for bundled dependencies (match common Homebrew Qt deps)
    local has_pcre2=false
    local lib
    for lib in "$game_frameworks"/libpcre2-16*.dylib "$game_frameworks"/libpcre2-8*.dylib; do
        if [[ -f "$lib" ]]; then
            has_pcre2=true
            break
        fi
    done
    if [[ -f "$game_frameworks/libglib-2.0.0.dylib" ]] && $has_pcre2; then
        has_deps=true
    fi

    if $has_agl && $has_qt && $has_deps; then
        echo "yes"
    elif $has_agl || $has_qt || $has_deps; then
        echo "partial"
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
    --log-file      Write logs to a specific file path
    --verbose       Show full verification output
    --debug         Enable debug tracing (writes a .trace log)

${BOLD}ENVIRONMENT VARIABLES:${NC}
    GAME_APP        Path to "Worms W.M.D.app" (for non-standard locations)
    LOG_FILE        Override the log file path
    LOG_DIR         Override the log directory
    WORMSWMD_DEBUG  Enable debug tracing (1/true/yes)
    WORMSWMD_VERBOSE Enable verbose output (1/true/yes)

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

${BOLD}AUTOMATIC FEATURES:${NC}
    • Rosetta 2 is auto-installed if missing (Apple Silicon)
    • Xcode Command Line Tools are auto-installed if missing
    • Game location is auto-detected (Steam, GOG, custom paths)
    • Qt frameworks are downloaded automatically (no Homebrew needed)

${BOLD}MORE INFO:${NC}
    Repository: https://github.com/cboyd0319/WormsWMD-macOS-Fix
    Issues:     https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues
EOF
}

# ============================================================
# Restore Function
# ============================================================

do_restore() {
    init_logging "fix_worms_wmd"
    print_header
    echo "Looking for backups..."
    echo ""

    backups=$(find "$HOME/Documents" -mindepth 1 -maxdepth 1 -type d -name "WormsWMD-Backup-*" -print 2>/dev/null)
    if [[ -z "$backups" ]]; then
        print_error "No backups found in $HOME/Documents/"
        echo ""
        echo "Backups are created automatically when running the fix."
        echo "If you haven't run the fix yet, there's nothing to restore."
        exit 1
    fi

    echo "Available backups:"
    echo "$backups"
    echo ""

    # Use the most recent backup
    latest=$(worms_latest_path_by_mtime "$HOME/Documents" "WormsWMD-Backup-*" "d")
    echo "Most recent backup: $latest"
    echo ""

    if ! $FORCE; then
        read -p "Restore from this backup? [y/N] " -n 1 -r < /dev/tty
        echo ""
        if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
            echo "Restore cancelled."
            exit 0
        fi
    fi

    validate_game_app

    print_step "Restoring Frameworks..."
    rm -rf "$GAME_APP/Contents/Frameworks"
    cp -R "$latest/Frameworks" "$GAME_APP/Contents/"

    print_step "Restoring PlugIns..."
    rm -rf "$GAME_APP/Contents/PlugIns"
    cp -R "$latest/PlugIns" "$GAME_APP/Contents/"

    if [[ -f "$latest/Info.plist" ]]; then
        print_step "Restoring Info.plist..."
        cp "$latest/Info.plist" "$GAME_APP/Contents/Info.plist"
    fi

    if [[ -d "$latest/DataOSX" ]] && [[ -d "$GAME_APP/Contents/Resources/DataOSX" ]]; then
        print_step "Restoring config files..."
        cp "$latest/DataOSX/"* "$GAME_APP/Contents/Resources/DataOSX/" 2>/dev/null || true
    fi

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
    init_logging "fix_worms_wmd"
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
    init_logging "fix_worms_wmd"
    print_header

    print_step "Pre-flight checks..."

    if [[ -d "$GAME_APP/Contents" ]] && [[ -f "$GAME_APP/Contents/MacOS/Worms W.M.D" ]]; then
        print_dry_run "Game found: $GAME_APP"
    else
        print_warning "Game not found at: $GAME_APP"
        print_info "Set GAME_APP to preview against a custom location."
        echo ""
    fi

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
        if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
            print_dry_run "Rosetta 2: available"
        else
            print_error "Rosetta 2 is required but not installed"
            echo ""
            echo "Install Rosetta 2 with:"
            echo "  softwareupdate --install-rosetta"
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
    local qt_version_path
    qt_version_path=$(worms_latest_path_by_mtime "/usr/local/Cellar/qt@5" "*" "d")
    if [[ -n "$qt_version_path" ]]; then
        qt_version=$(basename "$qt_version_path")
    else
        qt_version="unknown"
    fi
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

    print_dry_run "Replace Qt frameworks found in the game bundle"
    print_dry_run "  (upgrade to Qt $qt_version and add QtDBus if missing)"
    echo ""

    print_dry_run "Copy dependencies referenced by Qt frameworks/plugins"
    print_dry_run "  (resolved from /usr/local and @rpath entries)"
    echo ""

    print_dry_run "Update library paths to use @executable_path"
    print_dry_run "Replace platform plugin: libqcocoa.dylib"
    print_dry_run "Update image format plugins"
    print_dry_run "Update Info.plist metadata (bundle ID, HiDPI, min version)"
    print_dry_run "Secure config URLs (HTTP→HTTPS, disable internal URLs)"
    print_dry_run "Remove quarantine flags (xattr -rd com.apple.quarantine)"
    print_dry_run "Apply ad-hoc code signature (codesign --deep --sign -)"
    print_dry_run "Reset incompatible Qt window geometry (if present)"
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
    init_logging "fix_worms_wmd"
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
            read -p "Re-apply the fix anyway? [y/N] " -n 1 -r < /dev/tty
            echo ""
            if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
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

    # Check macOS version first
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
            read -p "Continue anyway? [y/N] " -n 1 -r < /dev/tty
            echo ""
            if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
                echo "Fix cancelled."
                exit 0
            fi
        fi
    fi

    # Check architecture and auto-install Rosetta if needed
    local arch_name
    arch_name=$(uname -m)
    print_substep "Architecture: $arch_name"

    if [[ "$arch_name" == "arm64" ]]; then
        ensure_rosetta
        print_substep "Rosetta 2: available"
    fi

    # Check for Xcode CLT and auto-install if needed
    ensure_xcode_clt
    print_substep "Build tools: available"

    # Find the game (with auto-detection)
    validate_game_app
    print_substep "Game found: $GAME_APP"

    # Check Qt source: prefer pre-built, fall back to Homebrew
    QT_SOURCE=""
    QT_PREFIX=""

    # First, try to use/download pre-built Qt frameworks
    chmod +x "$SCRIPTS_DIR/download_qt_frameworks.sh" 2>/dev/null || true
    if [[ -x "$SCRIPTS_DIR/download_qt_frameworks.sh" ]]; then
        local prebuild_check
        prebuild_check=$("$SCRIPTS_DIR/download_qt_frameworks.sh" --check 2>/dev/null || echo "unavailable")

        if [[ "$prebuild_check" == "available" ]]; then
            print_substep "Qt source: Pre-built frameworks (no Homebrew needed)"
            QT_SOURCE="prebuild"
        fi
    fi

    # Fall back to Homebrew if pre-built not available
    if [[ -z "$QT_SOURCE" ]]; then
        if [[ -f "/usr/local/bin/brew" ]] && [[ -d "/usr/local/opt/qt@5/lib/QtCore.framework" ]]; then
            local qt_version
            local qt_version_path
            qt_version_path=$(worms_latest_path_by_mtime "/usr/local/Cellar/qt@5" "*" "d")
            if [[ -n "$qt_version_path" ]]; then
                qt_version=$(basename "$qt_version_path")
            else
                qt_version="unknown"
            fi
            print_substep "Qt source: Homebrew ($qt_version)"
            QT_SOURCE="homebrew"
            QT_PREFIX="/usr/local/opt/qt@5"
        fi
    fi

    # If neither available, show installation options
    if [[ -z "$QT_SOURCE" ]]; then
        echo ""
        print_error "Qt frameworks not available"
        echo ""
        echo "Option 1 (Recommended): The fix will automatically download pre-built frameworks."
        echo "          Just run the fix and it will handle everything."
        echo ""
        echo "Option 2: Install Intel Homebrew and Qt manually:"
        echo "  arch -x86_64 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        echo "  arch -x86_64 /usr/local/bin/brew install qt@5"
        exit 1
    fi

    export QT_SOURCE QT_PREFIX

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

    BACKUP_DIR="$HOME/Documents/WormsWMD-Backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    start_spinner "Backing up Frameworks..."
    cp -R "$GAME_APP/Contents/Frameworks" "$BACKUP_DIR/"
    stop_spinner

    start_spinner "Backing up PlugIns..."
    cp -R "$GAME_APP/Contents/PlugIns" "$BACKUP_DIR/"
    stop_spinner

    if [[ -f "$GAME_APP/Contents/Info.plist" ]]; then
        cp "$GAME_APP/Contents/Info.plist" "$BACKUP_DIR/Info.plist"
    fi

    local data_dir="$GAME_APP/Contents/Resources/DataOSX"
    if [[ -d "$data_dir" ]]; then
        mkdir -p "$BACKUP_DIR/DataOSX"
        for config_file in SteamConfig.txt SteamConfigDemo.txt GOGConfig.txt; do
            if [[ -f "$data_dir/$config_file" ]]; then
                cp "$data_dir/$config_file" "$BACKUP_DIR/DataOSX/$config_file"
            fi
        done
    fi

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

    # If using pre-built, download first
    if [[ "$QT_SOURCE" == "prebuild" ]]; then
        start_spinner "Downloading Qt frameworks..."
        local qt_extract_dir
        qt_extract_output=$("$SCRIPTS_DIR/download_qt_frameworks.sh" 2>/dev/null || true)
        qt_extract_dir=$(echo "$qt_extract_output" | tail -1)
        stop_spinner

        if [[ -n "$qt_extract_dir" ]] && [[ -d "$qt_extract_dir/Frameworks" ]]; then
            export QT_PREFIX="$qt_extract_dir"
            print_substep "Using pre-built Qt 5.15"
        else
            print_warning "Pre-built download failed, falling back to Homebrew"
            QT_SOURCE="homebrew"
            QT_PREFIX="/usr/local/opt/qt@5"
        fi
    fi

    chmod +x "$SCRIPTS_DIR/02_replace_qt_frameworks.sh"
    export GAME_APP QT_SOURCE QT_PREFIX
    start_spinner "Copying frameworks..."
    "$SCRIPTS_DIR/02_replace_qt_frameworks.sh" > /dev/null
    stop_spinner

    local qt_version_display
    if [[ "$QT_SOURCE" == "prebuild" ]]; then
        qt_version_display="5.15 (pre-built)"
    else
        local qt_version_display_path
        qt_version_display_path=$(worms_latest_path_by_mtime "/usr/local/Cellar/qt@5" "*" "d")
        if [[ -n "$qt_version_display_path" ]]; then
            qt_version_display=$(basename "$qt_version_display_path")
        else
            qt_version_display="5.15"
        fi
    fi
    print_substep "Qt frameworks replaced (5.3.2 → $qt_version_display)"

    echo ""
    print_step "Copying dependencies..."
    chmod +x "$SCRIPTS_DIR/03_copy_dependencies.sh"
    start_spinner "Copying libraries..."
    local copy_output
    if ! copy_output=$("$SCRIPTS_DIR/03_copy_dependencies.sh" 2>&1); then
        stop_spinner
        print_error "Copying dependencies failed"
        if [[ -n "$copy_output" ]]; then
            echo "$copy_output"
        fi
        exit 1
    fi
    stop_spinner

    local copied missing
    copied=$(echo "$copy_output" | awk -F= '/^COPIED_LIBS=/{print $2}' | tail -1)
    missing=$(echo "$copy_output" | awk -F= '/^MISSING_LIBS=/{print $2}' | tail -1)

    if [[ -n "$copied" ]]; then
        print_substep "Dependencies bundled: $copied"
    else
        print_substep "Dependencies bundled"
    fi

    if [[ -n "$missing" ]] && [[ "$missing" =~ ^[0-9]+$ ]] && [[ "$missing" -gt 0 ]]; then
        print_warning "$missing dependencies were not found"
        echo "$copy_output" | grep -E "^WARNING:" | head -5 | while read -r line; do
            print_substep "$line"
        done || true
    fi

    echo ""
    print_step "Fixing library paths..."
    chmod +x "$SCRIPTS_DIR/04_fix_library_paths.sh"
    start_spinner "Updating install names..."
    "$SCRIPTS_DIR/04_fix_library_paths.sh" > /dev/null
    stop_spinner
    print_substep "All paths updated to @executable_path"

    # ============================================================
    # Apply enhancements
    # ============================================================
    echo ""
    print_step "Applying enhancements..."

    # Fix Info.plist
    if [[ -f "$SCRIPTS_DIR/06_fix_info_plist.sh" ]]; then
        chmod +x "$SCRIPTS_DIR/06_fix_info_plist.sh"
        "$SCRIPTS_DIR/06_fix_info_plist.sh" > /dev/null 2>&1 || true
        print_substep "Info.plist updated (bundle ID, HiDPI, min version)"
    fi

    # Fix config URLs
    if [[ -f "$SCRIPTS_DIR/07_fix_config_urls.sh" ]]; then
        chmod +x "$SCRIPTS_DIR/07_fix_config_urls.sh"
        "$SCRIPTS_DIR/07_fix_config_urls.sh" > /dev/null 2>&1 || true
        print_substep "Config URLs secured (HTTP→HTTPS)"
    fi

    # ============================================================
    # Post-fix: Code signing and quarantine removal
    # ============================================================
    echo ""
    print_step "Applying finishing touches..."

    # Remove quarantine flags
    xattr -rd com.apple.quarantine "$GAME_APP" 2>/dev/null || true
    if xattr -l "$GAME_APP" 2>/dev/null | grep -q "quarantine"; then
        print_warning "Quarantine flag still present (may cause Gatekeeper warnings)"
    else
        print_substep "No quarantine flags present"
    fi

    # Apply ad-hoc code signature
    # This reduces Gatekeeper friction without requiring a Developer ID
    if codesign --force --deep --sign - "$GAME_APP" 2>/dev/null; then
        print_substep "Ad-hoc code signature applied"
    else
        print_warning "Could not apply ad-hoc signature (game will still work)"
    fi

    # Reset Qt window geometry (old Qt 5.3 settings are incompatible with 5.15)
    # This prevents the "small window" issue on first launch after the fix
    if defaults read "com.team17.Worms W.M.D" "QtSystem_GameWindow.geometry" &>/dev/null; then
        defaults delete "com.team17.Worms W.M.D" "QtSystem_GameWindow.geometry" 2>/dev/null || true
        defaults delete "com.team17.Worms W.M.D" "QtSystem_GameWindow.windowState" 2>/dev/null || true
        print_substep "Reset incompatible Qt window geometry"
    fi

    CLEANUP_NEEDED=false  # Success - don't rollback on exit

    # ============================================================
    # Verify installation
    # ============================================================
    echo ""
    print_step "Verifying installation..."
    chmod +x "$SCRIPTS_DIR/05_verify_installation.sh"

    # Capture verification output
    local verify_output
    if worms_verbose_enabled; then
        if "$SCRIPTS_DIR/05_verify_installation.sh"; then
            print_substep "All checks passed"
        else
            print_warning "Some verification checks had warnings"
        fi
    else
        if verify_output=$("$SCRIPTS_DIR/05_verify_installation.sh" 2>&1); then
            print_substep "All checks passed"
        else
            print_warning "Some verification checks had warnings"
            echo "$verify_output" | grep -E "WARNING|ERROR" | head -5 | while read -r line; do
                print_substep "$line"
            done || true
        fi
    fi

    # ============================================================
    # Offer optional extras
    # ============================================================
    offer_steam_watcher

    # ============================================================
    # Done
    # ============================================================
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                    ${GREEN}FIX COMPLETE!${NC}                            ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "The fix has been applied successfully!"
    echo ""
    echo "You can now launch Worms W.M.D from Steam or your Applications folder."
    echo ""
    echo -e "${DIM}Backup location: $BACKUP_DIR${NC}"
    echo -e "${DIM}To undo the fix: ./fix_worms_wmd.sh --restore${NC}"
    echo ""
}

# ============================================================
# Argument Parsing
# ============================================================

FORCE=false
ACTION="fix"

set_action() {
    local next_action="$1"

    if [[ "$ACTION" != "fix" ]]; then
        print_error "Only one mode can be selected (currently: $ACTION)"
        exit 1
    fi

    ACTION="$next_action"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --restore|-r)
            set_action "restore"
            shift
            ;;
        --verify|-v)
            set_action "verify"
            shift
            ;;
        --dry-run|-n)
            set_action "dry-run"
            DRY_RUN=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --log-file)
            if [[ -z "${2:-}" ]]; then
                print_error "--log-file requires a path"
                exit 1
            fi
            LOG_FILE="$2"
            shift 2
            ;;
        --verbose)
            WORMSWMD_VERBOSE=1
            shift
            ;;
        --debug)
            WORMSWMD_DEBUG=1
            WORMSWMD_VERBOSE=1
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
case "$ACTION" in
    restore)
        do_restore
        ;;
    verify)
        do_verify
        ;;
    dry-run)
        do_dry_run
        ;;
    fix)
        do_fix
        ;;
esac
