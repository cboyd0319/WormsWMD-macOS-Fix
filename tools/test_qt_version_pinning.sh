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

if "$ROOT_DIR/tools/fetch_qt_homebrew_bottles.rb" \
    --output "$tmp_dir/provenance-prefix" \
    --write-lock "$tmp_dir/provenance.tsv" >"$tmp_dir/provenance.out" 2>&1; then
    fail "Homebrew bottle provenance fetcher accepted an unpinned root formula version"
fi
grep -Fq 'Pinned --version is required' "$tmp_dir/provenance.out" \
    || fail "Homebrew bottle provenance fetcher did not explain the missing version pin"

printf 'Qt version pinning check passed.\n'
