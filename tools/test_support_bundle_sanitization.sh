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

    if grep -Eq 'privateperson|privateperson@example\.com|/Users/privateperson|abc123|lower-token-value|shhh-secret|p4ssw0rd|api-key-value' "$path"; then
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
sensitive_user="/Users/privateperson"
plain_report="$tmp_dir/diagnostics.txt"
external_report="$tmp_dir/external-diagnostics.txt"
bundle_dir="$tmp_dir/bundles"
extract_dir="$tmp_dir/extracted"
test_home="$tmp_dir/home"
fixture_repo="$tmp_dir/fixture-repo"
fixture_home="$tmp_dir/fixture-home"
fixture_bundle_dir="$tmp_dir/fixture-bundles"
fixture_extract_dir="$tmp_dir/fixture-extracted"

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

ambiguous_home="$tmp_dir/ambiguous-home"
ambiguous_steam="$ambiguous_home/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
ambiguous_gog="$ambiguous_home/GOG Games/Worms W.M.D/Worms W.M.D.app"
mkdir -p "$ambiguous_steam/Contents/MacOS" "$ambiguous_gog/Contents/MacOS"
printf '#!/bin/bash\nexit 0\n' > "$ambiguous_steam/Contents/MacOS/Worms W.M.D"
printf '#!/bin/bash\nexit 0\n' > "$ambiguous_gog/Contents/MacOS/Worms W.M.D"
chmod +x \
    "$ambiguous_steam/Contents/MacOS/Worms W.M.D" \
    "$ambiguous_gog/Contents/MacOS/Worms W.M.D"
HOME="$ambiguous_home" "$diagnostics_script" > "$tmp_dir/ambiguous.txt"
grep -Fq 'Multiple installations detected; set GAME_APP to the installation being diagnosed.' "$tmp_dir/ambiguous.txt" \
    || fail "direct diagnostics silently selected one of multiple installations"
if grep -Fq 'Found: ~/Library/Application Support/Steam' "$tmp_dir/ambiguous.txt"; then
    fail "direct diagnostics inspected Steam despite an ambiguous multi-install state"
fi

GAME_APP="$fake_game" "$diagnostics_script" --output "$tmp_dir/output.txt" >/dev/null
assert_sanitized "$tmp_dir/output.txt"

mkdir -p "$test_home/Library/Logs/WormsWMD-Fix"
cat > "$test_home/Library/Logs/WormsWMD-Fix/fix_worms_wmd-20260101-000000.log" <<LOG
ℹ  Log file: ${sensitive_user}/Library/Logs/WormsWMD-Fix/fix_worms_wmd-20260101-000000.log
==> Creating backup...
    Backup created: ${sensitive_user}/Documents/WormsWMD-Backup-20260101-000000
==> Building AGL stub library...
Token: abc123
token=lower-token-value
Secret: shhh-secret
Password = p4ssw0rd
API_KEY=api-key-value
✗  ERROR: Required Qt framework missing from source: ${sensitive_user}/private-qt/QtSvg.framework
LOG
cat > "$test_home/Library/Logs/WormsWMD-Fix/fix_worms_wmd-20260101-000001.log" <<'LOG'
==> Verifying installation...
SUCCESS: All checks passed!
ERROR: Post-verify failure
LOG
{
    printf '\033[0;31mERROR: Colored failure detail\033[0m\n'
    printf '\033]0;hidden OSC title\007ERROR: OSC failure\033\\\n'
    printf 'ERROR: isolated controls\007\010\177 removed\n'
    printf 'Rolled back to original state.\n'
} >> "$test_home/Library/Logs/WormsWMD-Fix/fix_worms_wmd-20260101-000001.log"

mkdir -p "$test_home/Documents/WormsWMD-Backup-20260101-000000"
cat > "$test_home/Documents/WormsWMD-Backup-20260101-000000/BACKUP_MANIFEST.tsv" <<'TSV'
sha256	size	path
hash	1	Frameworks/privateperson@example.com
hash	1	Frameworks/API_KEY=api-key-value
TSV
printf '# WormsWMD backup metadata v1\ngame_app_path\t%s\ngame_source\tgog\n' \
    "$fake_game" > "$test_home/Documents/WormsWMD-Backup-20260101-000000/BACKUP_METADATA.tsv"
mkdir -p "$test_home/Documents/WormsWMD-Backup-20260101-000001"
cp "$test_home/Documents/WormsWMD-Backup-20260101-000000/BACKUP_MANIFEST.tsv" \
    "$test_home/Documents/WormsWMD-Backup-20260101-000001/BACKUP_MANIFEST.tsv"
cp "$test_home/Documents/WormsWMD-Backup-20260101-000000/BACKUP_METADATA.tsv" \
    "$test_home/Documents/WormsWMD-Backup-20260101-000001/BACKUP_METADATA.tsv"

HOME="$test_home" GAME_APP="$fake_game" "$diagnostics_script" --bundle --bundle-output "$bundle_dir" >/dev/null
bundle_path=$(find "$bundle_dir" -mindepth 1 -maxdepth 1 -type f -name 'wormswmd-support-*.tar.gz' -print -quit)
[[ -n "$bundle_path" ]] || fail "support bundle was not created"

mkdir -p "$extract_dir"
tar -xzf "$bundle_path" -C "$extract_dir"
assert_sanitized "$extract_dir/diagnostics.txt"

for bundled_file in install-summary.txt runtime-invariants.txt backup-summary.txt qt-package.txt; do
    [[ -f "$extract_dir/$bundled_file" ]] || fail "support bundle is missing $bundled_file"
    assert_sanitized "$extract_dir/$bundled_file"
done

grep -Fq "Latest installer logs" "$extract_dir/install-summary.txt" \
    || fail "install summary does not include latest installer logs"
grep -Fq "Inferred outcome:" "$extract_dir/install-summary.txt" \
    || fail "install summary does not include inferred outcome"
grep -Fq "Inferred outcome: failure: rollback completed" "$extract_dir/install-summary.txt" \
    || fail "install summary misclassified a mixed success/error rollback log"
if grep -Eq '\[[0-9;]+m' "$extract_dir/install-summary.txt"; then
    fail "install summary contains visible ANSI escape fragments"
fi
if grep -Fq 'hidden OSC title' "$extract_dir/install-summary.txt"; then
    fail "install summary retained an OSC terminal-control payload"
fi
if LC_ALL=C grep -q '[[:cntrl:]]' "$extract_dir/install-summary.txt"; then
    fail "install summary retained an unsafe C0 or DEL control byte"
fi
grep -Fq "Required runtime invariant matrix" "$extract_dir/runtime-invariants.txt" \
    || fail "runtime invariant matrix is missing"
grep -Fq "Backup integrity summary" "$extract_dir/backup-summary.txt" \
    || fail "backup summary is missing"
if ! grep -Fq "Local package: none" "$extract_dir/qt-package.txt"; then
    grep -Fq "Required archive contents" "$extract_dir/qt-package.txt" \
        || fail "Qt package summary does not verify required archive contents"
    grep -Eq "(PASS framework binary:|FAIL framework binary missing:) Frameworks/QtDBus[.]framework/Versions/5/QtDBus" "$extract_dir/qt-package.txt" \
        || fail "Qt package summary does not report required QtDBus binary status"
    grep -Eq "(PASS plugin:|FAIL plugin missing:) PlugIns/platforms/libqcocoa[.]dylib" "$extract_dir/qt-package.txt" \
        || fail "Qt package summary does not report required platform plugin status"
fi
manifest_count=$(find "$extract_dir/backup-manifests" -type f -name '*.tsv' ! -name 'index.tsv' -print | wc -l | tr -d ' ')
[[ "$manifest_count" == "1" ]] \
    || fail "support bundle did not deduplicate identical backup manifests"
bundled_manifest=$(find "$extract_dir/backup-manifests" -type f -name '*.tsv' ! -name 'index.tsv' -print -quit)
[[ -n "$bundled_manifest" ]] || fail "support bundle did not include a sanitized backup manifest"
assert_sanitized "$bundled_manifest"
grep -Fq "Game source: gog" "$extract_dir/backup-summary.txt" \
    || fail "backup summary does not identify the source storefront"

if ! tar -tvzf "$bundle_path" | awk '{ if ($3 != "root" || $4 != "wheel") exit 1 }'; then
    fail "support bundle archive leaks local owner or group metadata"
fi

if find "$extract_dir" -type f -print0 | xargs -0 grep -Eq 'privateperson|privateperson@example\.com|/Users/privateperson|abc123|lower-token-value|shhh-secret|p4ssw0rd|api-key-value'; then
    fail "support bundle contains a sensitive synthetic value"
fi

mkdir -p "$fixture_repo/tools" "$fixture_repo/scripts" "$fixture_repo/dist" "$fixture_repo/pkg" "$fixture_home"
cp "$diagnostics_script" "$fixture_repo/tools/collect_diagnostics.sh"
cp "$ROOT_DIR/scripts/common.sh" "$fixture_repo/scripts/common.sh"
cp "$ROOT_DIR/scripts/ui.sh" "$fixture_repo/scripts/ui.sh"
cat > "$fixture_repo/fix_worms_wmd.sh" <<'SH'
VERSION="test"
SH
cat > "$fixture_repo/scripts/download_qt_frameworks.sh" <<'SH'
#!/bin/bash
if [[ "${1:-}" == "--check" ]]; then
    echo "available"
else
    echo "available"
fi
SH
chmod +x "$fixture_repo/scripts/download_qt_frameworks.sh" "$fixture_repo/tools/collect_diagnostics.sh"

cat > "$fixture_repo/pkg/METADATA.txt" <<'META'
Qt Version: 5.15.42
Architecture: x86_64
Source: Qt prefix (/Users/privateperson/private-qt)
Token: abc123
API_KEY=api-key-value
META
(
    cd "$fixture_repo/pkg"
    tar -czf "$fixture_repo/dist/qt-frameworks-x86_64-5.15.42.tar.gz" METADATA.txt
)
(
    cd "$fixture_repo/dist"
    shasum -a 256 qt-frameworks-x86_64-5.15.42.tar.gz > qt-frameworks-x86_64-5.15.42.tar.gz.sha256
)

HOME="$fixture_home" GAME_APP="$fake_game" "$fixture_repo/tools/collect_diagnostics.sh" --bundle --bundle-output "$fixture_bundle_dir" >/dev/null
fixture_bundle_path=$(find "$fixture_bundle_dir" -mindepth 1 -maxdepth 1 -type f -name 'wormswmd-support-*.tar.gz' -print -quit)
[[ -n "$fixture_bundle_path" ]] || fail "fixture support bundle was not created"

mkdir -p "$fixture_extract_dir"
tar -xzf "$fixture_bundle_path" -C "$fixture_extract_dir"
assert_sanitized "$fixture_extract_dir/qt-package.txt"
grep -Fq "Source: Qt prefix (" "$fixture_extract_dir/qt-package.txt" \
    || fail "fixture Qt package metadata was not included"
grep -Fq "[redacted-secret]" "$fixture_extract_dir/qt-package.txt" \
    || fail "fixture Qt package metadata did not redact secret-like values"

rm -rf "$fixture_bundle_dir" "$fixture_extract_dir"
rm -f "$fixture_repo/dist/qt-frameworks-x86_64-5.15.42.tar.gz" "$fixture_repo/dist/qt-frameworks-x86_64-5.15.42.tar.gz.sha256"
(
    cd "$fixture_repo/pkg"
    tar -czf "$fixture_repo/dist/qt-frameworks-x86_64-5.15.43.tar.gz" METADATA.txt
)
HOME="$fixture_home" GAME_APP="$fake_game" "$fixture_repo/tools/collect_diagnostics.sh" --bundle --bundle-output "$fixture_bundle_dir" >/dev/null
fixture_bundle_path=$(find "$fixture_bundle_dir" -mindepth 1 -maxdepth 1 -type f -name 'wormswmd-support-*.tar.gz' -print -quit)
[[ -n "$fixture_bundle_path" ]] || fail "fixture missing-checksum support bundle was not created"
mkdir -p "$fixture_extract_dir"
tar -xzf "$fixture_bundle_path" -C "$fixture_extract_dir"
grep -Fq "Local package: qt-frameworks-x86_64-5.15.43.tar.gz" "$fixture_extract_dir/qt-package.txt" \
    || fail "Qt package summary hid a local package with missing checksum"
grep -Fq "Checksum: missing" "$fixture_extract_dir/qt-package.txt" \
    || fail "Qt package summary did not report a missing checksum"

rm -rf "$fixture_bundle_dir" "$fixture_extract_dir"
rm -f "$fixture_repo/dist/qt-frameworks-x86_64-5.15.43.tar.gz"
printf 'not a gzip archive\n' > "$fixture_repo/dist/qt-frameworks-x86_64-5.15.44.tar.gz"
(
    cd "$fixture_repo/dist"
    shasum -a 256 qt-frameworks-x86_64-5.15.44.tar.gz > qt-frameworks-x86_64-5.15.44.tar.gz.sha256
)
HOME="$fixture_home" GAME_APP="$fake_game" "$fixture_repo/tools/collect_diagnostics.sh" --bundle --bundle-output "$fixture_bundle_dir" >/dev/null
fixture_bundle_path=$(find "$fixture_bundle_dir" -mindepth 1 -maxdepth 1 -type f -name 'wormswmd-support-*.tar.gz' -print -quit)
[[ -n "$fixture_bundle_path" ]] || fail "fixture corrupt-archive support bundle was not created"
mkdir -p "$fixture_extract_dir"
tar -xzf "$fixture_bundle_path" -C "$fixture_extract_dir"
grep -Fq "Local package: qt-frameworks-x86_64-5.15.44.tar.gz" "$fixture_extract_dir/qt-package.txt" \
    || fail "Qt package summary hid a corrupt local package"
grep -Fq "FAIL unable to list archive contents" "$fixture_extract_dir/qt-package.txt" \
    || fail "Qt package summary did not report corrupt archive contents"

printf 'Support bundle sanitization check passed.\n'
