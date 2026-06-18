#!/bin/bash
#
# Regression checks for shared manifest write/verify helpers.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

fail() {
    printf 'manifest regression check failed: %s\n' "$*" >&2
    exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-manifest.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/Frameworks/Qt Core.framework" "$tmp_dir/PlugIns/image formats"
printf 'alpha\n' > "$tmp_dir/Frameworks/Qt Core.framework/file one"
printf 'beta\n' > "$tmp_dir/PlugIns/image formats/file two"
printf 'plist\n' > "$tmp_dir/Info.plist"

manifest="$tmp_dir/BACKUP_MANIFEST.tsv"
worms_write_manifest "$tmp_dir" "$manifest" Frameworks PlugIns Info.plist

grep -Fq 'Frameworks/Qt Core.framework/file one' "$manifest" \
    || fail "manifest did not include path with spaces"
worms_verify_manifest "$tmp_dir" "$manifest" \
    || fail "manifest did not verify after creation"

printf 'corrupted\n' > "$tmp_dir/Frameworks/Qt Core.framework/file one"
if worms_verify_manifest "$tmp_dir" "$manifest" 2>/dev/null; then
    fail "manifest verification did not detect file corruption"
fi

printf 'Manifest regression check passed.\n'
