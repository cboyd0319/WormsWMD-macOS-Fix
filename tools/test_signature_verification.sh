#!/bin/bash
# Regression checks for strict signature and recursive quarantine classification.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

fail() {
    printf 'signature verification check failed: %s\n' "$*" >&2
    exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-signature.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

complete_app="$tmp_dir/complete/Worms W.M.D.app"
original_app="$tmp_dir/original/Worms W.M.D.app"
fake_lipo="$tmp_dir/lipo"
fake_codesign="$tmp_dir/codesign"
fake_xattr="$tmp_dir/xattr"

mkdir -p "$complete_app/Contents/MacOS" \
    "$complete_app/Contents/Frameworks/AGL.framework/Versions/A" \
    "$complete_app/Contents/PlugIns/platforms" \
    "$complete_app/Contents/PlugIns/imageformats" \
    "$original_app/Contents/MacOS"
: > "$complete_app/Contents/MacOS/Worms W.M.D"
: > "$original_app/Contents/MacOS/Worms W.M.D"
: > "$complete_app/Contents/Frameworks/AGL.framework/Versions/A/AGL"
for framework in QtCore QtGui QtWidgets QtOpenGL QtPrintSupport QtDBus QtSvg; do
    mkdir -p "$complete_app/Contents/Frameworks/$framework.framework/Versions/5"
    : > "$complete_app/Contents/Frameworks/$framework.framework/Versions/5/$framework"
done
: > "$complete_app/Contents/PlugIns/platforms/libqcocoa.dylib"
: > "$complete_app/Contents/PlugIns/imageformats/libqsvg.dylib"

cat > "$fake_lipo" <<'STUB'
#!/bin/bash
[[ "${1:-}" == "-archs" ]] || exit 1
printf '%s\n' x86_64
STUB
cat > "$fake_codesign" <<'STUB'
#!/bin/bash
is_verify=false
for argument in "$@"; do
    [[ "$argument" == "--verify" ]] && is_verify=true
done
if $is_verify; then
    case "${SIGNATURE_MODE:-unsigned}" in
        valid-adhoc|valid-authority) exit 0 ;;
        unsigned) printf '%s\n' 'code object is not signed at all' >&2; exit 1 ;;
        invalid|metadata-only) printf '%s\n' 'code object is not signed at all or signature is invalid' >&2; exit 1 ;;
    esac
fi
case "${SIGNATURE_MODE:-unsigned}" in
    valid-adhoc|metadata-only) printf '%s\n' 'Signature=adhoc' >&2; exit 0 ;;
    valid-authority) printf '%s\n' 'Authority=Example Developer' >&2; exit 0 ;;
    invalid) printf '%s\n' 'Signature=adhoc' >&2; exit 0 ;;
    unsigned) printf '%s\n' 'code object is not signed at all' >&2; exit 1 ;;
esac
STUB
cat > "$fake_xattr" <<'STUB'
#!/bin/bash
[[ "${1:-}" == "-p" && "${2:-}" == "com.apple.quarantine" ]] || exit 2
path="${3:-}"
case ",${QUARANTINE_NAMES:-}," in
    *",$(basename "$path"),"*) exit 0 ;;
esac
exit 1
STUB
chmod +x "$fake_lipo" "$fake_codesign" "$fake_xattr"

assert_signature_state() {
    local expected="$1"
    local app="$2"
    local mode="$3"
    local actual

    actual=$(SIGNATURE_MODE="$mode" worms_classify_bundle_signature_with \
        "$app" "$fake_lipo" "$fake_codesign")
    [[ "$actual" == "$expected" ]] \
        || fail "expected $expected for $mode, got $actual"
}

assert_signature_state original-unsigned "$original_app" unsigned
assert_signature_state original-invalid "$original_app" invalid
assert_signature_state fixed-valid-adhoc "$complete_app" valid-adhoc
assert_signature_state fixed-valid "$complete_app" valid-authority
assert_signature_state fixed-invalid "$complete_app" invalid
assert_signature_state fixed-invalid "$complete_app" metadata-only

unavailable_state=$(worms_classify_bundle_signature_with \
    "$complete_app" "$fake_lipo" "")
[[ "$unavailable_state" == "fixed-unavailable" ]] \
    || fail "unavailable codesign was misclassified: $unavailable_state"

none_state=$(QUARANTINE_NAMES='' worms_quarantine_state_with \
    "$fake_xattr" /usr/bin/find "$complete_app" 2)
[[ "$none_state" == "none" ]] || fail "empty quarantine state was $none_state"

root_state=$(QUARANTINE_NAMES='Worms W.M.D.app' worms_quarantine_state_with \
    "$fake_xattr" /usr/bin/find "$complete_app" 2)
[[ "$root_state" == "present:1" ]] || fail "root quarantine was not detected: $root_state"

mkdir -p "$complete_app/Contents/Resources"
: > "$complete_app/Contents/Resources/nested-quarantine"
nested_state=$(QUARANTINE_NAMES='nested-quarantine' worms_quarantine_state_with \
    "$fake_xattr" /usr/bin/find "$complete_app" 2)
[[ "$nested_state" == "present:1" ]] \
    || fail "nested quarantine was not detected: $nested_state"

for name in q1 q2 q3; do : > "$complete_app/Contents/Resources/$name"; done
excess_state=$(QUARANTINE_NAMES='q1,q2,q3' worms_quarantine_state_with \
    "$fake_xattr" /usr/bin/find "$complete_app" 2)
[[ "$excess_state" == "present:2+" ]] \
    || fail "excess quarantine summary was not bounded: $excess_state"
if grep -Eq 'q1|q2|q3|nested-quarantine' <<< "$excess_state"; then
    fail "quarantine summary exposed raw filenames"
fi
[[ "$(worms_quarantine_state_with "" /usr/bin/find "$complete_app" 2)" == "unavailable" ]] \
    || fail "unavailable xattr was not reported"

signature_bin="$tmp_dir/signature-bin"
signature_home="$tmp_dir/signature-home"
diagnostic_report="$tmp_dir/signature-diagnostics.txt"
mkdir -p "$signature_bin" "$signature_home"
ln -s "$fake_lipo" "$signature_bin/lipo"
ln -s "$fake_codesign" "$signature_bin/codesign"
ln -s "$fake_xattr" "$signature_bin/xattr"
: > "$complete_app/Contents/Resources/private-quarantine-name"
SIGNATURE_MODE=invalid QUARANTINE_NAMES=private-quarantine-name \
    HOME="$signature_home" PATH="$signature_bin:$PATH" GAME_APP="$complete_app" \
    "$ROOT_DIR/tools/collect_diagnostics.sh" --output "$diagnostic_report" \
    >/dev/null
grep -Fq 'Complete fixed app strict signature: invalid' "$diagnostic_report" \
    || fail "diagnostics did not classify a complete invalid signature"
grep -Fq 'Recursive quarantine: 1 entries (names omitted)' "$diagnostic_report" \
    || fail "diagnostics did not report bounded recursive quarantine"
if grep -Fq 'private-quarantine-name' "$diagnostic_report"; then
    fail "diagnostics leaked a quarantined filename"
fi

for consumer in \
    "$ROOT_DIR/scripts/05_verify_installation.sh" \
    "$ROOT_DIR/tools/preflight_check.sh" \
    "$ROOT_DIR/tools/collect_diagnostics.sh"; do
    grep -Fq 'worms_classify_bundle_signature' "$consumer" \
        || fail "signature consumer does not use strict shared classification: $consumer"
    grep -Fq 'worms_quarantine_state' "$consumer" \
        || fail "quarantine consumer does not use bounded recursive state: $consumer"
done
# shellcheck disable=SC2016
grep -Fq 'codesign --verify --deep --strict "$GAME_APP"' "$ROOT_DIR/fix_worms_wmd.sh" \
    || fail "installer rollback gate lost its strict codesign verification"

printf 'Signature verification check passed.\n'
