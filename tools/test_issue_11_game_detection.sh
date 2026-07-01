#!/bin/bash
#
# Regression checks for issue #11 game discovery.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
installer="$ROOT_DIR/fix_worms_wmd.sh"

fail() {
    printf 'issue #11 game detection check failed: %s\n' "$*" >&2
    exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-issue11.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

function_file="$tmp_dir/auto_detect_game.sh"
awk '
    /^auto_detect_game\(\)/ { in_func=1 }
    in_func { print }
    /^}$/ && in_func { exit }
' "$installer" > "$function_file"

if [[ ! -s "$function_file" ]]; then
    fail "could not extract auto_detect_game"
fi

run_detection() (
    set -euo pipefail
    HOME="$1"
    # shellcheck source=/dev/null
    source "$ROOT_DIR/scripts/common.sh"
    # shellcheck source=/dev/null
    source "$function_file"
    # shellcheck disable=SC2329
    print_info() { printf 'INFO: %s\n' "$*"; }
    auto_detect_game
)

make_game() {
    local app_path="$1"

    mkdir -p "$app_path/Contents/MacOS"
    {
        printf '#!/bin/bash\n'
        printf 'exit 0\n'
    } > "$app_path/Contents/MacOS/Worms W.M.D"
    chmod +x "$app_path/Contents/MacOS/Worms W.M.D"
}

empty_home="$tmp_dir/empty-home"
mkdir -p "$empty_home"
empty_output=$(run_detection "$empty_home") \
    || fail "empty discovery crashed under Bash strict mode"
if [[ -n "$empty_output" ]]; then
    fail "empty discovery returned unexpected output: $empty_output"
fi

gog_home="$tmp_dir/gog-home"
gog_app="$gog_home/GOG Games/Worms W.M.D/Worms W.M.D.app"
make_game "$gog_app"
gog_output=$(run_detection "$gog_home") \
    || fail "GOG discovery crashed under Bash strict mode"
if [[ "$gog_output" != "$gog_app" ]]; then
    fail "GOG discovery returned '$gog_output' instead of '$gog_app'"
fi

diagnostics_output=$(HOME="$gog_home" "$ROOT_DIR/tools/collect_diagnostics.sh") \
    || fail "diagnostics failed with a GOG-style app path"
if ! grep -Fq "Found: ~/GOG Games/Worms W.M.D/Worms W.M.D.app" <<< "$diagnostics_output"; then
    fail "diagnostics did not auto-detect the GOG-style app path"
fi

preflight_output=$(HOME="$gog_home" "$ROOT_DIR/tools/preflight_check.sh" --quick 2>&1 || true)
if ! grep -Fq "Game found at: $gog_app" <<< "$preflight_output"; then
    fail "preflight did not auto-detect the GOG-style app path"
fi

watcher_output=$(HOME="$gog_home" "$ROOT_DIR/tools/watch_for_updates.sh" --check 2>&1 || true)
if grep -Fq "Game not found at:" <<< "$watcher_output"; then
    fail "update watcher did not auto-detect the GOG-style app path"
fi
if ! grep -Eq "Fix is (missing|partially applied|applied)" <<< "$watcher_output"; then
    fail "update watcher returned unexpected output for a GOG-style app path: $watcher_output"
fi

launch_output=$(HOME="$gog_home" "$ROOT_DIR/tools/launch_worms.sh" --no-crash-report 2>&1) \
    || fail "enhanced launcher did not auto-detect the GOG-style app path: $launch_output"

verify_output=$(HOME="$gog_home" "$installer" --verify 2>&1 || true)
if grep -Fq "Game not found at: $gog_home/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app" <<< "$verify_output"; then
    fail "installer --verify did not auto-detect the GOG-style app path"
fi
if ! grep -Fq "Game location: $gog_app" <<< "$verify_output"; then
    fail "installer --verify did not verify the GOG-style app path: $verify_output"
fi

dry_run_output=$(HOME="$gog_home" "$installer" --dry-run 2>&1 || true)
if ! grep -Fq "[dry-run] Game found: $gog_app" <<< "$dry_run_output"; then
    fail "installer --dry-run did not auto-detect the GOG-style app path: $dry_run_output"
fi

empty_game_app_output=$(HOME="$gog_home" GAME_APP="" "$installer" --dry-run 2>&1 || true)
if ! grep -Fq "[dry-run] Game found: $gog_app" <<< "$empty_game_app_output"; then
    fail "empty GAME_APP should not disable auto-detection: $empty_game_app_output"
fi

multi_home="$tmp_dir/multi-home"
multi_steam_app="$multi_home/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
multi_gog_app="$multi_home/GOG Games/Worms W.M.D/Worms W.M.D.app"
make_game "$multi_steam_app"
make_game "$multi_gog_app"
set +e
multi_output=$(run_detection "$multi_home" </dev/null 2>&1)
multi_status=$?
set -e
if [[ "$multi_status" -eq 0 ]] && [[ -n "$multi_output" ]]; then
    fail "noninteractive multiple-install discovery returned ambiguous output: $multi_output"
fi
if grep -Fq "Multiple game installations found" <<< "$multi_output"; then
    fail "noninteractive multiple-install discovery polluted stdout with menu text: $multi_output"
fi

verify_link_home="$tmp_dir/verify-link-home"
verify_link_app="$verify_link_home/Applications/Worms W.M.D.app"
verify_link_target="$tmp_dir/linked-dataosx"
make_game "$verify_link_app"
mkdir -p "$verify_link_app/Contents/Resources" "$verify_link_target"
ln -s "$verify_link_target" "$verify_link_app/Contents/Resources/DataOSX"
verify_link_output=$(HOME="$verify_link_home" GAME_APP="$verify_link_app" "$installer" --verify 2>&1 || true)
if grep -Fq "unsafe linked mutation paths" <<< "$verify_link_output"; then
    fail "installer --verify should not require mutation-safe bundle paths: $verify_link_output"
fi
if ! grep -Fq "Game location: $verify_link_app" <<< "$verify_link_output"; then
    fail "installer --verify did not reach read-only verification for linked resource paths: $verify_link_output"
fi

legacy_gog_home="$tmp_dir/legacy-gog-home"
legacy_gog_app="$legacy_gog_home/Library/Application Support/GOG.com/Games/Worms W.M.D/Worms W.M.D.app"
make_game "$legacy_gog_app"
legacy_gog_output=$(run_detection "$legacy_gog_home") \
    || fail "legacy GOG discovery crashed under Bash strict mode"
if [[ "$legacy_gog_output" != "$legacy_gog_app" ]]; then
    fail "legacy GOG discovery returned '$legacy_gog_output' instead of '$legacy_gog_app'"
fi

gog_no_periods_home="$tmp_dir/gog-no-periods-home"
gog_no_periods_app="$gog_no_periods_home/GOG Games/Worms WMD/Worms W.M.D.app"
make_game "$gog_no_periods_app"
gog_no_periods_output=$(run_detection "$gog_no_periods_home") \
    || fail "period-stripped GOG folder discovery crashed under Bash strict mode"
if [[ "$gog_no_periods_output" != "$gog_no_periods_app" ]]; then
    fail "period-stripped GOG folder discovery returned '$gog_no_periods_output' instead of '$gog_no_periods_app'"
fi

direct_no_periods_home="$tmp_dir/direct-no-periods-home"
direct_no_periods_app="$direct_no_periods_home/Applications/Worms WMD.app"
make_game "$direct_no_periods_app"
direct_no_periods_output=$(run_detection "$direct_no_periods_home") \
    || fail "period-stripped direct app discovery crashed under Bash strict mode"
if [[ "$direct_no_periods_output" != "$direct_no_periods_app" ]]; then
    fail "period-stripped direct app discovery returned '$direct_no_periods_output' instead of '$direct_no_periods_app'"
fi

steam_home="$tmp_dir/steam-home"
steam_app="$steam_home/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
steam_config="$steam_home/Library/Application Support/Steam/steamapps/libraryfolders.vdf"
make_game "$steam_app"
mkdir -p "$(dirname "$steam_config")"
cat > "$steam_config" <<EOF
"libraryfolders"
{
    "0"
    {
        "path" "$steam_home/Library/Application Support/Steam"
    }
}
EOF

steam_output=$(run_detection "$steam_home") \
    || fail "duplicate Steam discovery crashed under Bash strict mode"
if [[ "$steam_output" != "$steam_app" ]]; then
    fail "duplicate Steam discovery returned '$steam_output' instead of '$steam_app'"
fi

printf 'Issue #11 game detection check passed.\n'
