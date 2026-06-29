#!/bin/bash
#
# Regression checks for preflight diagnostic edge cases.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
preflight="$ROOT_DIR/tools/preflight_check.sh"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-preflight-regression.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    printf 'preflight regression check failed: %s\n' "$*" >&2
    exit 1
}

write_stub_tools() {
    local bin_dir="$1"

    mkdir -p "$bin_dir"
    cat > "$bin_dir/sw_vers" <<'STUB'
#!/bin/bash
case "${1:-}" in
    -productVersion)
        printf '%s\n' "${WORMS_TEST_MACOS_VERSION:-27.0}"
        ;;
    -buildVersion)
        printf '%s\n' "99A999"
        ;;
    -productName)
        printf '%s\n' "macOS"
        ;;
    *)
        exit 1
        ;;
esac
STUB
    cat > "$bin_dir/uname" <<'STUB'
#!/bin/bash
printf '%s\n' "${WORMS_TEST_ARCH:-arm64}"
STUB
    cat > "$bin_dir/xcode-select" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-p" ]]; then
    printf '%s\n' "/Library/Developer/CommandLineTools"
    exit 0
fi
exit 0
STUB
    cat > "$bin_dir/lipo" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-archs" ]]; then
    printf '%s\n' "${WORMS_TEST_LIPO_ARCHS:-x86_64}"
    exit 0
fi
exit 1
STUB
    chmod +x "$bin_dir/sw_vers" "$bin_dir/uname" "$bin_dir/xcode-select" "$bin_dir/lipo"
}

run_preflight_for_version() {
    local version="$1"
    local fake_bin="$tmp_dir/bin-$version"
    local game_app="$tmp_dir/game-$version/Worms W.M.D.app"

    write_stub_tools "$fake_bin"
    mkdir -p "$game_app/Contents/MacOS"
    : > "$game_app/Contents/MacOS/Worms W.M.D"
    chmod +x "$game_app/Contents/MacOS/Worms W.M.D"

    WORMS_TEST_MACOS_VERSION="$version" \
        WORMS_TEST_ARCH=arm64 \
        PATH="$fake_bin:$PATH" \
        GAME_APP="$game_app" \
        "$preflight" --quick 2>&1 || true
}

run_preflight_agl_case() {
    local case_name="$1"
    local agl_archs="$2"
    local create_binary="$3"
    local fake_bin="$tmp_dir/bin-agl-$case_name"
    local game_app="$tmp_dir/game-agl-$case_name/Worms W.M.D.app"
    local status

    write_stub_tools "$fake_bin"
    mkdir -p "$game_app/Contents/MacOS" "$game_app/Contents/Frameworks/AGL.framework/Versions/A"
    : > "$game_app/Contents/MacOS/Worms W.M.D"
    chmod +x "$game_app/Contents/MacOS/Worms W.M.D"
    if [[ "$create_binary" == "true" ]]; then
        : > "$game_app/Contents/Frameworks/AGL.framework/Versions/A/AGL"
    fi

    set +e
    output=$(
        WORMS_TEST_MACOS_VERSION=26.0.1 \
            WORMS_TEST_ARCH=arm64 \
            WORMS_TEST_LIPO_ARCHS="$agl_archs" \
            PATH="$fake_bin:$PATH" \
            GAME_APP="$game_app" \
            "$preflight" --quick 2>&1
    )
    status=$?
    set -e

    printf '%s\t%s\n%s\n' "$status" "$case_name" "$output"
}

if grep -Fq 'https://ads.t17service.com' "$preflight"; then
    fail "preflight still uses the noisy Team17 service root URL"
fi

grep -Fq "team17_status=\$(http_status \"https://www.team17.com/games/worms-w-m-d\")" "$preflight" \
    || fail "Team17 network check does not use the public Worms W.M.D page"
grep -Fq "steam_status=\$(http_status \"https://store.steampowered.com/app/327030/Worms_WMD/\")" "$preflight" \
    || fail "Steam network check does not use the Worms W.M.D store page"
grep -Fq "gog_status=\$(http_status \"https://www.gog.com/en/game/worms_wmd\")" "$preflight" \
    || fail "GOG network check does not use the Worms W.M.D store page"
grep -Fq 'Team17 Worms W.M.D page reachable' "$preflight" \
    || fail "Team17 network check has the wrong user-facing label"
grep -Fq 'Steam Worms W.M.D store page reachable' "$preflight" \
    || fail "Steam network check has the wrong user-facing label"
grep -Fq 'GOG Worms W.M.D store page reachable' "$preflight" \
    || fail "GOG network check has the wrong user-facing label"
grep -Fq 'current version \([0-9][0-9.]*\)' "$preflight" \
    || fail "preflight does not parse the QtCore current version"
grep -Fq 'binary_archs()' "$preflight" \
    || fail "preflight architecture helper is missing"
grep -Fq 'macOS 27 (Golden Gate) detected' "$preflight" \
    || fail "preflight does not distinguish macOS 27 from macOS 26 Tahoe"
grep -Fq 'macOS 27 may need Rosetta reinstalled after upgrading' "$preflight" \
    || fail "preflight does not explain the macOS 27 Rosetta upgrade behavior"
grep -Fq 'section "Rosetta Notes"' "$preflight" \
    || fail "preflight uses a technical translation label instead of Rosetta Notes"
if grep -Fq 'Intel Translation Notes' "$preflight"; then
    fail "preflight exposes technical Intel translation wording"
fi
grep -Fq 'game-test-tool status' "$ROOT_DIR/fix_worms_wmd.sh" \
    || fail "fix engine does not report game-test-tool status after Rosetta install failures"
grep -Fq 'Rosetta 2 installed, but Worms still cannot use it' "$ROOT_DIR/fix_worms_wmd.sh" \
    || fail "fix engine does not verify x86_64 execution after Rosetta installation"
grep -Fq 'Worms W.M.D is an older Intel Mac game' "$ROOT_DIR/fix_worms_wmd.sh" \
    || fail "fix engine does not explain why Rosetta is needed"

preflight_26_output=$(run_preflight_for_version "26.5.1")
grep -Fq 'macOS version: 26.5.1' <<< "$preflight_26_output" \
    || fail "preflight test did not exercise the macOS 26 branch"
grep -Fq 'macOS 26 (Tahoe) detected - fix is REQUIRED' <<< "$preflight_26_output" \
    || fail "preflight does not preserve macOS 26 Tahoe messaging"
if grep -Fq 'macOS 27 (Golden Gate) detected' <<< "$preflight_26_output"; then
    fail "preflight incorrectly reports macOS 27 for macOS 26"
fi

preflight_27_output=$(run_preflight_for_version "27.0")
grep -Fq 'macOS version: 27.0' <<< "$preflight_27_output" \
    || fail "preflight test did not exercise the macOS 27 branch"
grep -Fq 'macOS 27 (Golden Gate) detected' <<< "$preflight_27_output" \
    || fail "preflight does not report macOS 27 Golden Gate"
if grep -Fq 'macOS 26 (Tahoe) detected' <<< "$preflight_27_output"; then
    fail "preflight incorrectly reports macOS 26 for macOS 27"
fi

missing_agl_output=$(run_preflight_agl_case "missing-binary" "x86_64" "false")
missing_agl_status=${missing_agl_output%%$'\t'*}
if [[ "$missing_agl_status" -eq 0 ]]; then
    fail "preflight succeeded with an AGL.framework directory but no AGL binary"
fi
grep -Fq "AGL stub binary NOT installed" <<< "$missing_agl_output" \
    || fail "preflight did not report the missing AGL binary"
if grep -Fq "AGL stub installed" <<< "$missing_agl_output"; then
    fail "preflight reported AGL installed when the binary was missing"
fi

wrong_agl_output=$(run_preflight_agl_case "wrong-arch" "arm64" "true")
wrong_agl_status=${wrong_agl_output%%$'\t'*}
if [[ "$wrong_agl_status" -eq 0 ]]; then
    fail "preflight succeeded with an AGL stub missing x86_64"
fi
grep -Fq "AGL stub does not include x86_64 architecture (arch: arm64)" <<< "$wrong_agl_output" \
    || fail "preflight did not report the wrong AGL architecture"

printf 'Preflight regression check passed.\n'
