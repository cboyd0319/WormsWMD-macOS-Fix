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

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
LAUNCH_AGENT_ID="com.wormswmd.fix.watcher"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_ID}.plist"
CHECK_INTERVAL=300  # 5 minutes

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

    # Quick checks for fix status
    local has_agl=false
    local has_qt515=false

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

    if $has_agl && $has_qt515; then
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
                            ./fix_worms_wmd.sh --force
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

    # Create LaunchAgent plist
    cat > "$LAUNCH_AGENT_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCH_AGENT_ID}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_DIR}/watch_for_updates.sh</string>
        <string>--daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/WormsWMD-Fix/watcher.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/WormsWMD-Fix/watcher.log</string>
</dict>
</plist>
EOF

    # Create log directory
    mkdir -p "$HOME/Library/Logs/WormsWMD-Fix"

    # Load the agent
    launchctl load "$LAUNCH_AGENT_PATH" 2>/dev/null || true

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

    if [[ -f "$LAUNCH_AGENT_PATH" ]]; then
        launchctl unload "$LAUNCH_AGENT_PATH" 2>/dev/null || true
        rm -f "$LAUNCH_AGENT_PATH"
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
                read -p "Reapply now? [Y/n] " -n 1 -r
                echo ""
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    cd "$REPO_DIR"
                    ./fix_worms_wmd.sh
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
