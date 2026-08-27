#!/bin/bash
# Regression checks for exact update checksum binding and atomic publication.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() {
    printf 'update download safety check failed: %s\n' "$*" >&2
    exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-update-download.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

fixture="$tmp_dir/repo"
fixture_home="$tmp_dir/home"
fake_bin="$tmp_dir/bin"
mkdir -p "$fixture/tools" "$fixture/scripts" "$fixture_home/Downloads" "$fake_bin"
cp "$ROOT_DIR/tools/check_updates.sh" "$fixture/tools/check_updates.sh"
cp "$ROOT_DIR/scripts/common.sh" "$fixture/scripts/common.sh"
cp "$ROOT_DIR/scripts/ui.sh" "$fixture/scripts/ui.sh"
chmod +x "$fixture/tools/check_updates.sh"
# shellcheck disable=SC2016
grep -Fq 'worms_validate_replaceable_regular_file "$DOWNLOAD_FILE"' \
    "$fixture/tools/check_updates.sh" \
    || fail "update checker does not reuse the shared safe-target validator"
cat > "$fixture/fix_worms_wmd.sh" <<'SH'
VERSION="1.0.0"
SH

cat > "$fake_bin/curl" <<'STUB'
#!/bin/bash
output=""
url=""
head_only=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            output="$2"
            shift 2
            ;;
        -I|-*I*)
            head_only=true
            shift
            ;;
        https://*)
            url="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done
if [[ "$url" == */releases/latest ]]; then
    printf '%s\n' '{"tag_name":"v2.0.0"}'
    exit 0
fi
$head_only && exit 0
case "$url" in
    *.zip.sha256)
        case "${CHECKSUM_MODE:-text}" in
            text) printf '%s  %s\n' "$PAYLOAD_SHA256" "$EXPECTED_BASENAME" > "$output" ;;
            binary) printf '%s *%s\n' "$PAYLOAD_SHA256" "$EXPECTED_BASENAME" > "$output" ;;
            decoy) printf '%s  %s.decoy\n' "$PAYLOAD_SHA256" "$EXPECTED_BASENAME" > "$output" ;;
            extra) printf '%s  %s\nextra\n' "$PAYLOAD_SHA256" "$EXPECTED_BASENAME" > "$output" ;;
            cr) printf '%s  %s\r\n' "$PAYLOAD_SHA256" "$EXPECTED_BASENAME" > "$output" ;;
            nul) printf '%s  %s\0\n' "$PAYLOAD_SHA256" "$EXPECTED_BASENAME" > "$output" ;;
            mismatch) printf '%064d  %s\n' 0 "$EXPECTED_BASENAME" > "$output" ;;
        esac
        ;;
    *.zip)
        printf '%s' "${PAYLOAD_CONTENT:-release payload}" > "$output"
        if [[ "${DOWNLOAD_FAIL:-0}" == "1" ]]; then
            exit 22
        fi
        ;;
    *)
        exit 22
        ;;
esac
STUB
chmod +x "$fake_bin/curl"
cat > "$fake_bin/mv" <<'STUB'
#!/bin/bash
source_path="${@: -2:1}"
target_path="${@: -1}"
if [[ "${PUBLISH_FAIL:-}" == "checksum" ]] \
    && [[ "$source_path" == */release.zip.sha256 ]] \
    && [[ "$target_path" == *.zip.sha256 ]]; then
    exit 1
fi
exec /bin/mv "$@"
STUB
chmod +x "$fake_bin/mv"

expected_basename="WormsWMD-macOS-Fix-v2.0.0.zip"
download_file="$fixture_home/Downloads/$expected_basename"
checksum_file="$download_file.sha256"

run_download() {
    local mode="$1"
    local payload="$2"
    local download_fail="${3:-0}"
    local publish_fail="${4:-}"
    local payload_sha

    payload_sha=$(printf '%s' "$payload" | shasum -a 256 | awk '{print $1}')
    HOME="$fixture_home" PATH="$fake_bin:$PATH" \
        CHECKSUM_MODE="$mode" PAYLOAD_CONTENT="$payload" \
        PAYLOAD_SHA256="$payload_sha" EXPECTED_BASENAME="$expected_basename" \
        DOWNLOAD_FAIL="$download_fail" PUBLISH_FAIL="$publish_fail" \
        "$fixture/tools/check_updates.sh" --download
}

run_download text 'first payload' >/dev/null \
    || fail "valid text checksum form was rejected"
grep -Fxq 'first payload' "$download_file" \
    || fail "valid text checksum did not publish its zip"

run_download binary 'second payload' >/dev/null \
    || fail "valid binary checksum form or safe regular replacement was rejected"
grep -Fxq 'second payload' "$download_file" \
    || fail "safe regular update target was not deliberately replaced"

for mode in decoy extra cr nul mismatch; do
    printf 'preserved zip\n' > "$download_file"
    printf 'preserved checksum\n' > "$checksum_file"
    if run_download "$mode" 'rejected payload' >/dev/null 2>&1; then
        fail "unsafe checksum mode was accepted: $mode"
    fi
    grep -Fxq 'preserved zip' "$download_file" \
        || fail "$mode checksum failure modified the prior zip"
    grep -Fxq 'preserved checksum' "$checksum_file" \
        || fail "$mode checksum failure modified the prior checksum"
done

printf 'preserved zip\n' > "$download_file"
printf 'preserved checksum\n' > "$checksum_file"
if run_download text 'partial payload' 1 >/dev/null 2>&1; then
    fail "interrupted zip download succeeded"
fi
grep -Fxq 'preserved zip' "$download_file" \
    || fail "interrupted download modified the prior zip"
grep -Fxq 'preserved checksum' "$checksum_file" \
    || fail "interrupted download modified the prior checksum"

if run_download text 'publish failure' 0 checksum >/dev/null 2>&1; then
    fail "forced checksum publication failure succeeded"
fi
grep -Fxq 'preserved zip' "$download_file" \
    || fail "publication failure did not restore the prior zip"
grep -Fxq 'preserved checksum' "$checksum_file" \
    || fail "publication failure did not restore the prior checksum"

rm -f "$download_file" "$checksum_file"
victim="$tmp_dir/victim"
printf 'victim\n' > "$victim"
ln -s "$victim" "$download_file"
if run_download text 'link payload' >/dev/null 2>&1; then
    fail "download accepted a symlink destination"
fi
[[ -L "$download_file" ]] || fail "symlink destination was replaced"
grep -Fxq victim "$victim" || fail "symlink destination modified its victim"

rm -f "$download_file"
printf 'hardlinked\n' > "$download_file"
ln "$download_file" "$tmp_dir/hardlink-alias"
if run_download text 'hardlink payload' >/dev/null 2>&1; then
    fail "download accepted a hardlinked destination"
fi
grep -Fxq hardlinked "$download_file" || fail "hardlinked destination was modified"
grep -Fxq hardlinked "$tmp_dir/hardlink-alias" || fail "hardlink alias was modified"

rm -f "$download_file" "$tmp_dir/hardlink-alias"
mkfifo "$download_file"
if run_download text 'fifo payload' >/dev/null 2>&1; then
    fail "download accepted a FIFO destination"
fi
[[ -p "$download_file" ]] || fail "FIFO destination was replaced"

if find "$fixture_home/Downloads" -mindepth 1 -maxdepth 1 \
    -name '.wormswmd-update-*' -print -quit | grep -q .; then
    fail "update download leaked temporary files"
fi

printf 'Update download safety check passed.\n'
