#!/bin/bash
#
# Regression check for top-level installer rollback after post-backup failures.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() {
    printf 'installer rollback regression check failed: %s\n' "$*" >&2
    exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-installer-rollback.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

agl_error_bin="$tmp_dir/agl-error-bin"
agl_error_build="$tmp_dir/agl-error-build"
mkdir -p "$agl_error_bin" "$agl_error_build"
cat > "$agl_error_bin/clang" <<'STUB'
#!/bin/bash
printf '%s\n' "synthetic compiler detail" >&2
exit 42
STUB
chmod +x "$agl_error_bin/clang"
set +e
agl_error_output=$(
    PATH="$agl_error_bin:$PATH" \
        BUILD_DIR="$agl_error_build" \
        "$ROOT_DIR/scripts/01_build_agl_stub.sh" 2>&1
)
agl_error_status=$?
set -e
if [[ "$agl_error_status" -eq 0 ]]; then
    fail "AGL build succeeded despite a compiler failure"
fi
grep -Fq "ERROR: Failed to compile AGL stub for x86_64" <<< "$agl_error_output" \
    || fail "AGL build did not label the failed architecture: $agl_error_output"
grep -Fq "synthetic compiler detail" <<< "$agl_error_output" \
    || fail "AGL build hid the compiler failure detail: $agl_error_output"

test_home="$tmp_dir/home"
fake_bin="$tmp_dir/bin"
game_app="$test_home/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"

mkdir -p \
    "$fake_bin" \
    "$game_app/Contents/MacOS" \
    "$game_app/Contents/Frameworks" \
    "$game_app/Contents/PlugIns/platforms" \
    "$game_app/Contents/PlugIns/imageformats" \
    "$game_app/Contents/Resources/DataOSX" \
    "$game_app/Contents/Resources/CommonData"

printf '#!/bin/bash\nexit 0\n' > "$game_app/Contents/MacOS/Worms W.M.D"
chmod +x "$game_app/Contents/MacOS/Worms W.M.D"
printf 'original framework\n' > "$game_app/Contents/Frameworks/original-framework.txt"
: > "$game_app/Contents/Frameworks/libsteam_api.dylib"
printf 'original platform plugin\n' > "$game_app/Contents/PlugIns/platforms/original-platform.dylib"
printf 'original image plugin\n' > "$game_app/Contents/PlugIns/imageformats/original-image.dylib"
printf '<plist version="1.0"><dict></dict></plist>\n' > "$game_app/Contents/Info.plist"
printf 'URL_Internal = "http://xom.team17.com"\n' > "$game_app/Contents/Resources/DataOSX/SteamConfig.txt"
printf 'MainUrl = "http://www.google-analytics.com"\n' > "$game_app/Contents/Resources/CommonData/AnalyticsConfig.txt"

cat > "$fake_bin/sw_vers" <<'STUB'
#!/bin/bash
case "${1:-}" in
    -productName) printf '%s\n' "macOS" ;;
    -productVersion) printf '%s\n' "26.0.1" ;;
    -buildVersion) printf '%s\n' "99A999" ;;
    *) exit 1 ;;
esac
STUB

cat > "$fake_bin/uname" <<'STUB'
#!/bin/bash
printf '%s\n' "x86_64"
STUB

cat > "$fake_bin/arch" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-x86_64" ]]; then
    shift
fi
exec "$@"
STUB

cat > "$fake_bin/clang" <<'STUB'
#!/bin/bash
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            out="${2:-}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
[[ -n "$out" ]] || exit 1
mkdir -p "$(dirname "$out")"
printf 'fake macho\n' > "$out"
exit 0
STUB

cat > "$fake_bin/lipo" <<'STUB'
#!/bin/bash
case "${1:-}" in
    -create)
        out=""
        while [[ $# -gt 0 ]]; do
            if [[ "$1" == "-output" ]]; then
                out="${2:-}"
                break
            fi
            shift
        done
        [[ -n "$out" ]] || exit 1
        printf 'fake universal macho\n' > "$out"
        ;;
    -archs)
        printf '%s\n' "x86_64"
        ;;
    -info)
        printf '%s\n' "Architectures in the fat file: ${2:-binary} are: x86_64 arm64"
        ;;
    *)
        exit 1
        ;;
esac
STUB

cat > "$fake_bin/file" <<'STUB'
#!/bin/bash
printf '%s: Mach-O universal binary with 2 architectures\n' "${1:-binary}"
STUB

cat > "$fake_bin/otool" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-L" ]]; then
    printf '%s:\n' "${2:-binary}"
    printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
    exit 0
fi
exit 1
STUB

cat > "$fake_bin/install_name_tool" <<'STUB'
#!/bin/bash
printf '%s\n' "forced install_name_tool failure" >&2
exit 1
STUB

cat > "$fake_bin/codesign" <<'STUB'
#!/bin/bash
exit 0
STUB

cat > "$fake_bin/xattr" <<'STUB'
#!/bin/bash
exit 0
STUB

chmod +x "$fake_bin"/*

set +e
output=$(
    HOME="$test_home" \
        PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        "$ROOT_DIR/fix_worms_wmd.sh" --force 2>&1
)
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
    fail "installer succeeded even though install_name_tool was forced to fail"
fi

grep -Fq "Rolled back to original game files." <<< "$output" \
    || fail "installer failure did not report successful rollback: $output"

grep -Fxq 'original framework' "$game_app/Contents/Frameworks/original-framework.txt" \
    || fail "original Frameworks contents were not restored"
grep -Fxq 'original platform plugin' "$game_app/Contents/PlugIns/platforms/original-platform.dylib" \
    || fail "original platform plugin contents were not restored"
grep -Fxq 'original image plugin' "$game_app/Contents/PlugIns/imageformats/original-image.dylib" \
    || fail "original image plugin contents were not restored"

[[ ! -e "$game_app/Contents/Frameworks/QtCore.framework" ]] \
    || fail "partial QtCore.framework remained after rollback"
[[ ! -e "$game_app/Contents/Frameworks/AGL.framework" ]] \
    || fail "partial AGL.framework remained after rollback"
[[ ! -e "$game_app/Contents/PlugIns/platforms/libqcocoa.dylib" ]] \
    || fail "partial platform plugin remained after rollback"

backup_count=$(find "$test_home/Documents" -mindepth 1 -maxdepth 1 -type d -name 'WormsWMD-Backup-*' -print 2>/dev/null | wc -l | tr -d ' ')
[[ "$backup_count" == "1" ]] || fail "expected one preserved rollback backup, found $backup_count"
if find "$test_home/Documents" -mindepth 1 -maxdepth 1 -name '.WormsWMD-Backup.partial.*' -print -quit | grep -q .; then
    fail "installer left an incomplete backup staging directory"
fi

partial_home="$tmp_dir/partial-home"
partial_game_app="$partial_home/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
partial_bin="$tmp_dir/partial-bin"
mkdir -p \
    "$partial_bin" \
    "$partial_game_app/Contents/MacOS" \
    "$partial_game_app/Contents/Frameworks" \
    "$partial_game_app/Contents/PlugIns/platforms" \
    "$partial_game_app/Contents/PlugIns/imageformats"
printf '#!/bin/bash\nexit 0\n' > "$partial_game_app/Contents/MacOS/Worms W.M.D"
chmod +x "$partial_game_app/Contents/MacOS/Worms W.M.D"
: > "$partial_game_app/Contents/Frameworks/libsteam_api.dylib"
printf 'original framework\n' > "$partial_game_app/Contents/Frameworks/original.txt"
printf 'original plugin\n' > "$partial_game_app/Contents/PlugIns/platforms/original.dylib"
cat > "$partial_bin/cp" <<'STUB'
#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == */Contents/PlugIns ]]; then
        printf '%s\n' 'synthetic backup copy failure' >&2
        exit 91
    fi
done
exec /bin/cp "$@"
STUB
chmod +x "$partial_bin/cp"
set +e
partial_output=$(
    HOME="$partial_home" \
        PATH="$partial_bin:$fake_bin:$PATH" \
        GAME_APP="$partial_game_app" \
        "$ROOT_DIR/fix_worms_wmd.sh" --force 2>&1
)
partial_status=$?
set -e
if [[ "$partial_status" -eq 0 ]]; then
    fail "installer succeeded despite an interrupted backup copy"
fi
if find "$partial_home/Documents" -mindepth 1 -maxdepth 1 -type d -name 'WormsWMD-Backup-*' -print -quit | grep -q .; then
    fail "interrupted backup was published as a restorable backup: $partial_output"
fi
if find "$partial_home/Documents" -mindepth 1 -maxdepth 1 -name '.WormsWMD-Backup.partial.*' -print -quit | grep -q .; then
    fail "interrupted backup staging directory was not cleaned up"
fi

printf 'Installer rollback regression check passed.\n'

readonly_home="$tmp_dir/readonly-home"
readonly_bin="$tmp_dir/readonly-bin"
readonly_game_app="$readonly_home/Games/Worms W.M.D.app"
readonly_qt_prefix="$tmp_dir/readonly-qt"

mkdir -p \
    "$readonly_bin" \
    "$readonly_game_app/Contents/MacOS" \
    "$readonly_game_app/Contents/PlugIns/accessible" \
    "$readonly_game_app/Contents/PlugIns/printsupport" \
    "$readonly_qt_prefix/lib" \
    "$readonly_qt_prefix/plugins/platforms" \
    "$readonly_qt_prefix/plugins/imageformats"
printf '#!/bin/bash\nexit 0\n' > "$readonly_game_app/Contents/MacOS/Worms W.M.D"
chmod +x "$readonly_game_app/Contents/MacOS/Worms W.M.D"
printf 'stale Qt 5.3 plugin\n' > "$readonly_game_app/Contents/PlugIns/accessible/libqtaccessiblewidgets.dylib"
printf 'stale Qt 5.3 plugin\n' > "$readonly_game_app/Contents/PlugIns/printsupport/libcocoaprintersupport.dylib"

for framework in QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus QtSvg; do
    framework_binary="$readonly_qt_prefix/lib/$framework.framework/Versions/5/$framework"
    mkdir -p "$(dirname "$framework_binary")"
    printf 'fake Mach-O\n' > "$framework_binary"
    chmod 444 "$framework_binary"
done
printf 'fake plugin\n' > "$readonly_qt_prefix/plugins/platforms/libqcocoa.dylib"
printf 'fake plugin\n' > "$readonly_qt_prefix/plugins/imageformats/libqsvg.dylib"

cat > "$readonly_bin/install_name_tool" <<'STUB'
#!/bin/bash
target=""
for target in "$@"; do
    :
done
if [[ -z "$target" ]] || [[ ! -w "$target" ]]; then
    printf '%s\n' "install_name_tool: can't write new headers in file: ${target:-unknown} (Bad file descriptor)" >&2
    exit 1
fi
STUB
chmod +x "$readonly_bin/install_name_tool"

if ! readonly_output=$(
    HOME="$readonly_home" \
        PATH="$readonly_bin:$PATH" \
        GAME_APP="$readonly_game_app" \
        QT_SOURCE=homebrew \
        QT_PREFIX="$readonly_qt_prefix" \
        WORMSWMD_ALLOW_CUSTOM_QT_PREFIX=1 \
        "$ROOT_DIR/scripts/02_replace_qt_frameworks.sh" 2>&1
); then
    fail "Qt replacement could not rewrite copied read-only framework binaries: $readonly_output"
fi

for framework in QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus QtSvg; do
    installed_binary="$readonly_game_app/Contents/Frameworks/$framework.framework/Versions/5/$framework"
    [[ -w "$installed_binary" ]] \
        || fail "installed $framework framework binary is not owner-writable"
done
[[ ! -e "$readonly_game_app/Contents/PlugIns/accessible" ]] \
    || fail "Qt replacement left the stale Qt 5.3 accessible plugin directory"
[[ ! -e "$readonly_game_app/Contents/PlugIns/printsupport" ]] \
    || fail "Qt replacement left the stale Qt 5.3 print support plugin directory"

printf 'Read-only Qt framework regression check passed.\n'

config_home="$tmp_dir/config-home"
config_fake_bin="$tmp_dir/config-bin"
config_game_app="$config_home/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"

mkdir -p \
    "$config_fake_bin" \
    "$config_game_app/Contents/MacOS" \
    "$config_game_app/Contents/Frameworks" \
    "$config_game_app/Contents/PlugIns/platforms" \
    "$config_game_app/Contents/PlugIns/imageformats" \
    "$config_game_app/Contents/Resources/DataOSX" \
    "$config_game_app/Contents/Resources/CommonData"

printf '#!/bin/bash\nexit 0\n' > "$config_game_app/Contents/MacOS/Worms W.M.D"
chmod +x "$config_game_app/Contents/MacOS/Worms W.M.D"
config_exec_original=$(cat "$config_game_app/Contents/MacOS/Worms W.M.D")
printf 'original galaxy library\n' > "$config_game_app/Contents/MacOS/libGalaxy.dylib"
config_galaxy_original=$(cat "$config_game_app/Contents/MacOS/libGalaxy.dylib")
printf 'original framework\n' > "$config_game_app/Contents/Frameworks/original-framework.txt"
printf 'original platform plugin\n' > "$config_game_app/Contents/PlugIns/platforms/original-platform.dylib"
printf 'original image plugin\n' > "$config_game_app/Contents/PlugIns/imageformats/original-image.dylib"
printf '<plist version="1.0"><dict></dict></plist>\n' > "$config_game_app/Contents/Info.plist"
printf 'URL_Internal = "http://xom.team17.com"\n' > "$config_game_app/Contents/Resources/DataOSX/SteamConfig.txt"
printf 'URL_Internal = "http://xom.team17.com"\n' > "$config_game_app/Contents/Resources/DataOSX/PcLanConfig.txt"
printf 'MainUrl = "http://www.google-analytics.com"\n' > "$config_game_app/Contents/Resources/CommonData/AnalyticsConfig.txt"
config_pclan_original=$(cat "$config_game_app/Contents/Resources/DataOSX/PcLanConfig.txt")

cat > "$config_fake_bin/sw_vers" <<'STUB'
#!/bin/bash
case "${1:-}" in
    -productName) printf '%s\n' "macOS" ;;
    -productVersion) printf '%s\n' "26.0.1" ;;
    -buildVersion) printf '%s\n' "99A999" ;;
    *) exit 1 ;;
esac
STUB

cat > "$config_fake_bin/uname" <<'STUB'
#!/bin/bash
printf '%s\n' "x86_64"
STUB

cat > "$config_fake_bin/arch" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-x86_64" ]]; then
    shift
fi
exec "$@"
STUB

cat > "$config_fake_bin/clang" <<'STUB'
#!/bin/bash
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            out="${2:-}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
[[ -n "$out" ]] || exit 1
mkdir -p "$(dirname "$out")"
printf 'fake macho\n' > "$out"
exit 0
STUB

cat > "$config_fake_bin/lipo" <<'STUB'
#!/bin/bash
case "${1:-}" in
    -create)
        out=""
        while [[ $# -gt 0 ]]; do
            if [[ "$1" == "-output" ]]; then
                out="${2:-}"
                break
            fi
            shift
        done
        [[ -n "$out" ]] || exit 1
        printf 'fake universal macho\n' > "$out"
        ;;
    -archs)
        if [[ "${WORMS_TEST_FAIL_AGL_VERIFY:-}" == "1" ]] \
            && [[ "${2:-}" == *"AGL.framework"* ]]; then
            printf '%s\n' "arm64"
        else
            printf '%s\n' "x86_64"
        fi
        ;;
    -info)
        printf '%s\n' "Architectures in the fat file: ${2:-binary} are: x86_64 arm64"
        ;;
    *)
        exit 1
        ;;
esac
STUB

cat > "$config_fake_bin/file" <<'STUB'
#!/bin/bash
printf '%s: Mach-O universal binary with 2 architectures\n' "${1:-binary}"
STUB

cat > "$config_fake_bin/otool" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-L" ]]; then
    printf '%s:\n' "${2:-binary}"
    if [[ "${2:-}" == */Contents/MacOS/Worms\ W.M.D ]]; then
        printf '\t@rpath/libglib-2.0.0.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
    fi
    printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
    exit 0
fi
if [[ "${1:-}" == "-l" ]] && [[ "${2:-}" == */Contents/MacOS/Worms\ W.M.D ]]; then
    cat <<'LOADS'
Load command 1
          cmd LC_RPATH
      cmdsize 48
         path @executable_path/../Frameworks (offset 12)
LOADS
    exit 0
fi
exit 1
STUB

cat > "$config_fake_bin/install_name_tool" <<'STUB'
#!/bin/bash
target=""
for target in "$@"; do
    :
done
if [[ "$target" == */Contents/MacOS/Worms\ W.M.D ]]; then
    printf '%s\n' '# mutated install names' >> "$target"
    if [[ "${WORMS_TEST_FORCE_HASH_MISMATCH:-}" == "1" ]]; then
        : > "$WORMS_TEST_HASH_MISMATCH_MARKER"
    fi
fi
exit 0
STUB

cat > "$config_fake_bin/codesign" <<'STUB'
#!/bin/bash
exit 0
STUB

cat > "$config_fake_bin/xattr" <<'STUB'
#!/bin/bash
exit 0
STUB

cat > "$config_fake_bin/shasum" <<'STUB'
#!/bin/bash
if [[ "${WORMS_TEST_FORCE_HASH_MISMATCH:-}" == "1" ]] \
    && [[ -f "$WORMS_TEST_HASH_MISMATCH_MARKER" ]]; then
    for arg in "$@"; do
        case "$arg" in
            "$WORMS_TEST_GAME_APP"/Contents/*)
                for candidate in "$@"; do
                    [[ "$candidate" == "$WORMS_TEST_GAME_APP"/Contents/* ]] || continue
                    printf '%064d  %s\n' 0 "$candidate"
                done
                exit 0
                ;;
        esac
    done
fi
exec /usr/bin/shasum "$@"
STUB

chmod +x "$config_fake_bin"/*

set +e
config_output=$(
    HOME="$config_home" \
        PATH="$config_fake_bin:$PATH" \
        GAME_APP="$config_game_app" \
        WORMS_TEST_GAME_APP="$config_game_app" \
        WORMS_TEST_FAIL_AGL_VERIFY=1 \
        WORMS_TEST_FORCE_HASH_MISMATCH=1 \
        WORMS_TEST_HASH_MISMATCH_MARKER="$tmp_dir/config-hash-mismatch" \
        "$ROOT_DIR/fix_worms_wmd.sh" --force 2>&1
)
config_status=$?
set -e

if [[ "$config_status" -eq 0 ]]; then
    fail "installer succeeded even though AGL verification was forced to fail"
fi

if grep -Fq "Rolled back to original state." <<< "$config_output"; then
    fail "rollback claimed original state after restored-file verification failed"
fi
grep -Fq "ERROR: Rollback restoration verification failed." <<< "$config_output" \
    || fail "rollback did not report failed restored-file verification: $config_output"

config_pclan_after=$(cat "$config_game_app/Contents/Resources/DataOSX/PcLanConfig.txt")
if [[ "$config_pclan_after" != "$config_pclan_original" ]]; then
    fail "PcLanConfig.txt was not restored after rollback"
fi
config_exec_after=$(cat "$config_game_app/Contents/MacOS/Worms W.M.D")
if [[ "$config_exec_after" != "$config_exec_original" ]]; then
    fail "main executable was not restored after a post-path-fix rollback"
fi
config_galaxy_after=$(cat "$config_game_app/Contents/MacOS/libGalaxy.dylib")
if [[ "$config_galaxy_after" != "$config_galaxy_original" ]]; then
    fail "Galaxy library was not restored after rollback"
fi

config_backup=$(find "$config_home/Documents" -mindepth 1 -maxdepth 1 -type d -name 'WormsWMD-Backup-*' -print -quit)
[[ -n "$config_backup" ]] || fail "post-path-fix rollback did not preserve its backup"
grep -Fq $'MacOS/Worms W.M.D' "$config_backup/BACKUP_MANIFEST.tsv" \
    || fail "backup manifest does not cover the mutable main executable"
grep -Fq $'MacOS/libGalaxy.dylib' "$config_backup/BACKUP_MANIFEST.tsv" \
    || fail "backup manifest does not cover the GOG library mutated by deep signing"
grep -Fq $'BACKUP_METADATA.tsv' "$config_backup/BACKUP_MANIFEST.tsv" \
    || fail "backup manifest does not cover source-app identity metadata"

sign_home="$tmp_dir/sign-home"
sign_game_app="$sign_home/GOG Games/Worms W.M.D/Worms W.M.D.app"
sign_bin="$tmp_dir/sign-bin"
mkdir -p "$(dirname "$sign_game_app")" "$sign_bin"
cp -R "$config_game_app" "$sign_game_app"
sign_exec_before=$(shasum -a 256 "$sign_game_app/Contents/MacOS/Worms W.M.D" | awk '{print $1}')
sign_galaxy_before=$(shasum -a 256 "$sign_game_app/Contents/MacOS/libGalaxy.dylib" | awk '{print $1}')
cat > "$sign_bin/codesign" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "--force" ]]; then
    printf '%s\n' '# partial signing mutation' >> "$WORMS_TEST_SIGN_APP/Contents/MacOS/Worms W.M.D"
    printf '%s\n' '# partial signing mutation' >> "$WORMS_TEST_SIGN_APP/Contents/MacOS/libGalaxy.dylib"
    printf '%s\n' 'synthetic codesign failure' >&2
    exit 92
fi
exit 0
STUB
chmod +x "$sign_bin/codesign"
set +e
sign_output=$(
    HOME="$sign_home" \
        PATH="$sign_bin:$config_fake_bin:$PATH" \
        GAME_APP="$sign_game_app" \
        WORMS_TEST_GAME_APP="$sign_game_app" \
        WORMS_TEST_HASH_MISMATCH_MARKER="$tmp_dir/unused-hash-mismatch" \
        WORMS_TEST_SIGN_APP="$sign_game_app" \
        "$ROOT_DIR/fix_worms_wmd.sh" --force 2>&1
)
sign_status=$?
set -e
if [[ "$sign_status" -eq 0 ]]; then
    fail "installer treated a partial codesign failure as success: $sign_output"
fi
grep -Fq 'Could not apply the ad-hoc code signature' <<< "$sign_output" \
    || fail "installer hid the codesign failure: $sign_output"
grep -Fq 'Rolled back to original game files.' <<< "$sign_output" \
    || fail "codesign failure did not trigger rollback: $sign_output"
[[ "$(shasum -a 256 "$sign_game_app/Contents/MacOS/Worms W.M.D" | awk '{print $1}')" == "$sign_exec_before" ]] \
    || fail "codesign rollback did not restore the main executable"
[[ "$(shasum -a 256 "$sign_game_app/Contents/MacOS/libGalaxy.dylib" | awk '{print $1}')" == "$sign_galaxy_before" ]] \
    || fail "codesign rollback did not restore libGalaxy.dylib"

restore_home="$tmp_dir/multi-restore-home"
restore_steam_app="$restore_home/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
restore_gog_app="$restore_home/GOG Games/Worms W.M.D/Worms W.M.D.app"
gog_backup="$restore_home/Documents/WormsWMD-Backup-20990101-000000"
mkdir -p \
    "$restore_steam_app/Contents/MacOS" \
    "$restore_steam_app/Contents/Frameworks" \
    "$restore_steam_app/Contents/PlugIns" \
    "$restore_gog_app/Contents/MacOS" \
    "$gog_backup/Frameworks" \
    "$gog_backup/PlugIns"
printf '#!/bin/bash\nexit 0\n' > "$restore_steam_app/Contents/MacOS/Worms W.M.D"
printf 'unexpected current MacOS file\n' > "$restore_steam_app/Contents/MacOS/unexpected-current.dylib"
printf '#!/bin/bash\nexit 0\n' > "$restore_gog_app/Contents/MacOS/Worms W.M.D"
chmod +x \
    "$restore_steam_app/Contents/MacOS/Worms W.M.D" \
    "$restore_gog_app/Contents/MacOS/Worms W.M.D"
restore_steam_real=$(cd "$restore_steam_app" && pwd -P)
restore_gog_real=$(cd "$restore_gog_app" && pwd -P)
printf 'steam original\n' > "$restore_steam_app/Contents/Frameworks/store-marker.txt"
: > "$restore_steam_app/Contents/Frameworks/libsteam_api.dylib"
printf 'gog backup\n' > "$gog_backup/Frameworks/store-marker.txt"
printf '<plist version="1.0"><dict></dict></plist>\n' > "$gog_backup/Info.plist"
printf '# WormsWMD backup metadata v1\ngame_app_path\t%s\ngame_source\tgog\n' \
    "$restore_gog_real" > "$gog_backup/BACKUP_METADATA.tsv"
gog_marker_hash=$(shasum -a 256 "$gog_backup/Frameworks/store-marker.txt" | awk '{print $1}')
gog_marker_size=$(stat -f%z "$gog_backup/Frameworks/store-marker.txt")
gog_info_hash=$(shasum -a 256 "$gog_backup/Info.plist" | awk '{print $1}')
gog_info_size=$(stat -f%z "$gog_backup/Info.plist")
printf '# WormsWMD manifest v1\n# sha256\tsize\tpath\n%s\t%s\t%s\n%s\t%s\t%s\n' \
    "$gog_marker_hash" "$gog_marker_size" "Frameworks/store-marker.txt" \
    "$gog_info_hash" "$gog_info_size" "Info.plist" \
    > "$gog_backup/BACKUP_MANIFEST.tsv"

set +e
cross_restore_output=$(
    HOME="$restore_home" \
        GAME_APP="$restore_steam_app" \
        "$ROOT_DIR/fix_worms_wmd.sh" --restore --force 2>&1
)
cross_restore_status=$?
set -e
if [[ "$cross_restore_status" -eq 0 ]]; then
    fail "restore accepted a backup bound to a different game installation"
fi
grep -Fq "No compatible backup found for: $restore_steam_app" <<< "$cross_restore_output" \
    || fail "cross-install restore refusal was not actionable: $cross_restore_output"
grep -Fxq 'steam original' "$restore_steam_app/Contents/Frameworks/store-marker.txt" \
    || fail "cross-install restore modified the selected Steam app"

printf '# WormsWMD backup metadata v1\ngame_app_path\t%s\ngame_source\tgog\n' \
    "$restore_steam_real" > "$gog_backup/BACKUP_METADATA.tsv"
set +e
unmanifested_output=$(
    HOME="$restore_home" \
        GAME_APP="$restore_steam_app" \
        "$ROOT_DIR/fix_worms_wmd.sh" --restore --force 2>&1
)
unmanifested_status=$?
set -e
if [[ "$unmanifested_status" -eq 0 ]]; then
    fail "restore trusted source-app metadata that was not covered by the manifest: $unmanifested_output"
fi
grep -Fxq 'steam original' "$restore_steam_app/Contents/Frameworks/store-marker.txt" \
    || fail "unmanifested backup metadata allowed a cross-install mutation"

single_restore_home="$tmp_dir/single-restore-home"
single_restore_app="$single_restore_home/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
single_unmanifested_backup="$single_restore_home/Documents/WormsWMD-Backup-20988000-000000"
mkdir -p \
    "$single_restore_home/Applications" \
    "$single_restore_app/Contents/MacOS" \
    "$single_restore_app/Contents/Frameworks" \
    "$single_restore_app/Contents/PlugIns" \
    "$single_unmanifested_backup/Frameworks" \
    "$single_unmanifested_backup/PlugIns"
printf '#!/bin/bash\nexit 0\n' > "$single_restore_app/Contents/MacOS/Worms W.M.D"
chmod +x "$single_restore_app/Contents/MacOS/Worms W.M.D"
: > "$single_restore_app/Contents/Frameworks/libsteam_api.dylib"
printf 'single original\n' > "$single_restore_app/Contents/Frameworks/store-marker.txt"
printf 'unmanifested replacement\n' > "$single_unmanifested_backup/Frameworks/store-marker.txt"
single_restore_real=$(cd "$single_restore_app" && pwd -P)
printf '# WormsWMD backup metadata v1\ngame_app_path\t%s\ngame_source\tsteam\ncode_signature_present\tfalse\n' \
    "$single_restore_real" > "$single_unmanifested_backup/BACKUP_METADATA.tsv"
set +e
single_unmanifested_output=$(
    HOME="$single_restore_home" \
        GAME_APP="$single_restore_app" \
        WORMSWMD_TEST_APPLICATIONS_ROOT="$single_restore_home/Applications" \
        "$ROOT_DIR/fix_worms_wmd.sh" --restore --force 2>&1
)
single_unmanifested_status=$?
set -e
if [[ "$single_unmanifested_status" -eq 0 ]]; then
    fail "single-install restore treated unmanifested metadata as a legacy backup: $single_unmanifested_output"
fi
grep -Fxq 'single original' "$single_restore_app/Contents/Frameworks/store-marker.txt" \
    || fail "unmanifested metadata modified a single detected installation"

same_path_gog_backup="$restore_home/Documents/WormsWMD-Backup-20987500-000000"
mkdir -p "$same_path_gog_backup/Frameworks" "$same_path_gog_backup/PlugIns"
printf 'same-path gog backup\n' > "$same_path_gog_backup/Frameworks/store-marker.txt"
printf '# WormsWMD backup metadata v1\ngame_app_path\t%s\ngame_source\tgog\ncode_signature_present\tfalse\n' \
    "$restore_steam_real" > "$same_path_gog_backup/BACKUP_METADATA.tsv"
(
    # shellcheck source=/dev/null
    source "$ROOT_DIR/scripts/common.sh"
    worms_write_manifest "$same_path_gog_backup" "$same_path_gog_backup/BACKUP_MANIFEST.tsv" \
        Frameworks PlugIns BACKUP_METADATA.tsv
)
set +e
same_path_output=$(
    HOME="$restore_home" \
        GAME_APP="$restore_steam_app" \
        "$ROOT_DIR/fix_worms_wmd.sh" --restore --force 2>&1
)
same_path_status=$?
set -e
if [[ "$same_path_status" -eq 0 ]]; then
    fail "restore accepted a GOG backup for a Steam app at the same canonical path: $same_path_output"
fi
grep -Fxq 'steam original' "$restore_steam_app/Contents/Frameworks/store-marker.txt" \
    || fail "same-path cross-store restore modified the selected Steam app"
mv "$same_path_gog_backup" "$restore_home/Rejected-WormsWMD-Backup-20987500-000000"

invalid_backup="$restore_home/Documents/WormsWMD-Backup-20985000-000000"
mkdir -p "$invalid_backup/Frameworks" "$invalid_backup/PlugIns" "$invalid_backup/MacOS"
printf 'invalid metadata backup\n' > "$invalid_backup/Frameworks/store-marker.txt"
printf '#!/bin/bash\nexit 99\n' > "$invalid_backup/MacOS/Worms W.M.D"
chmod +x "$invalid_backup/MacOS/Worms W.M.D"
printf '# WormsWMD backup metadata v1\ngame_app_path\t%s\ngame_source\tsteam\ncode_signature_present\tinvalid\n' \
    "$restore_steam_real" > "$invalid_backup/BACKUP_METADATA.tsv"
(
    # shellcheck source=/dev/null
    source "$ROOT_DIR/scripts/common.sh"
    worms_write_manifest "$invalid_backup" "$invalid_backup/BACKUP_MANIFEST.tsv" \
        Frameworks PlugIns MacOS BACKUP_METADATA.tsv
)
set +e
invalid_metadata_output=$(
    HOME="$restore_home" \
        GAME_APP="$restore_steam_app" \
        "$ROOT_DIR/fix_worms_wmd.sh" --restore --force 2>&1
)
invalid_metadata_status=$?
set -e
if [[ "$invalid_metadata_status" -eq 0 ]]; then
    fail "restore accepted invalid source-app metadata: $invalid_metadata_output"
fi
grep -Fxq 'steam original' "$restore_steam_app/Contents/Frameworks/store-marker.txt" \
    || fail "invalid backup metadata was detected only after game mutation began"
if grep -Fq 'exit 99' "$restore_steam_app/Contents/MacOS/Worms W.M.D"; then
    fail "invalid backup metadata allowed executable mutation"
fi
mv "$invalid_backup" "$restore_home/Rejected-WormsWMD-Backup-20985000-000000"

steam_backup="$restore_home/Documents/WormsWMD-Backup-20980101-000000"
mkdir -p \
    "$steam_backup/Frameworks" \
    "$steam_backup/PlugIns" \
    "$steam_backup/MacOS" \
    "$steam_backup/_CodeSignature"
printf 'steam restored\n' > "$steam_backup/Frameworks/store-marker.txt"
: > "$steam_backup/Frameworks/libsteam_api.dylib"
printf '#!/bin/bash\nexit 7\n' > "$steam_backup/MacOS/Worms W.M.D"
chmod +x "$steam_backup/MacOS/Worms W.M.D"
steam_backup_exec_hash=$(shasum -a 256 "$steam_backup/MacOS/Worms W.M.D" | awk '{print $1}')
steam_backup_exec_size=$(stat -f%z "$steam_backup/MacOS/Worms W.M.D")
printf 'original signature\n' > "$steam_backup/_CodeSignature/CodeResources"
printf '<plist version="1.0"><dict></dict></plist>\n' > "$steam_backup/Info.plist"
printf '# WormsWMD backup metadata v2\ngame_app_path\t%s\ngame_source\tsteam\ngame_executable_sha256\t%s\ngame_executable_size\t%s\nmacos_tree_complete\ttrue\ncode_signature_present\ttrue\n' \
    "$restore_steam_real" "$steam_backup_exec_hash" "$steam_backup_exec_size" \
    > "$steam_backup/BACKUP_METADATA.tsv"
(
    # shellcheck source=/dev/null
    source "$ROOT_DIR/scripts/common.sh"
    worms_write_manifest "$steam_backup" "$steam_backup/BACKUP_MANIFEST.tsv" \
        Frameworks PlugIns MacOS _CodeSignature Info.plist BACKUP_METADATA.tsv
)

valid_restore_output=$(HOME="$restore_home" \
    GAME_APP="$restore_steam_app" \
    "$ROOT_DIR/fix_worms_wmd.sh" --restore --force 2>&1) \
    || fail "restore rejected a valid backup bound to the selected Steam app: $valid_restore_output"
grep -Fxq 'steam restored' "$restore_steam_app/Contents/Frameworks/store-marker.txt" \
    || fail "valid source-bound backup did not restore Steam files"
grep -Fxq 'original signature' "$restore_steam_app/Contents/_CodeSignature/CodeResources" \
    || fail "restore did not restore original signature resources"
grep -Fq 'exit 7' "$restore_steam_app/Contents/MacOS/Worms W.M.D" \
    || fail "restore did not restore the original main executable"
[[ ! -e "$restore_steam_app/Contents/MacOS/unexpected-current.dylib" ]] \
    || fail "current v2 restore left a MacOS file absent from the backup"

custom_restore_home="$tmp_dir/custom-restore-home"
custom_default_app="$custom_restore_home/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
custom_target_app="$custom_restore_home/Custom Location/Worms W.M.D.app"
legacy_backup="$custom_restore_home/Documents/WormsWMD-Backup-20970101-000000"
mkdir -p \
    "$custom_default_app/Contents/MacOS" \
    "$custom_target_app/Contents/MacOS" \
    "$custom_target_app/Contents/Frameworks" \
    "$custom_target_app/Contents/PlugIns" \
    "$legacy_backup/Frameworks" \
    "$legacy_backup/PlugIns"
printf '#!/bin/bash\nexit 0\n' > "$custom_default_app/Contents/MacOS/Worms W.M.D"
printf '#!/bin/bash\nexit 0\n' > "$custom_target_app/Contents/MacOS/Worms W.M.D"
chmod +x \
    "$custom_default_app/Contents/MacOS/Worms W.M.D" \
    "$custom_target_app/Contents/MacOS/Worms W.M.D"
printf 'custom original\n' > "$custom_target_app/Contents/Frameworks/store-marker.txt"
printf 'legacy steam backup\n' > "$legacy_backup/Frameworks/store-marker.txt"
(
    # shellcheck source=/dev/null
    source "$ROOT_DIR/scripts/common.sh"
    worms_write_manifest "$legacy_backup" "$legacy_backup/BACKUP_MANIFEST.tsv" Frameworks PlugIns
)
set +e
custom_restore_output=$(
    HOME="$custom_restore_home" \
        GAME_APP="$custom_target_app" \
        "$ROOT_DIR/fix_worms_wmd.sh" --restore --force 2>&1
)
custom_restore_status=$?
set -e
if [[ "$custom_restore_status" -eq 0 ]]; then
    fail "restore treated a custom GAME_APP plus Steam as an unambiguous legacy target: $custom_restore_output"
fi
grep -Fxq 'custom original' "$custom_target_app/Contents/Frameworks/store-marker.txt" \
    || fail "ambiguous legacy restore modified a custom game installation"

gog_guidance_home="$tmp_dir/gog-guidance-home"
gog_guidance_app="$gog_guidance_home/GOG Games/Worms W.M.D/Worms W.M.D.app"
gog_guidance_backup="$gog_guidance_home/Documents/WormsWMD-Backup-20960101-000000"
mkdir -p \
    "$gog_guidance_app/Contents/MacOS" \
    "$gog_guidance_app/Contents/Frameworks" \
    "$gog_guidance_app/Contents/PlugIns" \
    "$gog_guidance_backup/Frameworks" \
    "$gog_guidance_backup/PlugIns" \
    "$gog_guidance_backup/MacOS"
printf '#!/bin/bash\nexit 0\n' > "$gog_guidance_app/Contents/MacOS/Worms W.M.D"
: > "$gog_guidance_app/Contents/MacOS/libGalaxy.dylib"
chmod +x "$gog_guidance_app/Contents/MacOS/Worms W.M.D"
cp "$gog_guidance_app/Contents/MacOS/Worms W.M.D" "$gog_guidance_backup/MacOS/Worms W.M.D"
cp "$gog_guidance_app/Contents/MacOS/libGalaxy.dylib" "$gog_guidance_backup/MacOS/libGalaxy.dylib"
printf 'current gog files\n' > "$gog_guidance_app/Contents/Frameworks/store-marker.txt"
printf 'restored gog files\n' > "$gog_guidance_backup/Frameworks/store-marker.txt"
gog_guidance_real=$(cd "$gog_guidance_app" && pwd -P)
gog_guidance_exec_hash=$(shasum -a 256 "$gog_guidance_backup/MacOS/Worms W.M.D" | awk '{print $1}')
gog_guidance_exec_size=$(stat -f%z "$gog_guidance_backup/MacOS/Worms W.M.D")
printf '# WormsWMD backup metadata v2\ngame_app_path\t%s\ngame_source\tgog\ngame_executable_sha256\t%s\ngame_executable_size\t%s\nmacos_tree_complete\ttrue\ncode_signature_present\tfalse\n' \
    "$gog_guidance_real" "$gog_guidance_exec_hash" "$gog_guidance_exec_size" \
    > "$gog_guidance_backup/BACKUP_METADATA.tsv"
(
    # shellcheck source=/dev/null
    source "$ROOT_DIR/scripts/common.sh"
    worms_write_manifest "$gog_guidance_backup" "$gog_guidance_backup/BACKUP_MANIFEST.tsv" \
        Frameworks PlugIns MacOS BACKUP_METADATA.tsv
)
gog_guidance_output=$(HOME="$gog_guidance_home" \
    GAME_APP="$gog_guidance_app" \
    "$ROOT_DIR/fix_worms_wmd.sh" --restore --force 2>&1) \
    || fail "restore rejected a valid GOG backup: $gog_guidance_output"
grep -Fq 'Use GOG Galaxy to repair the game if needed:' <<< "$gog_guidance_output" \
    || fail "GOG restore did not print storefront-appropriate repair guidance: $gog_guidance_output"
if grep -Fq 'Use Steam to repair the game if needed:' <<< "$gog_guidance_output"; then
    fail "GOG restore incorrectly printed Steam repair guidance"
fi

printf 'Installer config rollback regression check passed.\n'
