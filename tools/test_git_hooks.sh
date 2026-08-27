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

if WORMSWMD_KINGFISHER_BIN="$fake_kingfisher" \
    WORMSWMD_HOOK_ARGUMENT_LOG="$argument_log" \
    WORMSWMD_HOOK_CWD_LOG="$test_dir/cwd" \
    "$HOOK" >/dev/null 2>&1; then
    fail "pre-commit hook accepted the scanner override outside explicit test mode"
fi

WORMSWMD_HOOK_TEST_MODE=1 \
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

if WORMSWMD_HOOK_TEST_MODE=1 WORMSWMD_KINGFISHER_BIN="$test_dir/missing" "$HOOK" >/dev/null 2>&1; then
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
if WORMSWMD_HOOK_TEST_MODE=1 WORMSWMD_KINGFISHER_BIN="$fake_kingfisher" "$HOOK" >/dev/null 2>&1; then
    fail "pre-commit hook accepted an unpinned Kingfisher version"
fi

fixture="$test_dir/repo"
mock_bin="$test_dir/mock-bin"
mock_log="$test_dir/mock-curl.log"
mkdir -p "$fixture/tools" "$fixture/scripts" "$fixture/.githooks" "$mock_bin"
cp "$INSTALLER" "$fixture/tools/install_git_hooks.sh"
cp "$ROOT_DIR/tools/inspect_archive.py" "$fixture/tools/inspect_archive.py"
cp "$ROOT_DIR/scripts/common.sh" "$fixture/scripts/common.sh"
cp "$HOOK" "$fixture/.githooks/pre-commit"
chmod +x "$fixture/tools/install_git_hooks.sh" "$fixture/tools/inspect_archive.py" \
    "$fixture/.githooks/pre-commit"
cat > "$fixture/tools/inspect_archive.py" <<'PY'
#!/usr/bin/env python3
import os
import shutil
import sys

with open(os.environ["FAKE_ARCHIVE_FLOW_LOG"], "a", encoding="utf-8") as log:
    log.write("inspect\n")
with open(os.environ["FAKE_INSPECT_LOG"], "a", encoding="utf-8") as log:
    log.write(" ".join(sys.argv[1:]) + "\n")
if os.environ.get("FAKE_INSPECT_FAIL") == "1":
    raise SystemExit(1)
destination = sys.argv[sys.argv.index("--copy-to") + 1]
shutil.copyfile(sys.argv[-1], destination)
os.chmod(destination, 0o600)
PY
git -C "$fixture" init -q
git -C "$fixture" config user.name "Git hook test"
git -C "$fixture" config user.email "git-hook-test@example.invalid"
git -C "$fixture" add .
git -C "$fixture" commit -qm "fixture"
git -C "$fixture" update-ref refs/remotes/origin/main HEAD
git -C "$fixture" remote add origin https://example.invalid/untrusted-fork.git

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
for argument in "$@"; do
    if [[ "$argument" == "-c" ]]; then
        cat >/dev/null
        [[ "${FAKE_SHASUM_FAIL:-0}" != "1" ]]
        exit
    fi
done

if [[ "${FAKE_BINARY_HASH_MISMATCH:-0}" == "1" ]]; then
    digest="$(printf '0%.0s' {1..64})"
else
    case "${FAKE_UNAME_S}:${FAKE_UNAME_M}" in
        Darwin:arm64) digest="bcda56855b5aee9e868d8f6d45c89c84a77ed1d15180cbd28ebc6b17c1d55ffb" ;;
        Darwin:x86_64) digest="0013b6f7709fbd65408c8b0debd5211365bb0ce123912aaec23065a0627325fe" ;;
        Linux:x86_64) digest="e5aa138eb67931b5520cedcde0ed605516ad4f3251c56f6cf0d93bb885782f1c" ;;
        Linux:arm64|Linux:aarch64) digest="a3ffa17d13feb7236fc2a268ad1fb4b9e17059033c9a0aeb358c79676dd6e66b" ;;
        *) exit 2 ;;
    esac
fi
for argument in "$@"; do
    path="$argument"
done
printf '%s  %s\n' "$digest" "$path"
EOF
cat > "$mock_bin/tar" <<'EOF'
#!/bin/bash
printf '%s\n' "tar" >> "$FAKE_ARCHIVE_FLOW_LOG"
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
inspect_log="$test_dir/inspect.log"
archive_flow_log="$test_dir/archive-flow.log"
installer_env=(
    "PATH=$mock_bin:$PATH"
    "TMPDIR=$fixture_tmp"
    "FAKE_CURL_LOG=$mock_log"
    "FAKE_UNAME_S=Darwin"
    "FAKE_UNAME_M=arm64"
    "WORMSWMD_HOOK_TEST_MODE=1"
    "WORMSWMD_TEST_SHASUM_BIN=$mock_bin/shasum"
    "WORMSWMD_TEST_UNAME_BIN=$mock_bin/uname"
    "FAKE_INSPECT_LOG=$inspect_log"
    "FAKE_ARCHIVE_FLOW_LOG=$archive_flow_log"
)
if env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" >/dev/null 2>&1; then
    fail "hook installer trusted origin/main from an unrelated repository"
fi
git -C "$fixture" remote set-url origin https://github.com/cboyd0319/WormsWMD-macOS-Fix.git
env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" >/dev/null
grep -Fq -- '--profile kingfisher --copy-to' "$inspect_log" \
    || fail "hook installer did not invoke the shared Kingfisher archive profile"
[[ "$(sed -n '1p' "$archive_flow_log")" == "inspect" ]] \
    || fail "hook installer extracted the archive before safety inspection"
[[ "$(git -C "$fixture" config --local --get core.hooksPath)" == ".githooks" ]] \
    || fail "hook installer did not configure core.hooksPath"
[[ -x "$fixture/.git/tools/kingfisher" ]] \
    || fail "hook installer did not install the repository-local scanner"
grep -Fq '/v2.0.0/kingfisher-darwin-arm64.tgz' "$mock_log" \
    || fail "hook installer selected the wrong Darwin arm64 asset"
env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" --check >/dev/null \
    || fail "hook installer --check rejected a valid installation"
if env "${installer_env[@]}" FAKE_BINARY_HASH_MISMATCH=1 \
    "$fixture/tools/install_git_hooks.sh" --check >/dev/null 2>&1; then
    fail "hook installer --check accepted a changed installed scanner digest"
fi

for official_remote in \
    "git@github.com:cboyd0319/WormsWMD-macOS-Fix" \
    "git@github.com:cboyd0319/WormsWMD-macOS-Fix.git" \
    "ssh://git@github.com/cboyd0319/WormsWMD-macOS-Fix" \
    "ssh://git@github.com/cboyd0319/WormsWMD-macOS-Fix.git"; do
    env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" --uninstall >/dev/null
    git -C "$fixture" remote set-url origin "$official_remote"
    env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" >/dev/null \
        || fail "hook installer rejected official remote form: $official_remote"
done
git -C "$fixture" remote set-url origin https://github.com/cboyd0319/WormsWMD-macOS-Fix.git

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
if env "${installer_env[@]}" FAKE_INSPECT_FAIL=1 \
    "$fixture/tools/install_git_hooks.sh" >/dev/null 2>&1; then
    fail "hook installer ignored an archive inspection failure"
fi
if [[ -e "$fixture/.git/tools/kingfisher" ]]; then
    fail "hook installer installed a scanner after archive inspection failed"
fi
if find "$fixture_tmp" -mindepth 1 -print -quit | grep -q .; then
    fail "hook installer leaked temporary files after an inspection failure"
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
    "WORMSWMD_HOOK_TEST_MODE=1"
    "WORMSWMD_TEST_SHASUM_BIN=$mock_bin/shasum"
    "WORMSWMD_TEST_UNAME_BIN=$mock_bin/uname"
    "FAKE_INSPECT_LOG=$inspect_log"
    "FAKE_ARCHIVE_FLOW_LOG=$archive_flow_log"
)
env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" >/dev/null
grep -Fq '/v2.0.0/kingfisher-linux-x64.tgz' "$mock_log" \
    || fail "hook installer selected the wrong Linux x64 asset"

env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" --uninstall >/dev/null
git -C "$fixture" switch -qc reviewed-change
printf '%s\n' "reviewed branch" > "$fixture/REVIEWED.txt"
git -C "$fixture" add REVIEWED.txt
git -C "$fixture" commit -qm "reviewed branch"
reviewed_head=$(git -C "$fixture" rev-parse HEAD)

if env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" >/dev/null 2>&1; then
    fail "hook installer accepted an unreviewed branch without an exact commit acknowledgement"
fi
if env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" \
    --allow-reviewed-commit "0000000000000000000000000000000000000000" >/dev/null 2>&1; then
    fail "hook installer accepted an acknowledgement that did not match HEAD"
fi
if env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" \
    --allow-reviewed-commit "${reviewed_head:0:12}" >/dev/null 2>&1; then
    fail "hook installer accepted a non-full reviewed commit acknowledgement"
fi
env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" \
    --allow-reviewed-commit "$reviewed_head" >/dev/null \
    || fail "hook installer rejected an exact reviewed commit acknowledgement"

printf '%s\n' "# dirty" >> "$fixture/.githooks/pre-commit"
if env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" \
    --allow-reviewed-commit "$reviewed_head" >/dev/null 2>&1; then
    fail "hook installer accepted a checkout with tracked changes"
fi
git -C "$fixture" restore -- .githooks/pre-commit

env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" --uninstall >/dev/null
[[ -x "$fixture/.git/tools/kingfisher" ]] \
    || fail "hook uninstall removed the cached scanner before explicit purge"
env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" \
    --allow-reviewed-commit "$reviewed_head" >/dev/null
env "${installer_env[@]}" "$fixture/tools/install_git_hooks.sh" --purge >/dev/null
if git -C "$fixture" config --local --get core.hooksPath >/dev/null 2>&1; then
    fail "hook purge retained core.hooksPath"
fi
[[ ! -e "$fixture/.git/tools/kingfisher" ]] \
    || fail "hook purge retained the cached scanner"

printf '%s\n' "Git hook regression check passed."
