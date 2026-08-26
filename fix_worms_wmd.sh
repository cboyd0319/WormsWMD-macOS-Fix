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

set -Eeuo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
VERSION="1.7.5"
LOG_FILE="${LOG_FILE:-}"
TRACE_FILE="${TRACE_FILE:-}"
WORMSWMD_DEBUG="${WORMSWMD_DEBUG:-false}"
WORMSWMD_VERBOSE="${WORMSWMD_VERBOSE:-false}"

# shellcheck source=./scripts/logging.sh
source "$SCRIPTS_DIR/logging.sh"
# shellcheck source=./scripts/common.sh
source "$SCRIPTS_DIR/common.sh"

# Default game location (uses $HOME instead of ~ for reliability)
DEFAULT_GAME_PATH="$(worms_default_game_app)"
GAME_APP_EXPLICIT=false
if [[ -n "${GAME_APP:-}" ]]; then
    GAME_APP_EXPLICIT=true
fi
GAME_APP="${GAME_APP:-$DEFAULT_GAME_PATH}"
GAME_APP_AUTO_DETECTED=false

# Global state
DRY_RUN=false
BACKUP_DIR=""
CLEANUP_NEEDED=false
BUILD_DIR="${BUILD_DIR:-}"
BUILD_DIR_MANAGED=false
QT_SOURCE=""
QT_PREFIX=""
QT_VERSION_DISPLAY=""
QT_SOURCE_DISPLAY=""
BACKUP_MANIFEST_NAME="BACKUP_MANIFEST.tsv"
BACKUP_METADATA_NAME="BACKUP_METADATA.tsv"

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
    echo -e "${BLUE}║${NC}     ${GREEN}Worms W.M.D - macOS 26+ Fix${NC}                            ${BLUE}║${NC}"
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
    local unique_games=()
    local game
    local choice
    local prompt_output="/dev/stderr"

    while IFS= read -r -d '' game; do
        unique_games+=("$game")
    done < <(worms_find_game_apps)

    if [[ ${#unique_games[@]} -eq 0 ]]; then
        echo ""
    elif [[ ${#unique_games[@]} -eq 1 ]]; then
        echo "${unique_games[0]}"
    else
        if [[ ! -r /dev/tty ]] || [[ ! -w /dev/tty ]]; then
            echo "Several Worms W.M.D installations were found; set GAME_APP to the exact .app path." >&2
            return 1
        fi

        prompt_output="/dev/tty"

        # Multiple installations found - let user choose
        echo "" > "$prompt_output"
        print_info "Multiple game installations found:" > "$prompt_output"
        echo "" > "$prompt_output"
        local i=1
        for game in "${unique_games[@]}"; do
            echo "    $i) $game" > "$prompt_output"
            ((i++))
        done
        echo "" > "$prompt_output"

        while true; do
            printf "Which installation do you want to fix? [1-%s] " "${#unique_games[@]}" > "$prompt_output"
            if ! IFS= read -r choice < /dev/tty; then
                echo "Could not read selection; set GAME_APP to the exact .app path." >&2
                return 1
            fi
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#unique_games[@]} ]]; then
                echo "${unique_games[$((choice-1))]}"
                return
            fi
            echo "Please enter a number between 1 and ${#unique_games[@]}" > "$prompt_output"
        done
    fi
}

# Check and install Rosetta 2 if needed (Apple Silicon only)
print_game_test_tool_status() {
    if command -v game-test-tool >/dev/null 2>&1; then
        print_info "macOS 27 beta game support status:"
        game-test-tool status 2>&1 | sed 's/^/    /' || true
    fi
}

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
    print_info "Rosetta is required to run Worms W.M.D on Apple Silicon."
    echo ""
    echo "    Worms W.M.D is an older Intel Mac game. Rosetta is Apple's"
    echo "    compatibility layer that lets older Intel Mac games run on"
    echo "    M-series Macs."
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
        if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
            print_success "Rosetta 2 installed successfully!"
            echo ""
        else
            print_error "Rosetta 2 installed, but Worms still cannot use it."
            print_game_test_tool_status
            echo ""
            echo "Please restart your Mac, then run this launcher again and choose option 3."
            echo "If it still fails, choose option 5 to create a support bundle."
            exit 1
        fi
    else
        stop_spinner false
        print_error "Failed to install Rosetta 2."
        print_game_test_tool_status
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

    if $FORCE; then
        return 0  # Don't prompt or print an offer in force mode
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

    # Clean up the per-run build directory created by this script.
    if $BUILD_DIR_MANAGED && [[ -n "$BUILD_DIR" ]] && [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR" 2>/dev/null || true
    fi
}

game_source_for_backup() {
    local game_app="$1"
    local game_exec="$game_app/Contents/MacOS/Worms W.M.D"

    if [[ -f "$game_app/Contents/MacOS/libGalaxy.dylib" ]] \
        || worms_otool_dependencies "$game_exec" | grep -Fqi 'libGalaxy.dylib'; then
        echo "gog"
    elif [[ -f "$game_app/Contents/Frameworks/libsteam_api.dylib" ]] \
        || worms_otool_dependencies "$game_exec" | grep -Fqi 'libsteam_api.dylib'; then
        echo "steam"
    else
        echo "unknown"
    fi
}

write_game_backup_metadata() {
    local backup_dir="$1"
    local game_exec="$GAME_APP/Contents/MacOS/Worms W.M.D"
    local game_app_real source executable_hash executable_size

    game_app_real=$(worms_real_dir "$GAME_APP")
    source=$(game_source_for_backup "$GAME_APP")
    executable_hash=$(worms_file_sha256 "$game_exec")
    executable_size=$(worms_file_size "$game_exec")

    {
        printf '%s\n' '# WormsWMD backup metadata v1'
        printf 'game_app_path\t%s\n' "$game_app_real"
        printf 'game_source\t%s\n' "$source"
        printf 'game_executable_sha256\t%s\n' "$executable_hash"
        printf 'game_executable_size\t%s\n' "$executable_size"
        if [[ -d "$GAME_APP/Contents/_CodeSignature" ]]; then
            printf 'code_signature_present\ttrue\n'
        else
            printf 'code_signature_present\tfalse\n'
        fi
    } > "$backup_dir/$BACKUP_METADATA_NAME"
}

backup_metadata_value() {
    local backup_dir="$1"
    local key="$2"
    local metadata="$backup_dir/$BACKUP_METADATA_NAME"

    [[ -f "$metadata" ]] || return 1
    awk -F '\t' -v key="$key" '$1 == key { sub(/^[^\t]*\t/, ""); print; exit }' "$metadata"
}

backup_metadata_is_manifested() {
    local backup_dir="$1"

    [[ -f "$backup_dir/$BACKUP_METADATA_NAME" ]] \
        && [[ -f "$backup_dir/$BACKUP_MANIFEST_NAME" ]] \
        && awk -F '\t' -v metadata="$BACKUP_METADATA_NAME" \
            '$3 == metadata {found=1} END {exit(found ? 0 : 1)}' \
            "$backup_dir/$BACKUP_MANIFEST_NAME"
}

backup_targets_game_app() {
    local backup_dir="$1"
    local game_app="$2"
    local recorded_path recorded_source game_app_real current_source

    if ! backup_metadata_is_manifested "$backup_dir"; then
        return 2
    fi

    recorded_path=$(backup_metadata_value "$backup_dir" "game_app_path" || true)
    [[ -n "$recorded_path" ]] || return 2
    worms_reject_control_chars "$recorded_path" "backup game_app_path" || return 1
    [[ "$recorded_path" == /* ]] || return 1
    game_app_real=$(worms_real_dir "$game_app") || return 1
    [[ "$recorded_path" == "$game_app_real" ]] || return 1

    recorded_source=$(backup_metadata_value "$backup_dir" "game_source" || true)
    case "$recorded_source" in
        steam|gog|unknown)
            ;;
        *)
            return 1
            ;;
    esac
    current_source=$(game_source_for_backup "$game_app")
    [[ "$recorded_source" == "$current_source" ]]
}

print_store_repair_guidance() {
    local game_source="$1"

    case "$game_source" in
        gog)
            echo "Use GOG Galaxy to repair the game if needed:"
            echo "  Manage installation → Verify / Repair"
            ;;
        steam)
            echo "Use Steam to repair the game if needed:"
            echo "  Right-click Worms W.M.D → Properties → Installed Files → Verify integrity"
            ;;
        *)
            echo "Use your game store's verify or repair action if the bundle still needs recovery."
            ;;
    esac
}

write_game_backup_manifest() {
    local backup_dir="$1"

    worms_repair_agl_framework_symlinks "$backup_dir"
    worms_validate_tree_symlinks "$backup_dir"
    worms_write_manifest "$backup_dir" "$backup_dir/$BACKUP_MANIFEST_NAME" \
        Frameworks \
        PlugIns \
        MacOS \
        _CodeSignature \
        Info.plist \
        DataOSX \
        CommonData \
        "$BACKUP_METADATA_NAME"
}

verify_game_backup_manifest() {
    local backup_dir="$1"

    [[ -f "$backup_dir/$BACKUP_MANIFEST_NAME" ]] || return 2
    worms_validate_tree_symlinks "$backup_dir" || return 1
    worms_verify_manifest "$backup_dir" "$backup_dir/$BACKUP_MANIFEST_NAME"
}

backup_qtcore_version() {
    local backup_dir="$1"
    local qt_core="$backup_dir/Frameworks/QtCore.framework/Versions/5/QtCore"

    [[ -f "$qt_core" ]] || return 1
    command -v otool >/dev/null 2>&1 || return 1
    otool -L "$qt_core" 2>/dev/null | grep "QtCore" | grep -o "5\.[0-9]*\.[0-9]*" | head -1
}

backup_appears_already_fixed() {
    local backup_dir="$1"
    local qt_version

    if [[ -d "$backup_dir/Frameworks/AGL.framework" ]]; then
        return 0
    fi

    qt_version=$(backup_qtcore_version "$backup_dir" || true)
    [[ "$qt_version" == 5.15* ]]
}

latest_original_game_backup() {
    local game_app="$1"
    local allow_legacy="${2:-false}"
    local original_only="${3:-true}"
    local backup target_status

    while IFS= read -r backup; do
        [[ -n "$backup" ]] || continue
        target_status=0
        backup_targets_game_app "$backup" "$game_app" || target_status=$?
        if [[ "$target_status" -eq 2 ]]; then
            $allow_legacy || continue
        elif [[ "$target_status" -ne 0 ]]; then
            continue
        fi
        if ! $original_only || ! backup_appears_already_fixed "$backup"; then
            echo "$backup"
            return 0
        fi
    done < <(
        find "$HOME/Documents" -mindepth 1 -maxdepth 1 -type d -name "WormsWMD-Backup-*" -print0 2>/dev/null \
            | while IFS= read -r -d '' backup; do
                mtime=$(stat -f "%m" "$backup" 2>/dev/null || stat -c "%Y" "$backup" 2>/dev/null || echo 0)
                printf '%s\t%s\n' "$mtime" "$backup"
            done \
            | sort -nr \
            | cut -f2-
    )

    return 1
}

restore_game_backup_files() {
    local backup_dir="$1"
    local signature_present

    worms_validate_tree_symlinks "$backup_dir"
    worms_validate_game_app_for_mutation "$GAME_APP"

    signature_present=""
    if backup_metadata_is_manifested "$backup_dir"; then
        signature_present=$(backup_metadata_value "$backup_dir" "code_signature_present" || true)
    fi
    case "$signature_present" in
        true)
            [[ -d "$backup_dir/_CodeSignature" ]] || {
                echo "Backup metadata requires missing _CodeSignature resources." >&2
                return 1
            }
            ;;
        false|"")
            ;;
        *)
            echo "Invalid code_signature_present value in backup metadata." >&2
            return 1
            ;;
    esac

    if [[ -f "$backup_dir/MacOS/Worms W.M.D" ]]; then
        worms_refuse_linked_file_for_mutation \
            "$GAME_APP/Contents/MacOS/Worms W.M.D" "game executable"
        cp -p "$backup_dir/MacOS/Worms W.M.D" "$GAME_APP/Contents/MacOS/Worms W.M.D"
    fi

    case "$signature_present" in
        true)
            rm -rf "$GAME_APP/Contents/_CodeSignature"
            cp -R "$backup_dir/_CodeSignature" "$GAME_APP/Contents/"
            ;;
        false)
            rm -rf "$GAME_APP/Contents/_CodeSignature"
            ;;
        "")
            ;;
    esac

    if [[ -d "$backup_dir/Frameworks" ]]; then
        rm -rf "$GAME_APP/Contents/Frameworks"
        cp -R "$backup_dir/Frameworks" "$GAME_APP/Contents/"
    fi

    if [[ -d "$backup_dir/PlugIns" ]]; then
        rm -rf "$GAME_APP/Contents/PlugIns"
        cp -R "$backup_dir/PlugIns" "$GAME_APP/Contents/"
    fi

    if [[ -f "$backup_dir/Info.plist" ]]; then
        cp "$backup_dir/Info.plist" "$GAME_APP/Contents/Info.plist"
    fi

    if [[ -d "$backup_dir/DataOSX" ]]; then
        mkdir -p "$GAME_APP/Contents/Resources/DataOSX"
        cp -R "$backup_dir/DataOSX/." "$GAME_APP/Contents/Resources/DataOSX/"
    fi

    if [[ -d "$backup_dir/CommonData" ]]; then
        mkdir -p "$GAME_APP/Contents/Resources/CommonData"
        cp -R "$backup_dir/CommonData/." "$GAME_APP/Contents/Resources/CommonData/"
    fi
}

game_path_for_backup_relpath() {
    local rel_path="$1"

    case "$rel_path" in
        MacOS/Worms\ W.M.D)
            echo "$GAME_APP/Contents/MacOS/Worms W.M.D"
            ;;
        Frameworks/*|PlugIns/*|_CodeSignature/*)
            echo "$GAME_APP/Contents/$rel_path"
            ;;
        Info.plist)
            echo "$GAME_APP/Contents/Info.plist"
            ;;
        DataOSX/*)
            echo "$GAME_APP/Contents/Resources/$rel_path"
            ;;
        CommonData/*)
            echo "$GAME_APP/Contents/Resources/$rel_path"
            ;;
        *)
            return 1
            ;;
    esac
}

verify_restored_game_backup() {
    local backup_dir="$1"
    local manifest="$backup_dir/$BACKUP_MANIFEST_NAME"
    local expected_hash expected_size rel_path target actual_size status=0
    local paths_file expected_file actual_file hash_line actual_hash actual_path actual_extra expected_target
    local symlink_hash symlink_target

    [[ -f "$manifest" ]] || return 0

    paths_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-restore-paths.XXXXXX")
    expected_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-restore-expected.XXXXXX")
    actual_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-restore-actual.XXXXXX")

    while IFS=$'\t' read -r expected_hash expected_size rel_path extra; do
        [[ -n "${expected_hash:-}" ]] || continue
        [[ "$expected_hash" == \#* ]] && continue
        if [[ -n "${extra:-}" ]] || [[ -z "${rel_path:-}" ]]; then
            status=1
            continue
        fi
        if [[ "$rel_path" == "$BACKUP_METADATA_NAME" ]]; then
            continue
        fi
        target=$(game_path_for_backup_relpath "$rel_path" || true)
        if [[ -z "$target" ]]; then
            print_warning "Restored file missing: $rel_path"
            status=1
            continue
        fi

        if [[ "$expected_hash" == symlink:* ]]; then
            symlink_hash=${expected_hash#symlink:}
            if [[ ! -L "$target" ]]; then
                print_warning "Restored symlink missing: $rel_path"
                status=1
                continue
            fi
            symlink_target=$(readlink "$target" 2>/dev/null || true)
            actual_size=$(worms_text_size "$symlink_target")
            actual_hash=$(worms_text_sha256 "$symlink_target")
            if [[ "$actual_size" != "$expected_size" ]] || [[ "$actual_hash" != "$symlink_hash" ]]; then
                print_warning "Restored symlink did not match backup manifest: $rel_path"
                status=1
            fi
            continue
        fi

        if [[ ! -f "$target" ]] || [[ -L "$target" ]]; then
            print_warning "Restored file missing: $rel_path"
            status=1
            continue
        fi
        actual_size=$(worms_file_size "$target")
        if [[ "$actual_size" != "$expected_size" ]]; then
            print_warning "Restored file did not match backup manifest: $rel_path"
            status=1
            continue
        fi
        printf '%s\n' "$target" >> "$paths_file"
        printf '%s\t%s\t%s\n' "$expected_hash" "$rel_path" "$target" >> "$expected_file"
    done < "$manifest"

    worms_manifest_hashes "/" "$paths_file" | while IFS= read -r hash_line; do
        [[ -n "$hash_line" ]] || continue
        actual_hash=${hash_line%% *}
        actual_path=${hash_line#*  }
        printf '%s\t%s\n' "$actual_hash" "$actual_path"
    done > "$actual_file"

    exec 3< "$actual_file"
    while IFS=$'\t' read -r expected_hash rel_path expected_target; do
        if ! IFS=$'\t' read -r actual_hash actual_path actual_extra <&3; then
            print_warning "Restored file hash missing: $rel_path"
            status=1
            continue
        fi
        if [[ -n "${actual_extra:-}" ]] || [[ "$actual_path" != "$expected_target" ]] || [[ "$actual_hash" != "$expected_hash" ]]; then
            print_warning "Restored file did not match backup manifest: $rel_path"
            status=1
        fi
    done < "$expected_file"

    if IFS=$'\t' read -r actual_hash actual_path actual_extra <&3; then
        print_warning "Unexpected restored-file hash output: $actual_path"
        status=1
    fi
    exec 3<&-

    rm -f "$paths_file" "$expected_file" "$actual_file"

    return "$status"
}

rollback() {
    stop_spinner false

    echo ""
    print_error "An error occurred during the fix process."

    if [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]] && $CLEANUP_NEEDED; then
        echo ""
        print_step "Rolling back changes from backup..."

        if [[ -f "$BACKUP_DIR/$BACKUP_MANIFEST_NAME" ]]; then
            start_spinner "Verifying backup manifest (this can take a few minutes)..."
            if verify_game_backup_manifest "$BACKUP_DIR"; then
                stop_spinner
                print_substep "Backup manifest verified"
            else
                stop_spinner
                print_warning "Backup manifest verification failed; rollback skipped to avoid copying unverified files."
                print_info "Backup preserved at: $BACKUP_DIR"
                cleanup
                return 0
            fi
        else
            print_warning "Backup has no manifest; restoring as a legacy backup."
        fi

        restore_game_backup_files "$BACKUP_DIR"
        start_spinner "Verifying restored files..."
        if ! verify_restored_game_backup "$BACKUP_DIR"; then
            stop_spinner
            print_error "Rollback restoration verification failed."
            print_warning "Some files were copied back, but the original state could not be proven."
        else
            stop_spinner
            print_success "Rolled back to original game files."
        fi

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

validate_game_app_for_read() {
    worms_reject_control_chars "$GAME_APP" "GAME_APP"

    if ! $GAME_APP_EXPLICIT; then
        print_step "Looking for Worms W.M.D..."
        detect_game_app_if_needed
        if [[ -n "${GAME_APP:-}" ]] && [[ -d "$GAME_APP/Contents" ]]; then
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

validate_game_app() {
    validate_game_app_for_read

    if ! worms_validate_game_app_for_mutation "$GAME_APP"; then
        print_error "Game bundle contains unsafe linked mutation paths."
        echo ""
        echo "Refusing to modify a bundle whose writable subpaths resolve outside Contents."
        exit 1
    fi
    if ! worms_refuse_linked_file_for_mutation \
        "$GAME_APP/Contents/MacOS/Worms W.M.D" "game executable"; then
        print_error "Game executable is not safe to modify."
        exit 1
    fi
}

detect_game_app_if_needed() {
    worms_reject_control_chars "$GAME_APP" "GAME_APP"

    if $GAME_APP_EXPLICIT; then
        return 0
    fi
    if $GAME_APP_AUTO_DETECTED; then
        return 0
    fi

    local detected_game
    detected_game=$(auto_detect_game || true)
    if [[ -n "$detected_game" ]]; then
        GAME_APP="$detected_game"
        GAME_APP_AUTO_DETECTED=true
    fi
}

ensure_build_dir() {
    if [[ -n "$BUILD_DIR" ]]; then
        mkdir -p "$BUILD_DIR"
        export BUILD_DIR
        return 0
    fi

    BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agl_stub_build.XXXXXX")
    BUILD_DIR_MANAGED=true
    export BUILD_DIR
}

prebuilt_qt_available() {
    chmod +x "$SCRIPTS_DIR/download_qt_frameworks.sh" 2>/dev/null || true
    [[ -x "$SCRIPTS_DIR/download_qt_frameworks.sh" ]] || return 1

    local prebuild_check
    prebuild_check=$("$SCRIPTS_DIR/download_qt_frameworks.sh" --check 2>/dev/null || true)
    [[ "$prebuild_check" == "available" ]]
}

detect_prebuilt_qt_version() {
    local package package_name version

    package=$(worms_latest_qt_package_by_version "$SCRIPT_DIR/dist" true || true)
    if [[ -n "$package" ]]; then
        package_name=$(basename "$package")
        version=${package_name#qt-frameworks-x86_64-}
        version=${version%.tar.gz}
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    echo "5.15"
}

homebrew_qt_available() {
    [[ -f "/usr/local/bin/brew" ]] && [[ -d "/usr/local/opt/qt@5/lib/QtCore.framework" ]]
}

homebrew_qt_version() {
    local qt_version_path qmake header

    qmake="/usr/local/opt/qt@5/bin/qmake"
    if [[ -x "$qmake" ]]; then
        "$qmake" -query QT_VERSION 2>/dev/null && return 0
    fi

    header="/usr/local/opt/qt@5/lib/QtCore.framework/Headers/qglobal.h"
    if [[ -f "$header" ]]; then
        awk '/QT_VERSION_STR/ {gsub(/"/, "", $3); print $3; exit}' "$header" 2>/dev/null && return 0
    fi

    qt_version_path=$(worms_latest_path_by_mtime "/usr/local/Cellar/qt@5" "*" "d" || true)
    if [[ -n "$qt_version_path" ]]; then
        basename "$qt_version_path"
    else
        echo "unknown"
    fi
}

detect_qt_source() {
    QT_SOURCE=""
    QT_PREFIX=""
    QT_VERSION_DISPLAY=""
    QT_SOURCE_DISPLAY=""

    if prebuilt_qt_available; then
        QT_SOURCE="prebuild"
        QT_VERSION_DISPLAY=$(detect_prebuilt_qt_version)
        QT_SOURCE_DISPLAY="Pre-built Qt $QT_VERSION_DISPLAY frameworks (no Homebrew needed)"
        return 0
    fi

    if homebrew_qt_available; then
        local homebrew_version
        homebrew_version=$(homebrew_qt_version)
        if ! worms_supported_qt5_version "$homebrew_version"; then
            return 1
        fi

        QT_SOURCE="homebrew"
        QT_PREFIX="/usr/local/opt/qt@5"
        QT_VERSION_DISPLAY="$homebrew_version"
        QT_SOURCE_DISPLAY="Homebrew Qt $QT_VERSION_DISPLAY (/usr/local/opt/qt@5)"
        return 0
    fi

    return 1
}

check_already_applied() {
    local game_frameworks="$GAME_APP/Contents/Frameworks"
    local game_plugins="$GAME_APP/Contents/PlugIns"
    local has_agl=false
    local has_qt=false
    local has_deps=false
    local has_required_runtime=true
    local required_fw

    # Check for AGL stub
    if [[ -f "$game_frameworks/AGL.framework/Versions/A/AGL" ]]; then
        local agl_arch
        agl_arch=$(lipo -archs "$game_frameworks/AGL.framework/Versions/A/AGL" 2>/dev/null || echo "")
        if echo "$agl_arch" | tr ' ' '\n' | grep -qx "x86_64"; then
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

    for required_fw in QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus QtSvg; do
        if [[ ! -d "$game_frameworks/$required_fw.framework" ]]; then
            has_required_runtime=false
            break
        fi
    done
    if [[ ! -f "$game_plugins/platforms/libqcocoa.dylib" ]] \
        || [[ ! -f "$game_plugins/imageformats/libqsvg.dylib" ]]; then
        has_required_runtime=false
    fi

    if $has_agl && $has_qt && $has_deps && $has_required_runtime; then
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
${BOLD}Worms W.M.D - macOS 26+ Fix v${VERSION}${NC}

${BOLD}USAGE:${NC}
    ./fix_worms_wmd.sh [OPTIONS]

${BOLD}OPTIONS:${NC}
    --help, -h      Show this help message
    --verify, -v    Verify installation without making changes
    --restore, -r   Restore game from backup
    --dry-run, -n   Preview changes without applying them
    --force, -f     Skip confirmation prompts
    --log-file PATH Write logs to a .log file under ~/Library/Logs
    --verbose       Show full verification output
    --debug         Enable debug tracing (writes a .trace log)

${BOLD}ENVIRONMENT VARIABLES:${NC}
    GAME_APP        Path to "Worms W.M.D.app" (for non-standard locations)
    LOG_FILE        Override log file path (.log under ~/Library/Logs)
    LOG_DIR         Override log directory (under ~/Library/Logs)
    WORMSWMD_DEBUG  Enable debug tracing (1/true/yes)
    WORMSWMD_VERBOSE Enable verbose output (1/true/yes)

${BOLD}EXAMPLES:${NC}
    # Apply the fix (auto-detects common Steam and GOG locations)
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
    local detected_game detected_real game_app_real target_seen=false
    local installation_count=0 allow_legacy=false restore_source="unknown"

    init_logging "fix_worms_wmd"
    print_header
    validate_game_app

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

    game_app_real=$(worms_real_dir "$GAME_APP")
    while IFS= read -r -d '' detected_game; do
        installation_count=$((installation_count + 1))
        detected_real=$(worms_real_dir "$detected_game" || true)
        [[ "$detected_real" == "$game_app_real" ]] && target_seen=true
    done < <(worms_find_game_apps)
    if ! $target_seen; then
        installation_count=$((installation_count + 1))
    fi
    if [[ "$installation_count" -le 1 ]]; then
        allow_legacy=true
    fi

    # Use the most recent original backup bound to this installation.
    latest=$(latest_original_game_backup "$GAME_APP" "$allow_legacy" || true)
    if [[ -z "$latest" ]]; then
        latest=$(latest_original_game_backup "$GAME_APP" "$allow_legacy" false || true)
    fi
    if [[ -n "$latest" ]] && backup_appears_already_fixed "$latest"; then
        print_warning "Every backup found appears to already include the fix."
        print_warning "Restoring the most recent compatible backup may not undo the fix."
    fi
    if [[ -z "$latest" ]]; then
        print_error "No compatible backup found for: $GAME_APP"
        echo ""
        echo "Backups created for another Steam or GOG installation will not be applied here."
        if [[ "$installation_count" -gt 1 ]]; then
            echo "Choose the installation that created the backup and try restore again."
        fi
        exit 1
    fi
    echo "Selected backup: $latest"
    if [[ ! -f "$latest/$BACKUP_METADATA_NAME" ]]; then
        print_warning "This legacy backup has no source-app identity metadata."
    elif backup_metadata_is_manifested "$latest"; then
        restore_source=$(backup_metadata_value "$latest" "game_source" || echo "unknown")
    fi
    echo ""

    if ! $FORCE; then
        read -p "Restore from this backup? [y/N] " -n 1 -r < /dev/tty
        echo ""
        if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
            echo "Restore cancelled."
            exit 0
        fi
    fi

    if [[ -f "$latest/$BACKUP_MANIFEST_NAME" ]]; then
        print_step "Verifying backup manifest (this can take a few minutes)..."
        start_spinner "Verifying backup manifest..."
        if verify_game_backup_manifest "$latest"; then
            stop_spinner
            print_step "Backup manifest verified"
        else
            stop_spinner
            print_error "Backup manifest verification failed; restore cancelled."
            echo ""
            echo "The backup was not copied because its recorded file checksums do not match."
            exit 1
        fi
    else
        print_warning "Backup has no manifest; restoring as a legacy backup."
    fi

    print_step "Restoring game files..."
    restore_game_backup_files "$latest"
    print_step "Verifying restored files..."
    start_spinner "Verifying restored files..."
    if ! verify_restored_game_backup "$latest"; then
        stop_spinner
        print_error "Restore verification failed after copying files."
        echo ""
        echo "The backup was copied, but at least one restored file did not match its recorded checksum."
        print_store_repair_guidance "$restore_source"
        exit 1
    fi
    stop_spinner

    echo ""
    print_success "Game restored to original game files."
    echo ""
    print_store_repair_guidance "$restore_source"
    exit 0
}

# ============================================================
# Verify Function
# ============================================================

do_verify() {
    init_logging "fix_worms_wmd"
    print_header
    validate_game_app_for_read
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
    detect_game_app_if_needed

    if [[ -d "$GAME_APP/Contents" ]] && [[ -f "$GAME_APP/Contents/MacOS/Worms W.M.D" ]]; then
        print_dry_run "Game found: $GAME_APP"
    else
        print_warning "Game not found at: $GAME_APP"
        print_info "Set GAME_APP to preview against a custom location."
        echo ""
    fi

    # Check macOS version
    local macos_version major_version
    macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    major_version=$(echo "$macos_version" | cut -d. -f1)
    print_dry_run "macOS version: $macos_version"

    if [[ "$major_version" =~ ^[0-9]+$ ]] && [[ "$major_version" -lt 26 ]]; then
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
            print_warning "Rosetta is required but not currently available"
            if [[ "$major_version" =~ ^[0-9]+$ ]] && [[ "$major_version" -ge 27 ]]; then
                print_dry_run "macOS 27 may need Rosetta reinstalled after upgrade"
                if command -v game-test-tool >/dev/null 2>&1; then
                    print_dry_run "macOS 27 beta legacy game support tool detected"
                fi
            fi
            print_dry_run "Applying the fix would require Rosetta first"
        fi
    fi

    # Check Qt source: prefer pre-built, fall back to Homebrew.
    if ! detect_qt_source; then
        print_error "Qt frameworks not available"
        echo ""
        echo "Pre-built Qt frameworks could not be found, and Intel Homebrew Qt is unavailable."
        echo "Check your internet connection or install the Homebrew fallback:"
        echo "  arch -x86_64 /usr/local/bin/brew install qt@5"
        exit 1
    fi
    print_dry_run "Qt source: $QT_SOURCE_DISPLAY"

    echo ""
    print_step "Changes that would be made..."
    echo ""

    print_dry_run "Create a target-bound backup at: ~/Documents/WormsWMD-Backup-YYYYMMDD-HHMMSS/"
    print_dry_run "  (frameworks, plugins, main executable, metadata, and existing signature resources)"
    echo ""

    print_dry_run "Build AGL stub library (universal x86_64 + arm64)"
    print_dry_run "  Source: $SCRIPT_DIR/src/agl_stub.c"
    print_dry_run "  Target: $GAME_APP/Contents/Frameworks/AGL.framework/"
    echo ""

    print_dry_run "Replace Qt frameworks found in the game bundle"
    print_dry_run "  (upgrade to Qt $QT_VERSION_DISPLAY and add QtDBus if missing)"
    echo ""

    print_dry_run "Copy dependencies referenced by Qt frameworks/plugins"
    if [[ "$QT_SOURCE" == "prebuild" ]]; then
        print_dry_run "  (verify bundled dependencies from the pre-built package)"
    else
        print_dry_run "  (resolved from /usr/local and @rpath entries)"
    fi
    echo ""

    print_dry_run "Update portable library paths and validate bundled @rpath references"
    print_dry_run "Replace platform plugin: libqcocoa.dylib"
    print_dry_run "Update image format plugins"
    print_dry_run "Update Info.plist metadata (bundle ID, HiDPI, min version)"
    print_dry_run "Secure config URLs (HTTP→HTTPS, disable internal URLs)"
    print_dry_run "Verify the complete runtime before optional finishing touches"
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
    validate_game_app

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
    macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    major_version=$(echo "$macos_version" | cut -d. -f1)
    print_substep "macOS version: $macos_version"

    if [[ "$major_version" =~ ^[0-9]+$ ]] && [[ "$major_version" -lt 26 ]]; then
        echo ""
        print_warning "This fix is designed for macOS 26 and later."
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
    print_substep "Game found: $GAME_APP"

    # Check Qt source: prefer pre-built, fall back to Homebrew.
    if detect_qt_source; then
        print_substep "Qt source: $QT_SOURCE_DISPLAY"
    else
        echo ""
        print_error "Qt frameworks not available"
        echo ""
        echo "Option 1 (Recommended): Check your internet connection and re-run the fix."
        echo "          The fix downloads pre-built frameworks automatically when available."
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

    BACKUP_DIR=$(worms_unique_path "$HOME/Documents/WormsWMD-Backup-$(date +%Y%m%d-%H%M%S)")
    mkdir -p "$BACKUP_DIR"

    start_spinner "Backing up Frameworks..."
    cp -R "$GAME_APP/Contents/Frameworks" "$BACKUP_DIR/"
    stop_spinner

    start_spinner "Backing up PlugIns..."
    cp -R "$GAME_APP/Contents/PlugIns" "$BACKUP_DIR/"
    stop_spinner

    mkdir -p "$BACKUP_DIR/MacOS"
    cp -p "$GAME_APP/Contents/MacOS/Worms W.M.D" "$BACKUP_DIR/MacOS/Worms W.M.D"

    if [[ -d "$GAME_APP/Contents/_CodeSignature" ]]; then
        cp -R "$GAME_APP/Contents/_CodeSignature" "$BACKUP_DIR/"
    fi

    if [[ -f "$GAME_APP/Contents/Info.plist" ]]; then
        cp "$GAME_APP/Contents/Info.plist" "$BACKUP_DIR/Info.plist"
    fi

    local data_dir="$GAME_APP/Contents/Resources/DataOSX"
    if [[ -d "$data_dir" ]]; then
        mkdir -p "$BACKUP_DIR/DataOSX"
        while IFS= read -r config_file; do
            if [[ -f "$data_dir/$config_file" ]]; then
                cp "$data_dir/$config_file" "$BACKUP_DIR/DataOSX/$config_file"
            fi
        done < <(worms_dataosx_config_files)
    fi

    local common_data_dir="$GAME_APP/Contents/Resources/CommonData"
    if [[ -d "$common_data_dir" ]]; then
        mkdir -p "$BACKUP_DIR/CommonData"
        while IFS= read -r config_file; do
            if [[ -f "$common_data_dir/$config_file" ]]; then
                cp "$common_data_dir/$config_file" "$BACKUP_DIR/CommonData/$config_file"
            fi
        done < <(worms_commondata_config_files)
    fi

    write_game_backup_metadata "$BACKUP_DIR"

    print_substep "Creating backup manifest (this can take a few minutes)..."
    start_spinner "Creating backup manifest (this can take a few minutes)..."
    write_game_backup_manifest "$BACKUP_DIR"
    stop_spinner
    print_substep "Backup manifest created: $BACKUP_MANIFEST_NAME"
    print_substep "Backup created: $BACKUP_DIR"
    CLEANUP_NEEDED=true

    # ============================================================
    # Apply fixes
    # ============================================================
    echo ""
    print_step "Building AGL stub library..."
    ensure_build_dir
    print_substep "Build directory: $BUILD_DIR"
    chmod +x "$SCRIPTS_DIR/01_build_agl_stub.sh"
    "$SCRIPTS_DIR/01_build_agl_stub.sh"

    echo ""
    print_step "Replacing Qt frameworks..."

    # If using pre-built, download first
    if [[ "$QT_SOURCE" == "prebuild" ]]; then
        start_spinner "Downloading Qt frameworks..."
        local qt_extract_dir qt_extract_output
        qt_extract_output=$("$SCRIPTS_DIR/download_qt_frameworks.sh" 2>/dev/null || true)
        qt_extract_dir=$(echo "$qt_extract_output" | tail -1)
        stop_spinner

        if [[ -n "$qt_extract_dir" ]] && [[ -d "$qt_extract_dir/Frameworks" ]]; then
            export QT_PREFIX="$qt_extract_dir"
            print_substep "Using pre-built Qt $QT_VERSION_DISPLAY"
        else
            if homebrew_qt_available; then
                local homebrew_version
                homebrew_version=$(homebrew_qt_version)
                if ! worms_supported_qt5_version "$homebrew_version"; then
                    print_error "Installed Homebrew Qt is $homebrew_version; this fix requires Qt 5.15.x."
                    exit 1
                fi

                print_warning "Pre-built Qt prep failed, falling back to Homebrew"
                QT_SOURCE="homebrew"
                QT_PREFIX="/usr/local/opt/qt@5"
                QT_VERSION_DISPLAY="$homebrew_version"
            else
                print_error "Pre-built Qt frameworks could not be prepared and Homebrew Qt is unavailable."
                echo ""
                echo "Try again with a working network connection, or install the Homebrew fallback:"
                echo "  arch -x86_64 /usr/local/bin/brew install qt@5"
                exit 1
            fi
        fi
    fi

    chmod +x "$SCRIPTS_DIR/02_replace_qt_frameworks.sh"
    export GAME_APP QT_SOURCE QT_PREFIX
    start_spinner "Copying frameworks..."
    "$SCRIPTS_DIR/02_replace_qt_frameworks.sh" > /dev/null
    stop_spinner

    if [[ "$QT_SOURCE" == "prebuild" ]]; then
        print_substep "Qt frameworks installed ($QT_VERSION_DISPLAY pre-built)"
    else
        print_substep "Qt frameworks installed ($QT_VERSION_DISPLAY Homebrew)"
    fi

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
        return 1
    fi
    stop_spinner

    local copied bundled missing
    copied=$(echo "$copy_output" | awk -F= '/^COPIED_LIBS=/{print $2}' | tail -1)
    bundled=$(echo "$copy_output" | awk -F= '/^BUNDLED_LIBS=/{print $2}' | tail -1)
    missing=$(echo "$copy_output" | awk -F= '/^MISSING_LIBS=/{print $2}' | tail -1)

    if [[ -n "$bundled" ]]; then
        print_substep "Bundled dependencies verified: $bundled"
    elif [[ -n "$copied" ]]; then
        print_substep "Dependencies copied: $copied"
    else
        print_substep "Dependencies prepared"
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
    local path_fix_output
    if ! path_fix_output=$("$SCRIPTS_DIR/04_fix_library_paths.sh" 2>&1); then
        stop_spinner
        print_error "Fixing library paths failed"
        [[ -n "$path_fix_output" ]] && echo "$path_fix_output"
        return 1
    fi
    stop_spinner
    print_substep "Library paths validated and portable references updated"

    # ============================================================
    # Apply enhancements
    # ============================================================
    echo ""
    print_step "Applying enhancements..."

    # Fix Info.plist
    if [[ -f "$SCRIPTS_DIR/06_fix_info_plist.sh" ]]; then
        chmod +x "$SCRIPTS_DIR/06_fix_info_plist.sh"
        local info_plist_output
        if info_plist_output=$("$SCRIPTS_DIR/06_fix_info_plist.sh" 2>&1); then
            print_substep "Info.plist updated (bundle ID, HiDPI, min version)"
        else
            print_error "Info.plist update failed"
            echo "$info_plist_output" | head -5 | while read -r line; do
                [[ -n "$line" ]] && print_substep "$line"
            done || true
            return 1
        fi
    fi

    # Fix config URLs
    if [[ -f "$SCRIPTS_DIR/07_fix_config_urls.sh" ]]; then
        chmod +x "$SCRIPTS_DIR/07_fix_config_urls.sh"
        local config_output
        if config_output=$("$SCRIPTS_DIR/07_fix_config_urls.sh" 2>&1); then
            print_substep "Config URLs secured (HTTP→HTTPS)"
        else
            print_error "Config URL update failed"
            echo "$config_output" | head -5 | while read -r line; do
                [[ -n "$line" ]] && print_substep "$line"
            done || true
            return 1
        fi
    fi

    # ============================================================
    # Verify installation
    # ============================================================
    echo ""
    print_step "Verifying installation..."
    chmod +x "$SCRIPTS_DIR/05_verify_installation.sh"

    # Capture verification output
    local verify_output verify_status
    verify_output=""
    verify_status=0
    if worms_verbose_enabled; then
        if "$SCRIPTS_DIR/05_verify_installation.sh"; then
            print_substep "Verification completed"
        else
            verify_status=$?
            print_error "Installation verification failed"
        fi
    else
        if verify_output=$("$SCRIPTS_DIR/05_verify_installation.sh" 2>&1); then
            if echo "$verify_output" | grep -q "^PASSED with"; then
                echo "$verify_output" | grep -E "^PASSED with" | tail -1 | while read -r line; do
                    print_substep "$line"
                done
            else
                print_substep "All checks passed"
            fi
        else
            verify_status=$?
            print_error "Installation verification failed"
            echo "$verify_output" | grep -E "^(ERROR|WARNING|FAILED)" | head -10 | while read -r line; do
                print_substep "$line"
            done || true
        fi
    fi

    if [[ "$verify_status" -ne 0 ]]; then
        return "$verify_status"
    fi

    # Core bundle mutations are now verified. Optional finishing touches happen
    # after the rollback boundary so a verifier failure cannot leave preferences
    # or quarantine state changed outside the backup.
    CLEANUP_NEEDED=false

    # ============================================================
    # Post-fix: Code signing and quarantine removal
    # ============================================================
    echo ""
    print_step "Applying finishing touches..."

    xattr -rd com.apple.quarantine "$GAME_APP" 2>/dev/null || true
    if xattr -l "$GAME_APP" 2>/dev/null | grep -q "quarantine"; then
        print_warning "Quarantine flag still present (may cause Gatekeeper warnings)"
    else
        print_substep "No quarantine flags present"
    fi

    if codesign --force --deep --sign - "$GAME_APP" 2>/dev/null; then
        print_substep "Ad-hoc code signature applied"
    else
        print_warning "Could not apply ad-hoc signature (game will still work)"
    fi

    if defaults read "com.team17.Worms W.M.D" "QtSystem_GameWindow.geometry" &>/dev/null; then
        defaults delete "com.team17.Worms W.M.D" "QtSystem_GameWindow.geometry" 2>/dev/null || true
        defaults delete "com.team17.Worms W.M.D" "QtSystem_GameWindow.windowState" 2>/dev/null || true
        print_substep "Reset incompatible Qt window geometry"
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
    echo "You can now launch Worms W.M.D from Steam, GOG, or your Applications folder."
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
