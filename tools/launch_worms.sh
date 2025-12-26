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
#   --log-file PATH Write logs to specific file
#   --verbose       Extra verbose output
#   --qt-debug      Enable Qt debugging output
#   --opengl-debug  Enable OpenGL debugging
#   --check-fix     Verify fix before launching
#   --crash-report  Generate crash report if game crashes
#   --help          Show this help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    cat << 'EOF'
Worms W.M.D - Enhanced Launcher

USAGE:
    ./launch_worms.sh [OPTIONS]

OPTIONS:
    --steam             Steam launch mode (use with %command%)
    --safe-mode         Launch with reduced graphics (software rendering hints)
    --log               Enable diagnostic logging to ~/Library/Logs/WormsWMD/
    --log-file PATH     Write logs to a specific file
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
    LOG_DIR             Override log directory
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
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1"
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] $1" >> "$LOG_FILE"
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
            LOG_FILE="$2"
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
    mkdir -p "$LOG_DIR"
    if [[ -z "$LOG_FILE" ]]; then
        LOG_FILE="$LOG_DIR/worms-$(date '+%Y%m%d-%H%M%S').log"
    fi
    log_message "=== Worms W.M.D Diagnostic Launch ==="
    log_message "Game: $GAME_APP"
    log_message "macOS: $(sw_vers -productVersion)"
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
        if ! "$SCRIPT_DIR/watch_for_updates.sh" --check >/dev/null 2>&1; then
            echo -e "${YELLOW}Fix needs to be reapplied!${NC}"
            read -p "Reapply now? [Y/n] " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                cd "$REPO_DIR"
                ./fix_worms_wmd.sh --force
            else
                echo "Launching anyway (may not work correctly)..."
            fi
        else
            echo -e "${GREEN}Fix verified${NC}"
        fi
    fi
fi

# Create crash directory
mkdir -p "$CRASH_DIR"

# Generate crash report function
generate_crash_report() {
    local exit_code="$1"
    local crash_time
    crash_time=$(date '+%Y%m%d-%H%M%S')
    local crash_file="$CRASH_DIR/crash-$crash_time.txt"

    {
        echo "=== Worms W.M.D Crash Report ==="
        echo "Date: $(date)"
        echo "Exit Code: $exit_code"
        echo ""
        echo "=== System Info ==="
        echo "macOS: $(sw_vers -productVersion)"
        echo "Architecture: $(uname -m)"
        echo ""
        echo "=== Environment ==="
        env | grep -E "^(QT_|LIBGL_|MESA_|DISPLAY)" || echo "(none)"
        echo ""
        echo "=== Game Log (last 100 lines) ==="
        if [[ -f "$LOG_FILE" ]]; then
            tail -100 "$LOG_FILE"
        else
            echo "(no log file)"
        fi
        echo ""
        echo "=== Recent System Crash Logs ==="
        find "$HOME/Library/Logs/DiagnosticReports" -name "*Worms*" -mmin -10 2>/dev/null | head -3 | while read -r crash; do
            echo "--- $(basename "$crash") ---"
            head -50 "$crash" 2>/dev/null || true
        done
    } > "$crash_file"

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
