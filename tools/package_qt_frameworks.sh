#!/bin/bash
#
# package_qt_frameworks.sh - Package Qt frameworks for distribution
#
# This script packages the required Qt 5.15 x86_64 frameworks and dependencies
# into a tarball that can be committed to the repo (dist/) for download.
# This eliminates the need for users to install Homebrew.
#
# Usage:
#   ./package_qt_frameworks.sh [--output DIR] [--qt-prefix DIR] [--version VERSION]
#
# Requirements:
#   - Intel Homebrew with Qt 5 installed, or an explicit x86_64 Qt prefix
#   - Run on macOS with x86_64 support
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
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/../dist}"
QT_PREFIX="${QT_PREFIX:-/usr/local/opt/qt@5}"
QT_PACKAGE_VERSION="${QT_PACKAGE_VERSION:-}"
QT_DEP_PREFIX="${QT_DEP_PREFIX:-}"
QT_PACKAGE_SOURCE_LABEL="${QT_PACKAGE_SOURCE_LABEL:-}"
QT_SOURCE_PROVENANCE_FILE="${QT_SOURCE_PROVENANCE_FILE:-}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1704067200}"
PACKAGE_NAME="qt-frameworks-x86_64"

# shellcheck disable=SC1091
source "$REPO_DIR/scripts/common.sh"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/ui.sh"
worms_color_init

for cmd in date find gzip lipo mktemp otool shasum tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        worms_print_error "Missing required command: $cmd"
        exit 1
    fi
done

print_help() {
    cat << EOF
Usage: $0 [--output DIR] [--qt-prefix DIR] [--version VERSION]

Packages Qt 5.15 x86_64 frameworks for distribution.

Options:
  --output DIR      Write archive and checksum to DIR (default: dist/)
  --qt-prefix DIR   Use this Qt installation prefix (default: $QT_PREFIX)
  --version VERSION Override package version used in metadata and file name
  --help, -h        Show this help message

Environment:
  QT_PREFIX           Default Qt installation prefix
  QT_PACKAGE_VERSION  Same as --version
  QT_DEP_PREFIX       Additional Homebrew-like dependency prefix
  QT_PACKAGE_SOURCE_LABEL
                      Override source label written to metadata
  QT_SOURCE_PROVENANCE_FILE
                      TSV lock/provenance file to include in the archive
  SOURCE_DATE_EPOCH   Reproducible timestamp seed (default: $SOURCE_DATE_EPOCH)

Examples:
  $0 --output dist
  $0 --qt-prefix /usr/local/opt/qt@5 --version 5.15.19
  $0 --qt-prefix /path/to/qt-5.15.19 --version 5.15.19
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                worms_print_error "--output requires a directory"
                exit 1
            fi
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --qt-prefix)
            if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                worms_print_error "--qt-prefix requires a directory"
                exit 1
            fi
            QT_PREFIX="$2"
            shift 2
            ;;
        --version)
            if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                worms_print_error "--version requires a version string"
                exit 1
            fi
            QT_PACKAGE_VERSION="$2"
            shift 2
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            worms_print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

format_epoch_utc() {
    local epoch="$1"

    date -u -r "$epoch" +"%Y-%m-%d %H:%M:%S UTC" 2>/dev/null \
        || date -u -d "@$epoch" +"%Y-%m-%d %H:%M:%S UTC" 2>/dev/null
}

format_epoch_touch() {
    local epoch="$1"

    date -u -r "$epoch" +"%Y%m%d%H%M.%S" 2>/dev/null \
        || date -u -d "@$epoch" +"%Y%m%d%H%M.%S" 2>/dev/null
}

determine_qt_version() {
    local qmake="$QT_PREFIX/bin/qmake"
    local header="$QT_PREFIX/lib/QtCore.framework/Headers/qglobal.h"
    local qt_version_path

    if [[ -n "$QT_PACKAGE_VERSION" ]]; then
        echo "$QT_PACKAGE_VERSION"
        return 0
    fi

    if [[ -x "$qmake" ]]; then
        "$qmake" -query QT_VERSION 2>/dev/null && return 0
    fi

    if [[ -f "$header" ]]; then
        awk '/QT_VERSION_STR/ {gsub(/"/, "", $3); print $3; exit}' "$header" 2>/dev/null && return 0
    fi

    if [[ "$QT_PREFIX" == "/usr/local/opt/qt@5" ]]; then
        qt_version_path=$(worms_latest_path_by_mtime "/usr/local/Cellar/qt@5" "*" "d" || true)
        if [[ -n "$qt_version_path" ]]; then
            basename "$qt_version_path"
            return 0
        fi
    fi

    return 1
}

qt_source_label() {
    if [[ -n "$QT_PACKAGE_SOURCE_LABEL" ]]; then
        echo "$QT_PACKAGE_SOURCE_LABEL"
        return 0
    fi

    if [[ "$QT_PREFIX" == "/usr/local/opt/qt@5" ]]; then
        echo "Intel Homebrew ($QT_PREFIX)"
    else
        echo "Qt prefix ($QT_PREFIX)"
    fi
}

dependency_path_allowed() {
    local path="$1"

    case "$path" in
        /usr/local/*)
            return 0
            ;;
    esac

    if [[ "$path" == "$QT_PREFIX"/* ]]; then
        return 0
    fi

    if [[ -n "$QT_DEP_PREFIX" ]] && [[ "$path" == "$QT_DEP_PREFIX"/* ]]; then
        return 0
    fi

    return 1
}

validate_packaged_binary() {
    local binary="$1"
    local archs

    archs=$(lipo -archs "$binary" 2>/dev/null || true)
    if [[ -z "$archs" ]]; then
        worms_print_error "Could not inspect architecture: $binary"
        return 1
    fi
    if ! echo "$archs" | tr ' ' '\n' | grep -qx "x86_64"; then
        worms_print_error "Packaged binary is missing x86_64 slice: $binary ($archs)"
        return 1
    fi
}

prune_framework_for_runtime() {
    local framework_dir="$1"

    rm -rf "$framework_dir/Headers"
    rm -rf "$framework_dir/Versions/5/Headers"
}

normalize_archive_inputs() {
    local touch_time="$1"

    find "$WORK_DIR" -exec touch -h -t "$touch_time" {} + 2>/dev/null || true
}

create_reproducible_archive() {
    local archive_path="$1"
    local tar_list="$WORK_DIR/.tar-list"

    (
        cd "$WORK_DIR" || exit 1
        {
            find Frameworks PlugIns -print
            printf '%s\n' METADATA.txt MANIFEST.txt
            if [[ -f SOURCE_PROVENANCE.tsv ]]; then
                printf '%s\n' SOURCE_PROVENANCE.tsv
            fi
        } | LC_ALL=C sort > "$tar_list"

        COPYFILE_DISABLE=1 tar \
            --format ustar \
            --uid 0 \
            --gid 0 \
            --uname root \
            --gname wheel \
            -cf - \
            -T "$tar_list" \
            | gzip -n > "$archive_path"
    )
}

# Verify Qt installation
if [[ ! -d "$QT_PREFIX" ]]; then
    worms_print_error "Qt 5 not found at $QT_PREFIX"
    echo "Install with: arch -x86_64 /usr/local/bin/brew install qt@5"
    echo "Or pass --qt-prefix /path/to/qt --version 5.15.x"
    exit 1
fi

QT_VERSION=$(determine_qt_version || true)
if [[ -z "$QT_VERSION" ]] || [[ ! "$QT_VERSION" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
    worms_print_error "Could not determine Qt version"
    echo "Pass --version 5.15.x when packaging from a custom Qt prefix."
    exit 1
fi
if ! worms_supported_qt5_version "$QT_VERSION"; then
    worms_print_error "Unsupported Qt version: $QT_VERSION"
    echo "This project packages only Qt 5.15.x for Worms W.M.D compatibility."
    exit 1
fi
worms_reject_control_chars "$QT_PREFIX" "QT_PREFIX"
worms_reject_control_chars "$QT_DEP_PREFIX" "QT_DEP_PREFIX"
worms_reject_control_chars "$QT_PACKAGE_SOURCE_LABEL" "QT_PACKAGE_SOURCE_LABEL"
worms_reject_control_chars "$QT_SOURCE_PROVENANCE_FILE" "QT_SOURCE_PROVENANCE_FILE"
CREATED_AT=$(format_epoch_utc "$SOURCE_DATE_EPOCH")
TOUCH_TIME=$(format_epoch_touch "$SOURCE_DATE_EPOCH")
SOURCE_LABEL=$(qt_source_label)
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

echo ""
echo -e "${BLUE}Qt Framework Packager${NC}"
echo "Qt Version: $QT_VERSION"
echo "Qt Prefix: $QT_PREFIX"
if [[ -n "$QT_DEP_PREFIX" ]]; then
    echo "Dependency Prefix: $QT_DEP_PREFIX"
fi
echo "Output: $OUTPUT_DIR"
echo "Source Date Epoch: $SOURCE_DATE_EPOCH"
echo ""

# Create working directory
WORK_DIR=$(mktemp -d)
FRAMEWORKS_DIR="$WORK_DIR/Frameworks"
PLUGINS_DIR="$WORK_DIR/PlugIns"
mkdir -p "$FRAMEWORKS_DIR" "$PLUGINS_DIR"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Copy Qt frameworks
worms_print_step "Copying Qt frameworks..."
FRAMEWORKS=(
    "QtCore"
    "QtGui"
    "QtWidgets"
    "QtOpenGL"
    "QtPrintSupport"
    "QtDBus"
    "QtSvg"
)

for fw in "${FRAMEWORKS[@]}"; do
    if [[ -d "$QT_PREFIX/lib/${fw}.framework" ]]; then
        cp -R "$QT_PREFIX/lib/${fw}.framework" "$FRAMEWORKS_DIR/"
        binary=$(worms_framework_binary "$FRAMEWORKS_DIR/${fw}.framework" "$fw" || true)
        if [[ -z "$binary" ]]; then
            worms_print_error "${fw}.framework copied but framework binary was not found"
            exit 1
        fi
        validate_packaged_binary "$binary"
        prune_framework_for_runtime "$FRAMEWORKS_DIR/${fw}.framework"
        echo "  Copied ${fw}.framework"
    else
        worms_print_error "${fw}.framework not found at $QT_PREFIX/lib"
        exit 1
    fi
done

# Copy platform plugin
worms_print_step "Copying platform plugins..."
mkdir -p "$PLUGINS_DIR/platforms"
if [[ -f "$QT_PREFIX/plugins/platforms/libqcocoa.dylib" ]]; then
    cp "$QT_PREFIX/plugins/platforms/libqcocoa.dylib" "$PLUGINS_DIR/platforms/"
    validate_packaged_binary "$PLUGINS_DIR/platforms/libqcocoa.dylib"
    echo "  Copied libqcocoa.dylib"
else
    worms_print_error "Required platform plugin not found: $QT_PREFIX/plugins/platforms/libqcocoa.dylib"
    exit 1
fi

# Copy image format plugins
worms_print_step "Copying image format plugins..."
mkdir -p "$PLUGINS_DIR/imageformats"
for plugin in "$QT_PREFIX/plugins/imageformats/"*.dylib; do
    if [[ -f "$plugin" ]]; then
        cp "$plugin" "$PLUGINS_DIR/imageformats/"
        validate_packaged_binary "$PLUGINS_DIR/imageformats/$(basename "$plugin")"
        echo "  Copied $(basename "$plugin")"
    fi
done

# Find and copy all Homebrew dependencies
worms_print_step "Scanning for Homebrew dependencies..."
DEPS_DIR="$WORK_DIR/Dependencies"
mkdir -p "$DEPS_DIR"

COPIED_DEPS_FILE="$WORK_DIR/.copied_deps"
touch "$COPIED_DEPS_FILE"

copy_deps() {
    local binary="$1"

    while IFS= read -r dep; do
        # Only package external dylib dependencies that can travel with the app.
        if dependency_path_allowed "$dep"; then
            [[ "$dep" == *.dylib ]] || continue
            local dep_name
            dep_name=$(basename "$dep")

            # Skip if already copied
            if grep -Fqx -- "$dep_name" "$COPIED_DEPS_FILE"; then
                continue
            fi

            if [[ -f "$dep" ]]; then
                cp "$dep" "$DEPS_DIR/"
                validate_packaged_binary "$DEPS_DIR/$dep_name"
                echo "$dep_name" >> "$COPIED_DEPS_FILE"
                echo "  Copied $dep_name"

                # Recursively check this dependency
                copy_deps "$dep"
            fi
        fi
    done < <(
        worms_otool_dependencies "$binary" \
            | while IFS= read -r candidate; do
                if dependency_path_allowed "$candidate"; then
                    printf '%s\n' "$candidate"
                fi
            done
    )
}

# Scan all frameworks
for fw_dir in "$FRAMEWORKS_DIR"/*.framework; do
    if [[ -d "$fw_dir" ]]; then
        fw_name=$(basename "$fw_dir" .framework)
        binary=$(worms_framework_binary "$fw_dir" "$fw_name" || true)
        if [[ -n "$binary" ]]; then
            copy_deps "$binary"
        fi
    fi
done

# Scan all plugins
for plugin in "$PLUGINS_DIR"/*/*.dylib; do
    if [[ -f "$plugin" ]]; then
        copy_deps "$plugin"
    fi
done

# Move dependencies to Frameworks dir (where they'll be installed)
worms_print_step "Organizing dependencies..."
mv "$DEPS_DIR"/* "$FRAMEWORKS_DIR/" 2>/dev/null || true
rmdir "$DEPS_DIR" 2>/dev/null || true

# Count what we packaged
fw_count=$(find "$FRAMEWORKS_DIR" -name "*.framework" -type d | wc -l | tr -d ' ')
dylib_count=$(find "$FRAMEWORKS_DIR" -name "*.dylib" -type f | wc -l | tr -d ' ')
plugin_count=$(find "$PLUGINS_DIR" -name "*.dylib" -type f | wc -l | tr -d ' ')

echo ""
echo "Packaged: $fw_count frameworks, $dylib_count dylibs, $plugin_count plugins"

if [[ -n "$QT_SOURCE_PROVENANCE_FILE" ]]; then
    if [[ ! -f "$QT_SOURCE_PROVENANCE_FILE" ]]; then
        worms_print_error "Source provenance file not found: $QT_SOURCE_PROVENANCE_FILE"
        exit 1
    fi
    cp "$QT_SOURCE_PROVENANCE_FILE" "$WORK_DIR/SOURCE_PROVENANCE.tsv"
fi

# Create metadata file
worms_print_step "Creating metadata..."
cat > "$WORK_DIR/METADATA.txt" << EOF
Qt Frameworks Package for Worms W.M.D macOS Fix
================================================

Qt Version: $QT_VERSION
Architecture: x86_64
Created: $CREATED_AT
Source: $SOURCE_LABEL
Source Date Epoch: $SOURCE_DATE_EPOCH

Contents:
- Frameworks: $fw_count
- Dependencies: $dylib_count
- Plugins: $plugin_count

This package is part of the WormsWMD-macOS-Fix project.
https://github.com/cboyd0319/WormsWMD-macOS-Fix
EOF

# Create package manifest before archiving
worms_print_step "Creating manifest..."
manifest_inputs=(Frameworks PlugIns METADATA.txt)
if [[ -f "$WORK_DIR/SOURCE_PROVENANCE.tsv" ]]; then
    manifest_inputs+=(SOURCE_PROVENANCE.tsv)
fi
worms_write_manifest "$WORK_DIR" "$WORK_DIR/MANIFEST.txt" "${manifest_inputs[@]}"
worms_verify_manifest "$WORK_DIR" "$WORK_DIR/MANIFEST.txt"

# Normalize timestamps for reproducible archives.
normalize_archive_inputs "$TOUCH_TIME"

# Create the tarball
worms_print_step "Creating archive..."
ARCHIVE_NAME="${PACKAGE_NAME}-${QT_VERSION}.tar.gz"
ARCHIVE_PATH="$OUTPUT_DIR/$ARCHIVE_NAME"

create_reproducible_archive "$ARCHIVE_PATH"

# Calculate checksum
CHECKSUM=$(shasum -a 256 "$ARCHIVE_PATH" | cut -d' ' -f1)
echo "$CHECKSUM  $ARCHIVE_NAME" > "$OUTPUT_DIR/${ARCHIVE_NAME}.sha256"

# Get size
SIZE=$(du -h "$ARCHIVE_PATH" | cut -f1)

echo ""
echo -e "${GREEN}Package created successfully!${NC}"
echo ""
echo "Archive: $ARCHIVE_PATH"
echo "Size: $SIZE"
echo "SHA256: $CHECKSUM"
echo ""
echo "Commit these files to the repo dist/ folder:"
echo "  $ARCHIVE_PATH"
echo "  ${ARCHIVE_PATH}.sha256"
