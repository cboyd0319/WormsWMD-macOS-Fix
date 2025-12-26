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

set -e

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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FORCE=false
CHECK_ONLY=false

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
    response=$(curl -sf "$GITHUB_API_URL" 2>/dev/null) || return 1

    local urls
    urls=$(echo "$response" | grep -o '"download_url": *"[^"]*qt-frameworks-x86_64-[^"]*\.tar\.gz"' | cut -d'"' -f4)
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
        echo "available"
        exit 0
    fi
    if select_remote_package && curl -sfI "$DOWNLOAD_URL" >/dev/null 2>&1; then
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
        if ! curl -sfI "$DOWNLOAD_URL" >/dev/null 2>&1; then
            echo -e "${YELLOW}Pre-built Qt frameworks not available.${NC}"
            echo "FALLBACK_TO_HOMEBREW"
            exit 1
        fi

        # Download with progress
        if ! curl -L --progress-bar -o "$CACHED_PACKAGE" "$DOWNLOAD_URL"; then
            echo -e "${RED}ERROR:${NC} Download failed"
            rm -f "$CACHED_PACKAGE"
            exit 1
        fi
    fi
fi

# Verify checksum if available
echo "Verifying download..."
if $USE_LOCAL; then
    local_checksum="${CACHED_PACKAGE}.sha256"
    if [[ -f "$local_checksum" ]]; then
        EXPECTED=$(cut -d' ' -f1 "$local_checksum")
        ACTUAL=$(shasum -a 256 "$CACHED_PACKAGE" | cut -d' ' -f1)

        if [[ "$EXPECTED" != "$ACTUAL" ]]; then
            echo -e "${RED}ERROR:${NC} Checksum verification failed!"
            echo "Expected: $EXPECTED"
            echo "Actual:   $ACTUAL"
            exit 1
        fi
        echo -e "${GREEN}Checksum verified${NC}"
    else
        echo -e "${YELLOW}Warning: Could not verify checksum (missing .sha256)${NC}"
    fi
else
    if curl -sf "$CHECKSUM_URL" -o "$CACHED_PACKAGE.sha256" 2>/dev/null; then
        EXPECTED=$(cat "$CACHED_PACKAGE.sha256" | cut -d' ' -f1)
        ACTUAL=$(shasum -a 256 "$CACHED_PACKAGE" | cut -d' ' -f1)

        if [[ "$EXPECTED" != "$ACTUAL" ]]; then
            echo -e "${RED}ERROR:${NC} Checksum verification failed!"
            echo "Expected: $EXPECTED"
            echo "Actual:   $ACTUAL"
            rm -f "$CACHED_PACKAGE"
            exit 1
        fi
        echo -e "${GREEN}Checksum verified${NC}"
    else
        echo -e "${YELLOW}Warning: Could not verify checksum (continuing anyway)${NC}"
    fi
fi

# Extract
echo "Extracting..."
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$CACHED_PACKAGE" -C "$EXTRACT_DIR"

# Verify extraction
if [[ ! -d "$EXTRACT_DIR/Frameworks" ]] || [[ ! -d "$EXTRACT_DIR/PlugIns" ]]; then
    echo -e "${RED}ERROR:${NC} Extraction failed - missing Frameworks or PlugIns"
    rm -rf "$EXTRACT_DIR"
    exit 1
fi

echo ""
echo -e "${GREEN}Qt frameworks ready!${NC}"
echo "$EXTRACT_DIR"
