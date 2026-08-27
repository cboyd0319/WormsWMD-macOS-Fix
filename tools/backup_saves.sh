#!/bin/bash
#
# backup_saves.sh - Backup and restore Worms W.M.D save games
#
# Backs up save games, settings, and replays to a safe location.
# Can also restore from backups.
#
# Usage:
#   ./backup_saves.sh                   # Create backup
#   ./backup_saves.sh --restore         # Restore latest backup
#   ./backup_saves.sh --restore FILE    # Restore specific backup
#   ./backup_saves.sh --list            # List available backups
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

# Cleanup temp files on exit
TEMP_DIR=""
RESTORE_WORK_DIR=""
RESTORE_TRANSACTION_ACTIVE=false
RESTORE_TRANSACTION_COUNT=0
RESTORE_SOURCE_DIRS=()
RESTORE_TARGET_DIRS=()
RESTORE_ALLOWED_ROOTS=()
RESTORE_STAGE_DIRS=()
RESTORE_RETAINED_DIRS=()
RESTORE_HAD_OLD=()
RESTORE_APPLIED=()
cleanup() {
    if $RESTORE_TRANSACTION_ACTIVE \
        && declare -F rollback_save_transactions >/dev/null; then
        rollback_save_transactions "interrupted restore" || true
    fi
    if declare -F cleanup_save_transaction_stages >/dev/null; then
        cleanup_save_transaction_stages
    fi
    if [[ -n "$RESTORE_WORK_DIR" ]] && [[ -d "$RESTORE_WORK_DIR" ]]; then
        rm -rf "$RESTORE_WORK_DIR"
        return
    fi
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Save locations
STEAM_SAVES="$HOME/Library/Application Support/Steam/userdata"
TEAM17_SAVES="$HOME/Library/Application Support/Team17"
BACKUP_DIR="${BACKUP_DIR:-$HOME/Documents/WormsWMD-SaveBackups}"
SAVE_MANIFEST_NAME="MANIFEST.tsv"
RESTORE_ASSUME_YES=false
RESTORE_MAX_EXPANDED_SIZE=""
RESTORE_MAX_EXPANDED_BYTES=""
RESTORE_EXTERNAL_STEAM_ROOT=""
RESTORE_EXTERNAL_STEAM_ROOT_REAL=""
RESTORE_EXTERNAL_STEAM_ROOT_USED=false
RESTORE_STEAM_USER_IDS=()
RESTORE_STEAM_TARGETS=()
RESTORE_RESERVE_BYTES=$((512 * 1024 * 1024))
RESTORE_ABSOLUTE_MAX_BYTES=$((8 * 1024 * 1024 * 1024))
worms_reject_control_chars "$BACKUP_DIR" "BACKUP_DIR"
worms_reject_control_chars "$HOME" "HOME"

macos_product_version() {
    sw_vers -productVersion 2>/dev/null || echo "unknown"
}

restore_assume_yes() {
    if $RESTORE_ASSUME_YES; then
        return 0
    fi

    case "${WORMSWMD_RESTORE_ASSUME_YES:-}" in
        1|true|TRUE|yes|YES|y|Y)
            return 0
            ;;
    esac

    return 1
}

print_help() {
    cat << 'EOF'
Worms W.M.D - Save Game Backup Tool

USAGE:
    ./backup_saves.sh [OPTIONS]

OPTIONS:
    --backup, -b        Create a new backup (default)
    --restore, -r       Restore from latest backup
    --restore FILE      Restore from specific backup file
    --yes               Confirm a restore non-interactively
    --max-expanded-size SIZE
                        Bound restore expansion with a K, M, or G suffix
    --allow-external-steam-root PATH
                        Trust one exact canonical external 327030 destination
    --list, -l          List available backups
    --location          Show save game locations
    --help, -h          Show this help

EXAMPLES:
    # Create backup
    ./backup_saves.sh

    # List backups
    ./backup_saves.sh --list

    # Restore latest
    ./backup_saves.sh --restore

    # Restore specific backup
    ./backup_saves.sh --restore ~/Documents/WormsWMD-SaveBackups/saves-20251225-120000.tar.gz

    # Explicitly allow up to 2 GiB after safety and free-space checks
    ./backup_saves.sh --restore --yes --max-expanded-size 2G

    # Restore one deliberately relocated Steam save root
    ./backup_saves.sh --restore --yes \
        --allow-external-steam-root "$EXACT_EXTERNAL_327030_PATH"

SAVE LOCATIONS:
    Steam Cloud saves: ~/Library/Application Support/Steam/userdata/*/327030/
    Local saves:       ~/Library/Application Support/Team17/

EOF
}

parse_bounded_restore_size() {
    local value="$1"
    local number suffix multiplier bytes

    if [[ ! "$value" =~ ^([1-9][0-9]*)([KkMmGg])$ ]]; then
        printf 'ERROR: --max-expanded-size requires a positive K, M, or G value.\n' >&2
        return 1
    fi
    number="${BASH_REMATCH[1]}"
    suffix="${BASH_REMATCH[2]}"
    case "$suffix" in
        K|k) multiplier=1024 ;;
        M|m) multiplier=$((1024 * 1024)) ;;
        G|g) multiplier=$((1024 * 1024 * 1024)) ;;
    esac

    if (( number > RESTORE_ABSOLUTE_MAX_BYTES / multiplier )); then
        printf 'ERROR: --max-expanded-size exceeds the 8 GiB safety limit.\n' >&2
        return 1
    fi
    bytes=$((number * multiplier))
    printf '%s\n' "$bytes"
}

filesystem_available_bytes() {
    local path="$1"
    local available_kib

    available_kib=$(df -Pk "$path" 2>/dev/null | awk 'NR == 2 {print $4; exit}')
    if [[ ! "$available_kib" =~ ^[0-9]+$ ]]; then
        printf 'ERROR: Unable to determine free space for %s.\n' "$path" >&2
        return 1
    fi
    printf '%s\n' "$((available_kib * 1024))"
}

steam_process_state_with() {
    local pgrep_bin="$1"
    local status=0

    [[ -x "$pgrep_bin" ]] || { printf '%s\n' unknown; return 0; }
    "$pgrep_bin" -x steam_osx >/dev/null 2>&1 || status=$?
    if [[ "$status" -eq 0 ]]; then
        printf '%s\n' running
        return 0
    fi
    [[ "$status" -eq 1 ]] || { printf '%s\n' unknown; return 0; }

    status=0
    "$pgrep_bin" -x Steam >/dev/null 2>&1 || status=$?
    case "$status" in
        0) printf '%s\n' running ;;
        1) printf '%s\n' stopped ;;
        *)
        printf '%s\n' unknown
            ;;
    esac
}

steam_process_state() {
    steam_process_state_with /usr/bin/pgrep
}

wait_for_steam_close() {
    read -r -p "Press Return after Steam is closed, or Ctrl-C to cancel: " \
        < /dev/tty
}

ensure_steam_stopped() {
    local state

    state=$(steam_process_state)
    case "$state" in
        stopped)
            return 0
            ;;
        unknown)
            echo -e "${YELLOW}WARNING:${NC} Unable to determine whether Steam is running."
            return 0
            ;;
        running)
            if restore_assume_yes; then
                echo -e "${RED}ERROR:${NC} Steam is running; unattended restore is refused."
                return 1
            fi
            echo -e "${YELLOW}Steam is running. Close Steam before restoring saves.${NC}"
            wait_for_steam_close || return 1
            state=$(steam_process_state)
            case "$state" in
                stopped)
                    return 0
                    ;;
                unknown)
                    echo -e "${YELLOW}WARNING:${NC} Unable to recheck Steam; continuing interactively."
                    return 0
                    ;;
                *)
                    echo -e "${RED}ERROR:${NC} Steam is still running; restore cancelled."
                    return 1
                    ;;
            esac
            ;;
        *)
            echo -e "${YELLOW}WARNING:${NC} Unexpected Steam process state; continuing cautiously."
            return 0
            ;;
    esac
}

canonical_external_steam_root() {
    local input="$RESTORE_EXTERNAL_STEAM_ROOT"
    local input_trimmed real

    [[ -n "$input" ]] || return 1
    input_trimmed="${input%/}"
    [[ -n "$input_trimmed" ]] || input_trimmed="/"
    if [[ -L "$input_trimmed" ]] || [[ ! -d "$input_trimmed" ]]; then
        echo -e "${RED}ERROR:${NC} External Steam root must be an existing non-symlink directory: $input" >&2
        return 1
    fi
    real=$(worms_real_dir "$input_trimmed") || return 1
    if [[ "$input_trimmed" != "$real" ]]; then
        echo -e "${RED}ERROR:${NC} External Steam root must be its exact canonical path: $real" >&2
        return 1
    fi
    printf '%s\n' "$real"
}

queue_save_transaction() {
    local source_dir="$1"
    local target_dir="$2"
    local allowed_root="$3"
    local index

    worms_reject_control_chars "$source_dir" "save restore source" || return 1
    worms_reject_control_chars "$target_dir" "save restore target" || return 1
    worms_reject_control_chars "$allowed_root" "save restore allowed root" || return 1
    for ((index = 0; index < RESTORE_TRANSACTION_COUNT; index++)); do
        if [[ "${RESTORE_TARGET_DIRS[$index]}" == "$target_dir" ]]; then
            echo -e "${RED}ERROR:${NC} Multiple save roots resolve to the same target: $target_dir"
            return 1
        fi
    done

    index=$RESTORE_TRANSACTION_COUNT
    RESTORE_SOURCE_DIRS[index]="$source_dir"
    RESTORE_TARGET_DIRS[index]="$target_dir"
    RESTORE_ALLOWED_ROOTS[index]="$allowed_root"
    RESTORE_STAGE_DIRS[index]=""
    RESTORE_RETAINED_DIRS[index]=""
    RESTORE_HAD_OLD[index]=0
    RESTORE_APPLIED[index]=0
    RESTORE_TRANSACTION_COUNT=$((RESTORE_TRANSACTION_COUNT + 1))
}

remember_steam_target() {
    local user_id="$1"
    local target_dir="$2"
    local index=${#RESTORE_STEAM_USER_IDS[@]}

    RESTORE_STEAM_USER_IDS[index]="$user_id"
    RESTORE_STEAM_TARGETS[index]="$target_dir"
}

restore_steam_target_for_user() {
    local user_id="$1"
    local index

    for ((index = 0; index < ${#RESTORE_STEAM_USER_IDS[@]}; index++)); do
        if [[ "${RESTORE_STEAM_USER_IDS[$index]}" == "$user_id" ]]; then
            printf '%s\n' "${RESTORE_STEAM_TARGETS[$index]}"
            return 0
        fi
    done
    return 1
}

resolve_steam_restore_target() {
    local user_id="$1"
    local steam_root_real="$2"
    local user_path="$STEAM_SAVES/$user_id"
    local user_real target_path target_real allowed_root

    if [[ ! "$user_id" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}ERROR:${NC} Steam save user ID must be numeric: $user_id"
        return 1
    fi
    if [[ -L "$user_path" ]]; then
        echo -e "${RED}ERROR:${NC} Refusing intermediate Steam-user symlink: $user_path"
        return 1
    fi
    if [[ -e "$user_path" ]]; then
        [[ -d "$user_path" ]] || {
            echo -e "${RED}ERROR:${NC} Steam user path is not a directory: $user_path"
            return 1
        }
        user_real=$(worms_real_dir "$user_path") || return 1
        worms_path_inside_root "$steam_root_real" "$user_real" || {
            echo -e "${RED}ERROR:${NC} Steam user path escapes userdata: $user_path"
            return 1
        }
    else
        user_real="$steam_root_real/$user_id"
        worms_path_creatable_inside_root "$steam_root_real" "$user_real" || return 1
    fi

    target_path="$user_path/327030"
    if [[ -L "$target_path" ]]; then
        target_real=$(realpath "$target_path" 2>/dev/null || true)
        if [[ -z "$target_real" ]] || [[ ! -d "$target_real" ]] || [[ -L "$target_real" ]]; then
            echo -e "${RED}ERROR:${NC} Steam 327030 link target is unavailable: $target_path"
            return 1
        fi
    elif [[ -e "$target_path" ]]; then
        [[ -d "$target_path" ]] || {
            echo -e "${RED}ERROR:${NC} Steam 327030 target is not a directory: $target_path"
            return 1
        }
        target_real=$(worms_real_dir "$target_path") || return 1
    else
        target_real="$user_real/327030"
    fi

    if worms_path_inside_root "$steam_root_real" "$target_real" \
        || worms_path_creatable_inside_root "$steam_root_real" "$target_real"; then
        allowed_root="$steam_root_real"
    else
        [[ -n "$RESTORE_EXTERNAL_STEAM_ROOT_REAL" ]] || {
            echo -e "${RED}ERROR:${NC} Steam 327030 target escapes userdata: $target_real"
            return 1
        }
        if [[ "$target_real" != "$RESTORE_EXTERNAL_STEAM_ROOT_REAL" ]]; then
            echo -e "${RED}ERROR:${NC} External Steam root does not match this exact 327030 destination: $target_real"
            return 1
        fi
        allowed_root=$(dirname "$target_real")
        RESTORE_EXTERNAL_STEAM_ROOT_USED=true
        echo "External Steam restore target: $target_real"
    fi

    remember_steam_target "$user_id" "$target_real"
    queue_save_transaction "$TEMP_DIR/Steam/$user_id" "$target_real" "$allowed_root"
}

prepare_restore_targets() {
    local home_real steam_root_real entry user_id team17_real

    home_real=$(worms_real_dir "$HOME") || return 1
    if [[ -n "$RESTORE_EXTERNAL_STEAM_ROOT" ]]; then
        RESTORE_EXTERNAL_STEAM_ROOT_REAL=$(canonical_external_steam_root) || return 1
    fi

    if [[ -e "$TEMP_DIR/Team17" ]]; then
        [[ -d "$TEMP_DIR/Team17" ]] && [[ ! -L "$TEMP_DIR/Team17" ]] || return 1
        if [[ -L "$TEAM17_SAVES" ]]; then
            echo -e "${RED}ERROR:${NC} Refusing linked Team17 save destination: $TEAM17_SAVES"
            return 1
        elif [[ -e "$TEAM17_SAVES" ]]; then
            [[ -d "$TEAM17_SAVES" ]] || return 1
            team17_real=$(worms_real_dir "$TEAM17_SAVES") || return 1
            worms_path_inside_root "$home_real" "$team17_real" || return 1
        else
            team17_real="$TEAM17_SAVES"
            worms_path_creatable_inside_root "$home_real" "$team17_real" || return 1
        fi
        queue_save_transaction "$TEMP_DIR/Team17" "$team17_real" "$home_real"
    fi

    if [[ -e "$TEMP_DIR/Steam" ]]; then
        [[ -d "$TEMP_DIR/Steam" ]] && [[ ! -L "$TEMP_DIR/Steam" ]] || return 1
        if [[ -L "$STEAM_SAVES" ]]; then
            steam_root_real=$(worms_real_dir "$STEAM_SAVES") || return 1
        elif [[ -e "$STEAM_SAVES" ]]; then
            [[ -d "$STEAM_SAVES" ]] || return 1
            steam_root_real=$(worms_real_dir "$STEAM_SAVES") || return 1
        else
            echo -e "${RED}ERROR:${NC} Steam userdata is missing; launch Steam once before restoring Steam saves."
            return 1
        fi

        while IFS= read -r -d '' entry; do
            [[ -d "$entry" ]] && [[ ! -L "$entry" ]] || {
                echo -e "${RED}ERROR:${NC} Invalid Steam user entry in backup: $(basename "$entry")"
                return 1
            }
            user_id=$(basename "$entry")
            resolve_steam_restore_target "$user_id" "$steam_root_real" || return 1
        done < <(find "$TEMP_DIR/Steam" -mindepth 1 -maxdepth 1 -print0)
    fi

    if [[ -n "$RESTORE_EXTERNAL_STEAM_ROOT" ]] && ! $RESTORE_EXTERNAL_STEAM_ROOT_USED; then
        echo -e "${RED}ERROR:${NC} External Steam root was not required by this backup."
        return 1
    fi
    (( RESTORE_TRANSACTION_COUNT > 0 )) || {
        echo -e "${RED}ERROR:${NC} Backup contains no restorable save roots."
        return 1
    }
}

# Find Worms W.M.D Steam user data directories
find_steam_saves() {
    local found=()

    for user_dir in "$STEAM_SAVES"/*/327030; do
        if [[ -d "$user_dir" ]]; then
            found+=("$user_dir")
        fi
    done

    if (( ${#found[@]} > 0 )); then
        printf '%s\n' "${found[@]}"
    fi
}

validate_backup_archive_layout() {
    local archive="$1"
    local raw_entry entry

    if ! tar -tzf "$archive" 2>/dev/null | while IFS= read -r raw_entry; do
        [[ -n "$raw_entry" ]] || continue
        entry="${raw_entry#./}"
        while [[ "$entry" == */ ]]; do
            entry="${entry%/}"
        done
        [[ -n "$entry" ]] || continue

        if worms_path_has_parent_escape "$entry"; then
            echo -e "${RED}ERROR:${NC} Unsafe path in backup archive: $entry"
            exit 1
        fi

        case "$entry" in
            Team17|Team17/*|Steam|Steam/*|BACKUP_INFO.txt|"$SAVE_MANIFEST_NAME")
                ;;
            *)
                echo -e "${RED}ERROR:${NC} Unexpected entry in backup archive: $entry"
                exit 1
                ;;
        esac
    done; then
        echo -e "${RED}ERROR:${NC} Backup archive layout validation failed."
        return 1
    fi
}

restore_target_for_manifest_path() {
    local rel_path="$1"
    local steam_rel user_id save_rel steam_target

    case "$rel_path" in
        Team17/*)
            echo "$TEAM17_SAVES/${rel_path#Team17/}"
            ;;
        Steam/*/*)
            steam_rel="${rel_path#Steam/}"
            user_id="${steam_rel%%/*}"
            save_rel="${steam_rel#*/}"
            [[ -n "$user_id" ]] && [[ -n "$save_rel" ]] || return 1
            steam_target=$(restore_steam_target_for_user "$user_id") || return 1
            echo "$steam_target/$save_rel"
            ;;
        BACKUP_INFO.txt|"$SAVE_MANIFEST_NAME")
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

verify_restored_saves() {
    local manifest="$TEMP_DIR/$SAVE_MANIFEST_NAME"
    local expected_hash expected_size rel_path target actual_hash actual_size status=0
    local expected_rel_file actual_rel_file extra_rel user_dir user_id target_dir

    [[ -f "$manifest" ]] || return 0

    expected_rel_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-save-expected.XXXXXX")
    actual_rel_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-save-actual.XXXXXX")

    while IFS=$'\t' read -r expected_hash expected_size rel_path extra; do
        [[ -n "${expected_hash:-}" ]] || continue
        [[ "$expected_hash" == \#* ]] && continue
        [[ -z "${extra:-}" ]] || { status=1; continue; }

        target=$(restore_target_for_manifest_path "$rel_path" || true)
        [[ -n "$target" ]] || continue

        if [[ ! -f "$target" ]]; then
            echo -e "${YELLOW}WARNING:${NC} Restored file missing: $rel_path"
            status=1
            continue
        fi

        actual_hash=$(worms_file_sha256 "$target")
        actual_size=$(worms_file_size "$target")
        if [[ "$actual_hash" != "$expected_hash" ]] || [[ "$actual_size" != "$expected_size" ]]; then
            echo -e "${YELLOW}WARNING:${NC} Restored file does not match backup manifest: $rel_path"
            status=1
        fi
        printf '%s\n' "$rel_path" >> "$expected_rel_file"
    done < "$manifest"

    if [[ -d "$TEMP_DIR/Team17" ]] && [[ -d "$TEAM17_SAVES" ]]; then
        (
            cd "$TEAM17_SAVES" || exit 1
            find . -type f -print 2>/dev/null | sed 's#^\./#Team17/#'
        ) >> "$actual_rel_file"
    fi

    if [[ -d "$TEMP_DIR/Steam" ]]; then
        for user_dir in "$TEMP_DIR/Steam"/*; do
            [[ -d "$user_dir" ]] || continue
            user_id=$(basename "$user_dir")
            target_dir=$(restore_steam_target_for_user "$user_id" || true)
            [[ -n "$target_dir" ]] || { status=1; continue; }
            [[ -d "$target_dir" ]] || continue
            (
                cd "$target_dir" || exit 1
                find . -type f -print 2>/dev/null | sed "s#^\./#Steam/$user_id/#"
            ) >> "$actual_rel_file"
        done
    fi

    LC_ALL=C sort -u "$expected_rel_file" -o "$expected_rel_file"
    LC_ALL=C sort -u "$actual_rel_file" -o "$actual_rel_file"
    extra_rel=$(comm -13 "$expected_rel_file" "$actual_rel_file" | head -1 || true)
    if [[ -n "$extra_rel" ]]; then
        echo -e "${YELLOW}WARNING:${NC} Restore left an unexpected file: $extra_rel"
        status=1
    fi

    rm -f "$expected_rel_file" "$actual_rel_file"

    return "$status"
}

verify_save_tree_copy() {
    local source_dir="$1"
    local target_dir="$2"
    local manifest child status=0
    local inputs=()

    manifest=$(mktemp "${TMPDIR:-/tmp}/wormswmd-save-tree-manifest.XXXXXX")
    while IFS= read -r -d '' child; do
        inputs+=("$(basename "$child")")
    done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -print0)

    worms_write_manifest "$source_dir" "$manifest" "${inputs[@]}" \
        && worms_verify_manifest "$target_dir" "$manifest" \
        || status=1
    rm -f "$manifest"
    return "$status"
}

cleanup_save_transaction_stages() {
    local index stage

    for ((index = 0; index < RESTORE_TRANSACTION_COUNT; index++)); do
        stage="${RESTORE_STAGE_DIRS[$index]:-}"
        if [[ -n "$stage" ]] && [[ -d "$stage" ]] && [[ ! -L "$stage" ]]; then
            rm -rf "$stage"
            RESTORE_STAGE_DIRS[index]=""
        fi
    done
}

ensure_save_target_parent() {
    local target_dir="$1"
    local allowed_root="$2"
    local target_parent

    target_parent=$(dirname "$target_dir")
    if [[ -L "$target_parent" ]]; then
        echo -e "${RED}ERROR:${NC} Save target parent may not be a symlink: $target_parent"
        return 1
    fi
    if [[ ! -e "$target_parent" ]]; then
        worms_path_creatable_inside_root "$allowed_root" "$target_parent" || {
            echo -e "${RED}ERROR:${NC} Save target parent escapes its allowed root: $target_parent"
            return 1
        }
        mkdir -p "$target_parent"
        chmod 0700 "$target_parent"
    fi
    [[ -d "$target_parent" ]] && [[ ! -L "$target_parent" ]] || return 1
    worms_path_inside_root "$allowed_root" "$target_parent" || {
        echo -e "${RED}ERROR:${NC} Save target parent resolves outside its allowed root: $target_parent"
        return 1
    }
}

prepare_save_tree_stage() {
    local index="$1"
    local source_dir="${RESTORE_SOURCE_DIRS[$index]}"
    local target_dir="${RESTORE_TARGET_DIRS[$index]}"
    local allowed_root="${RESTORE_ALLOWED_ROOTS[$index]}"
    local target_parent target_base stage

    ensure_save_target_parent "$target_dir" "$allowed_root" || return 1
    if [[ -L "$target_dir" ]] || { [[ -e "$target_dir" ]] && [[ ! -d "$target_dir" ]]; }; then
        echo -e "${RED}ERROR:${NC} Save restore target is not a real directory: $target_dir"
        return 1
    fi

    target_parent=$(dirname "$target_dir")
    target_base=$(basename "$target_dir")
    stage=$(mktemp -d "$target_parent/.${target_base}.restore-stage.XXXXXX")
    chmod 0700 "$stage"
    RESTORE_STAGE_DIRS[index]="$stage"
    if ! cp -R "$source_dir/." "$stage/"; then
        echo -e "${RED}ERROR:${NC} Unable to stage save restore for: $target_dir"
        return 1
    fi
    worms_validate_no_special_entries "$stage" || return 1
    if ! verify_save_tree_copy "$source_dir" "$stage"; then
        echo -e "${RED}ERROR:${NC} Staged save tree verification failed: $target_dir"
        return 1
    fi
}

rollback_save_transactions() {
    local reason="${1:-restore failure}"
    local index target retained failed stage status=0

    echo -e "${YELLOW}Rolling back save restore after ${reason}...${NC}" >&2
    for ((index = RESTORE_TRANSACTION_COUNT - 1; index >= 0; index--)); do
        [[ "${RESTORE_APPLIED[$index]:-0}" == "1" ]] || continue
        target="${RESTORE_TARGET_DIRS[$index]}"
        retained="${RESTORE_RETAINED_DIRS[$index]}"
        stage="${RESTORE_STAGE_DIRS[$index]:-}"
        failed="$retained/failed-replacement"

        if [[ "${RESTORE_HAD_OLD[$index]:-0}" == "1" ]] \
            && [[ ! -d "$retained/original" ]]; then
            RESTORE_APPLIED[index]=0
            if rmdir "$retained" 2>/dev/null; then
                RESTORE_RETAINED_DIRS[index]=""
            else
                echo -e "${YELLOW}WARNING:${NC} Unused retention directory remains at: $retained" >&2
            fi
            continue
        fi
        if [[ "${RESTORE_HAD_OLD[$index]:-0}" == "0" ]] \
            && [[ -n "$stage" ]] && [[ -d "$stage" ]]; then
            RESTORE_APPLIED[index]=0
            if rmdir "$retained" 2>/dev/null; then
                RESTORE_RETAINED_DIRS[index]=""
            else
                echo -e "${YELLOW}WARNING:${NC} Unused retention directory remains at: $retained" >&2
            fi
            continue
        fi

        if [[ -e "$target" ]] || [[ -L "$target" ]]; then
            if ! mv "$target" "$failed"; then
                echo -e "${RED}ERROR:${NC} Could not retain failed replacement: $target" >&2
                status=1
                continue
            fi
        fi
        if [[ "${RESTORE_HAD_OLD[$index]:-0}" == "1" ]]; then
            if ! mv "$retained/original" "$target"; then
                echo -e "${RED}ERROR:${NC} Could not restore original save tree; retained at: $retained/original" >&2
                status=1
                continue
            fi
        fi
        RESTORE_APPLIED[index]=0
        rm -rf "$retained"
        RESTORE_RETAINED_DIRS[index]=""
    done
    RESTORE_TRANSACTION_ACTIVE=false

    if [[ "$status" -eq 0 ]]; then
        echo -e "${YELLOW}Save restore rollback completed.${NC}" >&2
    else
        echo -e "${RED}ERROR:${NC} Save restore rollback failed; retained originals require manual recovery." >&2
    fi
    return "$status"
}

finalize_save_transactions() {
    local index retained

    for ((index = 0; index < RESTORE_TRANSACTION_COUNT; index++)); do
        retained="${RESTORE_RETAINED_DIRS[$index]:-}"
        if [[ -n "$retained" ]] && [[ -d "$retained" ]] && [[ ! -L "$retained" ]]; then
            rm -rf "$retained"
            RESTORE_RETAINED_DIRS[index]=""
        fi
        RESTORE_APPLIED[index]=0
    done
    RESTORE_TRANSACTION_ACTIVE=false
}

prepare_save_transactions() {
    local index

    for ((index = 0; index < RESTORE_TRANSACTION_COUNT; index++)); do
        prepare_save_tree_stage "$index" || {
            cleanup_save_transaction_stages
            return 1
        }
    done
}

apply_save_transactions() {
    local index source target target_parent target_base stage retained

    RESTORE_TRANSACTION_ACTIVE=true
    for ((index = 0; index < RESTORE_TRANSACTION_COUNT; index++)); do
        source="${RESTORE_SOURCE_DIRS[$index]}"
        target="${RESTORE_TARGET_DIRS[$index]}"
        stage="${RESTORE_STAGE_DIRS[$index]}"
        if [[ -z "$stage" ]] || [[ ! -d "$stage" ]] || [[ -L "$stage" ]]; then
            rollback_save_transactions "missing staged replacement" || true
            return 1
        fi
        target_parent=$(dirname "$target")
        target_base=$(basename "$target")
        if [[ -L "$target" ]] \
            || { [[ -e "$target" ]] && [[ ! -d "$target" ]]; } \
            || ! worms_path_inside_root "${RESTORE_ALLOWED_ROOTS[$index]}" "$target"; then
            rollback_save_transactions "target changed during staging" || true
            return 1
        fi
        retained=$(mktemp -d "$target_parent/.${target_base}.restore-retained.XXXXXX") || {
            rollback_save_transactions "retained-tree reservation failure" || true
            return 1
        }
        chmod 0700 "$retained"
        RESTORE_RETAINED_DIRS[index]="$retained"
        RESTORE_APPLIED[index]=1

        if [[ -d "$target" ]]; then
            RESTORE_HAD_OLD[index]=1
            if ! mv "$target" "$retained/original"; then
                rollback_save_transactions "old-tree retention failure" || true
                return 1
            fi
        fi
        if ! mv "$stage" "$target"; then
            rollback_save_transactions "replacement publish failure" || true
            return 1
        fi
        RESTORE_STAGE_DIRS[index]=""
        if ! verify_save_tree_copy "$source" "$target"; then
            rollback_save_transactions "post-publish verification failure" || true
            return 1
        fi
    done

    if ! verify_restored_saves; then
        rollback_save_transactions "manifest verification failure" || true
        return 1
    fi
    finalize_save_transactions
}

# Create backup
do_backup() {
    echo -e "${BLUE}Creating save game backup...${NC}"
    echo ""

    mkdir -p "$BACKUP_DIR"

    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_file
    backup_file=$(worms_unique_path "$BACKUP_DIR/saves-$timestamp" ".tar.gz")
    TEMP_DIR=$(mktemp -d)

    local items_backed_up=0

    # Backup Team17 saves
    if [[ -d "$TEAM17_SAVES" ]]; then
        echo "Backing up Team17 saves..."
        mkdir -p "$TEMP_DIR/Team17"
        cp -R "$TEAM17_SAVES/." "$TEMP_DIR/Team17/"
        ((items_backed_up++))
    fi

    # Backup Steam Cloud saves
    local steam_save_dirs
    steam_save_dirs=$(find_steam_saves)

    if [[ -n "$steam_save_dirs" ]]; then
        mkdir -p "$TEMP_DIR/Steam"
        while IFS= read -r save_dir; do
            if [[ -d "$save_dir" ]]; then
                local user_id
                user_id=$(basename "$(dirname "$save_dir")")
                echo "Backing up Steam saves for user $user_id..."
                mkdir -p "$TEMP_DIR/Steam/$user_id"
                cp -R "$save_dir/." "$TEMP_DIR/Steam/$user_id/"
                ((items_backed_up++))
            fi
        done <<< "$steam_save_dirs"
    fi

    if [[ $items_backed_up -eq 0 ]]; then
        echo -e "${YELLOW}No save games found to backup.${NC}"
        exit 0
    fi

    # Create metadata
    cat > "$TEMP_DIR/BACKUP_INFO.txt" << EOF
Worms W.M.D Save Game Backup
Created: $(date)
macOS: $(macos_product_version)
Items: $items_backed_up save locations
EOF

    worms_validate_no_special_entries "$TEMP_DIR"
    worms_write_manifest "$TEMP_DIR" "$TEMP_DIR/$SAVE_MANIFEST_NAME" Team17 Steam BACKUP_INFO.txt
    worms_verify_manifest "$TEMP_DIR" "$TEMP_DIR/$SAVE_MANIFEST_NAME"

    # Create tarball
    echo ""
    echo "Creating archive..."
    tar -czf "$backup_file" -C "$TEMP_DIR" .

    local size
    size=$(du -h "$backup_file" | cut -f1)

    echo ""
    echo -e "${GREEN}Backup created successfully!${NC}"
    echo "File: $backup_file"
    echo "Size: $size"
    echo ""
    echo "To restore: ./backup_saves.sh --restore"
}

# Restore backup
do_restore() {
    local backup_file="$1"
    local archive_copy compressed_bytes free_bytes usable_bytes default_expanded_bytes
    local max_expanded_bytes required_bytes target_index

    # If no file specified, use latest
    if [[ -z "$backup_file" ]]; then
        backup_file=$(worms_latest_path_by_mtime "$BACKUP_DIR" "saves-*.tar.gz" "f")

        if [[ -z "$backup_file" ]]; then
            echo -e "${RED}No backups found in $BACKUP_DIR${NC}"
            exit 1
        fi

        echo "Using latest backup: $(basename "$backup_file")"
    fi

    if [[ ! -f "$backup_file" ]] || [[ -L "$backup_file" ]]; then
        echo -e "${RED}Backup file not found: $backup_file${NC}"
        exit 1
    fi
    worms_reject_control_chars "$backup_file" "backup file"

    if ! worms_python3 >/dev/null; then
        printf '%s\n' \
            "ERROR: Python 3.9 or newer is required for safe save restoration." \
            "Install or update Apple Command Line Tools, then run this command again." >&2
        exit 1
    fi

    compressed_bytes=$(worms_file_size "$backup_file")
    free_bytes=$(filesystem_available_bytes "$HOME") || exit 1
    if (( free_bytes <= compressed_bytes + RESTORE_RESERVE_BYTES )); then
        printf 'ERROR: Restore needs %s archive bytes plus a %s-byte free-space reserve; only %s bytes are free.\n' \
            "$compressed_bytes" "$RESTORE_RESERVE_BYTES" "$free_bytes" >&2
        exit 1
    fi
    usable_bytes=$((free_bytes - compressed_bytes - RESTORE_RESERVE_BYTES))
    default_expanded_bytes=$((usable_bytes / 2))
    if (( default_expanded_bytes > RESTORE_ABSOLUTE_MAX_BYTES )); then
        default_expanded_bytes=$RESTORE_ABSOLUTE_MAX_BYTES
    fi

    if [[ -n "$RESTORE_MAX_EXPANDED_BYTES" ]]; then
        max_expanded_bytes=$RESTORE_MAX_EXPANDED_BYTES
    else
        max_expanded_bytes=$default_expanded_bytes
    fi
    if (( max_expanded_bytes <= 0 )); then
        printf '%s\n' "ERROR: Insufficient free space for a bounded restore." >&2
        exit 1
    fi
    required_bytes=$((compressed_bytes + (2 * max_expanded_bytes) + RESTORE_RESERVE_BYTES))
    if (( required_bytes > free_bytes )); then
        printf 'ERROR: Restore limit requires %s free bytes including staging and reserve; only %s bytes are free.\n' \
            "$required_bytes" "$free_bytes" >&2
        exit 1
    fi

    RESTORE_WORK_DIR=$(mktemp -d "$HOME/.wormswmd-restore.XXXXXX")
    TEMP_DIR="$RESTORE_WORK_DIR/extracted"
    archive_copy="$RESTORE_WORK_DIR/backup.tar.gz"
    mkdir -m 0700 "$TEMP_DIR"
    if ! worms_copy_and_inspect_archive \
        "$backup_file" "$archive_copy" save "" \
        --max-expanded-bytes "$max_expanded_bytes" --quiet; then
        printf '%s\n' "ERROR: Backup archive safety inspection failed." >&2
        exit 1
    fi
    compressed_bytes=$(worms_file_size "$archive_copy")
    free_bytes=$(filesystem_available_bytes "$HOME") || exit 1
    required_bytes=$(((2 * max_expanded_bytes) + RESTORE_RESERVE_BYTES))
    if (( required_bytes > free_bytes )); then
        printf 'ERROR: Restore staging requires %s remaining free bytes; only %s bytes remain after the archive copy.\n' \
            "$required_bytes" "$free_bytes" >&2
        exit 1
    fi
    printf 'Restore safety limits: archive=%s bytes, expanded=%s bytes, remaining-free=%s bytes, reserve=%s bytes.\n' \
        "$compressed_bytes" "$max_expanded_bytes" "$free_bytes" "$RESTORE_RESERVE_BYTES"
    validate_backup_archive_layout "$archive_copy"

    # Extract backup
    tar -xzf "$archive_copy" -C "$TEMP_DIR"
    worms_validate_tree_paths "$TEMP_DIR"
    worms_validate_no_special_entries "$TEMP_DIR"

    if [[ -f "$TEMP_DIR/$SAVE_MANIFEST_NAME" ]]; then
        if worms_verify_manifest "$TEMP_DIR" "$TEMP_DIR/$SAVE_MANIFEST_NAME"; then
            echo "Backup manifest verified."
        else
            echo -e "${RED}ERROR:${NC} Backup manifest verification failed; restore cancelled."
            exit 1
        fi
    else
        echo -e "${YELLOW}WARNING:${NC} Backup has no manifest; restoring as a legacy archive."
    fi

    prepare_restore_targets || {
        echo -e "${RED}ERROR:${NC} Save restore target validation failed."
        exit 1
    }

    echo -e "${YELLOW}WARNING: This will replace the following save roots:${NC}"
    for ((target_index = 0; target_index < RESTORE_TRANSACTION_COUNT; target_index++)); do
        printf '  %s\n' "${RESTORE_TARGET_DIRS[$target_index]}"
    done
    echo ""
    if restore_assume_yes; then
        echo "Continuing with non-interactive confirmation."
    else
        read -p "Continue? [y/N] " -n 1 -r < /dev/tty
        echo ""
        if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
            echo "Restore cancelled."
            exit 0
        fi
    fi

    if ! prepare_save_transactions; then
        echo -e "${RED}ERROR:${NC} Save restore staging failed; existing saves were not changed."
        exit 1
    fi
    if [[ -d "$TEMP_DIR/Steam" ]]; then
        ensure_steam_stopped || exit 1
    fi

    echo ""
    echo -e "${BLUE}Restoring from: $(basename "$backup_file")${NC}"
    if ! apply_save_transactions; then
        echo -e "${RED}ERROR:${NC} Save restore failed. Review rollback messages above."
        exit 1
    fi

    echo ""
    echo -e "${GREEN}Saves restored successfully!${NC}"
}

# List backups
do_list() {
    echo -e "${BLUE}Available backups:${NC}"
    echo ""

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type f -name "saves-*.tar.gz" -print -quit 2>/dev/null)" ]]; then
        echo "No backups found in $BACKUP_DIR"
        exit 0
    fi

    echo ""
    local count=0
    while IFS= read -r backup; do
        [[ -n "$backup" ]] || continue
        if ls_line=$(ls -lh "$backup" 2>/dev/null); then
            echo "  $ls_line"
            count=$((count + 1))
        fi
    done < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type f -name "saves-*.tar.gz" -print 2>/dev/null | sort)
    echo "Total: $count backup(s)"
}

# Show save locations
do_location() {
    echo -e "${BLUE}Save Game Locations:${NC}"
    echo ""

    echo "Team17 Saves:"
    if [[ -d "$TEAM17_SAVES" ]]; then
        echo -e "  ${GREEN}Found:${NC} $TEAM17_SAVES"
        du -sh "$TEAM17_SAVES" 2>/dev/null | awk '{print "  Size: " $1}'
    else
        echo -e "  ${YELLOW}Not found${NC}"
    fi

    echo ""
    echo "Steam Cloud Saves:"
    local steam_saves
    steam_saves=$(find_steam_saves)

    if [[ -n "$steam_saves" ]]; then
        while IFS= read -r save_dir; do
            local user_id
            user_id=$(basename "$(dirname "$save_dir")")
            echo -e "  ${GREEN}User $user_id:${NC} $save_dir"
            du -sh "$save_dir" 2>/dev/null | awk '{print "    Size: " $1}'
        done <<< "$steam_saves"
    else
        echo -e "  ${YELLOW}Not found${NC}"
    fi
}

# Parse arguments
action=""
restore_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup|-b)
            [[ -z "$action" ]] || { echo -e "${RED}Choose only one action.${NC}"; exit 1; }
            action="backup"
            shift
            ;;
        --restore|-r)
            [[ -z "$action" ]] || { echo -e "${RED}Choose only one action.${NC}"; exit 1; }
            action="restore"
            shift
            if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
                restore_file="$1"
                shift
            fi
            ;;
        --yes)
            RESTORE_ASSUME_YES=true
            shift
            ;;
        --max-expanded-size)
            [[ $# -ge 2 ]] || { echo -e "${RED}--max-expanded-size requires a value.${NC}"; exit 1; }
            RESTORE_MAX_EXPANDED_SIZE="$2"
            shift 2
            ;;
        --allow-external-steam-root)
            [[ $# -ge 2 ]] || { echo -e "${RED}--allow-external-steam-root requires a path.${NC}"; exit 1; }
            RESTORE_EXTERNAL_STEAM_ROOT="$2"
            shift 2
            ;;
        --list|-l)
            [[ -z "$action" ]] || { echo -e "${RED}Choose only one action.${NC}"; exit 1; }
            action="list"
            shift
            ;;
        --location)
            [[ -z "$action" ]] || { echo -e "${RED}Choose only one action.${NC}"; exit 1; }
            action="location"
            shift
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage"
            exit 1
            ;;
    esac
done

action="${action:-backup}"
if [[ -n "$RESTORE_MAX_EXPANDED_SIZE" ]]; then
    [[ "$action" == "restore" ]] || {
        echo -e "${RED}--max-expanded-size is valid only with --restore.${NC}"
        exit 1
    }
    $RESTORE_ASSUME_YES || {
        echo -e "${RED}--max-expanded-size requires explicit --yes.${NC}"
        exit 1
    }
    RESTORE_MAX_EXPANDED_BYTES=$(parse_bounded_restore_size "$RESTORE_MAX_EXPANDED_SIZE") || exit 1
fi
if [[ -n "$RESTORE_EXTERNAL_STEAM_ROOT" ]]; then
    [[ "$action" == "restore" ]] || {
        echo -e "${RED}--allow-external-steam-root is valid only with --restore.${NC}"
        exit 1
    }
    $RESTORE_ASSUME_YES || {
        echo -e "${RED}--allow-external-steam-root requires explicit --yes.${NC}"
        exit 1
    }
    worms_reject_control_chars "$RESTORE_EXTERNAL_STEAM_ROOT" \
        "--allow-external-steam-root"
    [[ "$RESTORE_EXTERNAL_STEAM_ROOT" == /* ]] || {
        echo -e "${RED}--allow-external-steam-root requires an absolute path.${NC}"
        exit 1
    }
fi
if $RESTORE_ASSUME_YES && [[ "$action" != "restore" ]]; then
    echo -e "${RED}--yes is valid only with --restore.${NC}"
    exit 1
fi

case "$action" in
    backup) do_backup ;;
    restore) do_restore "$restore_file" ;;
    list) do_list ;;
    location) do_location ;;
esac
