#!/bin/bash
# Rebuild and compare every tagged release artifact before publication.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

if [[ $# -ne 3 ]] \
    || [[ ! "$1" =~ ^v[0-9]+[.][0-9]+[.][0-9]+$ ]] \
    || [[ -z "$2" ]] \
    || [[ ! -d "$3" ]] \
    || [[ -L "$3" ]]; then
    printf 'Usage: %s vVERSION TIMESTAMP RELEASE_DIR\n' "$(basename "$0")" >&2
    exit 2
fi

release_version="$1"
release_timestamp="$2"
release_dir="$3"
release_name="WormsWMD-macOS-Fix-${release_version}"
release_zip="$release_dir/${release_name}.zip"
release_checksum="${release_zip}.sha256"
release_sbom="$release_dir/${release_name}.cdx.json"
standalone="$ROOT_DIR/dist/qt-frameworks-x86_64-5.15.19.source-provenance.tsv"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-release-verify.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

expected_files="$work_dir/expected-release-files"
actual_files="$work_dir/actual-release-files"
printf '%s\n' \
    "${release_name}.cdx.json" \
    "${release_name}.zip" \
    "${release_name}.zip.sha256" \
    'RELEASE_NOTES.md' | LC_ALL=C sort > "$expected_files"
while IFS= read -r -d '' artifact; do
    if [[ ! -f "$artifact" ]] || [[ -L "$artifact" ]] \
        || [[ "$(worms_file_link_count "$artifact")" != "1" ]]; then
        printf 'Unexpected release artifact; refusing verification: %s\n' \
            "$artifact" >&2
        exit 1
    fi
    basename "$artifact"
done < <(find "$release_dir" -mindepth 1 -maxdepth 1 -print0) \
    | LC_ALL=C sort > "$actual_files"
if ! cmp -s "$expected_files" "$actual_files"; then
    printf 'Unexpected release artifact; refusing verification.\n' >&2
    exit 1
fi

"$ROOT_DIR/tools/build_release_bundle.sh" \
    --output-dir "$work_dir/expected" \
    --version "$release_version" \
    --timestamp "$release_timestamp" \
    --skip-zip >/dev/null
expected_tree="$work_dir/expected/$release_name"

worms_verify_exact_sha256_file \
    "$release_zip" "$release_checksum" "$(basename "$release_zip")"
/usr/bin/python3 "$ROOT_DIR/tools/verify_release_zip.py" \
    "$release_zip" --expected-tree "$expected_tree"

"$ROOT_DIR/tools/extract_release_notes.sh" "${release_version#v}" \
    > "$work_dir/regenerated-release-notes.md"
cmp -s "$work_dir/regenerated-release-notes.md" \
    "$release_dir/RELEASE_NOTES.md"

embedded="$work_dir/embedded-source-provenance.tsv"
cmp -s "$ROOT_DIR/packaging/qt-homebrew-lock.tsv" "$standalone"
tar -xOf "$ROOT_DIR/dist/qt-frameworks-x86_64-5.15.19.tar.gz" \
    SOURCE_PROVENANCE.tsv > "$embedded"
cmp -s "$ROOT_DIR/packaging/qt-homebrew-lock.tsv" "$embedded"

/usr/bin/python3 "$ROOT_DIR/tools/generate_sbom.py" \
    --version "$release_version" \
    --timestamp "$release_timestamp" \
    --archive "$ROOT_DIR/dist/qt-frameworks-x86_64-5.15.19.tar.gz" \
    --release-archive "$release_zip" \
    --release-checksum "$release_checksum" \
    --output "$work_dir/regenerated.cdx.json"
cmp -s "$work_dir/regenerated.cdx.json" "$release_sbom"

printf 'Release artifacts match the tagged source, manifest, provenance, and SBOM.\n'
