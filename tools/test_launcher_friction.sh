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

printf 'q\n' | bash "$launcher" > "$tmp_dir/menu.out" 2>&1 \
    || fail "launcher did not accept piped menu input"
if grep -Fq '/dev/tty' "$tmp_dir/menu.out"; then
    fail "launcher tried to read /dev/tty for piped menu input"
fi
grep -Fq 'Okay. No changes were made from this menu choice.' "$tmp_dir/menu.out" \
    || fail "launcher did not process piped quit input"

printf 'Launcher friction regression check passed.\n'
