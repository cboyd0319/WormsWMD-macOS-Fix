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

worms_log_has_control_chars() {
    case "${1:-}" in
        *$'\n'*|*$'\r'*)
            return 0
            ;;
    esac

    return 1
}

worms_log_real_dir() {
    local path="$1"

    (cd "$path" 2>/dev/null && pwd -P)
}

worms_log_file_link_count() {
    local path="$1"

    stat -f "%l" "$path" 2>/dev/null || stat -c "%h" "$path" 2>/dev/null || echo 1
}

worms_log_path_inside_root() {
    local root="$1"
    local path="$2"
    local root_real path_real

    root_real=$(worms_log_real_dir "$root") || return 1
    if [[ -d "$path" ]]; then
        path_real=$(worms_log_real_dir "$path") || return 1
    else
        path_real=$(worms_log_real_dir "$(dirname "$path")") || return 1
        path_real="$path_real/$(basename "$path")"
    fi

    case "$path_real" in
        "$root_real"|"$root_real"/*)
            return 0
            ;;
    esac

    return 1
}

worms_log_path_creatable_inside_root() {
    local root="$1"
    local path="$2"
    local root_real probe component probe_real

    case "$path" in
        /*)
            ;;
        *)
            return 1
            ;;
    esac
    case "$path" in
        ..|../*|*/..|*/../*)
            return 1
            ;;
    esac

    root_real=$(worms_log_real_dir "$root") || return 1
    if [[ -e "$path" ]] && [[ ! -d "$path" ]]; then
        probe=$(dirname "$path")
    else
        probe="$path"
    fi

    while [[ ! -e "$probe" ]]; do
        component=$(basename "$probe")
        case "$component" in
            ""|"."|"..")
                return 1
                ;;
        esac
        probe=$(dirname "$probe")
    done

    [[ -d "$probe" ]] || return 1
    probe_real=$(worms_log_real_dir "$probe") || return 1
    case "$probe_real" in
        "$root_real"|"$root_real"/*)
            return 0
            ;;
    esac

    return 1
}

worms_log_unique_path() {
    local base="$1"
    local suffix="$2"
    local candidate="${base}${suffix}"
    local counter=1

    while [[ -e "$candidate" ]]; do
        candidate="${base}-${counter}${suffix}"
        counter=$((counter + 1))
    done

    printf '%s\n' "$candidate"
}

worms_prepare_log_file() {
    local script_name="$1"
    local default_root="$HOME/Library/Logs"
    local default_log_dir="$default_root/WormsWMD-Fix"
    local timestamp

    timestamp="$(date +%Y%m%d-%H%M%S)"
    LOG_DIR="${LOG_DIR:-$default_log_dir}"

    if worms_log_has_control_chars "$LOG_DIR" || worms_log_has_control_chars "${LOG_FILE:-}"; then
        echo "Unsafe control character in log path" >&2
        return 1
    fi

    mkdir -p "$default_root"
    if ! worms_log_path_creatable_inside_root "$default_root" "$LOG_DIR" \
        || { [[ -e "$LOG_DIR" ]] && [[ ! -d "$LOG_DIR" ]]; }; then
        echo "LOG_DIR must be inside $default_root: $LOG_DIR" >&2
        return 1
    fi
    mkdir -p "$LOG_DIR"

    if [[ -z "${LOG_FILE:-}" ]]; then
        LOG_FILE=$(worms_log_unique_path "$LOG_DIR/${script_name}-${timestamp}-$$" ".log")
    fi

    case "$LOG_FILE" in
        *.log)
            ;;
        *)
            echo "LOG_FILE must end with .log: $LOG_FILE" >&2
            return 1
            ;;
    esac

    if ! worms_log_path_creatable_inside_root "$default_root" "$LOG_FILE"; then
        echo "LOG_FILE must be inside $default_root: $LOG_FILE" >&2
        return 1
    fi
    if [[ -L "$LOG_FILE" ]] || [[ -d "$LOG_FILE" ]] || { [[ -e "$LOG_FILE" ]] && [[ ! -f "$LOG_FILE" ]]; }; then
        echo "LOG_FILE must be a regular non-linked log file path: $LOG_FILE" >&2
        return 1
    fi
    if [[ -e "$LOG_FILE" ]]; then
        local link_count
        link_count=$(worms_log_file_link_count "$LOG_FILE")
        if [[ "$link_count" =~ ^[0-9]+$ ]] && [[ "$link_count" -gt 1 ]]; then
            echo "LOG_FILE must be a regular non-linked log file path: $LOG_FILE" >&2
            return 1
        fi
    fi
    mkdir -p "$(dirname "$LOG_FILE")"
}

worms_log_init() {
    local script_name="$1"

    worms_prepare_log_file "$script_name"

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
