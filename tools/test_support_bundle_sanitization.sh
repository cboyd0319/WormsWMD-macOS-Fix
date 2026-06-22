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

fake_game="/Users/privateperson/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
external_game="/Volumes/Private Drive/privateperson@example.com/Worms W.M.D.app"
plain_report="$tmp_dir/diagnostics.txt"
external_report="$tmp_dir/external-diagnostics.txt"
bundle_dir="$tmp_dir/bundles"
extract_dir="$tmp_dir/extracted"

GAME_APP="$fake_game" "$ROOT_DIR/tools/collect_diagnostics.sh" > "$plain_report"
assert_sanitized "$plain_report"

GAME_APP="$external_game" "$ROOT_DIR/tools/collect_diagnostics.sh" > "$external_report"
if grep -Eq 'Private Drive|privateperson@example\.com|/Volumes/Private' "$external_report"; then
    fail "external volume path with spaces was not redacted"
fi

GAME_APP="$fake_game" "$ROOT_DIR/tools/collect_diagnostics.sh" --output "$tmp_dir/output.txt" >/dev/null
assert_sanitized "$tmp_dir/output.txt"

GAME_APP="$fake_game" "$ROOT_DIR/tools/collect_diagnostics.sh" --bundle --bundle-output "$bundle_dir" >/dev/null
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
