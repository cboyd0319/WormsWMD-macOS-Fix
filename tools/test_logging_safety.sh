#!/bin/bash
# Regression checks for debug trace path validation and new-file creation.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
LOGGING_SCRIPT="$ROOT_DIR/scripts/logging.sh"

fail() {
    printf 'logging safety check failed: %s\n' "$*" >&2
    exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-logging-safety.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

run_debug() {
    local home_dir="$1"
    local log_file="$2"
    local trace_file="${3:-}"
    local explicit="${4:-false}"

    HOME="$home_dir" LOG_FILE="$log_file" TRACE_FILE="$trace_file" \
        WORMSWMD_DEBUG=1 \
        bash -c '
            set -euo pipefail
            source "$1"
            worms_log_init trace_test
            worms_debug_init "$2"
            printf "debug body\n"
            bash -c '\''
                set -euo pipefail
                source "$1"
                worms_log_init trace_child
                worms_debug_init
                printf "child debug body\n"
            '\'' _ "$1"
        ' _ "$LOGGING_SCRIPT" "$explicit"
}

env_home="$tmp_dir/env-home"
env_log="$env_home/Library/Logs/WormsWMD-Fix/env.log"
env_trace="$tmp_dir/outside-environment.trace"
mkdir -p "$env_home/Library/Logs"
set +e
env_output=$(run_debug "$env_home" "$env_log" "$env_trace" 2>&1)
env_status=$?
set -e
[[ "$env_status" -ne 0 ]] \
    || fail "environment TRACE_FILE outside ~/Library/Logs was accepted"
[[ ! -e "$env_trace" ]] \
    || fail "rejected environment TRACE_FILE was created"
grep -Fq -- '--trace-file' <<< "$env_output" \
    || fail "environment TRACE_FILE rejection omitted explicit-option guidance"

existing_trace="$env_home/Library/Logs/existing.trace"
printf 'preserved trace\n' > "$existing_trace"
set +e
existing_output=$(run_debug "$env_home" "$env_log" "$existing_trace" 2>&1)
existing_status=$?
set -e
[[ "$existing_status" -ne 0 ]] || fail "existing trace was accepted for append"
grep -Fxq 'preserved trace' "$existing_trace" || fail "existing trace was modified"
grep -Fq 'Choose a new path, for example:' <<< "$existing_output" \
    || fail "existing trace rejection omitted a unique-path suggestion"

victim="$tmp_dir/trace-victim"
linked_trace="$env_home/Library/Logs/linked.trace"
printf 'victim\n' > "$victim"
ln -s "$victim" "$linked_trace"
if run_debug "$env_home" "$env_log" "$linked_trace" >/dev/null 2>&1; then
    fail "symlink trace was accepted"
fi
grep -Fxq victim "$victim" || fail "symlink trace modified its victim"

hardlink_trace="$env_home/Library/Logs/hardlinked.trace"
ln "$victim" "$hardlink_trace"
if run_debug "$env_home" "$env_log" "$hardlink_trace" >/dev/null 2>&1; then
    fail "hardlinked trace was accepted"
fi
grep -Fxq victim "$victim" || fail "hardlinked trace modified its peer"

explicit_home="$tmp_dir/explicit-home"
explicit_log="$explicit_home/Library/Logs/WormsWMD-Fix/explicit.log"
explicit_trace="$tmp_dir/custom/debug.trace"
mkdir -p "$explicit_home/Library/Logs" "$(dirname "$explicit_trace")"
run_debug "$explicit_home" "$explicit_log" "$explicit_trace" true \
    > "$tmp_dir/explicit.out" 2>&1 \
    || fail "explicit safe custom trace was rejected"
[[ -f "$explicit_trace" ]] || fail "explicit custom trace was not created"
[[ "$(stat -f '%Lp' "$explicit_trace")" == "600" ]] \
    || fail "explicit custom trace mode is not 0600"
grep -Fq "Debug trace: $explicit_trace" "$tmp_dir/explicit.out" \
    || fail "explicit custom trace was not previewed"

default_home="$tmp_dir/default-home"
default_log="$default_home/Library/Logs/WormsWMD-Fix/default.log"
mkdir -p "$default_home/Library/Logs"
run_debug "$default_home" "$default_log" "" > "$tmp_dir/default.out" 2>&1 \
    || fail "default trace creation failed"
default_trace="${default_log}.trace"
[[ -f "$default_trace" ]] || fail "default trace was not created beside the log"
[[ "$(stat -f '%Lp' "$default_trace")" == "600" ]] \
    || fail "default trace mode is not 0600"

linked_parent_home="$tmp_dir/linked-parent-home"
linked_parent_real="$tmp_dir/linked-parent-real"
mkdir -p "$linked_parent_home/Library/Logs" "$linked_parent_real"
ln -s "$linked_parent_real" "$linked_parent_home/custom"
if run_debug \
    "$linked_parent_home" \
    "$linked_parent_home/Library/Logs/linked-parent.log" \
    "$linked_parent_home/custom/unsafe.trace" true >/dev/null 2>&1; then
    fail "explicit trace accepted a linked parent"
fi
[[ ! -e "$linked_parent_real/unsafe.trace" ]] \
    || fail "linked trace parent received output"

grep -Fq -- '--trace-file PATH' "$ROOT_DIR/fix_worms_wmd.sh" \
    || fail "installer help does not document --trace-file"

printf 'Logging safety check passed.\n'
