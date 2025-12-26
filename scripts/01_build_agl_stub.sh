#!/bin/bash
#
# 01_build_agl_stub.sh - Build AGL stub library for macOS 26+
#
# This script compiles the AGL stub library that provides empty
# implementations of all AGL functions removed in macOS 26.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")/src"
BUILD_DIR="/tmp/agl_stub_build"
LOGGING_PRESET="${WORMSWMD_LOGGING_INITIALIZED:-}"

source "$SCRIPT_DIR/logging.sh"
worms_log_init "01_build_agl_stub"
worms_debug_init

if [[ -z "$LOGGING_PRESET" ]]; then
    echo "Log file: $LOG_FILE"
    if worms_bool_true "${WORMSWMD_DEBUG:-}"; then
        echo "Trace log: $TRACE_FILE"
    fi
fi

echo "=== Building AGL Stub Library ==="

# Create build directory
mkdir -p "$BUILD_DIR"

# Compile for x86_64 (required for Rosetta 2 compatibility)
echo "Compiling agl_stub.c for x86_64..."
arch -x86_64 clang -arch x86_64 \
    -dynamiclib \
    -o "$BUILD_DIR/AGL" \
    -install_name "@executable_path/../Frameworks/AGL.framework/Versions/A/AGL" \
    -framework OpenGL \
    -compatibility_version 1.0.0 \
    -current_version 1.0.0 \
    "$SRC_DIR/agl_stub.c"

# Verify the build succeeded
if [[ ! -f "$BUILD_DIR/AGL" ]]; then
    echo "ERROR: Failed to build AGL stub - output file not found"
    exit 1
fi

echo "AGL stub built successfully at: $BUILD_DIR/AGL"
echo ""
echo "Library info:"
file "$BUILD_DIR/AGL"
otool -L "$BUILD_DIR/AGL" | head -5
