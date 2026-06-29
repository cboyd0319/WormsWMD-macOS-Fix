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

grep -Fq "Rolled back to original state." <<< "$output" \
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

printf 'Installer rollback regression check passed.\n'
