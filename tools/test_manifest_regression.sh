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
printf 'alternate\n' > "$tmp_dir/Frameworks/Qt Core.framework/file other"
printf 'beta\n' > "$tmp_dir/PlugIns/image formats/file two"
printf 'plist\n' > "$tmp_dir/Info.plist"
ln -s 'file one' "$tmp_dir/Frameworks/Qt Core.framework/file link"

manifest="$tmp_dir/BACKUP_MANIFEST.tsv"
worms_write_manifest "$tmp_dir" "$manifest" Frameworks PlugIns Info.plist

grep -Fq 'Frameworks/Qt Core.framework/file one' "$manifest" \
    || fail "manifest did not include path with spaces"
grep -Eq $'^symlink:[0-9a-f]{64}\t[0-9]+\tFrameworks/Qt Core[.]framework/file link$' "$manifest" \
    || fail "manifest did not record the symlink path and target digest"
worms_verify_manifest "$tmp_dir" "$manifest" \
    || fail "manifest did not verify after creation"

rm -f "$tmp_dir/Frameworks/Qt Core.framework/file link"
ln -s 'file other' "$tmp_dir/Frameworks/Qt Core.framework/file link"
worms_validate_tree_symlinks "$tmp_dir" \
    || fail "changed in-tree symlink should remain structurally safe"
if worms_verify_manifest "$tmp_dir" "$manifest" 2>/dev/null; then
    fail "manifest verification did not detect a changed symlink target"
fi
rm -f "$tmp_dir/Frameworks/Qt Core.framework/file link"
ln -s 'file one' "$tmp_dir/Frameworks/Qt Core.framework/file link"

legacy_root="$tmp_dir/legacy-v1"
mkdir -p "$legacy_root/Frameworks"
printf 'legacy\n' > "$legacy_root/Frameworks/file"
ln -s 'file' "$legacy_root/Frameworks/legacy link"
legacy_hash=$(worms_file_sha256 "$legacy_root/Frameworks/file")
legacy_size=$(worms_file_size "$legacy_root/Frameworks/file")
printf '# WormsWMD manifest v1\n# sha256\tsize\tpath\n%s\t%s\tFrameworks/file\n' \
    "$legacy_hash" "$legacy_size" > "$legacy_root/BACKUP_MANIFEST.tsv"
worms_validate_tree_symlinks "$legacy_root" \
    || fail "legacy v1 fixture contains an unsafe symlink"
worms_verify_manifest "$legacy_root" "$legacy_root/BACKUP_MANIFEST.tsv" \
    || fail "legacy v1 manifest compatibility was not preserved"

printf 'corrupted\n' > "$tmp_dir/Frameworks/Qt Core.framework/file one"
if worms_verify_manifest "$tmp_dir" "$manifest" 2>/dev/null; then
    fail "manifest verification did not detect file corruption"
fi

printf 'alpha\n' > "$tmp_dir/Frameworks/Qt Core.framework/file one"
worms_write_manifest "$tmp_dir" "$manifest" Frameworks PlugIns Info.plist
printf 'unrecorded\n' > "$tmp_dir/Frameworks/Qt Core.framework/unrecorded file"
if worms_verify_manifest "$tmp_dir" "$manifest" 2>/dev/null; then
    fail "manifest verification did not reject an unrecorded extra file"
fi
rm -f "$tmp_dir/Frameworks/Qt Core.framework/unrecorded file"
worms_write_manifest "$tmp_dir" "$manifest" Frameworks PlugIns Info.plist
ln -s 'file one' "$tmp_dir/Frameworks/Qt Core.framework/unrecorded link"
if worms_verify_manifest "$tmp_dir" "$manifest" 2>/dev/null; then
    fail "manifest verification did not reject an unrecorded symlink"
fi
rm -f "$tmp_dir/Frameworks/Qt Core.framework/unrecorded link"

duplicate_root="$tmp_dir/duplicate-archive"
duplicate_archive="$tmp_dir/duplicate.tar.gz"
mkdir -p "$duplicate_root/Frameworks"
printf 'duplicate\n' > "$duplicate_root/Frameworks/libduplicate.dylib"
(
    cd "$duplicate_root"
    tar -czf "$duplicate_archive" Frameworks/libduplicate.dylib Frameworks/libduplicate.dylib
)
if ! declare -F worms_validate_tar_no_duplicate_entries >/dev/null; then
    fail "shared archive validation does not detect duplicate members"
fi
if worms_validate_tar_no_duplicate_entries "$duplicate_archive" 2>/dev/null; then
    fail "archive validation accepted duplicate members"
fi

corrupt_archive="$tmp_dir/corrupt.tar.gz"
printf 'not a gzip archive\n' > "$corrupt_archive"
if worms_validate_tar_no_duplicate_entries "$corrupt_archive" 2>/dev/null; then
    fail "duplicate-entry validation accepted an unreadable archive"
fi

agl_root="$tmp_dir/agl-root"
mkdir -p "$agl_root/Frameworks/AGL.framework/Versions/A/Resources"
printf 'fake agl\n' > "$agl_root/Frameworks/AGL.framework/Versions/A/AGL"
ln -s A "$agl_root/Frameworks/AGL.framework/Versions/Current"
ln -s Versions/Current/AGL "$agl_root/Frameworks/AGL.framework/AGL"
ln -s Versions/Current/Resources "$agl_root/Frameworks/AGL.framework/Resources"
ln -s A "$agl_root/Frameworks/AGL.framework/Versions/A/A"
ln -s Versions/Current/Resources "$agl_root/Frameworks/AGL.framework/Versions/A/Resources/Resources"

if worms_validate_tree_symlinks "$agl_root" 2>/dev/null; then
    fail "stale nested AGL framework symlinks unexpectedly passed validation before repair"
fi
worms_repair_agl_framework_symlinks "$agl_root"
worms_validate_tree_symlinks "$agl_root" \
    || fail "repaired AGL framework symlinks did not pass validation"
[[ ! -L "$agl_root/Frameworks/AGL.framework/Versions/A/A" ]] \
    || fail "AGL symlink repair left nested Versions/A/A"
[[ ! -L "$agl_root/Frameworks/AGL.framework/Versions/A/Resources/Resources" ]] \
    || fail "AGL symlink repair left nested Resources/Resources"

printf 'Manifest regression check passed.\n'
