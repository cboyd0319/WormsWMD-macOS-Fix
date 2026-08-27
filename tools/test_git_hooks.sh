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

grep -Fq "trap 'rm -rf \"\$temporary_directory\"' EXIT" "$INSTALLER" \
    || fail "hook installer must clean temporary files on process exit"
if grep -Fq "trap 'rm -rf \"\$temporary_directory\"' RETURN" "$INSTALLER"; then
    fail "hook installer still uses function-return-only cleanup"
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

printf '%s\n' "Git hook regression check passed."
