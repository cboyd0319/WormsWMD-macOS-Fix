#!/bin/bash
#
# watch_for_updates.sh - Monitor game for Steam updates and prompt to reapply fix
#
# Steam's "Verify Integrity" feature and automatic updates will overwrite
# the fix. This script monitors the game bundle and alerts you when the
# fix needs to be reapplied.
#
# Usage:
#   ./watch_for_updates.sh              # Interactive mode
#   ./watch_for_updates.sh --check      # Single check (for automation)
#   ./watch_for_updates.sh --daemon     # Background monitoring
#   ./watch_for_updates.sh --install    # Install as LaunchAgent
#   ./watch_for_updates.sh --uninstall  # Remove LaunchAgent
#

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LAUNCH_AGENT_ID="com.wormswmd.fix.watcher"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_ID}.plist"
CHECK_INTERVAL=300  # 5 minutes
LAUNCH_AGENT_TEMP_FILE=""

# shellcheck disable=SC1091
source "$REPO_DIR/scripts/common.sh"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/ui.sh"
worms_color_init

cleanup_watcher_temp() {
    if [[ -n "$LAUNCH_AGENT_TEMP_FILE" ]] \
        && [[ -f "$LAUNCH_AGENT_TEMP_FILE" ]] \
        && [[ ! -L "$LAUNCH_AGENT_TEMP_FILE" ]]; then
        rm -f -- "$LAUNCH_AGENT_TEMP_FILE"
    fi
}

trap cleanup_watcher_temp EXIT

DEFAULT_GAME_PATH="$(worms_default_game_app)"
GAME_APP="${GAME_APP:-$DEFAULT_GAME_PATH}"
if [[ "$GAME_APP" == "$DEFAULT_GAME_PATH" ]] && [[ ! -d "$GAME_APP" ]]; then
    detected_game=$(worms_first_detected_game_app || true)
    if [[ -n "$detected_game" ]]; then
        GAME_APP="$detected_game"
    fi
fi
worms_reject_control_chars "$GAME_APP" "GAME_APP"

print_help() {
    cat << 'EOF'
Worms W.M.D Fix - Update Watcher

Monitors for Steam updates that overwrite the fix and prompts to reapply.

USAGE:
    ./watch_for_updates.sh [OPTIONS]

OPTIONS:
    --check         Single check, exit with status (0=fixed, 1=needs fix)
    --daemon        Run in background, check periodically
    --install       Install as LaunchAgent (starts on login)
    --uninstall     Remove LaunchAgent
    --help, -h      Show this help

EXAMPLES:
    # Check once if fix is still applied
    ./watch_for_updates.sh --check

    # Run watcher in background
    ./watch_for_updates.sh --daemon &

    # Install to run automatically on login
    ./watch_for_updates.sh --install

EOF
}

# Check if the fix is still applied
check_fix_status() {
    local game_frameworks="$GAME_APP/Contents/Frameworks"
    local game_plugins="$GAME_APP/Contents/PlugIns"

    # Quick checks for fix status
    local has_agl=false
    local has_qt515=false
    local has_required_runtime=true
    local required_fw

    # Check AGL stub (small file = stub)
    if [[ -f "$game_frameworks/AGL.framework/Versions/A/AGL" ]]; then
        local agl_size
        agl_size=$(stat -f%z "$game_frameworks/AGL.framework/Versions/A/AGL" 2>/dev/null || echo "0")
        if [[ "$agl_size" -lt 100000 ]]; then
            has_agl=true
        fi
    fi

    # Check Qt version
    local qt_core="$game_frameworks/QtCore.framework/Versions/5/QtCore"
    if [[ -f "$qt_core" ]]; then
        if otool -L "$qt_core" 2>/dev/null | grep -q "5.15"; then
            has_qt515=true
        fi
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

    if $has_agl && $has_qt515 && $has_required_runtime; then
        echo "applied"
    elif $has_agl || $has_qt515; then
        echo "partial"
    else
        echo "missing"
    fi
}

# Send macOS notification
send_notification() {
    local title="$1"
    local message="$2"

    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
}

xml_escape() {
    sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e "s/'/\&apos;/g"
}

prepare_launch_agent_directory() {
    local library_dir="$HOME/Library"
    local launch_agents_dir="$library_dir/LaunchAgents"

    worms_reject_control_chars "$HOME" "HOME" || return 1
    [[ -d "$HOME" ]] && [[ ! -L "$HOME" ]] || return 1
    if [[ -e "$library_dir" ]] || [[ -L "$library_dir" ]]; then
        [[ -d "$library_dir" ]] && [[ ! -L "$library_dir" ]] || return 1
    else
        mkdir "$library_dir" || return 1
    fi
    if [[ -e "$launch_agents_dir" ]] || [[ -L "$launch_agents_dir" ]]; then
        [[ -d "$launch_agents_dir" ]] && [[ ! -L "$launch_agents_dir" ]] || return 1
    else
        mkdir "$launch_agents_dir" || return 1
    fi
}

launch_agent_is_project_owned() {
    local path="$1"
    local link_count owner_uid label program

    [[ -f "$path" ]] && [[ ! -L "$path" ]] || return 1
    link_count=$(worms_file_link_count "$path") || return 1
    [[ "$link_count" == "1" ]] || return 1
    owner_uid=$(worms_file_owner_uid "$path") || return 1
    [[ "$owner_uid" == "$UID" ]] || return 1
    plutil -lint "$path" >/dev/null 2>&1 || return 1
    label=$(plutil -extract Label raw -o - "$path" 2>/dev/null) || return 1
    program=$(plutil -extract ProgramArguments.0 raw -o - "$path" 2>/dev/null) || return 1
    [[ "$label" == "$LAUNCH_AGENT_ID" ]] \
        && [[ "$program" == "$SCRIPT_DIR/watch_for_updates.sh" ]]
}

# Prompt user to reapply
prompt_reapply() {
    local response
    response=$(osascript -e 'display dialog "Worms W.M.D fix needs to be reapplied.\n\nSteam may have updated or verified the game files.\n\nWould you like to reapply the fix now?" buttons {"Later", "Reapply Now"} default button "Reapply Now" with title "Worms W.M.D Fix"' 2>/dev/null || echo "")

    if echo "$response" | grep -q "Reapply Now"; then
        return 0
    else
        return 1
    fi
}

# Single check mode
do_check() {
    if [[ ! -d "$GAME_APP" ]]; then
        echo "Game not found at: $GAME_APP"
        exit 2
    fi

    local status
    status=$(check_fix_status)

    case "$status" in
        applied)
            echo -e "${GREEN}Fix is applied${NC}"
            exit 0
            ;;
        partial)
            echo -e "${YELLOW}Fix is partially applied${NC}"
            exit 1
            ;;
        missing)
            echo -e "${RED}Fix is missing - needs to be reapplied${NC}"
            exit 1
            ;;
    esac
}

# Daemon mode - run in background
do_daemon() {
    echo "Starting update watcher (checking every $CHECK_INTERVAL seconds)..."
    echo "Press Ctrl+C to stop"

    local last_status=""

    while true; do
        if [[ -d "$GAME_APP" ]]; then
            local status
            status=$(check_fix_status)

            # Only alert on status change
            if [[ "$status" != "$last_status" ]]; then
                case "$status" in
                    missing|partial)
                        send_notification "Worms W.M.D Fix" "Fix needs to be reapplied after Steam update"
                        if prompt_reapply; then
                            echo "Reapplying fix..."
                            cd "$REPO_DIR"
                            GAME_APP="$GAME_APP" ./fix_worms_wmd.sh --force
                            send_notification "Worms W.M.D Fix" "Fix successfully reapplied!"
                        fi
                        ;;
                    applied)
                        if [[ -n "$last_status" ]]; then
                            echo "Fix verified: still applied"
                        fi
                        ;;
                esac
                last_status="$status"
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Install as LaunchAgent
do_install() {
    echo "Installing update watcher as LaunchAgent..."
    local launch_domain="gui/${UID}"
    local watcher_path log_path game_app_path retained_plist="" watcher_log_temp=""
    local logs_root="$HOME/Library/Logs"
    local project_log_dir="$logs_root/WormsWMD-Fix"
    local watcher_log_path="$project_log_dir/watcher.log"
    local prior_active=false old_umask

    if ! prepare_launch_agent_directory; then
        echo -e "${RED}Refusing an unsafe LaunchAgents directory${NC}" >&2
        return 1
    fi
    if [[ -e "$logs_root" ]] || [[ -L "$logs_root" ]]; then
        [[ -d "$logs_root" ]] && [[ ! -L "$logs_root" ]] || {
            echo -e "${RED}Refusing an unsafe Logs directory${NC}" >&2
            return 1
        }
    else
        mkdir "$logs_root"
    fi
    if [[ -e "$project_log_dir" ]] || [[ -L "$project_log_dir" ]]; then
        [[ -d "$project_log_dir" ]] && [[ ! -L "$project_log_dir" ]] || {
            echo -e "${RED}Refusing an unsafe watcher log directory${NC}" >&2
            return 1
        }
    else
        mkdir "$project_log_dir"
    fi
    if ! worms_validate_replaceable_regular_file "$watcher_log_path"; then
        echo -e "${RED}Refusing an unsafe watcher log target${NC}" >&2
        return 1
    fi
    if [[ ! -e "$watcher_log_path" ]]; then
        watcher_log_temp=$(worms_same_directory_temp_file "$watcher_log_path") || return 1
        chmod 600 "$watcher_log_temp"
        if ! mv -n -- "$watcher_log_temp" "$watcher_log_path" \
            || [[ -e "$watcher_log_temp" ]]; then
            rm -f -- "$watcher_log_temp"
            echo -e "${RED}Could not create a safe watcher log${NC}" >&2
            return 1
        fi
    else
        chmod 600 "$watcher_log_path"
    fi
    if [[ -e "$LAUNCH_AGENT_PATH" ]] || [[ -L "$LAUNCH_AGENT_PATH" ]]; then
        if ! launch_agent_is_project_owned "$LAUNCH_AGENT_PATH"; then
            echo -e "${RED}Refusing to replace a foreign or linked LaunchAgent${NC}" >&2
            return 1
        fi
        if launchctl print "$launch_domain/$LAUNCH_AGENT_ID" >/dev/null 2>&1; then
            prior_active=true
        fi
    fi
    watcher_path=$(printf '%s' "${SCRIPT_DIR}/watch_for_updates.sh" | xml_escape)
    log_path=$(printf '%s' "$watcher_log_path" | xml_escape)
    game_app_path=$(printf '%s' "$GAME_APP" | xml_escape)

    old_umask=$(umask)
    umask 077
    LAUNCH_AGENT_TEMP_FILE=$(mktemp "$(dirname "$LAUNCH_AGENT_PATH")/.${LAUNCH_AGENT_ID}.plist.XXXXXX")
    umask "$old_umask"
    cat > "$LAUNCH_AGENT_TEMP_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCH_AGENT_ID}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${watcher_path}</string>
        <string>--daemon</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>GAME_APP</key>
        <string>${game_app_path}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${log_path}</string>
    <key>StandardErrorPath</key>
    <string>${log_path}</string>
</dict>
</plist>
EOF
    chmod 600 "$LAUNCH_AGENT_TEMP_FILE"
    if ! plutil -lint "$LAUNCH_AGENT_TEMP_FILE" >/dev/null 2>&1; then
        rm -f -- "$LAUNCH_AGENT_TEMP_FILE"
        LAUNCH_AGENT_TEMP_FILE=""
        echo -e "${RED}Generated LaunchAgent failed plist validation${NC}" >&2
        return 1
    fi

    if [[ -e "$LAUNCH_AGENT_PATH" ]] || [[ -L "$LAUNCH_AGENT_PATH" ]]; then
        if ! launch_agent_is_project_owned "$LAUNCH_AGENT_PATH"; then
            echo -e "${RED}LaunchAgent became unsafe before replacement${NC}" >&2
            return 1
        fi
        retained_plist=$(mktemp "$(dirname "$LAUNCH_AGENT_PATH")/.${LAUNCH_AGENT_ID}.retained.XXXXXX")
        rm -f -- "$retained_plist"
        if ! mv -- "$LAUNCH_AGENT_PATH" "$retained_plist"; then
            echo -e "${RED}Could not retain the prior LaunchAgent${NC}" >&2
            return 1
        fi
        launchctl bootout "$launch_domain/$LAUNCH_AGENT_ID" 2>/dev/null || true
    fi
    if ! mv -n -- "$LAUNCH_AGENT_TEMP_FILE" "$LAUNCH_AGENT_PATH" \
        || [[ -e "$LAUNCH_AGENT_TEMP_FILE" ]]; then
        if [[ -n "$retained_plist" ]] \
            && [[ ! -e "$LAUNCH_AGENT_PATH" ]] && [[ ! -L "$LAUNCH_AGENT_PATH" ]]; then
            if mv -n -- "$retained_plist" "$LAUNCH_AGENT_PATH" \
                && [[ ! -e "$retained_plist" ]]; then
                $prior_active \
                    && launchctl bootstrap "$launch_domain" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 \
                    || true
            fi
        fi
        if [[ -n "$retained_plist" ]] && [[ -e "$retained_plist" ]]; then
            echo -e "${RED}Prior LaunchAgent retained at: $retained_plist${NC}" >&2
        fi
        echo -e "${RED}Could not publish the LaunchAgent${NC}" >&2
        return 1
    fi
    LAUNCH_AGENT_TEMP_FILE=""
    if ! launchctl bootstrap "$launch_domain" "$LAUNCH_AGENT_PATH"; then
        rm -f -- "$LAUNCH_AGENT_PATH"
        if [[ -n "$retained_plist" ]] && [[ -f "$retained_plist" ]]; then
            if mv -n -- "$retained_plist" "$LAUNCH_AGENT_PATH" \
                && [[ ! -e "$retained_plist" ]]; then
                if $prior_active \
                    && ! launchctl bootstrap "$launch_domain" "$LAUNCH_AGENT_PATH"; then
                    echo -e "${RED}Prior LaunchAgent was restored but could not be reactivated${NC}" >&2
                fi
            else
                echo -e "${RED}Prior LaunchAgent retained at: $retained_plist${NC}" >&2
            fi
        fi
        echo -e "${RED}LaunchAgent bootstrap failed; prior configuration restored${NC}" >&2
        return 1
    fi
    [[ -n "$retained_plist" ]] && rm -f -- "$retained_plist"

    echo -e "${GREEN}Update watcher installed!${NC}"
    echo ""
    echo "The watcher will start automatically on login and monitor for Steam updates."
    echo "Logs: ~/Library/Logs/WormsWMD-Fix/watcher.log"
    echo ""
    echo "To uninstall: $0 --uninstall"
}

# Uninstall LaunchAgent
do_uninstall() {
    echo "Uninstalling update watcher..."
    local launch_domain="gui/${UID}"

    if [[ -e "$LAUNCH_AGENT_PATH" ]] || [[ -L "$LAUNCH_AGENT_PATH" ]]; then
        if ! launch_agent_is_project_owned "$LAUNCH_AGENT_PATH"; then
            echo -e "${RED}Refusing to remove a foreign or linked LaunchAgent${NC}" >&2
            return 1
        fi
        launchctl bootout "$launch_domain/$LAUNCH_AGENT_ID" 2>/dev/null || true
        rm -f -- "$LAUNCH_AGENT_PATH"
        echo -e "${GREEN}Update watcher uninstalled${NC}"
    else
        echo "LaunchAgent not installed"
    fi
}

# Parse arguments
case "${1:-}" in
    --check|-c)
        do_check
        ;;
    --daemon|-d)
        do_daemon
        ;;
    --install|-i)
        do_install
        ;;
    --uninstall|-u)
        do_uninstall
        ;;
    --help|-h)
        print_help
        ;;
    "")
        # Interactive mode - single check with prompt
        if [[ ! -d "$GAME_APP" ]]; then
            echo -e "${RED}Game not found at: $GAME_APP${NC}"
            exit 1
        fi

        status=$(check_fix_status)
        case "$status" in
            applied)
                echo -e "${GREEN}Fix is currently applied.${NC}"
                echo ""
                echo "Options:"
                echo "  --daemon    Run in background to monitor for Steam updates"
                echo "  --install   Install to run automatically on login"
                ;;
            partial|missing)
                echo -e "${YELLOW}Fix needs to be reapplied.${NC}"
                echo ""
                read -p "Reapply now? [Y/n] " -n 1 -r < /dev/tty
                echo ""
                if [[ ! "${REPLY:-}" =~ ^[Nn]$ ]]; then
                    cd "$REPO_DIR"
                    GAME_APP="$GAME_APP" ./fix_worms_wmd.sh
                fi
                ;;
        esac
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Use --help for usage"
        exit 1
        ;;
esac
