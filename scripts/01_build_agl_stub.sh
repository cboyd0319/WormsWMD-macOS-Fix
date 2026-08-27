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

compile_arch() {
    local arch="$1"
    local output="$2"
    local compiler_output

    echo "Compiling agl_stub.c for $arch..."
    if ! compiler_output=$(clang -arch "$arch" \
        -dynamiclib \
        -o "$output" \
        -install_name "@executable_path/../Frameworks/AGL.framework/Versions/A/AGL" \
        -framework OpenGL \
        -compatibility_version 1.0.0 \
        -current_version 1.0.0 \
        "$SRC_DIR/agl_stub.c" 2>&1); then
        echo "ERROR: Failed to compile AGL stub for $arch"
        [[ -n "$compiler_output" ]] && echo "$compiler_output"
        return 1
    fi
}

# x86_64 is required for Rosetta 2; arm64 keeps the stub universal.
compile_arch "x86_64" "$BUILD_DIR/AGL_x86_64"
compile_arch "arm64" "$BUILD_DIR/AGL_arm64"

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

# Clean up architecture-specific files
rm -f "$BUILD_DIR/AGL_x86_64" "$BUILD_DIR/AGL_arm64"

# Verify the build succeeded
if [[ ! -f "$BUILD_DIR/AGL" ]]; then
    echo "ERROR: Failed to build AGL stub - output file not found"
    exit 1
fi

echo "AGL stub built successfully at: $BUILD_DIR/AGL"
echo ""
echo "Library info:"
file "$BUILD_DIR/AGL"
lipo -info "$BUILD_DIR/AGL"
otool -L "$BUILD_DIR/AGL" | head -5
