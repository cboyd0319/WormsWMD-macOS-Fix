#!/bin/bash
# Regression checks for archive-authoritative extracted Qt caches.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

fail() {
    printf 'Qt cache integrity check failed: %s\n' "$*" >&2
    exit 1
}

make_fixture() {
    local fixture="$1"

    mkdir -p "$fixture/scripts" "$fixture/tools" "$fixture/dist"
    cp "$ROOT_DIR/scripts/download_qt_frameworks.sh" "$fixture/scripts/download_qt_frameworks.sh"
    cp "$ROOT_DIR/scripts/common.sh" "$fixture/scripts/common.sh"
    cp "$ROOT_DIR/scripts/ui.sh" "$fixture/scripts/ui.sh"
    cp "$ROOT_DIR/tools/inspect_archive.py" "$fixture/tools/inspect_archive.py"
    cp "$ROOT_DIR/dist/qt-frameworks-x86_64-5.15.19.tar.gz" "$fixture/dist/"
    cp "$ROOT_DIR/dist/qt-frameworks-x86_64-5.15.19.tar.gz.sha256" "$fixture/dist/"
    chmod +x "$fixture/scripts/download_qt_frameworks.sh" "$fixture/tools/inspect_archive.py"
}

mode_of() {
    stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

qt_binary() {
    local cache="$1"
    local framework="$2"

    worms_framework_binary "$cache/Frameworks/${framework}.framework" "$framework"
}

regenerate_cache_manifest() {
    local cache="$1"
    local inputs=(Frameworks PlugIns METADATA.txt)

    [[ -f "$cache/SOURCE_PROVENANCE.tsv" ]] && inputs+=(SOURCE_PROVENANCE.tsv)
    worms_write_manifest "$cache" "$cache/MANIFEST.txt" "${inputs[@]}"
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-qt-cache.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

fixture="$tmp_dir/repo"
fixture_home="$tmp_dir/home"
cache_home="$tmp_dir/cache-home"
make_fixture "$fixture"
mkdir -p "$fixture_home" "$cache_home/wormswmd-fix"

archive="$fixture/dist/qt-frameworks-x86_64-5.15.19.tar.gz"
archive_sha=$(awk 'NR == 1 {print $1; exit}' "$archive.sha256")
cache_root="$cache_home/wormswmd-fix"
expected_cache="$cache_root/qt-frameworks-5.15.19-$archive_sha"

mkdir -p "$expected_cache"
printf 'foreign cache sentinel\n' > "$expected_cache/foreign.txt"
if HOME="$fixture_home" XDG_CACHE_HOME="$cache_home" \
    "$fixture/scripts/download_qt_frameworks.sh" >/dev/null 2>&1; then
    fail "Qt downloader overwrote an unmarked foreign digest cache"
fi
grep -Fxq 'foreign cache sentinel' "$expected_cache/foreign.txt" \
    || fail "foreign digest cache was modified"
mv "$expected_cache" "$tmp_dir/foreign-digest-cache"

first_output=$(HOME="$fixture_home" XDG_CACHE_HOME="$cache_home" \
    "$fixture/scripts/download_qt_frameworks.sh") \
    || fail "initial archive-authoritative cache creation failed"
cache_path=$(printf '%s\n' "$first_output" | tail -1)
[[ "$cache_path" == "$expected_cache" ]] \
    || fail "cache path is not bound to the full archive digest: $cache_path"
[[ "$(mode_of "$cache_root")" == "700" ]] \
    || fail "Qt cache root mode is not 0700"
[[ "$(mode_of "$cache_path")" == "700" ]] \
    || fail "published Qt cache mode is not 0700"
[[ -f "$cache_path/.wormswmd-qt-cache-v1" ]] \
    || fail "published Qt cache ownership marker is missing"

qt_core=$(qt_binary "$cache_path" QtCore)
qt_gui=$(qt_binary "$cache_path" QtGui)
expected_qt_core_hash=$(worms_file_sha256 "$qt_core")
chmod u+w "$qt_core"
cp "$qt_gui" "$qt_core"
regenerate_cache_manifest "$cache_path"
tampered_hash=$(worms_file_sha256 "$qt_core")
[[ "$tampered_hash" != "$expected_qt_core_hash" ]] \
    || fail "test fixture did not replace cached QtCore"

warm_bin="$tmp_dir/warm-bin"
mkdir -p "$warm_bin"
cat > "$warm_bin/curl" <<'STUB'
#!/bin/bash
exit 99
STUB
chmod +x "$warm_bin/curl"
repair_output=$(HOME="$fixture_home" XDG_CACHE_HOME="$cache_home" \
    PATH="$warm_bin:$PATH" "$fixture/scripts/download_qt_frameworks.sh") \
    || fail "tampered cache was not rebuilt without network"
[[ "$(printf '%s\n' "$repair_output" | tail -1)" == "$cache_path" ]] \
    || fail "cache repair returned a different digest path"
[[ "$(worms_file_sha256 "$(qt_binary "$cache_path" QtCore)")" == "$expected_qt_core_hash" ]] \
    || fail "cache-local manifest authenticated a replaced QtCore"

warm_start=$SECONDS
warm_output=$(HOME="$fixture_home" XDG_CACHE_HOME="$cache_home" \
    PATH="$warm_bin:$PATH" "$fixture/scripts/download_qt_frameworks.sh") \
    || fail "verified warm cache path attempted network or failed"
warm_seconds=$((SECONDS - warm_start))
[[ "$(printf '%s\n' "$warm_output" | tail -1)" == "$cache_path" ]] \
    || fail "warm cache returned a different digest path"
printf 'Qt warm-cache time: %ss (informational, target <=5s)\n' "$warm_seconds"

chmod 0755 "$cache_path"
if HOME="$fixture_home" XDG_CACHE_HOME="$cache_home" \
    "$fixture/scripts/download_qt_frameworks.sh" >/dev/null 2>&1; then
    fail "Qt downloader accepted an owned cache with unsafe directory mode"
fi
chmod 0700 "$cache_path"

legacy_cache="$cache_root/qt-frameworks-5.15.19"
cp -R "$cache_path" "$legacy_cache"
rm -f "$legacy_cache/.wormswmd-qt-cache-v1"
legacy_output=$(HOME="$fixture_home" XDG_CACHE_HOME="$cache_home" \
    "$fixture/scripts/download_qt_frameworks.sh") \
    || fail "valid version-only legacy cache was not migrated recoverably"
legacy_path=$(printf '%s\n' "$legacy_output" | sed -n 's/^Legacy Qt cache retained at: //p' | tail -1)
[[ -n "$legacy_path" && -d "$legacy_path" ]] \
    || fail "legacy cache was not retained under a reported path"
[[ -f "$legacy_path/.wormswmd-qt-cache-v1" ]] \
    || fail "retained legacy cache is not marker-scoped for pruning"
[[ ! -e "$legacy_cache" ]] \
    || fail "version-only legacy cache remained selectable"

interrupted="$cache_root/.qt-frameworks-5.15.19-$archive_sha.stage-interrupted"
mkdir -p "$interrupted"
printf 'interrupted sentinel\n' > "$interrupted/sentinel"
HOME="$fixture_home" XDG_CACHE_HOME="$cache_home" \
    "$fixture/scripts/download_qt_frameworks.sh" >/dev/null \
    || fail "interrupted staging sibling blocked valid cache reuse"
grep -Fxq 'interrupted sentinel' "$interrupted/sentinel" \
    || fail "unmarked interrupted staging directory was modified"

foreign_legacy="$cache_root/qt-frameworks-foreign.legacy-manual"
mkdir -p "$foreign_legacy"
printf 'foreign legacy sentinel\n' > "$foreign_legacy/sentinel"
prune_output=$(HOME="$fixture_home" XDG_CACHE_HOME="$cache_home" \
    "$fixture/scripts/download_qt_frameworks.sh" --prune-cache) \
    || fail "explicit marker-scoped cache prune failed"
grep -Fq "Removing owned legacy Qt cache: $legacy_path" <<< "$prune_output" \
    || fail "prune did not preview the exact owned legacy cache"
[[ ! -e "$legacy_path" ]] || fail "owned legacy cache survived explicit prune"
grep -Fxq 'foreign legacy sentinel' "$foreign_legacy/sentinel" \
    || fail "prune modified an unmarked foreign directory"
[[ -d "$cache_path" ]] || fail "legacy prune removed the current published cache"

mv "$archive" "$archive.absent"
if HOME="$fixture_home" XDG_CACHE_HOME="$cache_home" PATH="$warm_bin:$PATH" \
    "$fixture/scripts/download_qt_frameworks.sh" >/dev/null 2>&1; then
    fail "Qt cache reuse succeeded without its source archive authority"
fi
mv "$archive.absent" "$archive"

legacy_fixture="$tmp_dir/legacy-repo"
legacy_home="$tmp_dir/legacy-home"
legacy_cache_home="$tmp_dir/legacy-cache-home"
make_fixture "$legacy_fixture"
mkdir -p "$legacy_home" "$legacy_cache_home"
legacy_archive="$legacy_fixture/dist/qt-frameworks-x86_64-5.15.19.tar.gz"
legacy_extract="$tmp_dir/legacy-extract"
legacy_copy="$tmp_dir/legacy-source-copy.tar.gz"
mkdir -p "$legacy_extract"
worms_copy_and_inspect_archive \
    "$legacy_archive" "$legacy_copy" qt \
    "$(awk 'NR == 1 {print $1; exit}' "$legacy_archive.sha256")" --quiet
tar -xzf "$legacy_copy" -C "$legacy_extract"
rm -f "$legacy_extract/MANIFEST.txt"
COPYFILE_DISABLE=1 tar -czf "$legacy_archive" -C "$legacy_extract" \
    Frameworks PlugIns METADATA.txt SOURCE_PROVENANCE.tsv
legacy_sha=$(worms_file_sha256 "$legacy_archive")
printf '%s  %s\n' "$legacy_sha" "$(basename "$legacy_archive")" \
    > "$legacy_archive.sha256"
legacy_digest_cache="$legacy_cache_home/wormswmd-fix/qt-frameworks-5.15.19-$legacy_sha"
HOME="$legacy_home" XDG_CACHE_HOME="$legacy_cache_home" \
    "$legacy_fixture/scripts/download_qt_frameworks.sh" >/dev/null \
    || fail "checksummed legacy archive could not create a cache"
legacy_qt_core=$(qt_binary "$legacy_digest_cache" QtCore)
legacy_expected_hash=$(worms_file_sha256 "$legacy_qt_core")
chmod u+w "$legacy_qt_core"
cp "$(qt_binary "$legacy_digest_cache" QtGui)" "$legacy_qt_core"
regenerate_cache_manifest "$legacy_digest_cache"
HOME="$legacy_home" XDG_CACHE_HOME="$legacy_cache_home" \
    "$legacy_fixture/scripts/download_qt_frameworks.sh" >/dev/null \
    || fail "legacy archive cache was not regenerated on reuse"
[[ "$(worms_file_sha256 "$(qt_binary "$legacy_digest_cache" QtCore)")" == "$legacy_expected_hash" ]] \
    || fail "legacy archive reused a self-authenticated tampered cache"

# Remote archives with the same Qt version must follow the immutable source pin.
remote_fixture="$tmp_dir/remote-repo"
remote_cache_home="$tmp_dir/remote-cache-home"
remote_bin="$tmp_dir/remote-bin"
make_fixture "$remote_fixture"
mv "$remote_fixture/dist" "$remote_fixture/local-dist-disabled"
mkdir -p "$remote_cache_home/wormswmd-fix" "$remote_bin"
remote_name=$(basename "$archive")
unscoped_archive="$remote_cache_home/wormswmd-fix/$remote_name"
cp "$legacy_archive" "$unscoped_archive"
cp "$legacy_archive.sha256" "$unscoped_archive.sha256"
cat > "$remote_bin/curl" <<'STUB'
#!/bin/bash
set -euo pipefail
output=""
url=""
head_only=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        -sfI) head_only=true; shift ;;
        https://*) url="$1"; shift ;;
        *) shift ;;
    esac
done
base="https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/$WORMSWMD_QT_DIST_REF/dist/qt-frameworks-x86_64-5.15.19.tar.gz"
case "$url" in
    "https://api.github.com/repos/cboyd0319/WormsWMD-macOS-Fix/contents/dist?ref=$WORMSWMD_QT_DIST_REF")
        printf '[{"download_url":"%s"}]\n' "$base"
        ;;
    "$base"|"$base.sha256")
        [[ "${MOCK_QT_DENY_DOWNLOADS:-false}" == false ]] || exit 99
        $head_only && exit 0
        [[ -n "$output" ]] || exit 98
        if [[ "$url" == "$base" ]]; then
            cp "$MOCK_QT_ARCHIVE" "$output"
        else
            cp "$MOCK_QT_ARCHIVE.sha256" "$output"
        fi
        ;;
    *) exit 97 ;;
esac
STUB
chmod +x "$remote_bin/curl"

run_remote() {
    HOME="$fixture_home" XDG_CACHE_HOME="$remote_cache_home" \
        PATH="$remote_bin:$PATH" WORMSWMD_QT_DIST_REF="$1" \
        MOCK_QT_ARCHIVE="$2" MOCK_QT_DENY_DOWNLOADS="${3:-false}" \
        "$remote_fixture/scripts/download_qt_frameworks.sh"
}

remote_ref_a=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
remote_ref_b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
remote_ref_c=cccccccccccccccccccccccccccccccccccccccc
remote_output=$(run_remote "$remote_ref_a" "$archive") \
    || fail "remote package could not replace a stale version-only archive"
[[ "$(printf '%s\n' "$remote_output" | tail -1)" \
    == "$remote_cache_home/wormswmd-fix/qt-frameworks-5.15.19-$archive_sha" ]] \
    || fail "remote selection reused a stale version-only archive"
remote_output=$(run_remote "$remote_ref_b" "$legacy_archive") \
    || fail "remote package refresh failed after its source pin changed"
remote_expected="$remote_cache_home/wormswmd-fix/qt-frameworks-5.15.19-$legacy_sha"
[[ "$(printf '%s\n' "$remote_output" | tail -1)" == "$remote_expected" ]] \
    || fail "remote selection reused the previous source pin's archive"
remote_output=$(run_remote "$remote_ref_b" "$legacy_archive" true) \
    || fail "unchanged source pin unnecessarily downloaded its cached archive"
[[ "$(printf '%s\n' "$remote_output" | tail -1)" == "$remote_expected" ]] \
    || fail "warm remote cache returned a different archive"
if run_remote "$remote_ref_c" "$archive" true >/dev/null 2>&1; then
    fail "unavailable new source pin reused an older cached archive"
fi
[[ "$(worms_file_sha256 "$unscoped_archive")" == "$legacy_sha" ]] \
    || fail "remote refresh modified the retained version-only archive"

printf 'Qt cache integrity check passed.\n'
