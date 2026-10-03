#!/bin/bash
#
# Regression checks for curl-pipe bootstrap installer path safety.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() {
    printf 'bootstrap installer safety check failed: %s\n' "$*" >&2
    exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-bootstrap-safety.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

function_file="$tmp_dir/install-normalize.sh"
awk '
    /^print_error\(\)/ { print }
    /^install_dir_is_system_path\(\)/ { in_helper=1 }
    in_helper { print }
    /^}$/ && in_helper { in_helper=0 }
    /^normalize_install_dir\(\)/ { in_func=1 }
    in_func { print }
    /^}$/ && in_func { exit }
' "$ROOT_DIR/install.sh" > "$function_file"

if [[ ! -s "$function_file" ]]; then
    fail "could not extract normalize_install_dir"
fi

run_normalize() (
    set -euo pipefail
    # shellcheck disable=SC2034
    RED=""
    # shellcheck disable=SC2034
    NC=""
    HOME="$1"
    INSTALL_DIR="$2"
    # shellcheck source=/dev/null
    source "$function_file"
    normalize_install_dir
    printf '%s\n' "$INSTALL_DIR"
)

test_home="$tmp_dir/home"
mkdir -p "$test_home"
test_home_real=$(cd "$test_home" && pwd -P)

safe_output=$(run_normalize "$test_home" "$test_home/.wormswmd-fix") \
    || fail "safe user install dir was rejected"
if [[ "$safe_output" != "$test_home_real/.wormswmd-fix" ]]; then
    fail "safe user install dir normalized unexpectedly: $safe_output"
fi

link_parent="$tmp_dir/link-to-applications"
ln -s /Applications "$link_parent"

if run_normalize "$test_home" "$link_parent/wormswmd-fix" >/dev/null 2>&1; then
    fail "INSTALL_DIR with a symlinked system parent was accepted"
fi

if run_normalize "$test_home" "/tmp/../Applications/wormswmd-fix" >/dev/null 2>&1; then
    fail "INSTALL_DIR resolving through .. into a system path was accepted"
fi

# The extracted verification helpers call the stubs defined in this subshell.
# shellcheck disable=SC2329
run_pin_check() (
    set -euo pipefail
    local entrypoint="$1" pin="$2"
    local fixture_commit="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    local pin_functions="$tmp_dir/pin-functions.sh"
    RED="" NC=""
    DEFAULT_INSTALL_REF="v1.7.7" INSTALL_REF="v1.7.7"
    DEFAULT_INSTALL_COMMIT="$pin" INSTALL_COMMIT="$pin"
    INSTALL_DIR="$tmp_dir/checkout"
    print_error() { :; }
    print_info() { :; }
    git() { printf '%s\n' "$fixture_commit"; }
    read() { return 0; }
    # Extract only verification helpers, never run the network/UI entrypoints.
    awk '
        /^verify_(default_install|install)_commit\(\)/ { inside=1 }
        inside { print }
        inside && /^}/ { inside=0 }
    ' "$ROOT_DIR/$entrypoint" > "$pin_functions"
    # shellcheck source=/dev/null
    source "$pin_functions"
    if [[ "$entrypoint" == install.sh ]]; then
        verify_default_install_commit "$INSTALL_DIR"
    else
        verify_install_commit
    fi
)

for entrypoint in install.sh "Install Fix.command"; do
    for pin in "" PENDING_v1_7_7 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; do
        if run_pin_check "$entrypoint" "$pin" >/dev/null 2>&1; then
            fail "$entrypoint accepted an empty, pending, or mismatched release pin"
        fi
    done
    run_pin_check "$entrypoint" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        || fail "$entrypoint rejected a matching release pin"
    pin=$(sed -nE 's/^(DEFAULT_INSTALL_COMMIT|INSTALL_COMMIT)="([^"]*)"$/\2/p' "$ROOT_DIR/$entrypoint")
    [[ "$pin" == PENDING_* || "$pin" =~ ^[0-9a-f]{40}$ ]] \
        || fail "$entrypoint has no valid release pin or pending sentinel"
done

printf 'Bootstrap installer safety check passed.\n'
