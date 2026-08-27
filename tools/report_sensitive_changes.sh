#!/bin/bash
# Report security-sensitive changed surfaces without executing proposed code.

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
    printf '%s\n' "USAGE: report_sensitive_changes.sh pull_request|push BASE_SHA HEAD_SHA" >&2
    exit 2
fi

event_name="$1"
base_sha="$2"
head_sha="$3"

if [[ ! "$base_sha" =~ ^[0-9a-f]{40}$ || ! "$head_sha" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s\n' "ERROR: BASE_SHA and HEAD_SHA must be full lowercase Git object IDs." >&2
    exit 1
fi
if ! git cat-file -e "$base_sha^{commit}" 2>/dev/null \
    || ! git cat-file -e "$head_sha^{commit}" 2>/dev/null; then
    printf '%s\n' "ERROR: BASE_SHA or HEAD_SHA is not an available commit." >&2
    exit 1
fi

case "$event_name" in
    pull_request)
        diff_base=$(git merge-base "$base_sha" "$head_sha") || {
            printf '%s\n' "ERROR: BASE_SHA and HEAD_SHA have no merge base." >&2
            exit 1
        }
        ;;
    push)
        diff_base="$base_sha"
        ;;
    *)
        printf 'ERROR: Unsupported GitHub event for sensitive-change reporting: %s\n' "$event_name" >&2
        exit 1
        ;;
esac

findings=0

quote_path() {
    printf '%q' "$1"
}

report_path() {
    local category="$1"
    local change="$2"
    local path="$3"
    local rendered

    rendered=$(quote_path "$path")
    printf 'SENSITIVE [%s] %s %s\n' "$category" "$change" "$rendered"
    findings=$((findings + 1))
}

blob_is_binary_or_large() {
    local object_id="$1"
    local size

    [[ "$object_id" =~ ^0+$ ]] && return 1
    size=$(git cat-file -s "$object_id" 2>/dev/null || echo 0)
    if [[ "$size" == 0 ]]; then
        return 1
    fi
    if [[ "$size" =~ ^[0-9]+$ ]] && (( size > 1048576 )); then
        return 0
    fi
    if (
        set +o pipefail
        git cat-file blob "$object_id" 2>/dev/null | LC_ALL=C grep -Iq .
    ); then
        return 1
    fi
    return 0
}

diff_has_added_pattern() {
    local pattern="$1"

    (
        set +o pipefail
        git diff --no-ext-diff --no-renames --unified=0 "$diff_base" "$head_sha" -- \
            | head -c 1048576 \
            | LC_ALL=C grep -Eq "^\\+[^+]*($pattern)"
    )
}

printf '%s\n' \
    "Advisory security-sensitive change report" \
    "Comparison: $diff_base..$head_sha"

while IFS= read -r -d '' metadata; do
    if ! IFS= read -r -d '' path; then
        printf '%s\n' "ERROR: Malformed raw Git diff." >&2
        exit 1
    fi

    metadata=${metadata#:}
    read -r old_mode new_mode old_object new_object change_status <<< "$metadata"
    [[ -n "$path" ]] || continue

    case "$path" in
        .github/workflows/*)
            report_path "workflow" "$change_status" "$path"
            ;;
        AGENTS.md|AGENTS.override.md|.agents/*|.github/copilot-instructions.md|docs/runbooks/agent-session.md|docs/style/agent-harness.md)
            report_path "instructions" "$change_status" "$path"
            ;;
        docs/exec-plans/*)
            report_path "plan-state" "$change_status" "$path"
            ;;
        .github/pull_request_template.md|SECURITY.md|docs/TRUST.md|CONTRIBUTING.md)
            report_path "review-or-security-policy" "$change_status" "$path"
            ;;
        .githooks/*|tools/install_git_hooks.sh)
            report_path "hook" "$change_status" "$path"
            ;;
        dist/*)
            report_path "binary/provenance" "$change_status" "$path"
            ;;
        packaging/*|*SOURCE_PROVENANCE*|*source-provenance*|*.sha256)
            report_path "provenance" "$change_status" "$path"
            ;;
        tools/validate_harness.sh|tools/test_github_security.sh|tools/ci_changed_paths.sh|tools/ci_requires_macos.sh|tools/report_sensitive_changes.sh)
            report_path "security-check" "$change_status" "$path"
            ;;
        tools/build_release_bundle.sh|tools/extract_release_notes.sh|.github/dependabot.yml)
            report_path "release" "$change_status" "$path"
            ;;
        tools/test_*|*/test_*|tests/*)
            report_path "test" "$change_status" "$path"
            ;;
        fix_worms_wmd.sh|install.sh|*.command|scripts/*|tools/*|src/*)
            report_path "executable-source" "$change_status" "$path"
            ;;
    esac

    if [[ "$old_mode" != 000000 && "$new_mode" != 000000 && "$old_mode" != "$new_mode" ]]; then
        report_path "mode" "$change_status:$old_mode->$new_mode" "$path"
    fi
    if [[ "$old_mode" == 120000 || "$new_mode" == 120000 ]]; then
        report_path "symlink" "$change_status" "$path"
    fi
    if [[ "$old_mode" == 100755 || "$new_mode" == 100755 ]]; then
        report_path "executable" "$change_status" "$path"
    fi
    if [[ "$change_status" == D ]] && [[ "$path" == tools/test_* || "$path" == */test_* || "$path" == tests/* ]]; then
        report_path "test-deletion" "$change_status" "$path"
    fi

    inspect_object="$new_object"
    [[ "$change_status" == D ]] && inspect_object="$old_object"
    if blob_is_binary_or_large "$inspect_object"; then
        report_path "binary-or-large" "$change_status" "$path"
    fi
done < <(git diff --raw -z --no-renames --abbrev=40 "$diff_base" "$head_sha" --)

if diff_has_added_pattern '(shellcheck[[:space:]]+disable|nosemgrep|noqa|zizmor[^[:alnum:]]+ignore|skip[-_ ]*check|security[-_ ]*ignore)'; then
    printf '%s\n' "SENSITIVE [content] security suppression marker changed"
    findings=$((findings + 1))
fi
if diff_has_added_pattern '(curl[[:space:]]|wget[[:space:]]|fetch[[:space:](]|eval[[:space:](]|exec[[:space:](]|system\(|subprocess|os[.]system|launchctl|bash[[:space:]]+-c|sh[[:space:]]+-c)'; then
    printf '%s\n' "SENSITIVE [content] network or process execution marker changed"
    findings=$((findings + 1))
fi

if (( findings == 0 )); then
    printf '%s\n' "No security-sensitive changes detected."
else
    printf 'Review required: %d security-sensitive signal(s).\n' "$findings"
fi
