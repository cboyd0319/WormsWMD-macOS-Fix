#!/bin/bash
#
# validate_harness.sh - verify repo-local agent harness docs and links
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DOC_INDEX="$ROOT_DIR/docs/README.md"

failures=0

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    failures=$((failures + 1))
}

require_file() {
    local rel="$1"
    if [[ ! -f "$ROOT_DIR/$rel" ]]; then
        fail "Missing required file: $rel"
    fi
}

normalize_existing_path() {
    local path="$1"
    local dir
    local base

    dir=$(cd "$(dirname "$path")" && pwd -P)
    base=$(basename "$path")
    printf '%s/%s\n' "$dir" "$base"
}

path_is_inside_repo() {
    local path="$1"
    local abs_path

    abs_path=$(normalize_existing_path "$path")
    case "$abs_path" in
        "$ROOT_DIR"|"$ROOT_DIR"/*)
            return 0
            ;;
    esac

    return 1
}

is_external_link() {
    local target="$1"

    case "$target" in
        http://*|https://*|mailto:*|tel:*)
            return 0
            ;;
    esac

    return 1
}

strip_link_target() {
    local token="$1"
    local target

    target="${token#*\(}"
    target="${target%\)}"
    target="${target%%#*}"
    printf '%s\n' "$target"
}

check_local_links() {
    local source="$1"
    local source_abs="$ROOT_DIR/$source"
    local source_dir
    local token
    local target
    local target_path

    source_dir=$(dirname "$source_abs")

    while IFS= read -r token; do
        target=$(strip_link_target "$token")

        if [[ -z "$target" ]] || [[ "$target" == \#* ]] || is_external_link "$target"; then
            continue
        fi

        if [[ "$target" == /* ]]; then
            fail "$source uses an absolute local link: $target"
            continue
        fi

        target_path="$source_dir/$target"
        if [[ ! -e "$target_path" ]]; then
            fail "$source has a broken local link: $target"
        elif ! path_is_inside_repo "$target_path"; then
            fail "$source has a local link outside the repository: $target"
        fi
    done < <(grep -Eo '\[[^]]+\]\([^)]+\)' "$source_abs" || true)
}

collect_index_targets() {
    local output_file="$1"
    local token
    local target
    local target_path
    local abs_target

    : > "$output_file"

    while IFS= read -r token; do
        target=$(strip_link_target "$token")

        if [[ -z "$target" ]] || [[ "$target" == \#* ]] || is_external_link "$target"; then
            continue
        fi

        if [[ "$target" == /* ]]; then
            continue
        fi

        target_path="$ROOT_DIR/docs/$target"
        if [[ ! -e "$target_path" ]]; then
            continue
        fi

        abs_target=$(normalize_existing_path "$target_path")
        case "$abs_target" in
            "$ROOT_DIR"/*)
                printf '%s\n' "${abs_target#"$ROOT_DIR"/}" >> "$output_file"
                ;;
        esac
    done < <(grep -Eo '\[[^]]+\]\([^)]+\)' "$DOC_INDEX" || true)

    sort -u -o "$output_file" "$output_file"
}

check_exec_plan_index_statuses() {
    local plan_file
    local plan_name
    local status
    local expected
    local index_line
    local lower_line

    for plan_file in "$ROOT_DIR"/docs/exec-plans/*.md; do
        plan_name=$(basename "$plan_file")
        case "$plan_name" in
            README.md|TEMPLATE.md)
                continue
                ;;
        esac

        status=$(awk -F': *' '/^Status: / {print $2; exit}' "$plan_file")
        if [[ -z "$status" ]]; then
            fail "Execution plan is missing Status: docs/exec-plans/$plan_name"
            continue
        fi

        case "$status" in
            Active)
                expected="active"
                ;;
            Completed)
                expected="completed"
                ;;
            Superseded)
                expected="superseded"
                ;;
            *)
                fail "Execution plan has unknown Status '$status': docs/exec-plans/$plan_name"
                continue
                ;;
        esac

        index_line=$(grep -F "($plan_name)" "$ROOT_DIR/docs/exec-plans/README.md" || true)
        if [[ -z "$index_line" ]]; then
            fail "docs/exec-plans/README.md does not link execution plan: $plan_name"
            continue
        fi

        lower_line=$(printf '%s\n' "$index_line" | tr '[:upper:]' '[:lower:]')
        if ! printf '%s\n' "$lower_line" | grep -Fq "$expected"; then
            fail "docs/exec-plans/README.md status for $plan_name must say $expected"
        fi
    done
}

require_file "AGENTS.md"
require_file ".github/copilot-instructions.md"
require_file "docs/README.md"
require_file "docs/design/runtime-contracts.md"
require_file "docs/runbooks/agent-session.md"
require_file "docs/style/agent-harness.md"
require_file "docs/exec-plans/README.md"
require_file "docs/exec-plans/TEMPLATE.md"

if [[ -f "$ROOT_DIR/AGENTS.md" ]]; then
    agent_lines=$(wc -l < "$ROOT_DIR/AGENTS.md" | tr -d ' ')
    if (( agent_lines > 180 )); then
        fail "AGENTS.md is too long for an entrypoint: $agent_lines lines"
    fi
fi

for section in \
    "## Problem" \
    "## Scope and non-goals" \
    "## Constraints and risks" \
    "## Milestones" \
    "## Verification" \
    "## Progress" \
    "## Surprises & Discoveries" \
    "## Decision Log" \
    "## Outcomes & Retrospective"; do
    if ! grep -Fq "$section" "$ROOT_DIR/docs/exec-plans/TEMPLATE.md"; then
        fail "Execution plan template is missing section: $section"
    fi
done

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-harness.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

markdown_files="$tmp_dir/markdown-files.txt"
index_targets="$tmp_dir/index-targets.txt"

(
    cd "$ROOT_DIR"
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git ls-files --cached --others --exclude-standard '*.md' | sort
    else
        find . \
            \( -path ./.git -o -path ./build \) -prune -o \
            -name '*.md' -type f -print \
            | sed 's#^\./##' \
            | sort
    fi
) > "$markdown_files"

while IFS= read -r source; do
    check_local_links "$source"
done < "$markdown_files"

collect_index_targets "$index_targets"

while IFS= read -r doc; do
    if [[ "$doc" == "docs/README.md" ]]; then
        continue
    fi

    if ! grep -Fxq "$doc" "$index_targets"; then
        fail "docs/README.md does not link tracked Markdown file: $doc"
    fi
done < "$markdown_files"

check_exec_plan_index_statuses

if (( failures > 0 )); then
    printf 'Harness validation failed with %d issue(s).\n' "$failures" >&2
    exit 1
fi

printf 'Harness validation passed.\n'
