#!/bin/bash
#
# package_qt_frameworks.sh - Package Qt frameworks for distribution
#
# This script packages the required Qt 5.15 x86_64 frameworks and dependencies
# into a tarball that can be committed to the repo (dist/) for download.
# This eliminates the need for users to install Homebrew.
#
# Usage:
#   ./package_qt_frameworks.sh [--output DIR]
#
# Requirements:
#   - Intel Homebrew with Qt 5 installed
#   - Run on macOS with x86_64 support
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/../dist}"
QT_PREFIX="/usr/local/opt/qt@5"
PACKAGE_NAME="qt-frameworks-x86_64"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${GREEN}==>${NC} ${1}"
}

print_error() {
    echo -e "${RED}ERROR:${NC} ${1}"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} ${1}"
}

latest_path_by_mtime() {
    local search_dir="$1"
    local name_glob="$2"
    local type="${3:-d}"

    find "$search_dir" -mindepth 1 -maxdepth 1 -type "$type" -name "$name_glob" -print0 2>/dev/null \
        | while IFS= read -r -d '' item; do
            mtime=$(stat -f "%m" "$item" 2>/dev/null || echo 0)
            printf '%s\t%s\n' "$mtime" "$item"
        done \
        | sort -nr \
        | head -1 \
        | cut -f2-
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--output DIR]"
            echo ""
            echo "Packages Qt 5.15 x86_64 frameworks for distribution."
            echo "Requires Intel Homebrew with qt@5 installed."
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Verify Qt installation
if [[ ! -d "$QT_PREFIX" ]]; then
    print_error "Qt 5 not found at $QT_PREFIX"
    echo "Install with: arch -x86_64 /usr/local/bin/brew install qt@5"
    exit 1
fi

QT_VERSION_PATH=$(latest_path_by_mtime "/usr/local/Cellar/qt@5" "*" "d")
if [[ -n "$QT_VERSION_PATH" ]]; then
    QT_VERSION=$(basename "$QT_VERSION_PATH")
else
    QT_VERSION=""
fi
if [[ -z "$QT_VERSION" ]]; then
    print_error "Could not determine Qt version"
    exit 1
fi

echo ""
echo -e "${BLUE}Qt Framework Packager${NC}"
echo "Qt Version: $QT_VERSION"
echo "Output: $OUTPUT_DIR"
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
print_step "Copying Qt frameworks..."
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
        echo "  Copied ${fw}.framework"
    else
        print_warning "${fw}.framework not found, skipping"
    fi
done

# Copy platform plugin
print_step "Copying platform plugins..."
mkdir -p "$PLUGINS_DIR/platforms"
if [[ -f "$QT_PREFIX/plugins/platforms/libqcocoa.dylib" ]]; then
    cp "$QT_PREFIX/plugins/platforms/libqcocoa.dylib" "$PLUGINS_DIR/platforms/"
    echo "  Copied libqcocoa.dylib"
fi

# Copy image format plugins
print_step "Copying image format plugins..."
mkdir -p "$PLUGINS_DIR/imageformats"
for plugin in "$QT_PREFIX/plugins/imageformats/"*.dylib; do
    if [[ -f "$plugin" ]]; then
        cp "$plugin" "$PLUGINS_DIR/imageformats/"
        echo "  Copied $(basename "$plugin")"
    fi
done

# Find and copy all Homebrew dependencies
print_step "Scanning for Homebrew dependencies..."
DEPS_DIR="$WORK_DIR/Dependencies"
mkdir -p "$DEPS_DIR"

COPIED_DEPS_FILE="$WORK_DIR/.copied_deps"
touch "$COPIED_DEPS_FILE"

copy_deps() {
    local binary="$1"

    while IFS= read -r dep; do
        # Only process /usr/local dependencies
        if [[ "$dep" == /usr/local/* ]]; then
            local dep_name
            dep_name=$(basename "$dep")

            # Skip if already copied
            if grep -Fqx -- "$dep_name" "$COPIED_DEPS_FILE"; then
                continue
            fi

            if [[ -f "$dep" ]]; then
                cp "$dep" "$DEPS_DIR/"
                echo "$dep_name" >> "$COPIED_DEPS_FILE"
                echo "  Copied $dep_name"

                # Recursively check this dependency
                copy_deps "$dep"
            fi
        fi
    done < <(otool -L "$binary" 2>/dev/null | awk 'NR>1 {print $1}' | grep "^/usr/local" || true)
}

# Scan all frameworks
for fw_dir in "$FRAMEWORKS_DIR"/*.framework; do
    if [[ -d "$fw_dir" ]]; then
        fw_name=$(basename "$fw_dir" .framework)
        for binary in "$fw_dir/Versions/5/$fw_name" "$fw_dir/Versions/A/$fw_name" "$fw_dir/$fw_name"; do
            if [[ -f "$binary" ]]; then
                copy_deps "$binary"
                break
            fi
        done
    fi
done

# Scan all plugins
for plugin in "$PLUGINS_DIR"/*/*.dylib; do
    if [[ -f "$plugin" ]]; then
        copy_deps "$plugin"
    fi
done

# Move dependencies to Frameworks dir (where they'll be installed)
print_step "Organizing dependencies..."
mv "$DEPS_DIR"/* "$FRAMEWORKS_DIR/" 2>/dev/null || true
rmdir "$DEPS_DIR" 2>/dev/null || true

# Count what we packaged
fw_count=$(find "$FRAMEWORKS_DIR" -name "*.framework" -type d | wc -l | tr -d ' ')
dylib_count=$(find "$FRAMEWORKS_DIR" -name "*.dylib" -type f | wc -l | tr -d ' ')
plugin_count=$(find "$PLUGINS_DIR" -name "*.dylib" -type f | wc -l | tr -d ' ')

echo ""
echo "Packaged: $fw_count frameworks, $dylib_count dylibs, $plugin_count plugins"

# Create metadata file
print_step "Creating metadata..."
cat > "$WORK_DIR/METADATA.txt" << EOF
Qt Frameworks Package for Worms W.M.D macOS Fix
================================================

Qt Version: $QT_VERSION
Architecture: x86_64
Created: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Source: Intel Homebrew (/usr/local/opt/qt@5)

Contents:
- Frameworks: $fw_count
- Dependencies: $dylib_count
- Plugins: $plugin_count

This package is part of the WormsWMD-macOS-Fix project.
https://github.com/cboyd0319/WormsWMD-macOS-Fix
EOF

# Create the tarball
print_step "Creating archive..."
mkdir -p "$OUTPUT_DIR"
ARCHIVE_NAME="${PACKAGE_NAME}-${QT_VERSION}.tar.gz"
ARCHIVE_PATH="$OUTPUT_DIR/$ARCHIVE_NAME"

cd "$WORK_DIR"
tar -czf "$ARCHIVE_PATH" Frameworks PlugIns METADATA.txt

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
