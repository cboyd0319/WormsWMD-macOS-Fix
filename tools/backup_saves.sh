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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/common.sh"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/ui.sh"
worms_color_init

# Cleanup temp files on exit
TEMP_DIR=""
cleanup() {
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

print_help() {
    cat << 'EOF'
Worms W.M.D - Save Game Backup Tool

USAGE:
    ./backup_saves.sh [OPTIONS]

OPTIONS:
    --backup, -b        Create a new backup (default)
    --restore, -r       Restore from latest backup
    --restore FILE      Restore from specific backup file
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

SAVE LOCATIONS:
    Steam Cloud saves: ~/Library/Application Support/Steam/userdata/*/327030/
    Local saves:       ~/Library/Application Support/Team17/

EOF
}

# Find Worms W.M.D Steam user data directories
find_steam_saves() {
    local found=()

    for user_dir in "$STEAM_SAVES"/*/327030; do
        if [[ -d "$user_dir" ]]; then
            found+=("$user_dir")
        fi
    done

    printf '%s\n' "${found[@]}"
}

validate_backup_archive_layout() {
    local archive="$1"
    local listing raw_entry entry

    if ! listing=$(tar -tzf "$archive" 2>/dev/null); then
        echo -e "${RED}ERROR:${NC} Unable to read backup archive."
        return 1
    fi

    while IFS= read -r raw_entry; do
        [[ -n "$raw_entry" ]] || continue
        entry="${raw_entry#./}"
        while [[ "$entry" == */ ]]; do
            entry="${entry%/}"
        done
        [[ -n "$entry" ]] || continue

        if [[ "$entry" == /* ]] || [[ "$entry" == *"../"* ]] || [[ "$entry" == *"/.."* ]] || [[ "$entry" == ".." ]]; then
            echo -e "${RED}ERROR:${NC} Unsafe path in backup archive: $entry"
            return 1
        fi

        case "$entry" in
            Team17|Team17/*|Steam|Steam/*|BACKUP_INFO.txt|"$SAVE_MANIFEST_NAME")
                ;;
            *)
                echo -e "${RED}ERROR:${NC} Unexpected entry in backup archive: $entry"
                return 1
                ;;
        esac
    done <<< "$listing"
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

    [[ -f "$manifest" ]] || return 0

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
    done < "$manifest"

    return "$status"
}

# Create backup
do_backup() {
    echo -e "${BLUE}Creating save game backup...${NC}"
    echo ""

    mkdir -p "$BACKUP_DIR"

    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_file="$BACKUP_DIR/saves-$timestamp.tar.gz"
    TEMP_DIR=$(mktemp -d)

    local items_backed_up=0

    # Backup Team17 saves
    if [[ -d "$TEAM17_SAVES" ]]; then
        echo "Backing up Team17 saves..."
        mkdir -p "$TEMP_DIR/Team17"
        cp -R "$TEAM17_SAVES"/* "$TEMP_DIR/Team17/" 2>/dev/null || true
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
                cp -R "$save_dir"/* "$TEMP_DIR/Steam/$user_id/" 2>/dev/null || true
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
macOS: $(sw_vers -productVersion)
Items: $items_backed_up save locations
EOF

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

    # If no file specified, use latest
    if [[ -z "$backup_file" ]]; then
        backup_file=$(worms_latest_path_by_mtime "$BACKUP_DIR" "saves-*.tar.gz" "f")

        if [[ -z "$backup_file" ]]; then
            echo -e "${RED}No backups found in $BACKUP_DIR${NC}"
            exit 1
        fi

        echo "Using latest backup: $(basename "$backup_file")"
    fi

    if [[ ! -f "$backup_file" ]]; then
        echo -e "${RED}Backup file not found: $backup_file${NC}"
        exit 1
    fi

    validate_backup_archive_layout "$backup_file"

    echo -e "${YELLOW}WARNING: This will overwrite your current save games!${NC}"
    echo ""
    read -p "Continue? [y/N] " -n 1 -r < /dev/tty
    echo ""

    if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
        echo "Restore cancelled."
        exit 0
    fi

    echo ""
    echo -e "${BLUE}Restoring from: $(basename "$backup_file")${NC}"

    TEMP_DIR=$(mktemp -d)

    # Extract backup
    tar -xzf "$backup_file" -C "$TEMP_DIR"

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
        mkdir -p "$TEAM17_SAVES"
        cp -R "$TEMP_DIR/Team17"/* "$TEAM17_SAVES/" 2>/dev/null || true
    fi

    # Restore Steam saves
    if [[ -d "$TEMP_DIR/Steam" ]]; then
        for user_dir in "$TEMP_DIR/Steam"/*; do
            if [[ -d "$user_dir" ]]; then
                local user_id
                user_id=$(basename "$user_dir")
                local target_dir="$STEAM_SAVES/$user_id/327030"

                echo "Restoring Steam saves for user $user_id..."
                mkdir -p "$target_dir"
                cp -R "$user_dir"/* "$target_dir/" 2>/dev/null || true
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
case "${1:-}" in
    --backup|-b|"")
        do_backup
        ;;
    --restore|-r)
        do_restore "${2:-}"
        ;;
    --list|-l)
        do_list
        ;;
    --location)
        do_location
        ;;
    --help|-h)
        print_help
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Use --help for usage"
        exit 1
        ;;
esac
