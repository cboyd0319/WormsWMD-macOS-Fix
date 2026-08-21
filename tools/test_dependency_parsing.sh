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

rpath_game_app="$tmp_dir/rpath/Worms W.M.D.app"
rpath_build_dir="$tmp_dir/rpath/build"
mkdir -p \
    "$rpath_game_app/Contents/MacOS" \
    "$rpath_game_app/Contents/Frameworks" \
    "$rpath_game_app/Contents/PlugIns/platforms" \
    "$rpath_game_app/Contents/PlugIns/imageformats" \
    "$rpath_build_dir"

cat > "$tmp_dir/galaxy.c" <<'EOF'
int galaxy(void) { return 0; }
EOF
cat > "$tmp_dir/main.c" <<'EOF'
int galaxy(void);
int main(void) { return galaxy(); }
EOF

clang -arch x86_64 -dynamiclib \
    -Wl,-install_name,@rpath/libGalaxy.dylib \
    -o "$rpath_game_app/Contents/MacOS/libGalaxy.dylib" \
    "$tmp_dir/galaxy.c"
clang -arch x86_64 \
    '-Wl,-rpath,@executable_path' \
    -L"$rpath_game_app/Contents/MacOS" \
    -lGalaxy \
    -o "$rpath_game_app/Contents/MacOS/Worms W.M.D" \
    "$tmp_dir/main.c"
cp "$rpath_game_app/Contents/MacOS/libGalaxy.dylib" "$rpath_build_dir/AGL"

GAME_APP="$rpath_game_app" BUILD_DIR="$rpath_build_dir" \
    "$ROOT_DIR/scripts/04_fix_library_paths.sh" >/dev/null

if worms_otool_dependencies "$rpath_game_app/Contents/MacOS/Worms W.M.D" \
    | grep -Fq '@rpath/libGalaxy.dylib'; then
    fail "GOG Galaxy dependency was not rewritten from @rpath"
fi
if ! worms_otool_dependencies "$rpath_game_app/Contents/MacOS/Worms W.M.D" \
    | grep -Fq '@executable_path/libGalaxy.dylib'; then
    fail "GOG Galaxy dependency was not rewritten beside the executable"
fi

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

for fw in QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus QtSvg; do
    mkdir -p "$game_app/Contents/Frameworks/$fw.framework/Versions/5"
    : > "$game_app/Contents/Frameworks/$fw.framework/Versions/5/$fw"
done
: > "$game_app/Contents/Frameworks/AGL.framework/Versions/A/AGL"
: > "$game_app/Contents/Frameworks/libwebp.7.dylib"
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
    || fail "verifier did not warn about optional WebP libsharpyuv dependency: $verify_output"
if grep -Fq "ERROR: libwebp.7.dylib has unresolved @rpath dependency: @rpath/libsharpyuv.0.dylib" <<< "$verify_output"; then
    fail "verifier treated optional WebP libsharpyuv dependency as an error"
fi

printf 'Dependency parsing regression check passed.\n'
