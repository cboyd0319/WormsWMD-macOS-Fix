#!/bin/bash
#
# 01_build_agl_stub.sh - Build AGL stub library for macOS 26+
#
# This script compiles the AGL stub library that provides empty
# implementations of all AGL functions removed in macOS 26.
#

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")/src"
if [[ -z "${BUILD_DIR:-}" ]]; then
    BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agl_stub_build.XXXXXX")
fi
export BUILD_DIR
LOGGING_PRESET="${WORMSWMD_LOGGING_INITIALIZED:-}"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/logging.sh"
worms_log_init "01_build_agl_stub"
worms_debug_init

if [[ -z "$LOGGING_PRESET" ]]; then
    echo "Log file: $LOG_FILE"
    if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
        echo "Trace log: $TRACE_FILE"
    fi
fi

echo "=== Building AGL Stub Library (Universal Binary) ==="

# Create build directory
mkdir -p "$BUILD_DIR"

# Resolve the compiler and SDK together; PATH or SDKROOT can select mismatched tools.
compiler=$(xcrun --toolchain default --sdk macosx --find clang)
sdk_path=$(xcrun --toolchain default --sdk macosx --show-sdk-path)
echo "AGL build: Compiler: $compiler"

compile_arch() {
    local arch="$1"
    local output="$2"
    local compiler_output
    local minimum_version=10.9

    [[ "$arch" != arm64 ]] || minimum_version=11.0

    echo "Compiling agl_stub.c for $arch..."
    if ! compiler_output=$("$compiler" -arch "$arch" \
        -dynamiclib \
        -isysroot "$sdk_path" \
        -mmacosx-version-min="$minimum_version" \
        -o "$output" \
        -install_name "@executable_path/../Frameworks/AGL.framework/Versions/A/AGL" \
        -compatibility_version 1.0.0 \
        -current_version 1.0.0 \
        "$SRC_DIR/agl_stub.c" 2>&1); then
        echo "ERROR: Failed to compile AGL stub for $arch"
        if [[ -n "$compiler_output" ]]; then
            printf '%s\n' "$compiler_output" | sed 's/^/AGL build: /'
        fi
        return 1
    fi
}

# Use one SDK for both slices. If the selected SDK cannot link, try installed
# sibling macOS SDKs without changing xcode-select or any system files.
sdk_candidates=("$sdk_path")
for candidate in "$(dirname "$sdk_path")"/MacOSX*.sdk; do
    [[ -d "$candidate" ]] || continue
    [[ "$(cd "$candidate" && pwd -P)" != "$(cd "$sdk_path" && pwd -P)" ]] || continue
    sdk_candidates+=("$candidate")
done
built=false
for sdk_path in "${sdk_candidates[@]}"; do
    echo "AGL build: SDK: $sdk_path"
    # x86_64 is required for the game under Rosetta; never ship an arm64-only stub.
    if compile_arch "x86_64" "$BUILD_DIR/AGL_x86_64" \
        && compile_arch "arm64" "$BUILD_DIR/AGL_arm64"; then
        built=true
        break
    fi
    echo "AGL build: Trying another installed macOS SDK if available."
done
if ! "$built"; then
    echo "ERROR: No installed macOS SDK could build both required AGL slices."
    echo "AGL build: Update Apple Command Line Tools, then retry the fix."
    exit 1
fi

# Create universal binary
echo "Creating universal binary..."
if ! lipo_output=$(lipo -create \
    "$BUILD_DIR/AGL_x86_64" \
    "$BUILD_DIR/AGL_arm64" \
    -output "$BUILD_DIR/AGL" 2>&1); then
    echo "ERROR: Failed to create universal AGL stub"
    [[ -n "$lipo_output" ]] && echo "$lipo_output"
    exit 1
fi

# Verify the build succeeded
if [[ ! -f "$BUILD_DIR/AGL" ]]; then
    echo "ERROR: Failed to build AGL stub - output file not found"
    exit 1
fi
for arch in x86_64 arm64; do
    if ! lipo "$BUILD_DIR/AGL" -verify_arch "$arch"; then
        echo "ERROR: Built AGL stub is missing the required $arch architecture."
        exit 1
    fi
done

# Clean up architecture-specific files only after the combined output verifies.
rm -f "$BUILD_DIR/AGL_x86_64" "$BUILD_DIR/AGL_arm64"

echo "AGL stub built successfully at: $BUILD_DIR/AGL"
echo ""
echo "Library info:"
file "$BUILD_DIR/AGL"
lipo -info "$BUILD_DIR/AGL"
otool -L "$BUILD_DIR/AGL" | head -5
