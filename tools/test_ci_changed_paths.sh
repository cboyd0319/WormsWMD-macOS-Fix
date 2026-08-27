#!/bin/bash
# Regression checks for event-aware GitHub Actions changed-path selection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELECTOR="$SCRIPT_DIR/ci_changed_paths.sh"
CLASSIFIER="$SCRIPT_DIR/ci_requires_macos.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-ci-paths.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
repo="$test_dir/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.name "CI path test"
git -C "$repo" config user.email "ci-path-test@example.invalid"
git -C "$repo" config diff.renames true

printf '%s\n' "initial" > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm "initial"
initial=$(git -C "$repo" rev-parse HEAD)

git -C "$repo" switch -qc docs-change
mkdir -p "$repo/docs"
printf '%s\n' "docs" > "$repo/docs/guide.md"
git -C "$repo" add docs/guide.md
git -C "$repo" commit -qm "docs"
feature_head=$(git -C "$repo" rev-parse HEAD)

git -C "$repo" switch -q main
printf '%s\n' "runtime" > "$repo/fix_worms_wmd.sh"
git -C "$repo" add fix_worms_wmd.sh
git -C "$repo" commit -qm "runtime"
updated_base=$(git -C "$repo" rev-parse HEAD)

pull_paths="$test_dir/pull-paths"
(cd "$repo" && "$SELECTOR" pull_request "$updated_base" "$feature_head") > "$pull_paths"
if "$CLASSIFIER" < "$pull_paths"; then
    fail "three-dot pull-request diff included an unrelated base-branch runtime change"
fi
[[ "$(tr '\0' '\n' < "$pull_paths")" == "docs/guide.md" ]] \
    || fail "pull-request diff did not contain exactly the feature change"

push_paths="$test_dir/push-paths"
(cd "$repo" && "$SELECTOR" push "$initial" "$updated_base") > "$push_paths"
if ! "$CLASSIFIER" < "$push_paths"; then
    fail "two-dot push diff omitted the pushed runtime change"
fi
[[ "$(tr '\0' '\n' < "$push_paths")" == "fix_worms_wmd.sh" ]] \
    || fail "push diff did not contain exactly the pushed change"

git -C "$repo" switch -qc runtime-rename
mkdir -p "$repo/docs"
git -C "$repo" mv fix_worms_wmd.sh docs/renamed-runtime.md
git -C "$repo" commit -qm "rename runtime into docs"
rename_head=$(git -C "$repo" rev-parse HEAD)
rename_paths="$test_dir/rename-paths"
(cd "$repo" && "$SELECTOR" pull_request "$updated_base" "$rename_head") > "$rename_paths"
if ! "$CLASSIFIER" < "$rename_paths"; then
    fail "cross-boundary rename hid the original runtime path"
fi
tr '\0' '\n' < "$rename_paths" | grep -Fxq 'fix_worms_wmd.sh' \
    || fail "changed-path selector omitted the source of a rename"
tr '\0' '\n' < "$rename_paths" | grep -Fxq 'docs/renamed-runtime.md' \
    || fail "changed-path selector omitted the destination of a rename"

if (cd "$repo" && "$SELECTOR" schedule "$initial" "$updated_base") >/dev/null 2>&1; then
    fail "changed-path selector accepted an unsupported event"
fi
if (cd "$repo" && "$SELECTOR" pull_request main "$feature_head") >/dev/null 2>&1; then
    fail "changed-path selector accepted a non-SHA revision"
fi

printf '%s\n' "CI changed-path selection check passed."
