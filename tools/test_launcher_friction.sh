#!/bin/bash
#
# Regression checks for the friendly launcher and first-read friction points.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

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
grep -Fq "GAME_APP=\"\$GAME_APP\" ./fix_worms_wmd.sh --force" "$ROOT_DIR/tools/watch_for_updates.sh" \
    || fail "watcher daemon reapply does not forward GAME_APP"
if ! grep -F "GAME_APP=\"\$GAME_APP\" ./fix_worms_wmd.sh" "$ROOT_DIR/tools/watch_for_updates.sh" | grep -Fvq -- "--force"; then
    fail "watcher interactive reapply does not forward GAME_APP"
fi

grep -Fq 'macOS 26+ Fix Installer' "$ROOT_DIR/install.sh" \
    || fail "install.sh banner still uses stale macOS version wording"
grep -Fq 'macOS 26+ and macOS 27 Golden Gate' "$ROOT_DIR/Install Fix.command" \
    || fail "Install Fix.command banner does not mention macOS 27 Golden Gate"

watch_home="$tmp_dir/watch-home"
watch_bin="$tmp_dir/watch-bin"
watch_log="$tmp_dir/launchctl.log"
custom_game_app="$tmp_dir/Custom & Path/Worms W.M.D.app"
mkdir -p "$watch_home" "$watch_bin" "$custom_game_app/Contents/MacOS"
: > "$custom_game_app/Contents/MacOS/Worms W.M.D"
chmod +x "$custom_game_app/Contents/MacOS/Worms W.M.D"
cat > "$watch_bin/launchctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$WORMS_TEST_LAUNCHCTL_LOG"
exit 0
STUB
chmod +x "$watch_bin/launchctl"

HOME="$watch_home" \
    GAME_APP="$custom_game_app" \
    WORMS_TEST_LAUNCHCTL_LOG="$watch_log" \
    PATH="$watch_bin:$PATH" \
    "$ROOT_DIR/tools/watch_for_updates.sh" --install >/dev/null \
    || fail "watcher install failed with a custom GAME_APP"

watch_plist="$watch_home/Library/LaunchAgents/com.wormswmd.fix.watcher.plist"
[[ -f "$watch_plist" ]] || fail "watcher install did not create a LaunchAgent plist"
grep -Fq '<key>EnvironmentVariables</key>' "$watch_plist" \
    || fail "watcher LaunchAgent does not persist environment variables"
grep -Fq '<key>GAME_APP</key>' "$watch_plist" \
    || fail "watcher LaunchAgent does not persist GAME_APP"
grep -Fq '<string>'"$tmp_dir"'/Custom &amp; Path/Worms W.M.D.app</string>' "$watch_plist" \
    || fail "watcher LaunchAgent does not XML-escape and persist the custom GAME_APP"
grep -Fq "bootstrap gui/" "$watch_log" \
    || fail "watcher install did not attempt to bootstrap the LaunchAgent"

printf 'q\n' | bash "$launcher" > "$tmp_dir/menu.out" 2>&1 \
    || fail "launcher did not accept piped menu input"
if grep -Fq '/dev/tty' "$tmp_dir/menu.out"; then
    fail "launcher tried to read /dev/tty for piped menu input"
fi
grep -Fq 'Okay. No changes were made from this menu choice.' "$tmp_dir/menu.out" \
    || fail "launcher did not process piped quit input"

printf 'Launcher friction regression check passed.\n'
