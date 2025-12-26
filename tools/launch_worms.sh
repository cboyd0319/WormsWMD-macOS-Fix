#!/bin/bash
#
# launch_worms.sh - Diagnostic Game Launcher for Worms W.M.D
#
# This launcher provides:
# - Diagnostic logging for troubleshooting
# - Safe mode for graphics issues
# - Environment variable overrides for debugging
#
# Usage:
#   ./launch_worms.sh [OPTIONS]
#
# Options:
#   --safe-mode     Launch with reduced graphics settings
#   --log           Enable diagnostic logging
#   --log-file PATH Write logs to specific file
#   --verbose       Extra verbose output
#   --qt-debug      Enable Qt debugging output
#   --opengl-debug  Enable OpenGL debugging
#   --help          Show this help
#

set -e

# Configuration
GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
GAME_EXEC="$GAME_APP/Contents/MacOS/Worms W.M.D"
LOG_DIR="${LOG_DIR:-$HOME/Library/Logs/WormsWMD}"
LOG_FILE=""
SAFE_MODE=false
VERBOSE=false
QT_DEBUG=false
OPENGL_DEBUG=false
ENABLE_LOGGING=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    cat << 'EOF'
Worms W.M.D - Diagnostic Launcher

USAGE:
    ./launch_worms.sh [OPTIONS]

OPTIONS:
    --safe-mode         Launch with reduced graphics (software rendering hints)
    --log               Enable diagnostic logging to ~/Library/Logs/WormsWMD/
    --log-file PATH     Write logs to a specific file
    --verbose           Extra verbose output
    --qt-debug          Enable Qt plugin and platform debugging
    --opengl-debug      Enable OpenGL debugging output
    --help, -h          Show this help message

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
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
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

# Launch the game
echo -e "${GREEN}Launching Worms W.M.D...${NC}"

if [[ "$ENABLE_LOGGING" == true ]]; then
    log_message "Launching game..."

    # Run game and capture output
    "$GAME_EXEC" 2>&1 | while IFS= read -r line; do
        log_message "[GAME] $line"
        [[ "$VERBOSE" == true ]] && echo "$line"
    done

    exit_code=${PIPESTATUS[0]}
    log_message "Game exited with code: $exit_code"

    echo ""
    echo -e "${BLUE}Log saved to: $LOG_FILE${NC}"
else
    # Normal launch
    exec "$GAME_EXEC"
fi
