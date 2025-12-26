#!/bin/bash
#
# ui.sh - shared UI helpers (colors + output) for Worms W.M.D tools
#

worms_color_init() {
    local mode="${1:-auto}"
    local enable=false

    case "$mode" in
        always)
            enable=true
            ;;
        never)
            enable=false
            ;;
        auto|*)
            if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
                enable=true
            fi
            ;;
    esac

    if $enable; then
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
}

worms_print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

worms_print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

worms_print_success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}

worms_print_info() {
    echo -e "${BLUE}INFO:${NC} $1"
}

worms_print_step() {
    echo -e "${GREEN}==>${NC} $1"
}
