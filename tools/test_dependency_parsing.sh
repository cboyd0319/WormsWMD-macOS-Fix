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
export HOME="$tmp_dir/test-home"
mkdir -p "$HOME/Library/Logs/WormsWMD-Fix"

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
    if [[ "${WORMS_TEST_UNREADABLE_ARCH:-}" == "1" ]] \
        && [[ "${2:-}" == */Contents/MacOS/Worms\ W.M.D ]]; then
        exit 1
    fi
    printf '%s\n' "x86_64"
    exit 0
fi
exit 1
STUB

cat > "$fake_bin/otool" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-D" ]]; then
    printf '%s:\n' "${2:-binary}"
    if [[ "${WORMS_TEST_PLUGIN_SELF_ID:-}" == "1" ]] \
        && [[ "${2:-}" == */PlugIns/platforms/libqcocoa.dylib ]]; then
        printf '%s\n' libqcocoa.dylib
    fi
    exit 0
fi
if [[ "${1:-}" == "-L" ]]; then
    printf '%s:\n' "${2:-binary}"
    case "${2:-}" in
        */Contents/MacOS/Worms\ W.M.D)
            printf '\t@executable_path/libOptionalGalaxy.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            printf '\t@rpath/libGalaxy.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            printf '\t@rpath/libGalaxyCSharp.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            printf '\t@rpath/libglib-2.0.0.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            if [[ "${WORMS_TEST_DIRECT_ESCAPE:-}" == "1" ]]; then
                printf '\t@loader_path/../../../outside-direct.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
                printf '\tlibRelative.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            fi
            if [[ "${WORMS_TEST_STRONG_MISSING:-}" == "1" ]]; then
                printf '\t@rpath/libMissingStrong.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            fi
            ;;
        */Contents/MacOS/libGalaxy.dylib)
            if [[ "${WORMS_TEST_MACOS_UNSAFE:-}" == "1" ]]; then
                printf '\t/usr/local/lib/libUnexpectedGalaxyDependency.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            fi
            ;;
        *QtCore.framework*)
            printf '\t@executable_path/../Frameworks/QtCore.framework/Versions/5/QtCore (compatibility version 5.15.0, current version 5.15.19)\n'
            if [[ -n "${WORMS_TEST_COPY_SOURCE:-}" ]]; then
                printf '\t%s (compatibility version 1.0.0, current version 1.0.0)\n' \
                    "$WORMS_TEST_COPY_SOURCE"
            fi
            ;;
        *QtGui.framework*)
            if [[ -n "${WORMS_TEST_COPY_SOURCE_TWO:-}" ]]; then
                printf '\t%s (compatibility version 1.0.0, current version 1.0.0)\n' \
                    "$WORMS_TEST_COPY_SOURCE_TWO"
            fi
            ;;
        *libwebp.7.dylib)
            printf '\t@loader_path/libOptionalWebPHelper.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
            printf '\t@rpath/libsharpyuv.0.dylib (compatibility version 2.0.0, current version 2.2.0)\n'
            ;;
        */PlugIns/platforms/libqcocoa.dylib)
            if [[ "${WORMS_TEST_PLUGIN_SELF_ID:-}" == "1" ]]; then
                printf '\tlibqcocoa.dylib (compatibility version 0.0.0, current version 0.0.0)\n'
            fi
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
          cmd LC_LOAD_WEAK_DYLIB
      cmdsize 64
         name @executable_path/libOptionalGalaxy.dylib (offset 24)
Load command 5
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
      cmdsize 64
         name @loader_path/libOptionalWebPHelper.dylib (offset 24)
Load command 2
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

cat > "$fake_bin/install_name_tool" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$fake_bin/install_name_tool"

cat > "$fake_bin/find" <<'STUB'
#!/bin/bash
if [[ "${WORMS_TEST_PLUGIN_FIND_FAIL:-}" == "1" ]] && [[ "${1:-}" == */Contents/PlugIns ]]; then
    exit 93
fi
exec /usr/bin/find "$@"
STUB
chmod +x "$fake_bin/find"

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
rm -f "$game_app/Contents/MacOS/libEscaping.dylib"

owner_bin="$tmp_dir/owner-bin"
owner_plugin="$game_app/Contents/PlugIns/imageformats/libowner.dylib"
owner_dependency="$game_app/Contents/MacOS/libOwnedByExecutable.dylib"
mkdir -p "$owner_bin"
: > "$owner_plugin"
: > "$owner_dependency"
cat > "$owner_bin/otool" <<'STUB'
#!/bin/bash
if [[ "${1:-}" != "-l" ]]; then
    exit 1
fi
case "${2:-}" in
    */Contents/MacOS/Worms\ W.M.D)
        cat <<'LOADS'
Load command 1
          cmd LC_RPATH
      cmdsize 32
         path @loader_path (offset 12)
LOADS
        ;;
    *libowner.dylib)
        cat <<'LOADS'
Load command 1
          cmd LC_LOAD_WEAK_DYLIB
      cmdsize 64
         name @rpath/Weak Galaxy Library.dylib (offset 24)
LOADS
        ;;
esac
STUB
chmod +x "$owner_bin/otool"

owner_resolved=$(PATH="$owner_bin:$PATH" worms_resolve_macho_rpath_dependency \
    "$owner_plugin" \
    '@rpath/libOwnedByExecutable.dylib' \
    "$game_app/Contents/MacOS/Worms W.M.D" \
    "$game_app" || true)
[[ "$owner_resolved" == "$owner_dependency" ]] \
    || fail "main executable LC_RPATH expanded @loader_path relative to the nested plugin: $owner_resolved"
PATH="$owner_bin:$PATH" worms_macho_dependency_is_weak \
    "$owner_plugin" '@rpath/Weak Galaxy Library.dylib' \
    || fail "weak-load parser truncated an install name containing spaces"

resolver_root="$tmp_dir/Resolver Root With Spaces"
resolver_tools="$tmp_dir/resolver-tools"
resolver_owner="$resolver_root/bin/libowner.dylib"
resolver_game_exec="$resolver_root/bin/game"
mkdir -p "$resolver_tools" "$resolver_root/bin" \
    "$resolver_root/deps" "$resolver_root/deps-one" "$resolver_root/deps-two"
: > "$resolver_owner"
: > "$resolver_game_exec"
printf 'valid dependency\n' > "$resolver_root/deps/libValid.dylib"
printf 'first duplicate\n' > "$resolver_root/deps-one/libDuplicate.dylib"
printf 'second duplicate\n' > "$resolver_root/deps-two/libDuplicate.dylib"
printf 'arm only\n' > "$resolver_root/deps/libNoX86.dylib"
printf 'outside\n' > "$tmp_dir/libOutside.dylib"
ln -s "$tmp_dir/libOutside.dylib" "$resolver_root/deps/libSymlink.dylib"
printf 'hardlinked\n' > "$resolver_root/deps/libHardlink.dylib"
ln "$resolver_root/deps/libHardlink.dylib" "$tmp_dir/libHardlinkAlias.dylib"

cat > "$resolver_tools/otool" <<'STUB'
#!/bin/bash
has_loads=false
for argument in "$@"; do
    [[ "$argument" == "-l" ]] && has_loads=true
done
$has_loads || exit 1
if [[ "${RESOLVER_MODE:-single}" == "multiple" ]]; then
    cat <<'LOADS'
Load command 1
          cmd LC_RPATH
      cmdsize 48
         path @loader_path/../deps-one (offset 12)
Load command 2
          cmd LC_RPATH
      cmdsize 48
         path @loader_path/../deps-two (offset 12)
LOADS
else
    cat <<'LOADS'
Load command 1
          cmd LC_RPATH
      cmdsize 48
         path @loader_path/../deps (offset 12)
LOADS
fi
STUB
cat > "$resolver_tools/lipo" <<'STUB'
#!/bin/bash
[[ "${1:-}" == "-archs" ]] || exit 1
case "${2:-}" in
    *libNoX86.dylib) printf '%s\n' arm64 ;;
    *) printf '%s\n' x86_64 ;;
esac
STUB
chmod +x "$resolver_tools"/*

resolver_root_real=$(cd "$resolver_root" && pwd -P)
resolved_source=$(PATH="$resolver_tools:$PATH" worms_resolve_macho_dependency_source \
    "$resolver_owner" '@rpath/libValid.dylib' "$resolver_game_exec" \
    "$resolver_root_real")
[[ "$resolved_source" == "$resolver_root_real/deps/libValid.dylib" ]] \
    || fail "loader-owned rpath with spaces resolved incorrectly: $resolved_source"

for unsafe_dependency in \
    '@loader_path/../deps/libValid.dylib' \
    "$tmp_dir/libOutside.dylib" \
    '@rpath/libSymlink.dylib' \
    '@rpath/libHardlink.dylib' \
    '@rpath/libNoX86.dylib'; do
    if PATH="$resolver_tools:$PATH" worms_resolve_macho_dependency_source \
        "$resolver_owner" "$unsafe_dependency" "$resolver_game_exec" \
        "$resolver_root_real" >/dev/null 2>&1; then
        fail "dependency source policy accepted unsafe input: $unsafe_dependency"
    fi
done

set +e
multiple_output=$(RESOLVER_MODE=multiple PATH="$resolver_tools:$PATH" \
    worms_resolve_macho_dependency_source "$resolver_owner" \
    '@rpath/libDuplicate.dylib' "$resolver_game_exec" \
    "$resolver_root_real" 2>&1)
multiple_status=$?
set -e
[[ "$multiple_status" -eq 2 ]] \
    || fail "multiple valid dependency sources were not an actionable ambiguity: $multiple_output"
grep -Fq 'Multiple valid dependency sources' <<< "$multiple_output" \
    || fail "ambiguous dependency sources were not explained: $multiple_output"

source_record="$tmp_dir/dependency-sources.tsv"
worms_record_dependency_source "$source_record" libDuplicate.dylib \
    "$resolver_root_real/deps-one/libDuplicate.dylib"
if worms_record_dependency_source "$source_record" libDuplicate.dylib \
    "$resolver_root_real/deps-two/libDuplicate.dylib" >/dev/null 2>&1; then
    fail "duplicate dependency basename accepted two canonical sources"
fi

homebrew_root="$tmp_dir/Custom Homebrew Root"
homebrew_dep_root="$tmp_dir/Custom Dependency Root"
dependency_home="$tmp_dir/dependency-home"
homebrew_log="$dependency_home/Library/Logs/WormsWMD-Fix/homebrew-copy.log"
mkdir -p "$homebrew_root" "$homebrew_dep_root/lib" "$(dirname "$homebrew_log")"
runtime_source="$homebrew_dep_root/lib/libRuntime With Spaces.dylib"
printf 'runtime source\n' > "$runtime_source"
homebrew_copy_output=$(PATH="$fake_bin:$PATH" \
    GAME_APP="$game_app" \
    HOME="$dependency_home" \
    QT_SOURCE=homebrew \
    QT_PREFIX="$homebrew_root" \
    QT_DEP_PREFIX="$homebrew_dep_root" \
    WORMSWMD_ALLOW_CUSTOM_QT_PREFIX=1 \
    WORMSWMD_LOGGING_INITIALIZED=1 \
    LOG_FILE="$homebrew_log" \
    WORMS_TEST_COPY_SOURCE="$runtime_source" \
    "$ROOT_DIR/scripts/03_copy_dependencies.sh" 2>&1) \
    || fail "runtime dependency copy rejected a valid explicit root: $homebrew_copy_output"
grep -Fxq 'runtime source' "$game_app/Contents/Frameworks/$(basename "$runtime_source")" \
    || fail "runtime dependency copy did not use the canonical explicit source"

first_duplicate="$homebrew_dep_root/lib-one/libDuplicate.dylib"
second_duplicate="$homebrew_dep_root/lib-two/libDuplicate.dylib"
mkdir -p "$(dirname "$first_duplicate")" "$(dirname "$second_duplicate")"
printf 'first\n' > "$first_duplicate"
printf 'second\n' > "$second_duplicate"
set +e
duplicate_copy_output=$(PATH="$fake_bin:$PATH" \
    GAME_APP="$game_app" HOME="$dependency_home" QT_SOURCE=homebrew QT_PREFIX="$homebrew_root" \
    QT_DEP_PREFIX="$homebrew_dep_root" WORMSWMD_ALLOW_CUSTOM_QT_PREFIX=1 \
    WORMSWMD_LOGGING_INITIALIZED=1 LOG_FILE="$homebrew_log" \
    WORMS_TEST_COPY_SOURCE="$first_duplicate" \
    WORMS_TEST_COPY_SOURCE_TWO="$second_duplicate" \
    "$ROOT_DIR/scripts/03_copy_dependencies.sh" 2>&1)
duplicate_copy_status=$?
set -e
[[ "$duplicate_copy_status" -ne 0 ]] \
    || fail "runtime dependency copy accepted duplicate basenames from different roots"
grep -Fq 'Dependency basename maps to multiple sources' <<< "$duplicate_copy_output" \
    || fail "runtime duplicate-basename error was not actionable: $duplicate_copy_output"

for unsafe_source in \
    "$homebrew_dep_root/lib/libMissing.dylib" \
    "$tmp_dir/libOutside.dylib" \
    "$resolver_root/deps/libNoX86.dylib"; do
    set +e
    unsafe_copy_output=$(PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" HOME="$dependency_home" QT_SOURCE=homebrew QT_PREFIX="$homebrew_root" \
        QT_DEP_PREFIX="$homebrew_dep_root" WORMSWMD_ALLOW_CUSTOM_QT_PREFIX=1 \
        WORMSWMD_LOGGING_INITIALIZED=1 LOG_FILE="$homebrew_log" \
        WORMS_TEST_COPY_SOURCE="$unsafe_source" \
        "$ROOT_DIR/scripts/03_copy_dependencies.sh" 2>&1)
    unsafe_copy_status=$?
    set -e
    [[ "$unsafe_copy_status" -ne 0 ]] \
        || fail "runtime dependency copy accepted unsafe source: $unsafe_source"
done

if grep -Fq 'resolve_rpath_dep' "$ROOT_DIR/scripts/03_copy_dependencies.sh"; then
    fail "runtime dependency copy still uses broad basename search"
fi
grep -Fq 'worms_resolve_macho_dependency_source' \
    "$ROOT_DIR/scripts/03_copy_dependencies.sh" \
    || fail "runtime dependency copy does not use the shared canonical resolver"
grep -Fq 'worms_resolve_macho_dependency_source' \
    "$ROOT_DIR/tools/package_qt_frameworks.sh" \
    || fail "Qt packager does not use the shared canonical resolver"

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
grep -Fq "WARNING: Worms W.M.D has optional missing dependency: @executable_path/libOptionalGalaxy.dylib" <<< "$verify_output" \
    || fail "verifier treated an optional @executable_path dependency as required: $verify_output"
grep -Fq "WARNING: libwebp.7.dylib has optional missing dependency: @loader_path/libOptionalWebPHelper.dylib" <<< "$verify_output" \
    || fail "verifier treated an optional @loader_path dependency as required: $verify_output"
if grep -Fq "ERROR: Main executable has unresolved @rpath dependency: @rpath/libGalaxy.dylib" <<< "$verify_output"; then
    fail "verifier rejected a Galaxy dependency resolved by LC_RPATH"
fi

set +e
self_id_output=$(PATH="$fake_bin:$PATH" GAME_APP="$game_app" \
    WORMS_TEST_PLUGIN_SELF_ID=1 \
    "$ROOT_DIR/scripts/05_verify_installation.sh" 2>&1)
self_id_status=$?
set -e
if [[ "$self_id_status" -ne 0 ]]; then
    fail "verifier treated a plugin's own install ID as a dependency: $self_id_output"
fi
if grep -Fq 'unportable relative dependency: libqcocoa.dylib' <<< "$self_id_output"; then
    fail "verifier did not exclude the owning plugin install ID"
fi

ln -s libqsvg.dylib "$game_app/Contents/PlugIns/imageformats/liblinked.dylib"
set +e
linked_plugin_output=$(
    PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        "$ROOT_DIR/scripts/05_verify_installation.sh" 2>&1
)
linked_plugin_status=$?
set -e
rm -f "$game_app/Contents/PlugIns/imageformats/liblinked.dylib"
if [[ "$linked_plugin_status" -eq 0 ]]; then
    fail "verifier accepted a linked Qt plugin entry"
fi
grep -Fq 'Linked Qt plugin entry is not supported: PlugIns/imageformats/liblinked.dylib' <<< "$linked_plugin_output" \
    || fail "verifier did not report the linked plugin entry: $linked_plugin_output"

set +e
plugin_find_output=$(
    PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        WORMS_TEST_PLUGIN_FIND_FAIL=1 \
        "$ROOT_DIR/scripts/05_verify_installation.sh" 2>&1
)
plugin_find_status=$?
set -e
if [[ "$plugin_find_status" -eq 0 ]]; then
    fail "verifier accepted an incomplete plugin inventory"
fi
grep -Fq 'Unable to inventory every Qt plugin entry' <<< "$plugin_find_output" \
    || fail "verifier did not report the plugin inventory failure: $plugin_find_output"

: > "$tmp_dir/outside-direct.dylib"
set +e
direct_escape_output=$(
    PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        WORMS_TEST_DIRECT_ESCAPE=1 \
        "$ROOT_DIR/scripts/05_verify_installation.sh" 2>&1
)
direct_escape_status=$?
set -e
if [[ "$direct_escape_status" -eq 0 ]]; then
    fail "verifier accepted direct or relative dependencies outside the app bundle"
fi
grep -Fq '@loader_path/../../../outside-direct.dylib' <<< "$direct_escape_output" \
    || fail "verifier did not report an escaping @loader_path dependency: $direct_escape_output"
grep -Fq 'libRelative.dylib' <<< "$direct_escape_output" \
    || fail "verifier did not report a relative dependency: $direct_escape_output"

set +e
macos_library_output=$(
    PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        WORMS_TEST_MACOS_UNSAFE=1 \
        "$ROOT_DIR/scripts/05_verify_installation.sh" 2>&1
)
macos_library_status=$?
set -e
if [[ "$macos_library_status" -eq 0 ]]; then
    fail "verifier ignored an unsafe dependency in Contents/MacOS/libGalaxy.dylib"
fi
grep -Fq 'libUnexpectedGalaxyDependency.dylib' <<< "$macos_library_output" \
    || fail "verifier did not report the unsafe Galaxy library dependency: $macos_library_output"

set +e
unreadable_arch_output=$(
    PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        WORMS_TEST_UNREADABLE_ARCH=1 \
        "$ROOT_DIR/scripts/05_verify_installation.sh" 2>&1
)
unreadable_arch_status=$?
set -e
if [[ "$unreadable_arch_status" -eq 0 ]]; then
    fail "verifier accepted an unreadable main executable architecture"
fi
grep -Fq 'Unable to read architectures for Main executable' <<< "$unreadable_arch_output" \
    || fail "verifier did not report the unreadable main executable architecture: $unreadable_arch_output"

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

set +e
wrapped_verify_output=$(
    PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        WORMS_TEST_STRONG_MISSING=1 \
        "$ROOT_DIR/fix_worms_wmd.sh" --verify 2>&1
)
wrapped_verify_status=$?
set -e
if [[ "$wrapped_verify_status" -eq 0 ]]; then
    fail "top-level verification accepted an unresolved strong dependency"
fi
if grep -Fq 'An error occurred during the fix process.' <<< "$wrapped_verify_output"; then
    fail "read-only verification reported a mutating installer failure: $wrapped_verify_output"
fi

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
