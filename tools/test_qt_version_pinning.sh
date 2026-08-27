#!/bin/bash
#
# Regression checks for supported Qt package and fallback versions.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

fail() {
    printf 'Qt version pinning check failed: %s\n' "$*" >&2
    exit 1
}

assert_supported() {
    local version="$1"

    worms_supported_qt5_version "$version" \
        || fail "expected Qt $version to be supported"
}

assert_rejected() {
    local version="$1"

    if worms_supported_qt5_version "$version"; then
        fail "expected Qt $version to be rejected"
    fi
}

assert_supported "5.15.18"
assert_supported "5.15.19"
assert_rejected "5.14.2"
assert_rejected "5.16.0"
assert_rejected "6.0.0"
assert_rejected "5.15"
assert_rejected "5.15.19_1"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-qt-pin.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

touch "$tmp_dir/qt-frameworks-x86_64-5.14.2.tar.gz"
touch "$tmp_dir/qt-frameworks-x86_64-5.15.18.tar.gz"
touch "$tmp_dir/qt-frameworks-x86_64-5.15.19.tar.gz"
touch "$tmp_dir/qt-frameworks-x86_64-6.0.0.tar.gz"

version=$(worms_qt_package_version "$tmp_dir/qt-frameworks-x86_64-5.15.19.tar.gz" || true)
[[ "$version" == "5.15.19" ]] || fail "failed to parse supported package version"

if worms_qt_package_version "$tmp_dir/qt-frameworks-x86_64-5.14.2.tar.gz" >/dev/null 2>&1; then
    fail "accepted unsupported Qt 5.14 package"
fi

latest=$(worms_latest_qt_package_by_version "$tmp_dir" false || true)
[[ "$(basename "$latest")" == "qt-frameworks-x86_64-5.15.19.tar.gz" ]] \
    || fail "did not choose the highest supported Qt 5.15 package"

# shellcheck disable=SC2016
grep -Fq 'worms_supported_qt5_version "$QT_VERSION"' "$ROOT_DIR/tools/package_qt_frameworks.sh" \
    || fail "Qt packager does not enforce supported Qt 5.15.x versions"
# shellcheck disable=SC2016
grep -Fq 'worms_supported_qt5_version "$homebrew_version"' "$ROOT_DIR/fix_worms_wmd.sh" \
    || fail "installer fallback does not enforce supported Homebrew Qt 5.15.x versions"
grep -Fq 'SOURCE_PROVENANCE.tsv' "$ROOT_DIR/scripts/download_qt_frameworks.sh" \
    || fail "Qt archive validator does not allow source provenance"
[[ -x "$ROOT_DIR/tools/fetch_qt_homebrew_bottles.rb" ]] \
    || fail "Homebrew bottle provenance fetcher is missing or not executable"

committed_package="$ROOT_DIR/dist/qt-frameworks-x86_64-5.15.19.tar.gz"
archive_manifest=$(tar -xOzf "$committed_package" MANIFEST.txt)
grep -Fq '# WormsWMD manifest v2' <<< "$archive_manifest" \
    || fail "committed Qt package manifest does not cover symlink entries"
archive_symlink_count=$(tar -tvzf "$committed_package" \
    | awk 'substr($1,1,1) == "l" {count++} END {print count+0}')
manifest_symlink_count=$(grep -c '^symlink:' <<< "$archive_manifest" || true)
[[ "$archive_symlink_count" == "$manifest_symlink_count" ]] \
    || fail "Qt package manifest symlink count does not match the archive"
if tar -tzf "$committed_package" \
    | awk -F/ '$1 == "Frameworks" && NF == 2 && $2 ~ /^libq.*[.]dylib$/ { found=1 } END { exit(found ? 0 : 1) }'; then
    fail "committed Qt package duplicates plugin self-references as framework dependencies"
fi
metadata_dependency_count=$(tar -xOzf "$committed_package" METADATA.txt \
    | awk -F': ' '/^- Dependencies:/ {print $2; exit}')
archive_dependency_count=$(tar -tzf "$committed_package" \
    | awk -F/ '$1 == "Frameworks" && NF == 2 && $2 ~ /[.]dylib$/ {seen[$2]=1} END {for (name in seen) count++; print count+0}')
[[ "$metadata_dependency_count" == "$archive_dependency_count" ]] \
    || fail "Qt package metadata dependency count does not match the archive"
[[ "$archive_dependency_count" == "16" ]] \
    || fail "Qt package does not contain the complete 16-dylib runtime closure"
tar -tzf "$committed_package" | grep -Fxq 'Frameworks/libsharpyuv.0.dylib' \
    || fail "Qt package omits libwebp's bundled libsharpyuv dependency"
if tar -tzf "$committed_package" | grep -Eq '[.]prl$'; then
    fail "Qt runtime package still contains build-only .prl metadata"
fi
duplicate_archive_entry=$(tar -tzf "$committed_package" | LC_ALL=C sort | uniq -d | head -1)
[[ -z "$duplicate_archive_entry" ]] \
    || fail "Qt package contains duplicate archive entry: $duplicate_archive_entry"

package_root="$tmp_dir/package-root"
mkdir -p "$package_root"
tar -xzf "$committed_package" -C "$package_root"
while IFS= read -r -d '' binary; do
    install_id=$(otool -D "$binary" 2>/dev/null | sed -n '2p' || true)
    while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        [[ "$dependency" == "$install_id" ]] && continue
        case "$dependency" in
            /usr/lib/*|/System/Library/*)
                ;;
            *".framework/"*)
                framework_name=$(basename "${dependency%%.framework/*}")
                [[ -d "$package_root/Frameworks/$framework_name.framework" ]] \
                    || fail "Qt package dependency closure is missing $framework_name.framework for $(basename "$binary")"
                ;;
            *.dylib)
                dependency_name=$(basename "$dependency")
                [[ -f "$package_root/Frameworks/$dependency_name" ]] \
                    || fail "Qt package dependency closure is missing $dependency_name for $(basename "$binary")"
                ;;
            *)
                fail "Qt package contains an unportable dependency in $(basename "$binary"): $dependency"
                ;;
        esac
    done < <(worms_otool_dependencies "$binary")
done < <(find "$package_root/Frameworks" "$package_root/PlugIns" -type f -print0 | while IFS= read -r -d '' candidate; do
    file "$candidate" 2>/dev/null | grep -Fq 'Mach-O' && printf '%s\0' "$candidate"
done)

if "$ROOT_DIR/tools/fetch_qt_homebrew_bottles.rb" \
    --output "$tmp_dir/provenance-prefix" \
    --write-lock "$tmp_dir/provenance.tsv" >"$tmp_dir/provenance.out" 2>&1; then
    fail "Homebrew bottle provenance fetcher accepted an unpinned root formula version"
fi
grep -Fq 'Pinned --version is required' "$tmp_dir/provenance.out" \
    || fail "Homebrew bottle provenance fetcher did not explain the missing version pin"

printf 'Qt version pinning check passed.\n'
