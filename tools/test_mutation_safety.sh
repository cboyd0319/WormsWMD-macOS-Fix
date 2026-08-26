#!/bin/bash
#
# Regression checks for game-bundle mutation safety boundaries.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

fail() {
    printf 'mutation safety regression check failed: %s\n' "$*" >&2
    exit 1
}

make_game() {
    local app_path="$1"

    mkdir -p \
        "$app_path/Contents/MacOS" \
        "$app_path/Contents/Frameworks" \
        "$app_path/Contents/PlugIns/platforms" \
        "$app_path/Contents/PlugIns/imageformats" \
        "$app_path/Contents/Resources/DataOSX" \
        "$app_path/Contents/Resources/CommonData"
    printf '#!/bin/bash\nexit 0\n' > "$app_path/Contents/MacOS/Worms W.M.D"
    chmod +x "$app_path/Contents/MacOS/Worms W.M.D"
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-mutation-safety.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

if worms_reject_control_chars $'unsafe\tpath' "tabbed test path" 2>/dev/null; then
    fail "control-character validation accepted a tab-delimited path"
fi

malformed_app="$tmp_dir/Malformed.app"
make_game "$malformed_app"
rm -rf "$malformed_app/Contents/Resources/DataOSX"
printf 'not a directory\n' > "$malformed_app/Contents/Resources/DataOSX"

if worms_validate_game_app_for_mutation "$malformed_app" 2>/dev/null; then
    fail "mutation validation accepted a non-directory DataOSX path"
fi

symlink_app="$tmp_dir/Symlink.app"
outside_config="$tmp_dir/outside-config.txt"
make_game "$symlink_app"
printf 'MainUrl = "http://www.team17.com"\n' > "$outside_config"
rm -f "$symlink_app/Contents/Resources/DataOSX/SteamConfig.txt"
ln -s "$outside_config" "$symlink_app/Contents/Resources/DataOSX/SteamConfig.txt"

set +e
symlink_output=$(GAME_APP="$symlink_app" "$ROOT_DIR/scripts/07_fix_config_urls.sh" 2>&1)
symlink_status=$?
set -e

if [[ "$symlink_status" -eq 0 ]]; then
    fail "config URL fixer accepted a symlinked config file"
fi
grep -Fq 'Refusing symlinked SteamConfig.txt' <<< "$symlink_output" \
    || fail "config URL fixer did not explain symlink refusal: $symlink_output"
grep -Fxq 'MainUrl = "http://www.team17.com"' "$outside_config" \
    || fail "symlinked outside config was modified"

hardlink_app="$tmp_dir/Hardlink.app"
hardlink_peer="$tmp_dir/hardlink-peer.txt"
make_game "$hardlink_app"
printf 'MainUrl = "http://www.team17.com"\n' > "$hardlink_peer"
rm -f "$hardlink_app/Contents/Resources/DataOSX/SteamConfig.txt"
ln "$hardlink_peer" "$hardlink_app/Contents/Resources/DataOSX/SteamConfig.txt"

set +e
hardlink_output=$(GAME_APP="$hardlink_app" "$ROOT_DIR/scripts/07_fix_config_urls.sh" 2>&1)
hardlink_status=$?
set -e

if [[ "$hardlink_status" -eq 0 ]]; then
    fail "config URL fixer accepted a hardlinked config file"
fi
grep -Fq 'Refusing hardlinked SteamConfig.txt' <<< "$hardlink_output" \
    || fail "config URL fixer did not explain hardlink refusal: $hardlink_output"
grep -Fxq 'MainUrl = "http://www.team17.com"' "$hardlink_peer" \
    || fail "hardlinked peer config was modified"

printf 'Mutation safety regression check passed.\n'
