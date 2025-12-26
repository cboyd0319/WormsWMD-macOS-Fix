#!/bin/bash
#
# logging.sh - shared logging helpers for Worms W.M.D fix scripts
#
# Usage:
#   source "$SCRIPT_DIR/logging.sh"
#   worms_log_init "script_name"
#   worms_debug_init
#

worms_bool_true() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

worms_log_init() {
    local script_name="$1"
    local log_dir
    local timestamp

    log_dir="${LOG_DIR:-$HOME/Library/Logs/WormsWMD-Fix}"
    timestamp="$(date +%Y%m%d-%H%M%S)"

    if [[ -z "${LOG_FILE:-}" ]]; then
        LOG_FILE="$log_dir/${script_name}-${timestamp}.log"
    fi

    mkdir -p "$(dirname "$LOG_FILE")"

    if [[ -z "${WORMSWMD_LOGGING_INITIALIZED:-}" ]]; then
        exec > >(tee -a "$LOG_FILE") 2>&1
        export WORMSWMD_LOGGING_INITIALIZED=1
    fi

    export LOG_FILE
    export LOG_DIR
}

worms_debug_init() {
    if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
        if [[ -z "${TRACE_FILE:-}" ]]; then
            TRACE_FILE="${LOG_FILE}.trace"
        fi

        mkdir -p "$(dirname "$TRACE_FILE")"
        exec 3>>"$TRACE_FILE"
        export BASH_XTRACEFD=3
        export PS4='+(${BASH_SOURCE##*/}:${LINENO}): '
        set -x
        export TRACE_FILE
    fi
}

worms_verbose_enabled() {
    worms_bool_true "${WORMSWMD_VERBOSE:-}"
}
