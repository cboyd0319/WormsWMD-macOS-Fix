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

set -e

# Save locations
STEAM_SAVES="$HOME/Library/Application Support/Steam/userdata"
TEAM17_SAVES="$HOME/Library/Application Support/Team17"
BACKUP_DIR="${BACKUP_DIR:-$HOME/Documents/WormsWMD-SaveBackups}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

latest_path_by_mtime() {
    local search_dir="$1"
    local name_glob="$2"
    local type="${3:-f}"

    find "$search_dir" -mindepth 1 -maxdepth 1 -type "$type" -name "$name_glob" -print0 2>/dev/null \
        | while IFS= read -r -d '' item; do
            mtime=$(stat -f "%m" "$item" 2>/dev/null || echo 0)
            printf '%s\t%s\n' "$mtime" "$item"
        done \
        | sort -nr \
        | head -1 \
        | cut -f2-
}

# Create backup
do_backup() {
    echo -e "${BLUE}Creating save game backup...${NC}"
    echo ""

    mkdir -p "$BACKUP_DIR"

    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_file="$BACKUP_DIR/saves-$timestamp.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)

    local items_backed_up=0

    # Backup Team17 saves
    if [[ -d "$TEAM17_SAVES" ]]; then
        echo "Backing up Team17 saves..."
        mkdir -p "$temp_dir/Team17"
        cp -R "$TEAM17_SAVES"/* "$temp_dir/Team17/" 2>/dev/null || true
        ((items_backed_up++))
    fi

    # Backup Steam Cloud saves
    local steam_save_dirs
    steam_save_dirs=$(find_steam_saves)

    if [[ -n "$steam_save_dirs" ]]; then
        mkdir -p "$temp_dir/Steam"
        while IFS= read -r save_dir; do
            if [[ -d "$save_dir" ]]; then
                local user_id
                user_id=$(basename "$(dirname "$save_dir")")
                echo "Backing up Steam saves for user $user_id..."
                mkdir -p "$temp_dir/Steam/$user_id"
                cp -R "$save_dir"/* "$temp_dir/Steam/$user_id/" 2>/dev/null || true
                ((items_backed_up++))
            fi
        done <<< "$steam_save_dirs"
    fi

    if [[ $items_backed_up -eq 0 ]]; then
        echo -e "${YELLOW}No save games found to backup.${NC}"
        rm -rf "$temp_dir"
        exit 0
    fi

    # Create metadata
    cat > "$temp_dir/BACKUP_INFO.txt" << EOF
Worms W.M.D Save Game Backup
Created: $(date)
macOS: $(sw_vers -productVersion)
Items: $items_backed_up save locations
EOF

    # Create tarball
    echo ""
    echo "Creating archive..."
    tar -czf "$backup_file" -C "$temp_dir" .

    # Cleanup
    rm -rf "$temp_dir"

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
        backup_file=$(latest_path_by_mtime "$BACKUP_DIR" "saves-*.tar.gz" "f")

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

    echo -e "${YELLOW}WARNING: This will overwrite your current save games!${NC}"
    echo ""
    read -p "Continue? [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Restore cancelled."
        exit 0
    fi

    echo ""
    echo -e "${BLUE}Restoring from: $(basename "$backup_file")${NC}"

    local temp_dir
    temp_dir=$(mktemp -d)

    # Extract backup
    tar -xzf "$backup_file" -C "$temp_dir"

    # Restore Team17 saves
    if [[ -d "$temp_dir/Team17" ]]; then
        echo "Restoring Team17 saves..."
        mkdir -p "$TEAM17_SAVES"
        cp -R "$temp_dir/Team17"/* "$TEAM17_SAVES/" 2>/dev/null || true
    fi

    # Restore Steam saves
    if [[ -d "$temp_dir/Steam" ]]; then
        for user_dir in "$temp_dir/Steam"/*; do
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

    # Cleanup
    rm -rf "$temp_dir"

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
