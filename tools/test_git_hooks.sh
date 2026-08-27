#!/bin/bash
# Regression checks for the enforced repository Kingfisher pre-commit hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
HOOK="$ROOT_DIR/.githooks/pre-commit"
INSTALLER="$ROOT_DIR/tools/install_git_hooks.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -x "$HOOK" ]] || fail ".githooks/pre-commit is required and must be executable"
[[ -x "$INSTALLER" ]] || fail "tools/install_git_hooks.sh is required and must be executable"

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-git-hooks.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
fake_kingfisher="$test_dir/kingfisher"
argument_log="$test_dir/arguments"

cat > "$fake_kingfisher" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "kingfisher 2.0.0"
    exit 0
fi
printf '%s\n' "$@" > "$WORMSWMD_HOOK_ARGUMENT_LOG"
pwd > "$WORMSWMD_HOOK_CWD_LOG"
EOF
chmod +x "$fake_kingfisher"

WORMSWMD_KINGFISHER_BIN="$fake_kingfisher" \
WORMSWMD_HOOK_ARGUMENT_LOG="$argument_log" \
WORMSWMD_HOOK_CWD_LOG="$test_dir/cwd" \
    "$HOOK"

for expected in scan . --staged --git-history none --exclude '**/.git/**' --exclude 'dist/*.tar.gz' --no-extract-archives --redact --no-validate --confidence medium --quiet --no-update-check; do
    grep -Fxq -- "$expected" "$argument_log" || fail "pre-commit hook omitted Kingfisher argument: $expected"
done
[[ "$(cat "$test_dir/cwd")" == "$ROOT_DIR" ]] || fail "pre-commit hook did not anchor at repository root"

if grep -Fq 'command -v kingfisher' "$HOOK"; then
    fail "pre-commit hook accepts an arbitrary Kingfisher from PATH"
fi

if WORMSWMD_KINGFISHER_BIN="$test_dir/missing" "$HOOK" >/dev/null 2>&1; then
    fail "pre-commit hook succeeded without its pinned scanner"
fi

cat > "$fake_kingfisher" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "kingfisher 1.113.0"
    exit 0
fi
exit 0
EOF
chmod +x "$fake_kingfisher"
if WORMSWMD_KINGFISHER_BIN="$fake_kingfisher" "$HOOK" >/dev/null 2>&1; then
    fail "pre-commit hook accepted an unpinned Kingfisher version"
fi

fixture="$test_dir/repo"
mock_bin="$test_dir/mock-bin"
mock_log="$test_dir/mock-curl.log"
mkdir -p "$fixture/tools" "$fixture/.githooks" "$mock_bin"
cp "$INSTALLER" "$fixture/tools/install_git_hooks.sh"
cp "$HOOK" "$fixture/.githooks/pre-commit"
chmod +x "$fixture/tools/install_git_hooks.sh" "$fixture/.githooks/pre-commit"
git -C "$fixture" init -q

cat > "$mock_bin/uname" <<'EOF'
#!/bin/bash
case "${1:-}" in
    -s) printf '%s\n' "$FAKE_UNAME_S" ;;
    -m) printf '%s\n' "$FAKE_UNAME_M" ;;
    *) exit 2 ;;
esac
EOF
cat > "$mock_bin/curl" <<'EOF'
#!/bin/bash
if [[ "${FAKE_CURL_FAIL:-0}" == "1" ]]; then
    exit 22
fi
output=""
url=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --output)
            output="$2"
            shift 2
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
printf '%s\n' "$url" >> "$FAKE_CURL_LOG"
printf '%s\n' "mock archive" > "$output"
EOF
cat > "$mock_bin/shasum" <<'EOF'
#!/bin/bash
cat >/dev/null
[[ "${FAKE_SHASUM_FAIL:-0}" != "1" ]]
EOF
cat > "$mock_bin/tar" <<'EOF'
#!/bin/bash
destination=""
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "-C" ]]; then
        destination="$2"
        break
    fi
    shift
done
[[ -n "$destination" ]] || exit 2
cat > "$destination/kingfisher" <<'SCANNER'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
    printf 'kingfisher %s\n' "${FAKE_SCANNER_VERSION:-2.0.0}"
    exit 0
fi
exit 0
SCANNER
chmod +x "$destination/kingfisher"
EOF
cat > "$mock_bin/kingfisher" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "kingfisher 2.0.0"
    exit 0
fi
exit 0
EOF
chmod +x "$mock_bin"/*

if (cd "$fixture" && PATH="$mock_bin:$PATH" ./.githooks/pre-commit) >/dev/null 2>&1; then
    fail "isolated pre-commit hook accepted an unpinned PATH scanner"
fi

fixture_tmp="$test_dir/installer-tmp"
mkdir -p "$fixture_tmp"
installer_env=(
    "PATH=$mock_bin:$PATH"
    "TMPDIR=$fixture_tmp"
    "FAKE_CURL_LOG=$mock_log"
    "FAKE_UNAME_S=Darwin"
    "FAKE_UNAME_M=arm64"
)
env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" >/dev/null
[[ "$(git -C "$fixture" config --local --get core.hooksPath)" == ".githooks" ]] \
    || fail "hook installer did not configure core.hooksPath"
[[ -x "$fixture/.git/tools/kingfisher" ]] \
    || fail "hook installer did not install the repository-local scanner"
grep -Fq '/v2.0.0/kingfisher-darwin-arm64.tgz' "$mock_log" \
    || fail "hook installer selected the wrong Darwin arm64 asset"
env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" --check >/dev/null \
    || fail "hook installer --check rejected a valid installation"

env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" --uninstall >/dev/null
if git -C "$fixture" config --local --get core.hooksPath >/dev/null 2>&1; then
    fail "hook installer --uninstall retained core.hooksPath"
fi
[[ -x "$fixture/.git/tools/kingfisher" ]] \
    || fail "hook installer --uninstall removed the cached scanner"

rm "$fixture/.git/tools/kingfisher"
if env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" --check >/dev/null 2>&1; then
    fail "hook installer --check accepted a missing scanner"
fi
if env "${installer_env[@]}" FAKE_CURL_FAIL=1 \
    "$fixture/tools/install_git_hooks.sh" >/dev/null 2>&1; then
    fail "hook installer ignored a download failure"
fi
if find "$fixture_tmp" -mindepth 1 -print -quit | grep -q .; then
    fail "hook installer leaked temporary files after a download failure"
fi
if env "${installer_env[@]}" FAKE_SHASUM_FAIL=1 \
    "$fixture/tools/install_git_hooks.sh" >/dev/null 2>&1; then
    fail "hook installer ignored a checksum failure"
fi
if find "$fixture_tmp" -mindepth 1 -print -quit | grep -q .; then
    fail "hook installer leaked temporary files after a checksum failure"
fi
if env "${installer_env[@]}" FAKE_SCANNER_VERSION=1.113.0 \
    "$fixture/tools/install_git_hooks.sh" >/dev/null 2>&1; then
    fail "hook installer accepted an extracted scanner with the wrong version"
fi
if [[ -e "$fixture/.git/tools/kingfisher" ]]; then
    fail "hook installer placed an unverified scanner in the Git directory"
fi
if find "$fixture_tmp" -mindepth 1 -print -quit | grep -q .; then
    fail "hook installer leaked temporary files after a version failure"
fi

: > "$mock_log"
installer_env=(
    "PATH=$mock_bin:$PATH"
    "TMPDIR=$fixture_tmp"
    "FAKE_CURL_LOG=$mock_log"
    "FAKE_UNAME_S=Linux"
    "FAKE_UNAME_M=x86_64"
)
env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" >/dev/null
grep -Fq '/v2.0.0/kingfisher-linux-x64.tgz' "$mock_log" \
    || fail "hook installer selected the wrong Linux x64 asset"

printf '%s\n' "Git hook regression check passed."
