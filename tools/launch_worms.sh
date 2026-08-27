#!/bin/bash
#
# launch_worms.sh - Enhanced Game Launcher for Worms W.M.D
#
# This launcher provides:
# - Crash detection and reporting
# - Diagnostic logging for troubleshooting
# - Safe mode for graphics issues
# - Fix verification before launch
# - Steam launch options integration
#
# Usage:
#   ./launch_worms.sh [OPTIONS]
#
# Steam Launch Options:
#   "/path/to/launch_worms.sh" --steam %command%
#
# Options:
#   --steam         Steam mode (expects %command% as next arg)
#   --safe-mode     Launch with reduced graphics settings
#   --log           Enable diagnostic logging
#   --log-file PATH Write logs to a .log file under ~/Library/Logs
#   --verbose       Extra verbose output
#   --qt-debug      Enable Qt debugging output
#   --opengl-debug  Enable OpenGL debugging
#   --check-fix     Verify fix before launching
#   --crash-report  Generate crash report if game crashes
#   --help          Show this help
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

# shellcheck disable=SC1091
source "$REPO_DIR/scripts/common.sh"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/ui.sh"
worms_color_init

# Configuration
DEFAULT_GAME_PATH="$(worms_default_game_app)"
GAME_APP="${GAME_APP:-$DEFAULT_GAME_PATH}"
if [[ "$GAME_APP" == "$DEFAULT_GAME_PATH" ]] && [[ ! -f "$GAME_APP/Contents/MacOS/Worms W.M.D" ]]; then
    detected_game=$(worms_first_detected_game_app || true)
    if [[ -n "$detected_game" ]]; then
        GAME_APP="$detected_game"
    fi
fi
GAME_EXEC="$GAME_APP/Contents/MacOS/Worms W.M.D"
LOG_DIR="${LOG_DIR:-$HOME/Library/Logs/WormsWMD}"
CRASH_DIR="$LOG_DIR/crashes"
LOG_FILE=""
SAFE_MODE=false
VERBOSE=false
QT_DEBUG=false
OPENGL_DEBUG=false
ENABLE_LOGGING=false
CHECK_FIX=false
CRASH_REPORT=true
STEAM_MODE=false
CRASH_TEMP_FILE=""

cleanup_launcher_output() {
    if [[ -n "$CRASH_TEMP_FILE" ]] && [[ -f "$CRASH_TEMP_FILE" ]] \
        && [[ ! -L "$CRASH_TEMP_FILE" ]]; then
        rm -f -- "$CRASH_TEMP_FILE"
    fi
}

trap cleanup_launcher_output EXIT

print_help() {
    cat << 'EOF'
Worms W.M.D - Enhanced Launcher

USAGE:
    ./launch_worms.sh [OPTIONS]

OPTIONS:
    --steam             Steam launch mode (use with %command%)
    --safe-mode         Launch with reduced graphics (software rendering hints)
    --log               Enable diagnostic logging to ~/Library/Logs/WormsWMD/
    --log-file PATH     Write logs to a .log file under ~/Library/Logs
    --verbose           Extra verbose output
    --qt-debug          Enable Qt plugin and platform debugging
    --opengl-debug      Enable OpenGL debugging output
    --check-fix         Verify fix is applied before launching
    --no-crash-report   Disable crash reporting
    --help, -h          Show this help message

STEAM LAUNCH OPTIONS:
    To use this launcher with Steam:
    1. Right-click Worms W.M.D in Steam → Properties
    2. In "Launch Options", enter:
       "/full/path/to/launch_worms.sh" --steam %command%

ENVIRONMENT VARIABLES:
    GAME_APP            Path to "Worms W.M.D.app"
    LOG_DIR             Override log directory under ~/Library/Logs
    QT_DEBUG_PLUGINS    Qt plugin debugging (set by --qt-debug)
    LIBGL_DEBUG         OpenGL debugging (set by --opengl-debug)

EXAMPLES:
    # Normal launch with logging
    ./launch_worms.sh --log

    # Safe mode for graphics issues
    ./launch_worms.sh --safe-mode --log

    # Full debug mode
    ./launch_worms.sh --qt-debug --opengl-debug --log --verbose

    # Steam launch options
    "/Users/you/WormsWMD-macOS-Fix/tools/launch_worms.sh" --steam %command%

EOF
}

log_message() {
    local timestamp
    local message
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    message=$(printf '%s' "$1" | tr '\r\n' '  ')
    echo "[$timestamp] $message"
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] $message" >> "$LOG_FILE"
    fi
}

prepare_logging_paths() {
    local logs_root="$HOME/Library/Logs"

    worms_reject_control_chars "$GAME_APP" "GAME_APP" || return 1
    worms_reject_control_chars "$GAME_EXEC" "GAME_EXEC" || return 1
    worms_reject_control_chars "$LOG_DIR" "LOG_DIR" || return 1
    worms_reject_control_chars "$LOG_FILE" "LOG_FILE" || return 1

    mkdir -p "$logs_root"
    if ! worms_path_creatable_inside_root "$logs_root" "$LOG_DIR" \
        || { [[ -e "$LOG_DIR" ]] && [[ ! -d "$LOG_DIR" ]]; }; then
        echo -e "${RED}LOG_DIR must be inside $logs_root${NC}"
        exit 1
    fi
    mkdir -p "$LOG_DIR"

    if [[ -z "$LOG_FILE" ]]; then
        LOG_FILE=$(worms_unique_path \
            "$LOG_DIR/worms-$(date '+%Y%m%d-%H%M%S')-$$" ".log")
    fi

    case "$LOG_FILE" in
        *.log)
            ;;
        *)
            echo -e "${RED}--log-file must end with .log${NC}"
            exit 1
            ;;
    esac
    if ! worms_path_creatable_inside_root "$logs_root" "$LOG_FILE"; then
        echo -e "${RED}--log-file must be inside $logs_root${NC}"
        exit 1
    fi
    if ! worms_validate_replaceable_regular_file "$LOG_FILE"; then
        echo -e "${RED}--log-file must be a regular non-linked log file path${NC}"
        exit 1
    fi
    mkdir -p "$(dirname "$LOG_FILE")"
    if [[ ! -e "$LOG_FILE" ]]; then
        local old_umask
        old_umask=$(umask)
        umask 077
        : > "$LOG_FILE"
        umask "$old_umask"
        chmod 600 "$LOG_FILE"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --steam)
            STEAM_MODE=true
            ENABLE_LOGGING=true
            CRASH_REPORT=true
            shift
            # Skip the %command% argument (it's the game executable path)
            if [[ $# -gt 0 ]] && [[ "$1" == *"Worms W.M.D"* ]]; then
                GAME_EXEC="$1"
                GAME_APP="$(dirname "$(dirname "$(dirname "$1")")")"
                shift
            fi
            ;;
        --safe-mode)
            SAFE_MODE=true
            shift
            ;;
        --log)
            ENABLE_LOGGING=true
            shift
            ;;
        --log-file)
            ENABLE_LOGGING=true
            if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                echo -e "${RED}--log-file requires a path${NC}"
                exit 1
            fi
            LOG_FILE="$2"
            if [[ -d "$LOG_FILE" ]]; then
                echo -e "${RED}--log-file must be a file path, not a directory${NC}"
                exit 1
            fi
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --qt-debug)
            QT_DEBUG=true
            shift
            ;;
        --opengl-debug)
            OPENGL_DEBUG=true
            shift
            ;;
        --check-fix)
            CHECK_FIX=true
            shift
            ;;
        --no-crash-report)
            CRASH_REPORT=false
            shift
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            # In Steam mode, ignore unknown args (could be Steam-passed args)
            if $STEAM_MODE; then
                shift
            else
                echo -e "${RED}Unknown option: $1${NC}"
                echo "Use --help for usage information"
                exit 1
            fi
            ;;
    esac
done

worms_reject_control_chars "$GAME_APP" "GAME_APP"
worms_reject_control_chars "$GAME_EXEC" "GAME_EXEC"

# Validate game exists
if [[ ! -f "$GAME_EXEC" ]]; then
    echo -e "${RED}ERROR: Game executable not found at:${NC}"
    echo "  $GAME_EXEC"
    echo ""
    echo "Set GAME_APP to the correct location:"
    echo "  GAME_APP=\"/path/to/Worms W.M.D.app\" ./launch_worms.sh"
    exit 1
fi

# Setup logging
if [[ "$ENABLE_LOGGING" == true ]]; then
    prepare_logging_paths
    log_message "=== Worms W.M.D Diagnostic Launch ==="
    log_message "Game: $GAME_APP"
    log_message "macOS: $(sw_vers -productVersion 2>/dev/null || echo "unknown")"
    log_message "Architecture: $(uname -m)"
    log_message "Safe Mode: $SAFE_MODE"
    echo -e "${BLUE}Logging to: $LOG_FILE${NC}"
fi

# Build environment
export_vars=()

# Qt debugging
if [[ "$QT_DEBUG" == true ]]; then
    export QT_DEBUG_PLUGINS=1
    export QT_LOGGING_RULES="qt.*=true"
    export_vars+=("QT_DEBUG_PLUGINS=1")
    [[ "$VERBOSE" == true ]] && echo -e "${YELLOW}Qt debugging enabled${NC}"
fi

# OpenGL debugging
if [[ "$OPENGL_DEBUG" == true ]]; then
    export LIBGL_DEBUG=verbose
    export MESA_DEBUG=1
    export_vars+=("LIBGL_DEBUG=verbose")
    [[ "$VERBOSE" == true ]] && echo -e "${YELLOW}OpenGL debugging enabled${NC}"
fi

# Safe mode settings
if [[ "$SAFE_MODE" == true ]]; then
    echo -e "${YELLOW}Launching in SAFE MODE${NC}"
    echo "  - Software rendering hints enabled"
    echo "  - Reduced graphics quality"
    echo ""

    # Qt software rendering fallback hints
    export QT_QUICK_BACKEND=software
    export LIBGL_ALWAYS_SOFTWARE=1
    export_vars+=("QT_QUICK_BACKEND=software" "LIBGL_ALWAYS_SOFTWARE=1")

    [[ "$ENABLE_LOGGING" == true ]] && log_message "Safe mode: software rendering enabled"
fi

# Log environment
if [[ "$ENABLE_LOGGING" == true && ${#export_vars[@]} -gt 0 ]]; then
    log_message "Environment variables:"
    for var in "${export_vars[@]}"; do
        log_message "  $var"
    done
fi

# Check fix status if requested
if [[ "$CHECK_FIX" == true ]]; then
    echo -e "${BLUE}Checking fix status...${NC}"

    if [[ -x "$SCRIPT_DIR/watch_for_updates.sh" ]]; then
        if ! GAME_APP="$GAME_APP" "$SCRIPT_DIR/watch_for_updates.sh" --check >/dev/null 2>&1; then
            echo -e "${YELLOW}Fix needs to be reapplied!${NC}"
            read -p "Reapply now? [Y/n] " -n 1 -r < /dev/tty
            echo ""
            if [[ ! "${REPLY:-}" =~ ^[Nn]$ ]]; then
                cd "$REPO_DIR"
                GAME_APP="$GAME_APP" ./fix_worms_wmd.sh --force
            else
                echo "Launching anyway (may not work correctly)..."
            fi
        else
            echo -e "${GREEN}Fix verified${NC}"
        fi
    fi
fi

# Create crash directory only when it can be used. LOG_DIR is validated in
# logging setup above, and crash reports are only generated in logging mode.
if [[ "$ENABLE_LOGGING" == true && "$CRASH_REPORT" == true ]]; then
    logs_root="$HOME/Library/Logs"
    if ! worms_path_creatable_inside_root "$logs_root" "$CRASH_DIR" \
        || { [[ -e "$CRASH_DIR" ]] && { [[ ! -d "$CRASH_DIR" ]] || [[ -L "$CRASH_DIR" ]]; }; }; then
        echo -e "${RED}Crash directory must be a non-linked directory under $logs_root${NC}" >&2
        exit 1
    fi
    mkdir -p "$CRASH_DIR"
fi

# Generate crash report function
generate_crash_report() {
    local exit_code="$1"
    local crash_time crash_file publish_attempt
    crash_time=$(date '+%Y%m%d-%H%M%S')
    crash_file=$(worms_unique_path "$CRASH_DIR/crash-$crash_time" ".txt")
    CRASH_TEMP_FILE=$(worms_same_directory_temp_file "$crash_file") || {
        echo -e "${RED}Could not create a secure crash-report staging file${NC}" >&2
        return 1
    }

    if ! {
        echo "=== Worms W.M.D Crash Report ==="
        echo "Date: $(date)"
        echo "Exit Code: $exit_code"
        echo ""
        echo "=== System Info ==="
        echo "macOS: $(sw_vers -productVersion 2>/dev/null || echo "unknown")"
        echo "Architecture: $(uname -m)"
        echo ""
        echo "=== Environment ==="
        env | grep -E "^(QT_DEBUG_PLUGINS|QT_LOGGING_RULES|QT_QUICK_BACKEND|LIBGL_DEBUG|LIBGL_ALWAYS_SOFTWARE|MESA_DEBUG|DISPLAY)=" || echo "(none)"
        echo ""
        echo "=== Game Log (last 100 lines) ==="
        if [[ -f "$LOG_FILE" ]]; then
            tail -100 "$LOG_FILE"
        else
            echo "(no log file)"
        fi
        echo ""
        echo "=== Recent System Crash Logs ==="
        while read -r crash; do
            echo "--- $(basename "$crash") ---"
            head -50 "$crash" 2>/dev/null || true
        done < <(find "$HOME/Library/Logs/DiagnosticReports" \
            -name "*Worms*" -mmin -10 2>/dev/null | head -3)
    } > "$CRASH_TEMP_FILE"; then
        echo -e "${RED}Could not write crash report${NC}" >&2
        return 1
    fi
    chmod 600 "$CRASH_TEMP_FILE"
    publish_attempt=0
    while [[ "$publish_attempt" -lt 10 ]]; do
        publish_attempt=$((publish_attempt + 1))
        if mv -n -- "$CRASH_TEMP_FILE" "$crash_file" \
            && [[ ! -e "$CRASH_TEMP_FILE" ]]; then
            CRASH_TEMP_FILE=""
            break
        fi
        crash_file=$(worms_unique_path "$CRASH_DIR/crash-$crash_time" ".txt")
    done
    if [[ -n "$CRASH_TEMP_FILE" ]]; then
        echo -e "${RED}Could not publish a unique crash report${NC}" >&2
        return 1
    fi

    echo -e "${RED}Crash report saved: $crash_file${NC}"

    # Show notification
    osascript -e "display notification \"Crash report saved to logs\" with title \"Worms W.M.D Crashed\"" 2>/dev/null || true
}

# Launch the game
echo -e "${GREEN}Launching Worms W.M.D...${NC}"

if [[ "$ENABLE_LOGGING" == true ]]; then
    log_message "Launching game..."
    log_message "Steam mode: $STEAM_MODE"
    log_message "Crash reporting: $CRASH_REPORT"

    # Run game and capture output
    set +e
    "$GAME_EXEC" 2>&1 | while IFS= read -r line; do
        log_message "[GAME] $line"
        [[ "$VERBOSE" == true ]] && echo "$line"
    done

    exit_code=${PIPESTATUS[0]}
    set -e

    log_message "Game exited with code: $exit_code"

    # Check for crash
    if [[ "$exit_code" -ne 0 ]] && [[ "$CRASH_REPORT" == true ]]; then
        echo -e "${RED}Game crashed with exit code: $exit_code${NC}"
        generate_crash_report "$exit_code"
    fi

    if [[ "$VERBOSE" == true ]] || [[ "$exit_code" -ne 0 ]]; then
        echo ""
        echo -e "${BLUE}Log saved to: $LOG_FILE${NC}"
    fi

    exit "$exit_code"
else
    # Normal launch (no logging, no crash report)
    exec "$GAME_EXEC"
fi
