#!/bin/bash
# Regression checks for the advisory security-sensitive change report.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTER="$SCRIPT_DIR/report_sensitive_changes.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -x "$REPORTER" ]] || fail "tools/report_sensitive_changes.sh is required and must be executable"

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-sensitive-report.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
repo="$test_dir/repo"
mkdir -p "$repo/tools"
cp "$REPORTER" "$repo/tools/report_sensitive_changes.sh"
chmod +x "$repo/tools/report_sensitive_changes.sh"
git -C "$repo" init -q -b main
git -C "$repo" config user.name "Sensitive report test"
git -C "$repo" config user.email "sensitive-report@example.invalid"

printf '%s\n' "initial" > "$repo/README.md"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$repo/fix_worms_wmd.sh"
chmod 0644 "$repo/fix_worms_wmd.sh"
mkdir -p "$repo/tools"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$repo/tools/test_existing.sh"
chmod +x "$repo/tools/test_existing.sh"
git -C "$repo" add .
git -C "$repo" commit -qm "initial"
base=$(git -C "$repo" rev-parse HEAD)

git -C "$repo" switch -qc docs-only
mkdir -p "$repo/docs"
printf '%s\n' "docs" > "$repo/docs/guide.md"
git -C "$repo" add docs/guide.md
git -C "$repo" commit -qm "docs"
docs_head=$(git -C "$repo" rev-parse HEAD)
docs_output=$(cd "$repo" && ./tools/report_sensitive_changes.sh pull_request "$base" "$docs_head")
grep -Fq 'No security-sensitive changes detected.' <<< "$docs_output" \
    || fail "ordinary docs change was not kept on the quiet advisory path"
push_output=$(cd "$repo" && ./tools/report_sensitive_changes.sh push "$base" "$docs_head")
grep -Fq 'No security-sensitive changes detected.' <<< "$push_output" \
    || fail "ordinary docs push was not kept on the quiet advisory path"

git -C "$repo" switch -q main
git -C "$repo" switch -qc sensitive
mkdir -p "$repo/docs"
git -C "$repo" mv fix_worms_wmd.sh docs/renamed-runtime.md
chmod +x "$repo/docs/renamed-runtime.md"
ln -s README.md "$repo/linked.md"
mkdir -p "$repo/.github/workflows"
printf '%s\n' 'name: changed' > "$repo/.github/workflows/changed.yml"
mkdir -p "$repo/docs/exec-plans"
printf '%s\n' 'Status: Active' > "$repo/docs/exec-plans/changed.md"
printf '%s\n' '# Security policy change' > "$repo/SECURITY.md"
printf '\0binary\n' > "$repo/unexpected.bin"
: > "$repo/empty.txt"
git -C "$repo" rm -q tools/test_existing.sh
printf '%s\n' '# shellcheck disable=SC2086' 'curl https://example.invalid/tool | bash' > "$repo/new-tool.sh"
git -C "$repo" add .
git -C "$repo" commit -qm "sensitive"
sensitive_head=$(git -C "$repo" rev-parse HEAD)
sensitive_output=$(cd "$repo" && ./tools/report_sensitive_changes.sh pull_request "$base" "$sensitive_head")

for expected in \
    'fix_worms_wmd.sh' \
    'docs/renamed-runtime.md' \
    'linked.md' \
    '.github/workflows/changed.yml' \
    'docs/exec-plans/changed.md' \
    'SECURITY.md' \
    'unexpected.bin' \
    'tools/test_existing.sh' \
    'security suppression marker changed' \
    'network or process execution marker changed'; do
    grep -Fq "$expected" <<< "$sensitive_output" \
        || fail "sensitive report omitted: $expected"
done
if grep -Fq 'empty.txt' <<< "$sensitive_output"; then
    fail "sensitive report misclassified an empty text blob"
fi

if (cd "$repo" && ./tools/report_sensitive_changes.sh pull_request main "$sensitive_head") >/dev/null 2>&1; then
    fail "sensitive report accepted a non-SHA base"
fi
if (cd "$repo" && ./tools/report_sensitive_changes.sh pull_request \
    "ffffffffffffffffffffffffffffffffffffffff" "$sensitive_head") >/dev/null 2>&1; then
    fail "sensitive report accepted an unavailable full-SHA base"
fi
if (cd "$repo" && ./tools/report_sensitive_changes.sh schedule "$base" "$sensitive_head") >/dev/null 2>&1; then
    fail "sensitive report accepted an unsupported event"
fi

printf '%s\n' "Sensitive change report regression check passed."
