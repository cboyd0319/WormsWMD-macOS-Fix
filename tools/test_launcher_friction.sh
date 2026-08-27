#!/bin/bash
#
# Regression checks for the friendly launcher and first-read friction points.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

fail() {
    printf 'launcher friction check failed: %s\n' "$*" >&2
    exit 1
}

launcher="$ROOT_DIR/Worms W.M.D Fix.command"
readme_first="$ROOT_DIR/README_FIRST.txt"
readme="$ROOT_DIR/README.md"
install_doc="$ROOT_DIR/docs/INSTALL.md"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-launcher-friction.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

grep -Fq 'Launch Worms W.M.D now? [Y/n]' "$launcher" \
    || fail "launcher does not offer to launch after applying the fix"
grep -Fq 'run_launch_readiness_check' "$launcher" \
    || fail "launcher does not have a launch-readiness check"
readiness_block=$(awk '/^run_launch_readiness_check\(\)/ {inside=1} inside {print} /^}/ && inside {exit}' "$launcher")
grep -Fq 'select_game_app_if_needed' <<< "$readiness_block" \
    || fail "launcher readiness check does not preserve the selected installation"
launch_block=$(awk '/^launch_game\(\)/ {inside=1} inside {print} /^}/ && inside {exit}' "$launcher")
grep -Fq 'select_game_app_if_needed' <<< "$launch_block" \
    || fail "launcher launch action does not preserve the selected installation"
# shellcheck disable=SC2016
if grep -Fq 'print_line "  $i) $game"' "$launcher" \
    || grep -Fq 'print_line "Open this installation directly: $GAME_APP"' "$launcher"; then
    fail "launcher still sends an untrusted game path through printf %b"
fi
if grep -Fq "printf '%b" "$launcher"; then
    fail "launcher still interprets backslash escapes in rendered text"
fi
grep -Fq 'tools/preflight_check.sh" --quick' "$launcher" \
    || fail "launcher readiness check does not run quick preflight"
grep -Fq 'fix_worms_wmd.sh" --verify' "$launcher" \
    || fail "launcher readiness check does not run fix verification"
grep -Fq 'steam://run/327030' "$launcher" \
    || fail "launcher does not use the Steam app launch URL"
grep -Fq "7\${NC}) Launch Worms W.M.D" "$launcher" \
    || fail "launcher menu does not include launch option 7"
grep -Fq 'Please choose 1, 2, 3, 4, 5, 6, 7, or q.' "$launcher" \
    || fail "launcher invalid-choice prompt is missing option 7"

grep -Fq 'option 7' "$readme_first" \
    || fail "README_FIRST.txt does not mention launch option 7"
grep -Fq 'WormsWMD-macOS-Fix-VERSION.zip.sha256' "$readme_first" \
    || fail "README_FIRST.txt does not use a version-neutral checksum example"
if grep -Eq 'v1\.6\.[0-9]+' "$readme_first"; then
    fail "README_FIRST.txt contains a hardcoded release version"
fi

grep -Fq "| \`7\` | Launch Worms W.M.D. |" "$readme" \
    || fail "README.md launcher options table is missing option 7"
grep -Fq 'option 7 to launch Worms W.M.D' "$install_doc" \
    || fail "docs/INSTALL.md launcher option list is missing option 7"
# shellcheck disable=SC2016
grep -Fq 'if $HAS_GALAXY && ! $HAS_STEAM' "$install_doc" \
    || fail "manual restore docs do not reject ambiguous storefront identity"
grep -Fq "GAME_APP=\"\$GAME_APP\" ./fix_worms_wmd.sh --force" "$ROOT_DIR/tools/watch_for_updates.sh" \
    || fail "watcher daemon reapply does not forward GAME_APP"
if ! grep -F "GAME_APP=\"\$GAME_APP\" ./fix_worms_wmd.sh" "$ROOT_DIR/tools/watch_for_updates.sh" | grep -Fvq -- "--force"; then
    fail "watcher interactive reapply does not forward GAME_APP"
fi
grep -Fq "GAME_APP=\"\$GAME_APP\" ./fix_worms_wmd.sh --force" "$ROOT_DIR/tools/launch_worms.sh" \
    || fail "enhanced launcher --check-fix reapply does not forward GAME_APP"

grep -Fq 'macOS 26+ Fix Installer' "$ROOT_DIR/install.sh" \
    || fail "install.sh banner still uses stale macOS version wording"
grep -Fq 'macOS 26+ and macOS 27 Golden Gate' "$ROOT_DIR/Install Fix.command" \
    || fail "Install Fix.command banner does not mention macOS 27 Golden Gate"

watch_home="$tmp_dir/watch-home"
watch_bin="$tmp_dir/watch-bin"
watch_log="$tmp_dir/launchctl.log"
custom_game_app="$tmp_dir/Custom & Path/Worms W.M.D.app"
mkdir -p "$watch_home" "$watch_bin" "$custom_game_app/Contents/MacOS"
printf '#!/bin/bash\nexit 0\n' > "$custom_game_app/Contents/MacOS/Worms W.M.D"
chmod +x "$custom_game_app/Contents/MacOS/Worms W.M.D"
cat > "$watch_bin/launchctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$WORMS_TEST_LAUNCHCTL_LOG"
if [[ "${1:-}" == "print" ]]; then
    [[ "${WORMS_TEST_AGENT_ACTIVE:-0}" == "1" ]]
    exit
fi
if [[ "${1:-}" == "bootstrap" ]] \
    && [[ "${WORMS_TEST_BOOTSTRAP_FAIL_ONCE:-0}" == "1" ]]; then
    count=0
    [[ -f "$WORMS_TEST_BOOTSTRAP_COUNT" ]] && read -r count < "$WORMS_TEST_BOOTSTRAP_COUNT"
    count=$((count + 1))
    printf '%s\n' "$count" > "$WORMS_TEST_BOOTSTRAP_COUNT"
    [[ "$count" -gt 1 ]]
    exit
fi
exit 0
STUB
chmod +x "$watch_bin/launchctl"
cat > "$watch_bin/plutil" <<'STUB'
#!/bin/bash
[[ "${WORMS_TEST_PLUTIL_FAIL:-0}" != "1" ]] || exit 1
if [[ "${1:-}" == "-extract" ]]; then
    case "${2:-}" in
        Label)
            sed -n '/<key>Label<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;q;}' "${@: -1}"
            ;;
        ProgramArguments.0)
            sed -n '/<key>ProgramArguments<\/key>/{n;n;s/.*<string>\(.*\)<\/string>.*/\1/p;q;}' "${@: -1}"
            ;;
    esac
fi
exit 0
STUB
chmod +x "$watch_bin/plutil"

control_watch_home="$tmp_dir/control"$'\n'"watch-home"
mkdir -p "$control_watch_home"
if HOME="$control_watch_home" GAME_APP="$custom_game_app" \
    WORMS_TEST_LAUNCHCTL_LOG="$tmp_dir/control-watch-launchctl.log" \
    PATH="$watch_bin:$PATH" \
    "$ROOT_DIR/tools/watch_for_updates.sh" --install >/dev/null 2>&1; then
    fail "watcher install accepted a control-character HOME"
fi
[[ ! -e "$control_watch_home/Library/LaunchAgents" ]] \
    || fail "watcher install mutated a control-character HOME"

HOME="$watch_home" \
    GAME_APP="$custom_game_app" \
    WORMS_TEST_LAUNCHCTL_LOG="$watch_log" \
    PATH="$watch_bin:$PATH" \
    "$ROOT_DIR/tools/watch_for_updates.sh" --install >/dev/null \
    || fail "watcher install failed with a custom GAME_APP"

watch_plist="$watch_home/Library/LaunchAgents/com.wormswmd.fix.watcher.plist"
[[ -f "$watch_plist" ]] || fail "watcher install did not create a LaunchAgent plist"
[[ "$(stat -f '%Lp' "$watch_plist")" == "600" ]] \
    || fail "watcher LaunchAgent mode is not 0600"
/usr/bin/plutil -lint "$watch_plist" >/dev/null \
    || fail "watcher install did not produce a valid plist"
[[ "$(/usr/bin/plutil -extract Label raw -o - "$watch_plist")" \
    == "com.wormswmd.fix.watcher" ]] \
    || fail "watcher LaunchAgent has the wrong parsed label"
[[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$watch_plist")" \
    == "$ROOT_DIR/tools/watch_for_updates.sh" ]] \
    || fail "watcher LaunchAgent has the wrong parsed program"
grep -Fq '<key>EnvironmentVariables</key>' "$watch_plist" \
    || fail "watcher LaunchAgent does not persist environment variables"
grep -Fq '<key>GAME_APP</key>' "$watch_plist" \
    || fail "watcher LaunchAgent does not persist GAME_APP"
grep -Fq '<string>'"$tmp_dir"'/Custom &amp; Path/Worms W.M.D.app</string>' "$watch_plist" \
    || fail "watcher LaunchAgent does not XML-escape and persist the custom GAME_APP"
grep -Fq "bootstrap gui/" "$watch_log" \
    || fail "watcher install did not attempt to bootstrap the LaunchAgent"

linked_watch_home="$tmp_dir/linked-watch-home"
linked_watch_victim="$tmp_dir/linked-watch-victim.plist"
linked_watch_path="$linked_watch_home/Library/LaunchAgents/com.wormswmd.fix.watcher.plist"
mkdir -p "$linked_watch_home/Library/LaunchAgents"
printf 'linked victim\n' > "$linked_watch_victim"
ln -s "$linked_watch_victim" "$linked_watch_path"
if HOME="$linked_watch_home" GAME_APP="$custom_game_app" \
    WORMS_TEST_LAUNCHCTL_LOG="$tmp_dir/linked-launchctl.log" \
    PATH="$watch_bin:$PATH" \
    "$ROOT_DIR/tools/watch_for_updates.sh" --install >/dev/null 2>&1; then
    fail "watcher install accepted a symlink LaunchAgent"
fi
grep -Fxq 'linked victim' "$linked_watch_victim" \
    || fail "watcher install modified a linked LaunchAgent victim"

linked_log_home="$tmp_dir/linked-log-watch-home"
linked_log_victim="$tmp_dir/linked-log-victim"
linked_log_path="$linked_log_home/Library/Logs/WormsWMD-Fix/watcher.log"
mkdir -p "$linked_log_home/Library/Logs/WormsWMD-Fix"
printf 'linked watcher log victim\n' > "$linked_log_victim"
ln -s "$linked_log_victim" "$linked_log_path"
if HOME="$linked_log_home" GAME_APP="$custom_game_app" \
    WORMS_TEST_LAUNCHCTL_LOG="$tmp_dir/linked-log-launchctl.log" \
    PATH="$watch_bin:$PATH" \
    "$ROOT_DIR/tools/watch_for_updates.sh" --install >/dev/null 2>&1; then
    fail "watcher install accepted a symlink log target"
fi
grep -Fxq 'linked watcher log victim' "$linked_log_victim" \
    || fail "watcher install modified a linked log victim"

foreign_watch_home="$tmp_dir/foreign-watch-home"
foreign_watch_path="$foreign_watch_home/Library/LaunchAgents/com.wormswmd.fix.watcher.plist"
mkdir -p "$(dirname "$foreign_watch_path")"
printf 'foreign plist\n' > "$foreign_watch_path"
if HOME="$foreign_watch_home" GAME_APP="$custom_game_app" \
    WORMS_TEST_LAUNCHCTL_LOG="$tmp_dir/foreign-launchctl.log" \
    PATH="$watch_bin:$PATH" \
    "$ROOT_DIR/tools/watch_for_updates.sh" --install >/dev/null 2>&1; then
    fail "watcher install accepted a foreign LaunchAgent"
fi
grep -Fxq 'foreign plist' "$foreign_watch_path" \
    || fail "watcher install modified a foreign LaunchAgent"
if HOME="$foreign_watch_home" GAME_APP="$custom_game_app" \
    WORMS_TEST_LAUNCHCTL_LOG="$tmp_dir/foreign-uninstall-launchctl.log" \
    PATH="$watch_bin:$PATH" \
    "$ROOT_DIR/tools/watch_for_updates.sh" --uninstall >/dev/null 2>&1; then
    fail "watcher uninstall accepted a foreign LaunchAgent"
fi
grep -Fxq 'foreign plist' "$foreign_watch_path" \
    || fail "watcher uninstall removed a foreign LaunchAgent"

hardlink_watch_home="$tmp_dir/hardlink-watch-home"
hardlink_watch_peer="$tmp_dir/hardlink-watch-peer.plist"
hardlink_watch_path="$hardlink_watch_home/Library/LaunchAgents/com.wormswmd.fix.watcher.plist"
mkdir -p "$(dirname "$hardlink_watch_path")"
printf 'hardlink plist\n' > "$hardlink_watch_peer"
ln "$hardlink_watch_peer" "$hardlink_watch_path"
if HOME="$hardlink_watch_home" GAME_APP="$custom_game_app" \
    WORMS_TEST_LAUNCHCTL_LOG="$tmp_dir/hardlink-launchctl.log" \
    PATH="$watch_bin:$PATH" \
    "$ROOT_DIR/tools/watch_for_updates.sh" --install >/dev/null 2>&1; then
    fail "watcher install accepted a hardlinked LaunchAgent"
fi
grep -Fxq 'hardlink plist' "$hardlink_watch_peer" \
    || fail "watcher install modified a hardlinked LaunchAgent peer"

prior_watch_plist="$tmp_dir/prior-watch.plist"
cp "$watch_plist" "$prior_watch_plist"
if HOME="$watch_home" GAME_APP="$custom_game_app" \
    WORMS_TEST_LAUNCHCTL_LOG="$tmp_dir/invalid-plutil.log" \
    WORMS_TEST_PLUTIL_FAIL=1 PATH="$watch_bin:$PATH" \
    "$ROOT_DIR/tools/watch_for_updates.sh" --install >/dev/null 2>&1; then
    fail "watcher install accepted a plist that failed lint"
fi
cmp -s "$watch_plist" "$prior_watch_plist" \
    || fail "failed plist lint modified the prior LaunchAgent"

replacement_game_app="$tmp_dir/Replacement/Worms W.M.D.app"
mkdir -p "$replacement_game_app/Contents/MacOS"
printf '#!/bin/bash\nexit 0\n' > "$replacement_game_app/Contents/MacOS/Worms W.M.D"
chmod +x "$replacement_game_app/Contents/MacOS/Worms W.M.D"
bootstrap_count="$tmp_dir/bootstrap-count"
bootstrap_log="$tmp_dir/bootstrap-failure.log"
if HOME="$watch_home" GAME_APP="$replacement_game_app" \
    WORMS_TEST_LAUNCHCTL_LOG="$bootstrap_log" \
    WORMS_TEST_AGENT_ACTIVE=1 WORMS_TEST_BOOTSTRAP_FAIL_ONCE=1 \
    WORMS_TEST_BOOTSTRAP_COUNT="$bootstrap_count" PATH="$watch_bin:$PATH" \
    "$ROOT_DIR/tools/watch_for_updates.sh" --install >/dev/null 2>&1; then
    fail "watcher install reported success after bootstrap failure"
fi
cmp -s "$watch_plist" "$prior_watch_plist" \
    || fail "bootstrap failure did not restore the prior LaunchAgent"
[[ "$(grep -c '^bootstrap ' "$bootstrap_log")" == "2" ]] \
    || fail "bootstrap failure did not reactivate the prior LaunchAgent"
uninstall_log="$tmp_dir/uninstall.log"
HOME="$watch_home" GAME_APP="$custom_game_app" \
    WORMS_TEST_LAUNCHCTL_LOG="$uninstall_log" PATH="$watch_bin:$PATH" \
    "$ROOT_DIR/tools/watch_for_updates.sh" --uninstall >/dev/null \
    || fail "watcher uninstall rejected its exact project-owned LaunchAgent"
[[ ! -e "$watch_plist" ]] || fail "watcher uninstall left its LaunchAgent"
grep -Eq '^bootout gui/[0-9]+/com[.]wormswmd[.]fix[.]watcher$' "$uninstall_log" \
    || fail "watcher uninstall did not target the exact service label"

log_home="$tmp_dir/log-home"
bad_log="$log_home/Library/Logs/../OutsideLauncher/worms.log"
mkdir -p "$log_home/Library/Logs"
set +e
bad_log_output=$(
    HOME="$log_home" \
        GAME_APP="$custom_game_app" \
        "$ROOT_DIR/tools/launch_worms.sh" --log-file "$bad_log" --no-crash-report 2>&1
)
bad_log_status=$?
set -e
if [[ "$bad_log_status" -eq 0 ]]; then
    fail "enhanced launcher accepted a log file outside ~/Library/Logs"
fi
grep -Fq -- '--log-file must be inside' <<< "$bad_log_output" \
    || fail "enhanced launcher did not explain rejected log file: $bad_log_output"
[[ ! -e "$log_home/Library/OutsideLauncher" ]] \
    || fail "enhanced launcher created a directory for a rejected log file"

safe_log_home="$tmp_dir/safe-log-home"
safe_log="$safe_log_home/Library/Logs/WormsWMD/Nested/worms.log"
mkdir -p "$safe_log_home/Library/Logs"
HOME="$safe_log_home" \
    GAME_APP="$custom_game_app" \
    "$ROOT_DIR/tools/launch_worms.sh" --log-file "$safe_log" --no-crash-report >/dev/null 2>&1 \
    || fail "enhanced launcher rejected a safe nested log file"
[[ -f "$safe_log" ]] \
    || fail "enhanced launcher did not create the safe nested log file"

hardlink_log_home="$tmp_dir/hardlink-log-home"
hardlink_peer="$hardlink_log_home/outside-log-peer.txt"
hardlink_log="$hardlink_log_home/Library/Logs/hardlinked.log"
mkdir -p "$hardlink_log_home/Library/Logs"
printf 'outside peer\n' > "$hardlink_peer"
ln "$hardlink_peer" "$hardlink_log"
set +e
hardlink_log_output=$(
    HOME="$hardlink_log_home" \
        GAME_APP="$custom_game_app" \
        "$ROOT_DIR/tools/launch_worms.sh" --log-file "$hardlink_log" --no-crash-report 2>&1
)
hardlink_log_status=$?
set -e
if [[ "$hardlink_log_status" -eq 0 ]]; then
    fail "enhanced launcher accepted a hardlinked log file"
fi
grep -Fq 'regular non-linked log file path' <<< "$hardlink_log_output" \
    || fail "enhanced launcher did not explain hardlinked log refusal: $hardlink_log_output"
grep -Fxq 'outside peer' "$hardlink_peer" \
    || fail "enhanced launcher wrote to a hardlinked log peer"

crash_home="$tmp_dir/crash-home"
bad_crash_log_dir="$crash_home/Library/Logs/../OutsideCrash"
mkdir -p "$crash_home/Library/Logs"
HOME="$crash_home" \
    GAME_APP="$custom_game_app" \
    LOG_DIR="$bad_crash_log_dir" \
    "$ROOT_DIR/tools/launch_worms.sh" --no-crash-report >/dev/null 2>&1 \
    || fail "enhanced launcher failed a normal launch while crash reporting was disabled"
[[ ! -e "$crash_home/Library/OutsideCrash" ]] \
    || fail "enhanced launcher created a crash directory while crash reporting was disabled"

crashing_game_app="$tmp_dir/Crashing/Worms W.M.D.app"
crash_collision_home="$tmp_dir/crash-collision-home"
crash_collision_bin="$tmp_dir/crash-collision-bin"
mkdir -p \
    "$crashing_game_app/Contents/MacOS" \
    "$crash_collision_home/Library/Logs" \
    "$crash_collision_bin"
printf '#!/bin/bash\nexit 7\n' > "$crashing_game_app/Contents/MacOS/Worms W.M.D"
chmod +x "$crashing_game_app/Contents/MacOS/Worms W.M.D"
cat > "$crash_collision_bin/date" <<'STUB'
#!/bin/bash
case "${1:-}" in
    +%Y%m%d-%H%M%S) printf '20260827-120000\n' ;;
    +%Y-%m-%d*) printf '2026-08-27 12:00:00\n' ;;
    *) printf 'Thu Aug 27 12:00:00 MDT 2026\n' ;;
esac
STUB
chmod +x "$crash_collision_bin/date"
for attempt in 1 2; do
    if HOME="$crash_collision_home" GAME_APP="$crashing_game_app" \
        PATH="$crash_collision_bin:$PATH" \
        "$ROOT_DIR/tools/launch_worms.sh" --log >/dev/null 2>&1; then
        fail "crashing fixture unexpectedly exited successfully on attempt $attempt"
    fi
done
crash_collision_dir="$crash_collision_home/Library/Logs/WormsWMD/crashes"
[[ "$(find "$crash_collision_dir" -type f -name 'crash-*.txt' | wc -l | tr -d ' ')" == "2" ]] \
    || fail "same-second crashes did not produce two unique reports"
while IFS= read -r crash_report; do
    [[ "$(stat -f '%Lp' "$crash_report")" == "600" ]] \
        || fail "crash report mode is not 0600: $crash_report"
done < <(find "$crash_collision_dir" -type f -name 'crash-*.txt')

multi_home="$tmp_dir/multi-home"
multi_steam_app="$multi_home/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
multi_gog_app="$multi_home/GOG Games/Worms W.M.D/Worms W.M.D.app"
mkdir -p \
    "$multi_home/Desktop" \
    "$multi_steam_app/Contents/MacOS" \
    "$multi_gog_app/Contents/MacOS"
printf '#!/bin/bash\nexit 0\n' > "$multi_steam_app/Contents/MacOS/Worms W.M.D"
printf '#!/bin/bash\nexit 0\n' > "$multi_gog_app/Contents/MacOS/Worms W.M.D"
chmod +x \
    "$multi_steam_app/Contents/MacOS/Worms W.M.D" \
    "$multi_gog_app/Contents/MacOS/Worms W.M.D"

multi_gog_choice=0
candidate_number=1
while IFS= read -r -d '' candidate_game; do
    if [[ "$candidate_game" == "$multi_gog_app" ]]; then
        multi_gog_choice=$candidate_number
        break
    fi
    candidate_number=$((candidate_number + 1))
done < <(HOME="$multi_home" worms_find_game_apps)
[[ "$multi_gog_choice" -gt 0 ]] || fail "test could not identify the synthetic GOG installation"

printf '5\n%s\n\nq\nq\n' "$multi_gog_choice" | HOME="$multi_home" bash "$launcher" > "$tmp_dir/multi-menu.out" 2>&1 \
    || fail "launcher did not create support for a selected GOG installation"
multi_bundle=$(find "$multi_home/Desktop" -type f -name 'wormswmd-support-*.tar.gz' -print -quit)
[[ -n "$multi_bundle" ]] || fail "multi-install launcher did not create a support bundle"
mkdir -p "$tmp_dir/multi-extracted"
inspected_multi_bundle="$tmp_dir/inspected-multi-bundle.tar.gz"
worms_copy_and_inspect_archive \
    "$multi_bundle" "$inspected_multi_bundle" save "" \
    --max-expanded-bytes $((128 * 1024 * 1024)) --quiet
tar -xzf "$inspected_multi_bundle" -C "$tmp_dir/multi-extracted"
grep -Fq 'Found: ~/GOG Games/Worms W.M.D/Worms W.M.D.app' "$tmp_dir/multi-extracted/diagnostics.txt" \
    || fail "support bundle inspected Steam instead of the selected GOG installation"

multi_bin="$tmp_dir/multi-bin"
multi_open_log="$tmp_dir/multi-open.log"
mkdir -p "$multi_bin"
cat > "$multi_bin/open" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$WORMS_TEST_OPEN_LOG"
if [[ -n "${WORMS_TEST_OPEN_FAIL_PATH:-}" ]] && [[ "${1:-}" == "$WORMS_TEST_OPEN_FAIL_PATH" ]]; then
    exit 1
fi
exit 0
STUB
chmod +x "$multi_bin/open"
printf '7\n%s\n\nq\n' "$multi_gog_choice" | \
    HOME="$multi_home" \
    PATH="$multi_bin:$PATH" \
    WORMS_TEST_OPEN_LOG="$multi_open_log" \
    bash "$launcher" > "$tmp_dir/multi-launch.out" 2>&1 \
    || fail "launcher did not launch the selected GOG installation"
grep -Fxq "$multi_gog_app" "$multi_open_log" \
    || fail "launcher did not pass the selected GOG app to open: $(cat "$multi_open_log")"
if grep -Fq 'steam://run/327030' "$multi_open_log"; then
    fail "launcher ignored the selected GOG app and launched Steam"
fi

failed_gog_open_log="$tmp_dir/failed-gog-open.log"
printf '7\n%s\n\nq\n' "$multi_gog_choice" | \
    HOME="$multi_home" \
    PATH="$multi_bin:$PATH" \
    WORMS_TEST_OPEN_LOG="$failed_gog_open_log" \
    WORMS_TEST_OPEN_FAIL_PATH="$multi_gog_app" \
    bash "$launcher" > "$tmp_dir/failed-gog-launch.out" 2>&1 \
    || fail "launcher menu failed after the selected GOG app could not be opened"
if grep -Fq 'steam://run/327030' "$failed_gog_open_log"; then
    fail "launcher fell back to Steam after the selected GOG installation failed to open"
fi

printf 'q\n' | bash "$launcher" > "$tmp_dir/menu.out" 2>&1 \
    || fail "launcher did not accept piped menu input"
if grep -Fq '/dev/tty' "$tmp_dir/menu.out"; then
    fail "launcher tried to read /dev/tty for piped menu input"
fi
grep -Fq 'Okay. No changes were made from this menu choice.' "$tmp_dir/menu.out" \
    || fail "launcher did not process piped quit input"

control_game_app="$tmp_dir/Control"$'\033'"Path/Worms W.M.D.app"
mkdir -p "$control_game_app/Contents/MacOS"
printf '#!/bin/bash\nexit 0\n' > "$control_game_app/Contents/MacOS/Worms W.M.D"
chmod +x "$control_game_app/Contents/MacOS/Worms W.M.D"
printf '7\n\nq\n' | GAME_APP="$control_game_app" bash "$launcher" \
    > "$tmp_dir/control-path-menu.out" 2>&1 \
    || fail "launcher menu crashed while rejecting a control-byte GAME_APP"
if LC_ALL=C grep -q '[[:cntrl:]]' "$tmp_dir/control-path-menu.out"; then
    fail "launcher rendered a terminal control byte from GAME_APP"
fi

printf 'Launcher friction regression check passed.\n'
