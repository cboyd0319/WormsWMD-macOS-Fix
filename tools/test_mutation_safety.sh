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
for control_path in $'unsafe\033path' $'unsafe\apath' $'unsafe\bpath' $'unsafe\177path'; do
    if worms_reject_control_chars "$control_path" "control-byte test path" 2>/dev/null; then
        fail "control-character validation accepted a non-whitespace control byte"
    fi
done

malformed_app="$tmp_dir/Malformed.app"
make_game "$malformed_app"
rm -rf "$malformed_app/Contents/Resources/DataOSX"
printf 'not a directory\n' > "$malformed_app/Contents/Resources/DataOSX"

if worms_validate_game_app_for_mutation "$malformed_app" 2>/dev/null; then
    fail "mutation validation accepted a non-directory DataOSX path"
fi

linked_macos_app="$tmp_dir/LinkedMacOS.app"
outside_macos="$tmp_dir/outside-macos"
make_game "$linked_macos_app"
mv "$linked_macos_app/Contents/MacOS" "$outside_macos"
ln -s "$outside_macos" "$linked_macos_app/Contents/MacOS"
if worms_validate_game_app_for_mutation "$linked_macos_app" 2>/dev/null; then
    fail "mutation validation accepted a MacOS directory linked outside the app"
fi

linked_macos_file_app="$tmp_dir/LinkedMacOSFile.app"
outside_macos_file="$tmp_dir/outside-macos-file.dylib"
make_game "$linked_macos_file_app"
printf 'outside Mach-O placeholder\n' > "$outside_macos_file"
ln -s "$outside_macos_file" "$linked_macos_file_app/Contents/MacOS/libGalaxy.dylib"
if worms_validate_game_app_for_mutation "$linked_macos_file_app" 2>/dev/null; then
    fail "mutation validation accepted a nested MacOS symlink outside the app"
fi

hardlinked_macos_file_app="$tmp_dir/HardlinkedMacOSFile.app"
outside_macos_peer="$tmp_dir/outside-macos-peer.dylib"
make_game "$hardlinked_macos_file_app"
printf 'outside hardlink peer\n' > "$outside_macos_peer"
ln "$outside_macos_peer" "$hardlinked_macos_file_app/Contents/MacOS/libGalaxy.dylib"
if worms_validate_game_app_for_mutation "$hardlinked_macos_file_app" 2>/dev/null; then
    fail "mutation validation accepted a nested hardlink that deep signing can modify"
fi

linked_signature_app="$tmp_dir/LinkedSignature.app"
outside_signature="$tmp_dir/outside-signature"
make_game "$linked_signature_app"
mkdir -p "$outside_signature"
ln -s "$outside_signature" "$linked_signature_app/Contents/_CodeSignature"
if worms_validate_game_app_for_mutation "$linked_signature_app" 2>/dev/null; then
    fail "mutation validation accepted linked signature resources outside the app"
fi

invalid_signature_app="$tmp_dir/InvalidSignature.app"
make_game "$invalid_signature_app"
printf 'not a directory\n' > "$invalid_signature_app/Contents/_CodeSignature"
if worms_validate_game_app_for_mutation "$invalid_signature_app" 2>/dev/null; then
    fail "mutation validation accepted non-directory signature resources"
fi

in_tree_config_link_app="$tmp_dir/InTreeConfigLink.app"
make_game "$in_tree_config_link_app"
printf 'MainUrl = "http://www.team17.com"\n' \
    > "$in_tree_config_link_app/Contents/Resources/DataOSX/config-target.txt"
ln -s config-target.txt \
    "$in_tree_config_link_app/Contents/Resources/DataOSX/SteamConfig.txt"
if worms_validate_game_app_for_mutation "$in_tree_config_link_app" 2>/dev/null; then
    fail "mutation validation accepted an in-tree symlink for a mutable config file"
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
grep -Eq 'Refusing symlinked (SteamConfig[.]txt|game bundle mutation file)|Unsafe symlink target' <<< "$symlink_output" \
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
grep -Eq 'Refusing hardlinked (SteamConfig[.]txt|game bundle mutation file|tree file)' <<< "$hardlink_output" \
    || fail "config URL fixer did not explain hardlink refusal: $hardlink_output"
grep -Fxq 'MainUrl = "http://www.team17.com"' "$hardlink_peer" \
    || fail "hardlinked peer config was modified"

printf 'Mutation safety regression check passed.\n'
