#!/bin/bash
# Regression checks for deterministic Mach-O normalization and Qt comparison.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

fail() {
    printf 'Qt artifact comparison check failed: %s\n' "$*" >&2
    exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-qt-artifact.XXXXXX")
tmp_dir=$(cd "$tmp_dir" && pwd -P)
trap 'rm -rf "$tmp_dir"' EXIT

[[ -x "$ROOT_DIR/tools/normalize_qt_macho_tree.sh" ]] \
    || fail "tools/normalize_qt_macho_tree.sh is required and executable"
mkdir -p "$tmp_dir/empty/Frameworks" "$tmp_dir/empty/PlugIns"
if "$ROOT_DIR/tools/normalize_qt_macho_tree.sh" "$tmp_dir/empty" \
    >/dev/null 2>&1; then
    fail "Mach-O normalizer accepted an empty Qt tree"
fi

build_fixture() {
    local fixture_root="$1"
    local tree="$fixture_root/tree"
    local helper="$tree/Frameworks/libhelper.1.dylib"
    local core="$tree/Frameworks/QtCore.framework/Versions/5/QtCore"
    local plugin="$tree/PlugIns/imageformats/libqtest.dylib"

    mkdir -p "$(dirname "$helper")" "$(dirname "$core")" "$(dirname "$plugin")"
    printf 'int helper(void) { return 7; }\n' > "$fixture_root/helper.c"
    printf 'extern int helper(void); int core(void) { return helper(); }\n' \
        > "$fixture_root/core.c"
    printf 'extern int core(void); int plugin(void) { return core(); }\n' \
        > "$fixture_root/plugin.c"

    clang -arch x86_64 -dynamiclib \
        -install_name "$fixture_root/source/libhelper.1.dylib" \
        -o "$helper" "$fixture_root/helper.c"
    clang -arch x86_64 -dynamiclib \
        -install_name "$fixture_root/source/QtCore.framework/Versions/5/QtCore" \
        -Wl,-rpath,"$fixture_root/build-rpath" \
        -o "$core" "$fixture_root/core.c" "$helper"
    clang -arch x86_64 -dynamiclib \
        -install_name "$fixture_root/source/plugins/libqtest.dylib" \
        -Wl,-rpath,"$fixture_root/plugin-rpath" \
        -o "$plugin" "$fixture_root/plugin.c" "$core"
}

first_root="$tmp_dir/First Root"
second_root="$tmp_dir/Second Root"
mkdir -p "$first_root" "$second_root"
build_fixture "$first_root"
build_fixture "$second_root"

first_core="$first_root/tree/Frameworks/QtCore.framework/Versions/5/QtCore"
second_core="$second_root/tree/Frameworks/QtCore.framework/Versions/5/QtCore"
if [[ "$(worms_file_sha256 "$first_core")" == "$(worms_file_sha256 "$second_core")" ]]; then
    fail "synthetic roots did not reproduce pre-normalization hash drift"
fi
{ otool -D "$first_core"; otool -L "$first_core"; otool -l "$first_core"; } \
    | grep -F 'First Root' >/dev/null \
    || fail "synthetic fixture did not embed its build root"

"$ROOT_DIR/tools/normalize_qt_macho_tree.sh" "$first_root/tree"
"$ROOT_DIR/tools/normalize_qt_macho_tree.sh" "$second_root/tree"

[[ "$(worms_file_sha256 "$first_core")" == "$(worms_file_sha256 "$second_core")" ]] \
    || fail "normalized framework hashes still depend on the build root"
first_plugin="$first_root/tree/PlugIns/imageformats/libqtest.dylib"
second_plugin="$second_root/tree/PlugIns/imageformats/libqtest.dylib"
[[ "$(worms_file_sha256 "$first_plugin")" == "$(worms_file_sha256 "$second_plugin")" ]] \
    || fail "normalized plugin hashes still depend on the build root"
first_metadata=$({
    for inspected_binary in "$first_core" "$first_plugin"; do
        otool -D "$inspected_binary" | sed '1d'
        otool -L "$inspected_binary" | sed '1d'
        otool -l "$inspected_binary" | sed '1d'
    done
})
if grep -F 'First Root' <<< "$first_metadata" >/dev/null; then
    grep -F 'First Root' <<< "$first_metadata" >&2
    fail "normalized Mach-O files retain the first build root"
fi
second_metadata=$({
    for inspected_binary in "$second_core" "$second_plugin"; do
        otool -D "$inspected_binary" | sed '1d'
        otool -L "$inspected_binary" | sed '1d'
        otool -l "$inspected_binary" | sed '1d'
    done
})
if grep -F 'Second Root' <<< "$second_metadata" >/dev/null; then
    grep -F 'Second Root' <<< "$second_metadata" >&2
    fail "normalized Mach-O files retain the second build root"
fi

[[ -x "$ROOT_DIR/tools/compare_qt_artifacts.sh" ]] \
    || fail "tools/compare_qt_artifacts.sh is required and executable"

prepare_archive_tree() {
    local tree="$1"
    printf 'Qt Version: 5.15.19\nCreated: fixed\nSource: synthetic\nSource Date Epoch: 1704067200\n' \
        > "$tree/METADATA.txt"
    printf 'name\tversion\tbottle_tag\nqt@5\t5.15.19\tsonoma\n' \
        > "$tree/SOURCE_PROVENANCE.tsv"
    worms_write_manifest "$tree" "$tree/MANIFEST.txt" \
        Frameworks PlugIns METADATA.txt SOURCE_PROVENANCE.tsv
}

create_archive() {
    local tree="$1"
    local archive="$2"

    find "$tree" -exec touch -h -t 202601010000.00 {} +
    (
        cd "$tree"
        find . -print | LC_ALL=C sort \
            | COPYFILE_DISABLE=1 tar --format ustar --no-recursion -cf - -T - \
            | gzip -n > "$archive"
    )
}

prepare_archive_tree "$first_root/tree"
prepare_archive_tree "$second_root/tree"
first_archive="$tmp_dir/first.tar.gz"
second_archive="$tmp_dir/second.tar.gz"
create_archive "$first_root/tree" "$first_archive"
create_archive "$second_root/tree" "$second_archive"
"$ROOT_DIR/tools/compare_qt_artifacts.sh" \
    "$first_archive" "$second_archive" >/dev/null \
    || fail "artifact comparator rejected two normalized clean-root builds"

sed -i '' 's/5[.]15[.]19/5.15.20/g' "$second_root/tree/METADATA.txt" \
    "$second_root/tree/SOURCE_PROVENANCE.tsv"
worms_write_manifest "$second_root/tree" "$second_root/tree/MANIFEST.txt" \
    Frameworks PlugIns METADATA.txt SOURCE_PROVENANCE.tsv
create_archive "$second_root/tree" "$second_archive"
if "$ROOT_DIR/tools/compare_qt_artifacts.sh" \
    "$first_archive" "$second_archive" >/dev/null 2>&1; then
    fail "exact artifact comparison accepted expected version/hash changes"
fi
"$ROOT_DIR/tools/compare_qt_artifacts.sh" \
    "$first_archive" "$second_archive" --allow-version-change >/dev/null \
    || fail "version-aware comparison rejected version/hash-only changes"

printf 'unexpected structure\n' > "$second_root/tree/Frameworks/unexpected.txt"
worms_write_manifest "$second_root/tree" "$second_root/tree/MANIFEST.txt" \
    Frameworks PlugIns METADATA.txt SOURCE_PROVENANCE.tsv
create_archive "$second_root/tree" "$second_archive"
if "$ROOT_DIR/tools/compare_qt_artifacts.sh" \
    "$first_archive" "$second_archive" --allow-version-change >/dev/null 2>&1; then
    fail "version-aware comparison accepted structural member drift"
fi

current_root="$tmp_dir/current-package"
mkdir -p "$current_root"
current_checksum=$(awk 'NR == 1 {print $1; exit}' \
    "$ROOT_DIR/dist/qt-frameworks-x86_64-5.15.19.tar.gz.sha256")
worms_copy_and_inspect_archive \
    "$ROOT_DIR/dist/qt-frameworks-x86_64-5.15.19.tar.gz" \
    "$tmp_dir/current-inspected.tar.gz" qt "$current_checksum" --quiet
tar -xzf "$tmp_dir/current-inspected.tar.gz" -C "$current_root"
"$ROOT_DIR/tools/normalize_qt_macho_tree.sh" "$current_root"
current_macho_count=0
while IFS= read -r -d '' current_binary; do
    file "$current_binary" 2>/dev/null | grep -Fq 'Mach-O' || continue
    current_macho_count=$((current_macho_count + 1))
done < <(find "$current_root/Frameworks" "$current_root/PlugIns" -type f -print0)
[[ "$current_macho_count" == "35" ]] \
    || fail "normalized current package did not contain all 35 Mach-O files"

"$ROOT_DIR/tools/compare_qt_artifacts.sh" \
    "$ROOT_DIR/dist/qt-frameworks-x86_64-5.15.19.tar.gz" \
    "$ROOT_DIR/dist/qt-frameworks-x86_64-5.15.19.tar.gz" >/dev/null \
    || fail "artifact comparator rejected identical current archives"

printf 'Qt artifact comparison check passed.\n'
