#!/bin/bash
#
# check_updates.sh - Check for fix updates on GitHub
#
# Compares the installed version with the latest GitHub release
# and notifies if an update is available.
#
# Usage:
#   ./check_updates.sh              # Check and show result
#   ./check_updates.sh --quiet      # Silent, exit code only
#   ./check_updates.sh --download   # Download and verify latest release
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
GITHUB_REPO="cboyd0319/WormsWMD-macOS-Fix"
LATEST_RELEASE_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
CURL_BASE=(--proto '=https' --tlsv1.2 --retry 3 --retry-delay 1 --retry-connrefused)

# shellcheck disable=SC1091
source "$REPO_DIR/scripts/ui.sh"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/common.sh"
worms_color_init

QUIET=false
DOWNLOAD=false
DOWNLOAD_WORK_DIR=""
DOWNLOAD_FILE=""
CHECKSUM_FILE=""
PUBLISHED_DOWNLOAD=false
PUBLISHED_CHECKSUM=false
PUBLISHING_DOWNLOAD=false

cleanup_download_work() {
    local rollback_failed=false

    if $PUBLISHING_DOWNLOAD; then
        if $PUBLISHED_DOWNLOAD || [[ ! -f "$DOWNLOAD_WORK_DIR/release.zip" ]]; then
            rm -f -- "$DOWNLOAD_FILE"
        fi
        if $PUBLISHED_CHECKSUM || [[ ! -f "$DOWNLOAD_WORK_DIR/release.zip.sha256" ]]; then
            rm -f -- "$CHECKSUM_FILE"
        fi
        if [[ -f "$DOWNLOAD_WORK_DIR/previous.zip" ]]; then
            if ! mv -f -- "$DOWNLOAD_WORK_DIR/previous.zip" "$DOWNLOAD_FILE"; then
                echo "Rollback failed; prior download retained in $DOWNLOAD_WORK_DIR" >&2
                rollback_failed=true
            fi
        fi
        if [[ -f "$DOWNLOAD_WORK_DIR/previous.sha256" ]]; then
            if ! mv -f -- "$DOWNLOAD_WORK_DIR/previous.sha256" "$CHECKSUM_FILE"; then
                echo "Rollback failed; prior checksum retained in $DOWNLOAD_WORK_DIR" >&2
                rollback_failed=true
            fi
        fi
    fi

    $rollback_failed && return 1

    if [[ -n "$DOWNLOAD_WORK_DIR" ]] && [[ -d "$DOWNLOAD_WORK_DIR" ]]; then
        rm -f -- \
            "$DOWNLOAD_WORK_DIR/release.zip" \
            "$DOWNLOAD_WORK_DIR/release.zip.sha256" \
            "$DOWNLOAD_WORK_DIR/previous.zip" \
            "$DOWNLOAD_WORK_DIR/previous.sha256"
        rmdir "$DOWNLOAD_WORK_DIR" 2>/dev/null || true
    fi
}

trap cleanup_download_work EXIT
trap 'exit 2' HUP INT TERM

if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}curl is required but not installed.${NC}"
    exit 2
fi

print_help() {
    cat << 'EOF'
Worms W.M.D Fix - Update Checker

Checks for new versions of the fix on GitHub releases.

USAGE:
    ./check_updates.sh [OPTIONS]

OPTIONS:
    --quiet, -q     Silent mode (exit code only: 0=up to date, 1=update available)
    --download, -d  Download latest release zip and verify its checksum
    --help, -h      Show this help

EXIT CODES:
    0   Up to date (or update downloaded successfully)
    1   Update available
    2   Error (network, parsing, etc.)

EXAMPLES:
    # Check for updates
    ./check_updates.sh

    # Silent check (for scripts)
    if ./check_updates.sh --quiet; then
        echo "Up to date"
    else
        echo "Update available"
    fi

EOF
}

# Get current version from fix script
get_current_version() {
    if [[ -f "$REPO_DIR/fix_worms_wmd.sh" ]]; then
        grep -m1 'VERSION=' "$REPO_DIR/fix_worms_wmd.sh" | cut -d'"' -f2 || true
    else
        echo "unknown"
    fi
}

# Get latest release tag from GitHub
get_latest_release_tag() {
    local response tag
    response=$(curl "${CURL_BASE[@]}" -sf --max-time 15 "$LATEST_RELEASE_API_URL" 2>/dev/null) || return 1

    tag=$(printf '%s\n' "$response" | awk -F'"' '/"tag_name"[[:space:]]*:/ {print $4; exit}')
    if [[ -z "$tag" ]] || [[ ! "$tag" =~ ^v?[0-9]+([.][0-9]+)*$ ]]; then
        return 2
    fi
    echo "$tag"
}

# Get download URL for latest version
get_download_url() {
    local tag="$1"
    local url="https://github.com/${GITHUB_REPO}/releases/download/${tag}/WormsWMD-macOS-Fix-${tag}.zip"

    if curl "${CURL_BASE[@]}" -sfI --max-time 10 "$url" >/dev/null 2>&1; then
        echo "$url"
    else
        return 1
    fi
}

get_checksum_url() {
    local tag="$1"
    local url="https://github.com/${GITHUB_REPO}/releases/download/${tag}/WormsWMD-macOS-Fix-${tag}.zip.sha256"

    if curl "${CURL_BASE[@]}" -sfI --max-time 10 "$url" >/dev/null 2>&1; then
        echo "$url"
    else
        return 1
    fi
}

validate_download_target() {
    local path="$1"

    if [[ -e "$path" ]] || [[ -L "$path" ]]; then
        [[ -f "$path" ]] && [[ ! -L "$path" ]] \
            && [[ "$(worms_file_link_count "$path")" -eq 1 ]]
    fi
}

prepare_download_directory() {
    local downloads_dir="$1"
    local home_dir="${HOME:-}"

    [[ -n "$home_dir" ]] && [[ "$home_dir" == /* ]] \
        && ! worms_has_control_chars "$home_dir" || return 1
    [[ -d "$home_dir" ]] && [[ ! -L "$home_dir" ]] || return 1

    if [[ -e "$downloads_dir" ]] || [[ -L "$downloads_dir" ]]; then
        [[ -d "$downloads_dir" ]] && [[ ! -L "$downloads_dir" ]] || return 1
    else
        mkdir "$downloads_dir" || return 1
    fi
}

# Compare versions (returns 0 if v1 >= v2, 1 if v1 < v2)
version_compare() {
    local v1="$1"
    local v2="$2"

    # Convert to comparable numbers
    local v1_parts v2_parts
    IFS='.' read -ra v1_parts <<< "$v1"
    IFS='.' read -ra v2_parts <<< "$v2"

    local max_parts=${#v1_parts[@]}
    if [[ ${#v2_parts[@]} -gt $max_parts ]]; then
        max_parts=${#v2_parts[@]}
    fi

    for ((i=0; i<max_parts; i++)); do
        local p1="${v1_parts[$i]:-0}"
        local p2="${v2_parts[$i]:-0}"

        if [[ ! "$p1" =~ ^[0-9]+$ ]]; then
            p1=0
        fi
        if [[ ! "$p2" =~ ^[0-9]+$ ]]; then
            p2=0
        fi

        if [[ "$p1" -gt "$p2" ]]; then
            return 0
        elif [[ "$p1" -lt "$p2" ]]; then
            return 1
        fi
    done

    return 0  # Equal
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet|-q)
            QUIET=true
            shift
            ;;
        --download|-d)
            DOWNLOAD=true
            shift
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 2
            ;;
    esac
done

# Get versions
current=$(get_current_version)
if latest_tag=$(get_latest_release_tag); then
    latest="${latest_tag#v}"
    :
else
    status=$?
    if ! $QUIET; then
        if [[ "$status" -eq 2 ]]; then
            echo -e "${YELLOW}Could not determine latest version (VERSION not found)${NC}"
        else
            echo -e "${RED}Could not check for updates (network error?)${NC}"
        fi
    fi
    exit 2
fi

if [[ -z "$latest" ]] || [[ "$latest" == "null" ]]; then
    if ! $QUIET; then
        echo -e "${RED}Could not check for updates (network error?)${NC}"
    fi
    exit 2
fi

if $QUIET; then
    if version_compare "$current" "$latest"; then
        exit 0  # Up to date
    else
        exit 1  # Update available
    fi
fi

# Verbose output
echo -e "${BLUE}Worms W.M.D Fix - Update Check${NC}"
echo ""
echo "Current version: $current"
echo "Latest version:  $latest"
echo ""

if version_compare "$current" "$latest"; then
    echo -e "${GREEN}You're up to date!${NC}"
    exit 0
else
    echo -e "${YELLOW}Update available!${NC}"
    echo ""
    echo "Repo: https://github.com/${GITHUB_REPO}"
    echo ""

    if $DOWNLOAD; then
        echo "Downloading latest version..."

        if download_url=$(get_download_url "$latest_tag") && checksum_url=$(get_checksum_url "$latest_tag"); then
            :
        else
            echo -e "${RED}Could not get release download URLs${NC}"
            exit 2
        fi

        if [[ -z "$download_url" ]] || [[ -z "$checksum_url" ]]; then
            echo -e "${RED}Could not get release download URLs${NC}"
            exit 2
        fi

        downloads_dir="$HOME/Downloads"
        DOWNLOAD_FILE="$downloads_dir/WormsWMD-macOS-Fix-${latest_tag}.zip"
        CHECKSUM_FILE="$DOWNLOAD_FILE.sha256"
        if ! prepare_download_directory "$downloads_dir"; then
            echo -e "${RED}Unsafe Downloads directory${NC}"
            exit 2
        fi
        if ! validate_download_target "$DOWNLOAD_FILE" \
            || ! validate_download_target "$CHECKSUM_FILE"; then
            echo -e "${RED}Refusing an unsafe existing download target${NC}"
            exit 2
        fi

        old_umask=$(umask)
        umask 077
        DOWNLOAD_WORK_DIR=$(mktemp -d "$downloads_dir/.wormswmd-update-XXXXXX")
        umask "$old_umask"
        staged_download="$DOWNLOAD_WORK_DIR/release.zip"
        staged_checksum="$DOWNLOAD_WORK_DIR/release.zip.sha256"

        if ! curl "${CURL_BASE[@]}" -L --max-time 120 -o "$staged_download" "$download_url"; then
            echo -e "${RED}Download failed${NC}"
            exit 2
        fi
        if ! curl "${CURL_BASE[@]}" -L --max-time 30 -o "$staged_checksum" "$checksum_url"; then
            echo -e "${RED}Checksum download failed${NC}"
            exit 2
        fi
        chmod 600 "$staged_download" "$staged_checksum"
        if ! worms_verify_exact_sha256_file \
            "$staged_download" "$staged_checksum" "$(basename "$DOWNLOAD_FILE")"; then
            echo -e "${RED}Checksum verification failed${NC}"
            exit 2
        fi

        PUBLISHING_DOWNLOAD=true
        if [[ -e "$DOWNLOAD_FILE" ]]; then
            mv -- "$DOWNLOAD_FILE" "$DOWNLOAD_WORK_DIR/previous.zip"
        fi
        if [[ -e "$CHECKSUM_FILE" ]]; then
            mv -- "$CHECKSUM_FILE" "$DOWNLOAD_WORK_DIR/previous.sha256"
        fi
        if ! mv -- "$staged_download" "$DOWNLOAD_FILE"; then
            echo -e "${RED}Could not publish the verified download${NC}"
            exit 2
        fi
        PUBLISHED_DOWNLOAD=true
        if ! mv -- "$staged_checksum" "$CHECKSUM_FILE"; then
            echo -e "${RED}Could not publish the verified checksum${NC}"
            exit 2
        fi
        PUBLISHED_CHECKSUM=true
        PUBLISHING_DOWNLOAD=false
        cleanup_download_work
        DOWNLOAD_WORK_DIR=""

        echo -e "${GREEN}Downloaded and verified: $DOWNLOAD_FILE${NC}"
        echo ""
        echo "To install:"
        echo "  1. Extract the zip file"
        echo "  2. Replace your current fix folder"
        echo "  3. Run ./fix_worms_wmd.sh"
        exit 0
    else
        echo "To update:"
        echo "  git -C \"$REPO_DIR\" pull"
        echo ""
        echo "Or download and verify the release zip: ./check_updates.sh --download"
    fi

    exit 1
fi
