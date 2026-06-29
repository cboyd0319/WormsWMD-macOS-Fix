#!/bin/bash
#
# Regression check for issue #12 missing AGL stub partial installs.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() {
    printf 'issue #12 AGL install failure check failed: %s\n' "$*" >&2
    exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-issue12.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

agl_build_dir="$tmp_dir/agl-build"
if grep -Fq 'arch -x86_64 clang' "$ROOT_DIR/scripts/01_build_agl_stub.sh"; then
    fail "AGL build script still runs clang under Rosetta instead of using native cross-compilation"
fi
BUILD_DIR="$agl_build_dir" "$ROOT_DIR/scripts/01_build_agl_stub.sh" >/dev/null \
    || fail "AGL build script failed to build the universal stub"
agl_archs=$(lipo -archs "$agl_build_dir/AGL" 2>/dev/null || true)
echo "$agl_archs" | tr ' ' '\n' | grep -qx "x86_64" \
    || fail "AGL build output is missing x86_64 architecture: ${agl_archs:-unknown}"

make_game_app() {
    local game_app="$1"

    mkdir -p "$game_app/Contents/MacOS"
    printf '#!/bin/bash\nexit 0\n' > "$game_app/Contents/MacOS/Worms W.M.D"
    chmod +x "$game_app/Contents/MacOS/Worms W.M.D"
}

make_qt_framework_sources() {
    local qt_prefix="$1"
    local fw

    shift
    mkdir -p "$qt_prefix/lib" "$qt_prefix/plugins/platforms" "$qt_prefix/plugins/imageformats"
    for fw in "$@"; do
        mkdir -p "$qt_prefix/lib/$fw.framework/Versions/5"
        touch "$qt_prefix/lib/$fw.framework/Versions/5/$fw"
    done
}

make_installed_frameworks() {
    local game_app="$1"
    local fw

    for fw in QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus QtSvg; do
        mkdir -p "$game_app/Contents/Frameworks/$fw.framework/Versions/5"
        touch "$game_app/Contents/Frameworks/$fw.framework/Versions/5/$fw"
    done
    mkdir -p "$game_app/Contents/Frameworks/AGL.framework/Versions/A"
    touch "$game_app/Contents/Frameworks/AGL.framework/Versions/A/AGL"
}

write_verify_stubs() {
    local bin_dir="$1"

    mkdir -p "$bin_dir"
    cat > "$bin_dir/lipo" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-archs" ]]; then
    if [[ "${2:-}" == *"AGL.framework"* ]]; then
        printf '%s\n' "${WORMS_TEST_AGL_ARCHS:-x86_64}"
    else
        printf '%s\n' "x86_64"
    fi
    exit 0
fi
exit 1
STUB
    cat > "$bin_dir/otool" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-L" ]]; then
    printf '%s:\n' "${2:-binary}"
    printf '\t@rpath/QtCore.framework/Versions/5/QtCore (compatibility version 5.15.0, current version 5.15.19)\n'
    printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
    exit 0
fi
exit 1
STUB
    cat > "$bin_dir/sw_vers" <<'STUB'
#!/bin/bash
case "${1:-}" in
    -productName) printf '%s\n' "macOS" ;;
    -productVersion) printf '%s\n' "26.0.1" ;;
    *) exit 1 ;;
esac
STUB
    cat > "$bin_dir/uname" <<'STUB'
#!/bin/bash
printf '%s\n' "x86_64"
STUB
    cat > "$bin_dir/codesign" <<'STUB'
#!/bin/bash
printf '%s\n' "adhoc" >&2
exit 0
STUB
    cat > "$bin_dir/xattr" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$bin_dir/lipo" "$bin_dir/otool" "$bin_dir/sw_vers" "$bin_dir/uname" "$bin_dir/codesign" "$bin_dir/xattr"
}

game_app="$tmp_dir/missing-agl/Worms W.M.D.app"
build_dir="$tmp_dir/empty-build"
make_game_app "$game_app"
mkdir -p "$build_dir"

set +e
output=$(
    GAME_APP="$game_app" \
        BUILD_DIR="$build_dir" \
        "$ROOT_DIR/scripts/04_fix_library_paths.sh" 2>&1
)
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
    fail "library path fixer succeeded without a built AGL stub"
fi

if ! grep -Fq "ERROR: AGL stub not found at $build_dir/AGL" <<< "$output"; then
    fail "missing AGL stub did not produce the expected hard error: $output"
fi

if grep -Fq "Library path fixes complete." <<< "$output"; then
    fail "library path fixer continued after the missing AGL stub error"
fi

if [[ -e "$game_app/Contents/Frameworks/AGL.framework" ]]; then
    fail "library path fixer created an AGL framework without a built stub"
fi

stale_agl_game_app="$tmp_dir/stale-agl-links/Worms W.M.D.app"
stale_bin_dir="$tmp_dir/stale-agl-bin"
make_game_app "$stale_agl_game_app"
mkdir -p \
    "$stale_agl_game_app/Contents/Frameworks/AGL.framework/Versions/A/Resources" \
    "$stale_agl_game_app/Contents/PlugIns/platforms" \
    "$stale_agl_game_app/Contents/PlugIns/imageformats" \
    "$stale_bin_dir"
ln -s A "$stale_agl_game_app/Contents/Frameworks/AGL.framework/Versions/Current"
ln -s Versions/Current/AGL "$stale_agl_game_app/Contents/Frameworks/AGL.framework/AGL"
ln -s Versions/Current/Resources "$stale_agl_game_app/Contents/Frameworks/AGL.framework/Resources"
ln -s A "$stale_agl_game_app/Contents/Frameworks/AGL.framework/Versions/A/A"
ln -s Versions/Current/Resources "$stale_agl_game_app/Contents/Frameworks/AGL.framework/Versions/A/Resources/Resources"
cat > "$stale_bin_dir/install_name_tool" <<'STUB'
#!/bin/bash
exit 0
STUB
cat > "$stale_bin_dir/otool" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-L" ]]; then
    printf '%s:\n' "${2:-binary}"
    printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
    exit 0
fi
exit 1
STUB
chmod +x "$stale_bin_dir/install_name_tool" "$stale_bin_dir/otool"

PATH="$stale_bin_dir:$PATH" \
    GAME_APP="$stale_agl_game_app" \
    BUILD_DIR="$agl_build_dir" \
    "$ROOT_DIR/scripts/04_fix_library_paths.sh" >/dev/null \
    || fail "library path fixer failed when replacing stale AGL framework symlinks"
[[ ! -L "$stale_agl_game_app/Contents/Frameworks/AGL.framework/Versions/A/A" ]] \
    || fail "library path fixer left a nested Versions/A/A symlink after repeated AGL install"
[[ ! -L "$stale_agl_game_app/Contents/Frameworks/AGL.framework/Versions/A/Resources/Resources" ]] \
    || fail "library path fixer left a nested Resources/Resources symlink after repeated AGL install"
[[ -L "$stale_agl_game_app/Contents/Frameworks/AGL.framework/Versions/Current" ]] \
    || fail "library path fixer did not recreate Versions/Current as a symlink"
[[ -L "$stale_agl_game_app/Contents/Frameworks/AGL.framework/Resources" ]] \
    || fail "library path fixer did not recreate top-level Resources as a symlink"

qt_game_app="$tmp_dir/missing-qt/Worms W.M.D.app"
qt_prefix="$tmp_dir/qt-prefix"
make_game_app "$qt_game_app"
make_qt_framework_sources "$qt_prefix" QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus
touch "$qt_prefix/plugins/platforms/libqcocoa.dylib"
touch "$qt_prefix/plugins/imageformats/libqgif.dylib"

set +e
qt_output=$(
    GAME_APP="$qt_game_app" \
        QT_SOURCE=homebrew \
        QT_PREFIX="$qt_prefix" \
        WORMSWMD_ALLOW_CUSTOM_QT_PREFIX=1 \
        "$ROOT_DIR/scripts/02_replace_qt_frameworks.sh" 2>&1
)
qt_status=$?
set -e

if [[ "$qt_status" -eq 0 ]]; then
    fail "Qt replacement succeeded without required QtSvg.framework source"
fi

if ! grep -Fq "ERROR: Required Qt framework missing from source: $qt_prefix/lib/QtSvg.framework" <<< "$qt_output"; then
    fail "missing required Qt framework did not produce the expected hard error: $qt_output"
fi

if grep -Fq "Qt frameworks replaced successfully." <<< "$qt_output"; then
    fail "Qt replacement continued after the missing required framework error"
fi

plugin_game_app="$tmp_dir/missing-platform-plugin/Worms W.M.D.app"
plugin_prefix="$tmp_dir/qt-missing-platform-plugin"
make_game_app "$plugin_game_app"
make_qt_framework_sources "$plugin_prefix" QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus QtSvg
mkdir -p "$plugin_game_app/Contents/PlugIns/platforms" "$plugin_game_app/Contents/PlugIns/imageformats"
touch "$plugin_game_app/Contents/PlugIns/platforms/original-platform.dylib"
touch "$plugin_game_app/Contents/PlugIns/imageformats/original-image.dylib"
touch "$plugin_prefix/plugins/imageformats/libqsvg.dylib"

set +e
plugin_output=$(
    GAME_APP="$plugin_game_app" \
        QT_SOURCE=homebrew \
        QT_PREFIX="$plugin_prefix" \
        WORMSWMD_ALLOW_CUSTOM_QT_PREFIX=1 \
        "$ROOT_DIR/scripts/02_replace_qt_frameworks.sh" 2>&1
)
plugin_status=$?
set -e

if [[ "$plugin_status" -eq 0 ]]; then
    fail "Qt replacement succeeded without required libqcocoa.dylib source"
fi
if ! grep -Fq "ERROR: Required Qt platform plugin missing from source: $plugin_prefix/plugins/platforms/libqcocoa.dylib" <<< "$plugin_output"; then
    fail "missing platform plugin did not produce the expected hard error: $plugin_output"
fi
[[ -f "$plugin_game_app/Contents/PlugIns/platforms/original-platform.dylib" ]] \
    || fail "platform plugin preflight deleted existing plugins before failing"
[[ -f "$plugin_game_app/Contents/PlugIns/imageformats/original-image.dylib" ]] \
    || fail "platform plugin preflight deleted existing image plugins before failing"

image_plugin_game_app="$tmp_dir/missing-image-plugin/Worms W.M.D.app"
image_plugin_prefix="$tmp_dir/qt-missing-image-plugin"
make_game_app "$image_plugin_game_app"
make_qt_framework_sources "$image_plugin_prefix" QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus QtSvg
mkdir -p "$image_plugin_game_app/Contents/PlugIns/platforms" "$image_plugin_game_app/Contents/PlugIns/imageformats"
touch "$image_plugin_game_app/Contents/PlugIns/platforms/original-platform.dylib"
touch "$image_plugin_game_app/Contents/PlugIns/imageformats/original-image.dylib"
touch "$image_plugin_prefix/plugins/platforms/libqcocoa.dylib"
touch "$image_plugin_prefix/plugins/imageformats/libqgif.dylib"

set +e
image_plugin_output=$(
    GAME_APP="$image_plugin_game_app" \
        QT_SOURCE=homebrew \
        QT_PREFIX="$image_plugin_prefix" \
        WORMSWMD_ALLOW_CUSTOM_QT_PREFIX=1 \
        "$ROOT_DIR/scripts/02_replace_qt_frameworks.sh" 2>&1
)
image_plugin_status=$?
set -e

if [[ "$image_plugin_status" -eq 0 ]]; then
    fail "Qt replacement succeeded without required libqsvg.dylib source"
fi
if ! grep -Fq "ERROR: Required Qt image plugin missing from source: $image_plugin_prefix/plugins/imageformats/libqsvg.dylib" <<< "$image_plugin_output"; then
    fail "missing image plugin did not produce the expected hard error: $image_plugin_output"
fi
[[ -f "$image_plugin_game_app/Contents/PlugIns/platforms/original-platform.dylib" ]] \
    || fail "image plugin preflight deleted existing platform plugins before failing"
[[ -f "$image_plugin_game_app/Contents/PlugIns/imageformats/original-image.dylib" ]] \
    || fail "image plugin preflight deleted existing image plugins before failing"

verify_bin="$tmp_dir/verify-bin"
write_verify_stubs "$verify_bin"
verify_game_app="$tmp_dir/verify-missing-plugins/Worms W.M.D.app"
make_game_app "$verify_game_app"
make_installed_frameworks "$verify_game_app"

set +e
verify_output=$(
    PATH="$verify_bin:$PATH" \
        GAME_APP="$verify_game_app" \
        "$ROOT_DIR/scripts/05_verify_installation.sh" 2>&1
)
verify_status=$?
set -e

if [[ "$verify_status" -eq 0 ]]; then
    fail "installation verifier succeeded without required Qt plugins"
fi
grep -Fq "ERROR: Required platform plugin missing: platforms/libqcocoa.dylib" <<< "$verify_output" \
    || fail "verifier did not report missing platform plugin: $verify_output"
grep -Fq "ERROR: Required image plugin missing: imageformats/libqsvg.dylib" <<< "$verify_output" \
    || fail "verifier did not report missing image plugin: $verify_output"

agl_arch_game_app="$tmp_dir/verify-agl-arch/Worms W.M.D.app"
make_game_app "$agl_arch_game_app"
make_installed_frameworks "$agl_arch_game_app"
mkdir -p "$agl_arch_game_app/Contents/PlugIns/platforms" "$agl_arch_game_app/Contents/PlugIns/imageformats"
touch "$agl_arch_game_app/Contents/PlugIns/platforms/libqcocoa.dylib"
touch "$agl_arch_game_app/Contents/PlugIns/imageformats/libqsvg.dylib"

set +e
agl_arch_output=$(
    PATH="$verify_bin:$PATH" \
        WORMS_TEST_AGL_ARCHS=arm64 \
        GAME_APP="$agl_arch_game_app" \
        "$ROOT_DIR/scripts/05_verify_installation.sh" 2>&1
)
agl_arch_status=$?
set -e

if [[ "$agl_arch_status" -eq 0 ]]; then
    fail "installation verifier succeeded with an AGL stub missing x86_64"
fi
grep -Fq "ERROR: AGL stub architecture is arm64 (expected x86_64 or universal)" <<< "$agl_arch_output" \
    || fail "verifier did not report non-x86_64 AGL architecture: $agl_arch_output"

deps_game_app="$tmp_dir/missing-prebuilt-deps/Worms W.M.D.app"
make_game_app "$deps_game_app"
mkdir -p "$deps_game_app/Contents/Frameworks"
touch "$deps_game_app/Contents/Frameworks/libglib-2.0.0.dylib"

set +e
deps_output=$(
    GAME_APP="$deps_game_app" \
        QT_SOURCE=prebuild \
        "$ROOT_DIR/scripts/03_copy_dependencies.sh" 2>&1
)
deps_status=$?
set -e

if [[ "$deps_status" -eq 0 ]]; then
    fail "prebuilt dependency verification succeeded with only one bundled dylib"
fi
grep -Fq "ERROR: Required bundled dependency missing: libpcre2-16.0.dylib" <<< "$deps_output" \
    || fail "missing prebuilt dependency did not produce the expected hard error: $deps_output"

printf 'Issue #12 AGL install failure check passed.\n'
