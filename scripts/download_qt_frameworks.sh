#!/bin/bash
#
# download_qt_frameworks.sh - Download pre-built Qt frameworks
#
# Downloads pre-packaged Qt 5.15 x86_64 frameworks from GitHub Releases,
# eliminating the need for users to install Homebrew.
#
# Usage:
#   ./download_qt_frameworks.sh [--force]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wormswmd-fix"
QT_VERSION="5.15.18"
PACKAGE_NAME="qt-frameworks-x86_64-${QT_VERSION}.tar.gz"

# GitHub Release URL - update this when releasing new Qt package
GITHUB_REPO="cboyd0319/WormsWMD-macOS-Fix"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v1.3.0/${PACKAGE_NAME}"
CHECKSUM_URL="${DOWNLOAD_URL}.sha256"

# Fallback: if pre-built not available, we'll indicate to use Homebrew
PREBUILD_AVAILABLE=true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)
            FORCE=true
            shift
            ;;
        --check)
            # Just check if pre-built is available
            if $PREBUILD_AVAILABLE && curl -sfI "$DOWNLOAD_URL" >/dev/null 2>&1; then
                echo "available"
            else
                echo "unavailable"
            fi
            exit 0
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

# Create cache directory
mkdir -p "$CACHE_DIR"

CACHED_PACKAGE="$CACHE_DIR/$PACKAGE_NAME"
EXTRACT_DIR="$CACHE_DIR/qt-frameworks"

# Check if already cached and extracted
if [[ -d "$EXTRACT_DIR/Frameworks" ]] && [[ -d "$EXTRACT_DIR/PlugIns" ]] && ! $FORCE; then
    echo -e "${GREEN}Using cached Qt frameworks${NC}"
    echo "$EXTRACT_DIR"
    exit 0
fi

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

# Verify checksum if available
echo "Verifying download..."
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
