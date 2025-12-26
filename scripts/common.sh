#!/bin/bash
#
# common.sh - shared helpers for Worms W.M.D fix scripts and tools
#

worms_latest_path_by_mtime() {
    local search_dir="$1"
    local name_glob="$2"
    local type="${3:-d}"
    local result

    result=$(find "$search_dir" -mindepth 1 -maxdepth 1 -type "$type" -name "$name_glob" -print0 2>/dev/null \
        | while IFS= read -r -d '' item; do
            mtime=$(stat -f "%m" "$item" 2>/dev/null || echo 0)
            printf '%s\t%s\n' "$mtime" "$item"
        done \
        | sort -nr \
        | head -1 \
        | cut -f2- || true)

    if [[ -n "$result" ]]; then
        echo "$result"
    fi
}

worms_framework_binary() {
    local fw_dir="$1"
    local fw_name="${2:-}"
    local candidate

    if [[ -z "$fw_name" ]]; then
        fw_name=$(basename "$fw_dir" .framework)
    fi

    for candidate in \
        "$fw_dir/Versions/5/$fw_name" \
        "$fw_dir/Versions/Current/$fw_name" \
        "$fw_dir/Versions/A/$fw_name" \
        "$fw_dir/$fw_name"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}
