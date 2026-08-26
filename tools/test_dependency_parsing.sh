#!/bin/bash
#
# Regression check for Mach-O dependency parsing.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

fail() {
    printf 'dependency parsing regression check failed: %s\n' "$*" >&2
    exit 1
}

actual=$(
    cat <<'EOF' | worms_otool_dependencies_from_stdin
/Games/Worms W.M.D.app/Contents/Frameworks/libexample.dylib (architecture x86_64):
	/Users/example/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app/Contents/Frameworks/libfmodex.dylib (compatibility version 1.0.0, current version 1.0.0)
	@rpath/libsharpyuv.0.dylib (compatibility version 2.0.0, current version 2.2.0)
	/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1356.0.0)
/Games/Worms W.M.D.app/Contents/Frameworks/libexample.dylib (architecture arm64):
	/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL (compatibility version 1.0.0, current version 1.0.0)
EOF
)

expected=$'/Users/example/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app/Contents/Frameworks/libfmodex.dylib\n@rpath/libsharpyuv.0.dylib\n/usr/lib/libSystem.B.dylib\n/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL'

if [[ "$actual" != "$expected" ]]; then
    printf 'dependency parsing failed\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    exit 1
fi

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-dependency-parsing.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

game_app="$tmp_dir/Worms W.M.D.app"
fake_bin="$tmp_dir/bin"
mkdir -p \
    "$fake_bin" \
    "$game_app/Contents/MacOS" \
    "$game_app/Contents/Frameworks/AGL.framework/Versions/A" \
    "$game_app/Contents/PlugIns/platforms" \
    "$game_app/Contents/PlugIns/imageformats"

printf '#!/bin/bash\nexit 0\n' > "$game_app/Contents/MacOS/Worms W.M.D"
chmod +x "$game_app/Contents/MacOS/Worms W.M.D"
: > "$game_app/Contents/MacOS/libGalaxy.dylib"

for fw in QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus QtSvg; do
    mkdir -p "$game_app/Contents/Frameworks/$fw.framework/Versions/5"
    : > "$game_app/Contents/Frameworks/$fw.framework/Versions/5/$fw"
done
: > "$game_app/Contents/Frameworks/AGL.framework/Versions/A/AGL"
: > "$game_app/Contents/Frameworks/libwebp.7.dylib"
for required_lib in \
    libglib-2.0.0.dylib \
    libgthread-2.0.0.dylib \
    libintl.8.dylib \
    libpcre2-16.0.dylib \
    libpcre2-8.0.dylib \
    libzstd.1.dylib \
    libpng16.16.dylib \
    libjpeg.8.dylib \
    libfreetype.6.dylib \
    libmd4c.0.dylib \
    liblzma.5.dylib \
    libtiff.6.dylib; do
    : > "$game_app/Contents/Frameworks/$required_lib"
done
: > "$game_app/Contents/PlugIns/platforms/libqcocoa.dylib"
: > "$game_app/Contents/PlugIns/imageformats/libqsvg.dylib"

cat > "$game_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.wormswmd.test</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
</dict>
</plist>
PLIST

cat > "$fake_bin/lipo" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-archs" ]]; then
    printf '%s\n' "x86_64"
    exit 0
fi
exit 1
STUB

cat > "$fake_bin/otool" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-L" ]]; then
    printf '%s:\n' "${2:-binary}"
    case "${2:-}" in
        */Contents/MacOS/Worms\ W.M.D)
            printf '\t@rpath/libGalaxy.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            printf '\t@rpath/libGalaxyCSharp.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            printf '\t@rpath/libglib-2.0.0.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            if [[ "${WORMS_TEST_STRONG_MISSING:-}" == "1" ]]; then
                printf '\t@rpath/libMissingStrong.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            fi
            ;;
        *QtCore.framework*)
            printf '\t@executable_path/../Frameworks/QtCore.framework/Versions/5/QtCore (compatibility version 5.15.0, current version 5.15.19)\n'
            ;;
        *libwebp.7.dylib)
            printf '\t@rpath/libsharpyuv.0.dylib (compatibility version 2.0.0, current version 2.2.0)\n'
            ;;
    esac
    printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
    exit 0
fi
if [[ "${1:-}" == "-l" ]]; then
    case "${2:-}" in
        */Contents/MacOS/Worms\ W.M.D)
            cat <<'LOADS'
Load command 1
          cmd LC_RPATH
      cmdsize 32
         path @executable_path (offset 12)
Load command 2
          cmd LC_RPATH
      cmdsize 48
         path @executable_path/../Frameworks (offset 12)
Load command 3
          cmd LC_RPATH
      cmdsize 64
         path @loader_path/Path With Spaces (offset 12)
Load command 4
          cmd LC_LOAD_DYLIB
      cmdsize 48
         name @rpath/libGalaxy.dylib (offset 24)
Load command 5
          cmd LC_LOAD_WEAK_DYLIB
      cmdsize 56
         name @rpath/libGalaxyCSharp.dylib (offset 24)
Load command 5
          cmd LC_LOAD_DYLIB
      cmdsize 56
         name @rpath/libglib-2.0.0.dylib (offset 24)
LOADS
            if [[ "${WORMS_TEST_STRONG_MISSING:-}" == "1" ]]; then
                cat <<'LOADS'
Load command 6
          cmd LC_LOAD_DYLIB
      cmdsize 56
         name @rpath/libMissingStrong.dylib (offset 24)
LOADS
            fi
            ;;
        *libwebp.7.dylib)
            cat <<'LOADS'
Load command 1
          cmd LC_LOAD_WEAK_DYLIB
      cmdsize 56
         name @rpath/libsharpyuv.0.dylib (offset 24)
LOADS
            ;;
    esac
    exit 0
fi
exit 1
STUB

cat > "$fake_bin/sw_vers" <<'STUB'
#!/bin/bash
case "${1:-}" in
    -productName) printf '%s\n' "macOS" ;;
    -productVersion) printf '%s\n' "26.0.1" ;;
    *) exit 1 ;;
esac
STUB

cat > "$fake_bin/uname" <<'STUB'
#!/bin/bash
printf '%s\n' "x86_64"
STUB

cat > "$fake_bin/codesign" <<'STUB'
#!/bin/bash
printf '%s\n' "adhoc" >&2
exit 0
STUB

cat > "$fake_bin/xattr" <<'STUB'
#!/bin/bash
exit 0
STUB

chmod +x "$fake_bin"/*

rpath_output=$(PATH="$fake_bin:$PATH" worms_macho_rpaths "$game_app/Contents/MacOS/Worms W.M.D")
grep -Fxq '@loader_path/Path With Spaces' <<< "$rpath_output" \
    || fail "LC_RPATH parser truncated a path containing spaces: $rpath_output"

printf 'outside app\n' > "$tmp_dir/libEscaping.dylib"
ln -s "$tmp_dir/libEscaping.dylib" "$game_app/Contents/MacOS/libEscaping.dylib"
if PATH="$fake_bin:$PATH" worms_resolve_macho_rpath_dependency \
    "$game_app/Contents/MacOS/Worms W.M.D" \
    '@rpath/libEscaping.dylib' \
    "$game_app/Contents/MacOS/Worms W.M.D" \
    "$game_app" >/dev/null; then
    fail "@rpath resolution accepted a symlink target outside the app bundle"
fi

set +e
verify_output=$(
    PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        "$ROOT_DIR/scripts/05_verify_installation.sh" 2>&1
)
verify_status=$?
set -e

if [[ "$verify_status" -ne 0 ]]; then
    fail "verifier failed on optional WebP libsharpyuv dependency: $verify_output"
fi
grep -Fq "WARNING: libwebp.7.dylib has optional unresolved WebP dependency: @rpath/libsharpyuv.0.dylib" <<< "$verify_output" \
    || grep -Fq "WARNING: libwebp.7.dylib has optional unresolved @rpath dependency: @rpath/libsharpyuv.0.dylib" <<< "$verify_output" \
    || fail "verifier did not warn about optional WebP libsharpyuv dependency: $verify_output"
if grep -Fq "ERROR: libwebp.7.dylib has unresolved @rpath dependency: @rpath/libsharpyuv.0.dylib" <<< "$verify_output"; then
    fail "verifier treated optional WebP libsharpyuv dependency as an error"
fi
grep -Fq "WARNING: Main executable has optional unresolved @rpath dependency: @rpath/libGalaxyCSharp.dylib" <<< "$verify_output" \
    || fail "verifier did not preserve the optional unresolved Galaxy dependency: $verify_output"
if grep -Fq "ERROR: Main executable has unresolved @rpath dependency: @rpath/libGalaxy.dylib" <<< "$verify_output"; then
    fail "verifier rejected a Galaxy dependency resolved by LC_RPATH"
fi

set +e
missing_output=$(
    PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        WORMS_TEST_STRONG_MISSING=1 \
        "$ROOT_DIR/scripts/05_verify_installation.sh" 2>&1
)
missing_status=$?
set -e
if [[ "$missing_status" -eq 0 ]]; then
    fail "verifier accepted an unresolved strong @rpath dependency"
fi
grep -Fq "ERROR: Main executable has unresolved @rpath dependency: @rpath/libMissingStrong.dylib" <<< "$missing_output" \
    || fail "verifier did not report the unresolved strong dependency: $missing_output"

prebuilt_output=$(
    PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        QT_SOURCE=prebuild \
        "$ROOT_DIR/scripts/03_copy_dependencies.sh" 2>&1
) || fail "prebuilt dependency verification failed: $prebuilt_output"
grep -Fq "Verified " <<< "$prebuilt_output" \
    || fail "prebuilt dependency check still claims libraries were copied: $prebuilt_output"
if grep -Eq '^Copied [0-9]+ libraries$' <<< "$prebuilt_output"; then
    fail "prebuilt dependency check emitted the Homebrew copy message"
fi

path_fix_build="$tmp_dir/path-fix-build"
mkdir -p "$path_fix_build"
: > "$path_fix_build/AGL"
cat > "$fake_bin/install_name_tool" <<'STUB'
#!/bin/bash
target=""
for target in "$@"; do
    :
done
case "$target" in
    */Contents/MacOS/Worms\ W.M.D)
        printf '%s\n' "install_name_tool: deliberate main executable failure" >&2
        exit 1
        ;;
esac
exit 0
STUB
chmod +x "$fake_bin/install_name_tool"

set +e
path_fix_output=$(
    PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        BUILD_DIR="$path_fix_build" \
        "$ROOT_DIR/scripts/04_fix_library_paths.sh" 2>&1
)
path_fix_status=$?
set -e
if [[ "$path_fix_status" -eq 0 ]]; then
    fail "path fixer swallowed an install_name_tool failure for the main executable"
fi
grep -Fq "ERROR: Failed to update dependency in Worms W.M.D" <<< "$path_fix_output" \
    || fail "path fixer did not explain the failed dependency update: $path_fix_output"

printf 'Dependency parsing regression check passed.\n'
