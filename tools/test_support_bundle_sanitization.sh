#!/bin/bash
#
# Regression checks for diagnostics and support-bundle sanitization.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() {
    printf 'support bundle sanitization check failed: %s\n' "$*" >&2
    exit 1
}

assert_sanitized() {
    local path="$1"

    if grep -Eq 'privateperson|privateperson@example\.com|/Users/privateperson|Token[[:space:]]*[:=][[:space:]]*abc123' "$path"; then
        fail "sensitive synthetic value leaked in $path"
    fi
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-sanitize.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

diagnostics_script="$ROOT_DIR/tools/collect_diagnostics.sh"
grep -Fq 'Rosetta package receipt' "$diagnostics_script" \
    || fail "diagnostics do not report the Rosetta package receipt status"
grep -Fq 'Rosetta package version' "$diagnostics_script" \
    || fail "diagnostics do not report the installed Rosetta package version"
grep -Fq 'x86_64 execution probe' "$diagnostics_script" \
    || fail "diagnostics do not report x86_64 execution probe status"
grep -Fq 'oahd process' "$diagnostics_script" \
    || fail "diagnostics do not report oahd process status"
grep -Fq 'game-test-tool status' "$diagnostics_script" \
    || fail "diagnostics do not report macOS 27 game-test-tool status"
grep -Fq 'AGL stub missing x86_64 architecture' "$diagnostics_script" \
    || fail "diagnostics do not fail AGL stubs that are missing x86_64"

fake_game="/Users/privateperson/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
external_game="/Volumes/Private Drive/privateperson@example.com/Worms W.M.D.app"
plain_report="$tmp_dir/diagnostics.txt"
external_report="$tmp_dir/external-diagnostics.txt"
bundle_dir="$tmp_dir/bundles"
extract_dir="$tmp_dir/extracted"

GAME_APP="$fake_game" "$diagnostics_script" > "$plain_report"
assert_sanitized "$plain_report"
grep -Fq 'Version:' "$plain_report" \
    || fail "diagnostics report does not include macOS version"
grep -Fq 'Product:' "$plain_report" \
    || fail "diagnostics report does not include macOS product name"

GAME_APP="$external_game" "$diagnostics_script" > "$external_report"
if grep -Eq 'Private Drive|privateperson@example\.com|/Volumes/Private' "$external_report"; then
    fail "external volume path with spaces was not redacted"
fi

GAME_APP="$fake_game" "$diagnostics_script" --output "$tmp_dir/output.txt" >/dev/null
assert_sanitized "$tmp_dir/output.txt"

GAME_APP="$fake_game" "$diagnostics_script" --bundle --bundle-output "$bundle_dir" >/dev/null
bundle_path=$(find "$bundle_dir" -mindepth 1 -maxdepth 1 -type f -name 'wormswmd-support-*.tar.gz' -print -quit)
[[ -n "$bundle_path" ]] || fail "support bundle was not created"

mkdir -p "$extract_dir"
tar -xzf "$bundle_path" -C "$extract_dir"
assert_sanitized "$extract_dir/diagnostics.txt"

if ! tar -tvzf "$bundle_path" | awk '{ if ($3 != "root" || $4 != "wheel") exit 1 }'; then
    fail "support bundle archive leaks local owner or group metadata"
fi

if find "$extract_dir" -type f -print0 | xargs -0 grep -Eq 'privateperson|privateperson@example\.com|/Users/privateperson'; then
    fail "support bundle contains a sensitive synthetic value"
fi

printf 'Support bundle sanitization check passed.\n'
