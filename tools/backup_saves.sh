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
cleanup() {
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
RESTORE_RESERVE_BYTES=$((512 * 1024 * 1024))
RESTORE_ABSOLUTE_MAX_BYTES=$((8 * 1024 * 1024 * 1024))
worms_reject_control_chars "$BACKUP_DIR" "BACKUP_DIR"

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
    local steam_rel user_id save_rel

    case "$rel_path" in
        Team17/*)
            echo "$TEAM17_SAVES/${rel_path#Team17/}"
            ;;
        Steam/*/*)
            steam_rel="${rel_path#Steam/}"
            user_id="${steam_rel%%/*}"
            save_rel="${steam_rel#*/}"
            [[ -n "$user_id" ]] && [[ -n "$save_rel" ]] || return 1
            echo "$STEAM_SAVES/$user_id/327030/$save_rel"
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
            target_dir="$STEAM_SAVES/$user_id/327030"
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

replace_save_tree() {
    local source_dir="$1"
    local target_dir="$2"
    local target_parent target_base temp_target

    target_parent=$(dirname "$target_dir")
    target_base=$(basename "$target_dir")

    mkdir -p "$target_parent"
    temp_target=$(mktemp -d "$target_parent/.${target_base}.restore.XXXXXX")
    if ! cp -R "$source_dir/." "$temp_target/"; then
        rm -rf "$temp_target"
        return 1
    fi
    rm -rf "$target_dir"
    mv "$temp_target" "$target_dir"
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
    local max_expanded_bytes required_bytes

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

    echo -e "${YELLOW}WARNING: This will overwrite your current save games!${NC}"
    echo ""
    if restore_assume_yes; then
        echo "Continuing because WORMSWMD_RESTORE_ASSUME_YES is set."
    else
        read -p "Continue? [y/N] " -n 1 -r < /dev/tty
        echo ""

        if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
            echo "Restore cancelled."
            exit 0
        fi
    fi

    echo ""
    echo -e "${BLUE}Restoring from: $(basename "$backup_file")${NC}"

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

    # Restore Team17 saves
    if [[ -d "$TEMP_DIR/Team17" ]]; then
        echo "Restoring Team17 saves..."
        replace_save_tree "$TEMP_DIR/Team17" "$TEAM17_SAVES"
    fi

    # Restore Steam saves
    if [[ -d "$TEMP_DIR/Steam" ]]; then
        for user_dir in "$TEMP_DIR/Steam"/*; do
            if [[ -d "$user_dir" ]]; then
                local user_id
                user_id=$(basename "$user_dir")
                local target_dir="$STEAM_SAVES/$user_id/327030"

                echo "Restoring Steam saves for user $user_id..."
                replace_save_tree "$user_dir" "$target_dir"
            fi
        done
    fi

    if ! verify_restored_saves; then
        echo -e "${RED}ERROR:${NC} Restore verification failed after copying saves."
        echo "At least one restored file did not match the backup manifest."
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
