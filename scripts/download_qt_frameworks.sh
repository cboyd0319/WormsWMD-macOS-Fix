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

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$REPO_DIR/dist"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wormswmd-fix"

GITHUB_REPO="cboyd0319/WormsWMD-macOS-Fix"
QT_DIST_REF="${WORMSWMD_QT_DIST_REF:-c1592eb5cc1c2e4d61b5616c5811b42503533781}"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}/contents/dist?ref=${QT_DIST_REF}"
DOWNLOAD_URL=""
CHECKSUM_URL=""
PACKAGE_NAME=""
QT_VERSION=""
USE_LOCAL=false
CACHED_PACKAGE=""
EXTRACT_DIR=""
TEMP_EXTRACT=""
CHECKSUM_TMP=""
TEMP_ARCHIVE_DIR=""
INSPECTED_ARCHIVE=""

# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ui.sh"
worms_color_init

FORCE=false
CHECK_ONLY=false

CURL_BASE=(--proto '=https' --tlsv1.2 --retry 3 --retry-delay 1 --retry-connrefused --max-filesize $((64 * 1024 * 1024)))

cleanup() {
    if [[ -n "$TEMP_EXTRACT" ]] && [[ -d "$TEMP_EXTRACT" ]]; then
        rm -rf "$TEMP_EXTRACT"
    fi
    if [[ -n "$CHECKSUM_TMP" ]] && [[ -f "$CHECKSUM_TMP" ]]; then
        rm -f "$CHECKSUM_TMP"
    fi
    if [[ -n "$TEMP_ARCHIVE_DIR" ]] && [[ -d "$TEMP_ARCHIVE_DIR" ]]; then
        rm -rf "$TEMP_ARCHIVE_DIR"
    fi
}

trap cleanup EXIT

for cmd in curl tar shasum mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}ERROR:${NC} Missing required command: $cmd"
        exit 1
    fi
done

if [[ ! "$QT_DIST_REF" =~ ^[a-fA-F0-9]{40}$ ]]; then
    echo -e "${RED}ERROR:${NC} WORMSWMD_QT_DIST_REF must be a full commit SHA."
    exit 1
fi

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
    local raw_entry entry
    local listing

    if ! listing=$(tar -tzf "$archive" 2>/dev/null); then
        echo -e "${RED}ERROR:${NC} Unable to read archive contents."
        return 1
    fi

    if ! worms_validate_tar_no_duplicate_entries "$archive"; then
        echo -e "${RED}ERROR:${NC} Archive contains duplicate members."
        return 1
    fi

    while IFS= read -r raw_entry; do
        [[ -z "$raw_entry" ]] && continue
        entry="${raw_entry#./}"
        while [[ "$entry" == */ ]]; do
            entry="${entry%/}"
        done
        [[ -z "$entry" ]] && continue

        if worms_path_has_parent_escape "$entry"; then
            echo -e "${RED}ERROR:${NC} Unsafe path in archive: $entry"
            return 1
        fi

        case "$entry" in
            Frameworks|Frameworks/*|PlugIns|PlugIns/*|METADATA.txt|MANIFEST.txt|SOURCE_PROVENANCE.tsv)
                ;;
            *)
                echo -e "${RED}ERROR:${NC} Unexpected entry in archive: $entry"
                return 1
                ;;
        esac
    done <<< "$listing"

    if ! worms_validate_tar_entry_metadata "$archive" allow-relative-symlinks; then
        echo -e "${RED}ERROR:${NC} Unsafe archive entry metadata."
        return 1
    fi
}

validate_archive_metadata() {
    local archive="$1"
    local expected_version="${2:-}"
    local metadata version arch

    if ! metadata=$(tar -xOf "$archive" METADATA.txt 2>/dev/null); then
        echo -e "${RED}ERROR:${NC} Archive is missing METADATA.txt."
        return 1
    fi

    version=$(awk -F': ' '/^Qt Version:/ {print $2; exit}' <<< "$metadata")
    arch=$(awk -F': ' '/^Architecture:/ {print $2; exit}' <<< "$metadata")

    if [[ -z "$version" ]]; then
        echo -e "${RED}ERROR:${NC} Archive metadata is missing Qt Version."
        return 1
    fi
    if [[ -n "$expected_version" ]] && [[ "$version" != "$expected_version" ]]; then
        echo -e "${RED}ERROR:${NC} Archive version mismatch: expected $expected_version, found $version."
        return 1
    fi
    if [[ "$arch" != "x86_64" ]]; then
        echo -e "${RED}ERROR:${NC} Archive architecture must be x86_64; found ${arch:-unknown}."
        return 1
    fi
}

validate_macho_x86_64() {
    local binary="$1"
    local archs

    command -v lipo >/dev/null 2>&1 || return 0
    archs=$(lipo -archs "$binary" 2>/dev/null || true)
    if [[ -z "$archs" ]]; then
        echo -e "${RED}ERROR:${NC} Unable to inspect Mach-O architecture: $binary"
        return 1
    fi

    if ! echo "$archs" | tr ' ' '\n' | grep -qx "x86_64"; then
        echo -e "${RED}ERROR:${NC} Missing x86_64 slice: $binary ($archs)"
        return 1
    fi
}

validate_extracted_package() {
    local extract_dir="$1"
    local expected_version="${2:-}"
    local required_fw binary plugin dylib
    local required_frameworks=(
        QtCore
        QtGui
        QtWidgets
        QtOpenGL
        QtPrintSupport
        QtDBus
        QtSvg
    )

    if [[ ! -d "$extract_dir/Frameworks" ]] || [[ ! -d "$extract_dir/PlugIns" ]]; then
        echo -e "${RED}ERROR:${NC} Package is missing Frameworks or PlugIns."
        return 1
    fi

    if [[ ! -f "$extract_dir/METADATA.txt" ]]; then
        echo -e "${RED}ERROR:${NC} Package is missing METADATA.txt."
        return 1
    fi
    if [[ -n "$expected_version" ]] && ! grep -qx "Qt Version: $expected_version" "$extract_dir/METADATA.txt"; then
        echo -e "${RED}ERROR:${NC} Extracted package metadata does not match $expected_version."
        return 1
    fi
    if ! grep -qx "Architecture: x86_64" "$extract_dir/METADATA.txt"; then
        echo -e "${RED}ERROR:${NC} Extracted package metadata does not declare x86_64."
        return 1
    fi

    for required_fw in "${required_frameworks[@]}"; do
        if [[ ! -d "$extract_dir/Frameworks/${required_fw}.framework" ]]; then
            echo -e "${RED}ERROR:${NC} Package is missing ${required_fw}.framework."
            return 1
        fi
        binary=$(worms_framework_binary "$extract_dir/Frameworks/${required_fw}.framework" "$required_fw" || true)
        if [[ -z "$binary" ]]; then
            echo -e "${RED}ERROR:${NC} Package is missing ${required_fw} framework binary."
            return 1
        fi
        validate_macho_x86_64 "$binary" || return 1
    done

    if [[ ! -f "$extract_dir/PlugIns/platforms/libqcocoa.dylib" ]]; then
        echo -e "${RED}ERROR:${NC} Package is missing PlugIns/platforms/libqcocoa.dylib."
        return 1
    fi
    if [[ ! -f "$extract_dir/PlugIns/imageformats/libqsvg.dylib" ]]; then
        echo -e "${RED}ERROR:${NC} Package is missing PlugIns/imageformats/libqsvg.dylib."
        return 1
    fi

    while IFS= read -r -d '' plugin; do
        validate_macho_x86_64 "$plugin" || return 1
    done < <(find "$extract_dir/PlugIns" -type f -name "*.dylib" -print0 2>/dev/null)

    while IFS= read -r -d '' dylib; do
        validate_macho_x86_64 "$dylib" || return 1
    done < <(find "$extract_dir/Frameworks" -maxdepth 1 -type f -name "*.dylib" -print0 2>/dev/null)

    if [[ -f "$extract_dir/MANIFEST.txt" ]]; then
        worms_verify_manifest "$extract_dir" "$extract_dir/MANIFEST.txt" || {
            echo -e "${RED}ERROR:${NC} Package manifest verification failed."
            return 1
        }
    fi
}

ensure_extracted_manifest() {
    local extract_dir="$1"
    local manifest_inputs=(Frameworks PlugIns METADATA.txt)

    if [[ -f "$extract_dir/SOURCE_PROVENANCE.tsv" ]]; then
        manifest_inputs+=(SOURCE_PROVENANCE.tsv)
    fi

    if [[ ! -f "$extract_dir/MANIFEST.txt" ]]; then
        worms_write_manifest "$extract_dir" "$extract_dir/MANIFEST.txt" "${manifest_inputs[@]}"
    fi

    worms_verify_manifest "$extract_dir" "$extract_dir/MANIFEST.txt" || {
        echo -e "${RED}ERROR:${NC} Package manifest verification failed."
        return 1
    }
}

verify_local_package() {
    local package="$1"
    local version verify_dir archive_dir archive_copy expected_sha256 status=0

    version=$(worms_qt_package_version "$package") || return 1
    [[ -f "${package}.sha256" ]] || return 1
    expected_sha256=$(read_checksum "${package}.sha256") || return 1
    verify_checksum "$package" "${package}.sha256" || return 1

    archive_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-qt-archive.XXXXXX")
    archive_copy="$archive_dir/package.tar.gz"
    if ! worms_copy_and_inspect_archive \
        "$package" "$archive_copy" qt "$expected_sha256" --quiet; then
        rm -rf "$archive_dir"
        return 1
    fi
    if ! validate_tar_layout "$archive_copy" \
        || ! validate_archive_metadata "$archive_copy" "$version"; then
        rm -rf "$archive_dir"
        return 1
    fi

    verify_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-qt-extract.XXXXXX")
    if ! tar -xzf "$archive_copy" -C "$verify_dir" 2>/dev/null; then
        rm -rf "$verify_dir" "$archive_dir"
        return 1
    fi
    validate_extracted_package "$verify_dir" "$version" || status=1
    rm -rf "$verify_dir" "$archive_dir"
    return "$status"
}

select_local_package() {
    local best_version=""
    local best_path=""

    if [[ ! -d "$DIST_DIR" ]]; then
        return 1
    fi

    while IFS= read -r -d '' package; do
        local version
        version=$(worms_qt_package_version "$package" || true)
        [[ -n "$version" ]] || continue
        verify_local_package "$package" || continue

        if [[ -z "$best_version" ]] || worms_version_ge "$version" "$best_version"; then
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
        version=$(worms_qt_package_version "$name" || true)
        [[ -n "$version" ]] || continue

        if [[ -z "$best_version" ]] || worms_version_ge "$version" "$best_version"; then
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
    if validate_extracted_package "$EXTRACT_DIR" "$QT_VERSION" \
        && ensure_extracted_manifest "$EXTRACT_DIR"; then
        echo -e "${GREEN}Using cached Qt frameworks${NC}"
        echo "$EXTRACT_DIR"
        exit 0
    fi
    echo -e "${YELLOW}Cached Qt frameworks failed validation; refreshing cache.${NC}"
    rm -rf "$EXTRACT_DIR"
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
    checksum_path="${CACHED_PACKAGE}.sha256"
    if [[ ! -f "$checksum_path" ]]; then
        echo -e "${RED}ERROR:${NC} Missing checksum for local package: $checksum_path"
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
    $USE_LOCAL || rm -f "$CACHED_PACKAGE"
    echo "FALLBACK_TO_HOMEBREW"
    exit 1
fi
echo -e "${GREEN}Checksum verified${NC}"

expected_package_sha256=$(read_checksum "$CACHED_PACKAGE.sha256") || {
    echo -e "${RED}ERROR:${NC} Invalid package checksum file."
    echo "FALLBACK_TO_HOMEBREW"
    exit 1
}
TEMP_ARCHIVE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-qt-archive.XXXXXX")
INSPECTED_ARCHIVE="$TEMP_ARCHIVE_DIR/$PACKAGE_NAME"
if ! worms_copy_and_inspect_archive \
    "$CACHED_PACKAGE" "$INSPECTED_ARCHIVE" qt "$expected_package_sha256" --quiet; then
    echo -e "${RED}ERROR:${NC} Archive safety inspection failed."
    $USE_LOCAL || rm -f "$CACHED_PACKAGE"
    echo "FALLBACK_TO_HOMEBREW"
    exit 1
fi

# Verify archive layout before extraction
if ! validate_tar_layout "$INSPECTED_ARCHIVE"; then
    echo -e "${RED}ERROR:${NC} Archive validation failed."
    $USE_LOCAL || rm -f "$CACHED_PACKAGE"
    echo "FALLBACK_TO_HOMEBREW"
    exit 1
fi
if ! validate_archive_metadata "$INSPECTED_ARCHIVE" "$QT_VERSION"; then
    echo -e "${RED}ERROR:${NC} Archive metadata validation failed."
    $USE_LOCAL || rm -f "$CACHED_PACKAGE"
    echo "FALLBACK_TO_HOMEBREW"
    exit 1
fi

# Extract
echo "Extracting..."
TEMP_EXTRACT=$(mktemp -d)
tar -xzf "$INSPECTED_ARCHIVE" -C "$TEMP_EXTRACT"

rm -rf "$EXTRACT_DIR"
mkdir -p "$(dirname "$EXTRACT_DIR")"
if ! validate_extracted_package "$TEMP_EXTRACT" "$QT_VERSION" \
    || ! ensure_extracted_manifest "$TEMP_EXTRACT"; then
    echo -e "${RED}ERROR:${NC} Extracted Qt package validation failed."
    rm -rf "$TEMP_EXTRACT"
    TEMP_EXTRACT=""
    exit 1
fi
mv "$TEMP_EXTRACT" "$EXTRACT_DIR"
TEMP_EXTRACT=""

echo ""
echo -e "${GREEN}Qt frameworks ready!${NC}"
echo "$EXTRACT_DIR"
