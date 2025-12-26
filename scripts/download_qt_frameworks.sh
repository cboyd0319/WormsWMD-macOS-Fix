#!/bin/bash
#
# download_qt_frameworks.sh - Download pre-built Qt frameworks
#
# Downloads pre-packaged Qt 5.15 x86_64 frameworks from the repo dist/ folder,
# eliminating the need for users to install Homebrew.
#
# Usage:
#   ./download_qt_frameworks.sh [--force]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$REPO_DIR/dist"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wormswmd-fix"

GITHUB_REPO="cboyd0319/WormsWMD-macOS-Fix"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}/contents/dist"
DOWNLOAD_URL=""
CHECKSUM_URL=""
PACKAGE_NAME=""
QT_VERSION=""
USE_LOCAL=false
CACHED_PACKAGE=""
EXTRACT_DIR=""
TEMP_EXTRACT=""
CHECKSUM_TMP=""

# shellcheck disable=SC1091
source "$SCRIPT_DIR/ui.sh"
worms_color_init

FORCE=false
CHECK_ONLY=false

CURL_BASE=(--proto '=https' --tlsv1.2 --retry 3 --retry-delay 1 --retry-connrefused)

cleanup() {
    if [[ -n "$TEMP_EXTRACT" ]] && [[ -d "$TEMP_EXTRACT" ]]; then
        rm -rf "$TEMP_EXTRACT"
    fi
    if [[ -n "$CHECKSUM_TMP" ]] && [[ -f "$CHECKSUM_TMP" ]]; then
        rm -f "$CHECKSUM_TMP"
    fi
}

trap cleanup EXIT

for cmd in curl tar shasum mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}ERROR:${NC} Missing required command: $cmd"
        exit 1
    fi
done

read_checksum() {
    local checksum_file="$1"
    local expected

    expected=$(awk 'NR==1 {print $1}' "$checksum_file" 2>/dev/null || true)
    if [[ ! "$expected" =~ ^[a-fA-F0-9]{64}$ ]]; then
        return 1
    fi

    echo "$expected"
}

verify_checksum() {
    local archive="$1"
    local checksum_file="$2"
    local expected actual

    expected=$(read_checksum "$checksum_file") || return 1
    actual=$(shasum -a 256 "$archive" | awk '{print $1}')

    if [[ "$expected" != "$actual" ]]; then
        return 1
    fi
}

validate_tar_layout() {
    local archive="$1"
    local entry
    local listing

    if ! listing=$(tar -tzf "$archive" 2>/dev/null); then
        echo -e "${RED}ERROR:${NC} Unable to read archive contents."
        return 1
    fi

    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue

        if [[ "$entry" == /* ]] || [[ "$entry" == *"../"* ]] || [[ "$entry" == *"/.."* ]]; then
            echo -e "${RED}ERROR:${NC} Unsafe path in archive: $entry"
            return 1
        fi

        case "$entry" in
            Frameworks|Frameworks/*|PlugIns|PlugIns/*|METADATA.txt)
                ;;
            *)
                echo -e "${RED}ERROR:${NC} Unexpected entry in archive: $entry"
                return 1
                ;;
        esac
    done <<< "$listing"
}

version_compare() {
    local v1="$1"
    local v2="$2"

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

    return 0
}

select_local_package() {
    local best_version=""
    local best_path=""

    if [[ ! -d "$DIST_DIR" ]]; then
        return 1
    fi

    while IFS= read -r -d '' package; do
        local name version
        if [[ ! -f "${package}.sha256" ]]; then
            continue
        fi
        if ! read_checksum "${package}.sha256" >/dev/null; then
            continue
        fi
        name=$(basename "$package")
        version=${name#qt-frameworks-x86_64-}
        version=${version%.tar.gz}

        if [[ -z "$best_version" ]] || version_compare "$version" "$best_version"; then
            best_version="$version"
            best_path="$package"
        fi
    done < <(find "$DIST_DIR" -mindepth 1 -maxdepth 1 -type f -name "qt-frameworks-x86_64-*.tar.gz" -print0 2>/dev/null)

    if [[ -z "$best_path" ]]; then
        return 1
    fi

    USE_LOCAL=true
    PACKAGE_NAME=$(basename "$best_path")
    QT_VERSION="$best_version"
    DOWNLOAD_URL=""
    CHECKSUM_URL=""
    CACHED_PACKAGE="$best_path"
}

select_remote_package() {
    local response
    response=$(curl "${CURL_BASE[@]}" -sf --max-time 30 "$GITHUB_API_URL" 2>/dev/null) || return 1

    local urls
    urls=$(echo "$response" | grep -o '"download_url": *"[^"]*qt-frameworks-x86_64-[^"]*\.tar\.gz"' | cut -d'"' -f4 || true)
    if [[ -z "$urls" ]]; then
        return 1
    fi

    local best_url=""
    local best_version=""
    local best_name=""
    while IFS= read -r url; do
        [[ -n "$url" ]] || continue
        local name version
        name=$(basename "$url")
        version=${name#qt-frameworks-x86_64-}
        version=${version%.tar.gz}

        if [[ -z "$best_version" ]] || version_compare "$version" "$best_version"; then
            best_version="$version"
            best_url="$url"
            best_name="$name"
        fi
    done <<< "$urls"

    if [[ -z "$best_url" ]]; then
        return 1
    fi

    USE_LOCAL=false
    DOWNLOAD_URL="$best_url"
    PACKAGE_NAME="$best_name"
    QT_VERSION="$best_version"
    CHECKSUM_URL="${DOWNLOAD_URL}.sha256"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)
            FORCE=true
            shift
            ;;
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--check]"
            echo ""
            echo "Downloads pre-built Qt 5.15 x86_64 frameworks."
            echo ""
            echo "Options:"
            echo "  --force    Re-download even if cached"
            echo "  --check    Check if pre-built package is available"
            exit 0
            ;;
        *)
            echo -e "${RED}ERROR:${NC} Unknown option: $1"
            exit 1
            ;;
    esac
done

if $CHECK_ONLY; then
    if select_local_package; then
        if [[ -f "${CACHED_PACKAGE}.sha256" ]] && read_checksum "${CACHED_PACKAGE}.sha256" >/dev/null; then
            echo "available"
            exit 0
        fi
    fi
    CHECKSUM_TMP=$(mktemp -t wormswmd-checksum.XXXXXX)
    if select_remote_package \
        && curl "${CURL_BASE[@]}" -sfI --max-time 10 "$DOWNLOAD_URL" >/dev/null 2>&1 \
        && curl "${CURL_BASE[@]}" -sf --max-time 10 "$CHECKSUM_URL" -o "$CHECKSUM_TMP" 2>/dev/null \
        && read_checksum "$CHECKSUM_TMP" >/dev/null; then
        echo "available"
    else
        echo "unavailable"
    fi
    exit 0
fi

if ! select_local_package; then
    if ! select_remote_package; then
        echo -e "${YELLOW}Pre-built Qt frameworks not available.${NC}"
        echo "FALLBACK_TO_HOMEBREW"
        exit 1
    fi
fi

# Create cache directory
mkdir -p "$CACHE_DIR"

if [[ -z "$CACHED_PACKAGE" ]]; then
    CACHED_PACKAGE="$CACHE_DIR/$PACKAGE_NAME"
fi
if [[ -n "$QT_VERSION" ]]; then
    EXTRACT_DIR="$CACHE_DIR/qt-frameworks-$QT_VERSION"
else
    EXTRACT_DIR="$CACHE_DIR/qt-frameworks"
fi

# Check if already cached and extracted
if [[ -d "$EXTRACT_DIR/Frameworks" ]] && [[ -d "$EXTRACT_DIR/PlugIns" ]] && ! $FORCE; then
    echo -e "${GREEN}Using cached Qt frameworks${NC}"
    echo "$EXTRACT_DIR"
    exit 0
fi

if $USE_LOCAL; then
    echo -e "${GREEN}Using local Qt package${NC}"
    echo "Package: $CACHED_PACKAGE"
else
    echo -e "${CYAN}Downloading Qt frameworks...${NC}"
    echo "This is a one-time download (~50MB)"
    echo ""

    # Download package
    if [[ -f "$CACHED_PACKAGE" ]] && ! $FORCE; then
        echo "Using cached package: $CACHED_PACKAGE"
    else
        echo "Downloading from: $DOWNLOAD_URL"

        # Check if URL is accessible
        if ! curl "${CURL_BASE[@]}" -sfI --max-time 10 "$DOWNLOAD_URL" >/dev/null 2>&1; then
            echo -e "${YELLOW}Pre-built Qt frameworks not available.${NC}"
            echo "FALLBACK_TO_HOMEBREW"
            exit 1
        fi

        # Download with progress
        if ! curl "${CURL_BASE[@]}" -L --max-time 300 --progress-bar -o "$CACHED_PACKAGE" "$DOWNLOAD_URL"; then
            echo -e "${RED}ERROR:${NC} Download failed"
            rm -f "$CACHED_PACKAGE"
            exit 1
        fi
    fi
fi

if $USE_LOCAL; then
    local_checksum="${CACHED_PACKAGE}.sha256"
    if [[ ! -f "$local_checksum" ]]; then
        echo -e "${RED}ERROR:${NC} Missing checksum for local package: $local_checksum"
        echo "FALLBACK_TO_HOMEBREW"
        exit 1
    fi
else
    if ! curl "${CURL_BASE[@]}" -sf --max-time 10 "$CHECKSUM_URL" -o "$CACHED_PACKAGE.sha256" 2>/dev/null; then
        echo -e "${RED}ERROR:${NC} Could not download checksum."
        echo "FALLBACK_TO_HOMEBREW"
        exit 1
    fi
fi

# Verify checksum (required)
echo "Verifying download..."
if ! verify_checksum "$CACHED_PACKAGE" "$CACHED_PACKAGE.sha256"; then
    echo -e "${RED}ERROR:${NC} Checksum verification failed!"
    rm -f "$CACHED_PACKAGE"
    echo "FALLBACK_TO_HOMEBREW"
    exit 1
fi
echo -e "${GREEN}Checksum verified${NC}"

# Verify archive layout before extraction
if ! validate_tar_layout "$CACHED_PACKAGE"; then
    echo -e "${RED}ERROR:${NC} Archive validation failed."
    rm -f "$CACHED_PACKAGE"
    echo "FALLBACK_TO_HOMEBREW"
    exit 1
fi

# Extract
echo "Extracting..."
TEMP_EXTRACT=$(mktemp -d)
tar -xzf "$CACHED_PACKAGE" -C "$TEMP_EXTRACT"

rm -rf "$EXTRACT_DIR"
mkdir -p "$(dirname "$EXTRACT_DIR")"
mv "$TEMP_EXTRACT" "$EXTRACT_DIR"
TEMP_EXTRACT=""

# Verify extraction
if [[ ! -d "$EXTRACT_DIR/Frameworks" ]] || [[ ! -d "$EXTRACT_DIR/PlugIns" ]]; then
    echo -e "${RED}ERROR:${NC} Extraction failed - missing Frameworks or PlugIns"
    rm -rf "$EXTRACT_DIR"
    exit 1
fi

echo ""
echo -e "${GREEN}Qt frameworks ready!${NC}"
echo "$EXTRACT_DIR"
