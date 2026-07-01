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

printf 'Bootstrap installer safety check passed.\n'
