#!/bin/bash
#
# validate_harness.sh - verify repo-local agent harness docs, links, and path hygiene
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DOC_INDEX="$ROOT_DIR/docs/README.md"
SAFE_REPO_FILES=""

failures=0

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    failures=$((failures + 1))
}

require_file() {
    local rel="$1"
    if [[ -z "$SAFE_REPO_FILES" ]] || ! grep -Fxq "$rel" "$SAFE_REPO_FILES"; then
        fail "Missing or unsafe required file: $rel"
    fi
}

require_marker() {
    local rel="$1"
    local marker="$2"

    if [[ ! -f "$ROOT_DIR/$rel" ]]; then
        return
    fi
    if ! grep -Fq "$marker" "$ROOT_DIR/$rel"; then
        fail "$rel is missing required marker: $marker"
    fi
}

check_line_cap() {
    local rel="$1"
    local max_lines="$2"
    local line_count

    if [[ ! -f "$ROOT_DIR/$rel" ]]; then
        return
    fi

    line_count=$(wc -l < "$ROOT_DIR/$rel" | tr -d ' ')
    if (( line_count > max_lines )); then
        fail "$rel exceeds harness line cap: $line_count lines, max $max_lines"
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

repo_path_has_control_chars() {
    [[ "$1" =~ [[:cntrl:]] ]]
}

repo_file_link_count() {
    local path="$1"
    local count

    count=$(stat -f "%l" "$path" 2>/dev/null || stat -c "%h" "$path" 2>/dev/null || echo 0)
    printf '%s\n' "$count"
}

repo_file_size() {
    local path="$1"

    stat -f "%z" "$path" 2>/dev/null || stat -c "%s" "$path" 2>/dev/null || echo 0
}

validate_repo_source() {
    local rel="$1"
    local tracked_mode="${2:-}"
    local source_abs="$ROOT_DIR/$rel"
    local link_count

    if repo_path_has_control_chars "$rel"; then
        fail "Unsafe repository source: path contains a control character"
        return 1
    fi
    if (( ${#rel} > 4096 )); then
        fail "Unsafe repository source: path exceeds 4096 bytes"
        return 1
    fi
    case "$rel" in
        /*|../*|*/../*|*/..)
            fail "Unsafe repository source: $rel (noncanonical path)"
            return 1
            ;;
    esac
    case "$tracked_mode" in
        ""|100644|100755)
            ;;
        120000)
            fail "Unsafe repository source: $rel (symlink)"
            return 1
            ;;
        *)
            fail "Unsafe repository source: $rel (unsupported Git mode $tracked_mode)"
            return 1
            ;;
    esac
    if [[ -L "$source_abs" ]]; then
        fail "Unsafe repository source: $rel (symlink)"
        return 1
    fi
    if [[ ! -f "$source_abs" ]]; then
        fail "Unsafe repository source: $rel (not a regular file)"
        return 1
    fi
    if ! path_is_inside_repo "$source_abs"; then
        fail "Unsafe repository source: $rel (outside repository)"
        return 1
    fi
    link_count=$(repo_file_link_count "$source_abs")
    if [[ ! "$link_count" =~ ^[0-9]+$ ]] || (( link_count != 1 )); then
        fail "Unsafe repository source: $rel (link count $link_count)"
        return 1
    fi

    printf '%s\n' "$rel"
}

collect_safe_repo_files() {
    local record
    local metadata
    local mode
    local rel
    local untracked_count=0

    if command -v git >/dev/null 2>&1 \
        && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        while IFS= read -r -d '' record; do
            metadata=${record%%$'\t'*}
            rel=${record#*$'\t'}
            mode=${metadata%% *}
            validate_repo_source "$rel" "$mode" || true
        done < <(git -C "$ROOT_DIR" ls-files -s -z)

        while IFS= read -r -d '' rel; do
            untracked_count=$((untracked_count + 1))
            if (( untracked_count > 1000 )); then
                fail "Unsafe repository source inventory: more than 1000 untracked files"
                break
            fi
            validate_repo_source "$rel" || true
        done < <(git -C "$ROOT_DIR" ls-files --others --exclude-standard -z)

        while IFS= read -r -d '' rel; do
            rel=${rel#"$ROOT_DIR"/}
            if git -C "$ROOT_DIR" check-ignore -q -- "$rel" 2>/dev/null; then
                continue
            fi
            untracked_count=$((untracked_count + 1))
            if (( untracked_count > 1000 )); then
                fail "Unsafe repository source inventory: more than 1000 untracked files"
                break
            fi
            validate_repo_source "$rel" || true
        done < <(
            find "$ROOT_DIR" \
                \( -path "$ROOT_DIR/.git" -o -path "$ROOT_DIR/build" \) -prune -o \
                ! -type d ! -type f ! -type l -print0
        )
    else
        while IFS= read -r -d '' rel; do
            rel=${rel#./}
            validate_repo_source "$rel" || true
        done < <(
            cd "$ROOT_DIR"
            find . \
                \( -path ./.git -o -path ./build \) -prune -o \
                ! -type d -print0
        )
    fi
}

path_is_inside_repo() {
    local path="$1"
    local abs_path

    abs_path=$(realpath "$path" 2>/dev/null || normalize_existing_path "$path")
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
        if repo_path_has_control_chars "$target"; then
            fail "$source has a Markdown link target containing a control character"
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
        if repo_path_has_control_chars "$target"; then
            fail "docs/README.md has a link target containing a control character"
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

collect_repo_text_files() {
    local source
    local size

    while IFS= read -r source; do
        case "$source" in
            build/*|dist/*.tar|dist/*.tar.gz|dist/*.tgz|dist/*.zip|*.bmp|*.dmg|*.gif|*.icns|*.ico|*.jpg|*.jpeg|*.pdf|*.png|*.tiff|*.webp)
                continue
                ;;
        esac

        size=$(repo_file_size "$ROOT_DIR/$source")
        if [[ "$size" =~ ^[0-9]+$ ]] && (( size > 5242880 )); then
            fail "Unsafe repository source: $source (text read exceeds 5 MiB)"
            continue
        fi
        if LC_ALL=C grep -Iq . "$ROOT_DIR/$source"; then
            printf '%s\n' "$source"
        fi
    done < "$SAFE_REPO_FILES"
}

check_general_doc_plan_statuses() {
    local duplicated

    duplicated=$(awk '
        /^## / { plan = 0 }
        /^- \[/ { plan = ($0 ~ /\(exec-plans\//) }
        plan { print }
    ' "$DOC_INDEX" | LC_ALL=C grep -Ei '(^|[^[:alpha:]])(active|completed|superseded|shipped)([^[:alpha:]]|$)' || true)

    if [[ -n "$duplicated" ]]; then
        fail "docs/README.md execution-plan entries must not duplicate execution plan status"
    fi
}

check_no_local_machine_paths() {
    local source="$1"
    local source_abs="$ROOT_DIR/$source"
    local slash="/"
    local users_root="${slash}Users${slash}"
    local home_root="${slash}home${slash}"
    local var_folders="${slash}var${slash}folders${slash}"
    local volumes_root="${slash}Volumes${slash}"
    local forbidden_pattern
    local hit
    local line_number
    local line_text

    forbidden_pattern="(${users_root}[A-Za-z0-9._-]+${slash}|${home_root}[A-Za-z0-9._-]+${slash}|${var_folders}|${volumes_root}[A-Za-z0-9._-]+${slash}|[A-Za-z]:\\\\Users\\\\|~${slash}Documents${slash}GitHub(${slash}|$)|~${slash}\\.codex(${slash}|$))"

    while IFS= read -r hit; do
        line_number=${hit%%:*}
        line_text=${hit#*:}
        case "$line_text" in
            *"/Users/example/"*|*"/Users/you/"*|*"/Users/privateperson/"*)
                continue
                ;;
        esac
        fail "$source:$line_number contains a local machine path; use a repo-relative path or HOME-based placeholder"
    done < <(LC_ALL=C grep -nE "$forbidden_pattern" "$source_abs" || true)
}

check_harness_markers() {
    require_marker "AGENTS.md" "## Project Shape"
    require_marker "AGENTS.md" "## Non-Negotiables"
    require_marker "AGENTS.md" "## Untrusted Content Boundary"
    require_marker "AGENTS.md" "## Startup Path"
    require_marker "AGENTS.md" "## Common Commands"
    require_marker "AGENTS.md" "## Documentation Entrypoints"
    require_marker "AGENTS.md" "## Completion Checklist"

    require_marker ".agents/README.md" "## Inventory"
    require_marker ".agents/CLAUDE.md" "AGENTS.md"
    require_marker ".agents/rules/wormswmd-maintenance.md" "security-critical"
    require_marker ".agents/rules/wormswmd-maintenance.md" "local-path"
    require_marker ".agents/rules/wormswmd-maintenance.md" "Untrusted Content Boundary"
    require_marker ".github/copilot-instructions.md" "Untrusted Content Boundary"

    require_marker "docs/style/agent-harness.md" "## Five Subsystems"
    require_marker "docs/style/agent-harness.md" "## Harness Change Rules"
    require_marker "docs/style/agent-harness.md" "## Clean-State Checklist"
    require_marker "docs/runbooks/agent-session.md" "## Start A Session"
    require_marker "docs/runbooks/agent-session.md" "### External contributor review"
    require_marker "docs/runbooks/agent-session.md" "## Choose Validation"
    require_marker "docs/runbooks/agent-session.md" "## Clean-State Checklist"
    require_marker "docs/design/runtime-contracts.md" "## Validation Contract"
}

check_harness_line_caps() {
    check_line_cap "AGENTS.md" 180
    check_line_cap ".agents/README.md" 180
    check_line_cap ".agents/CLAUDE.md" 120
    check_line_cap ".agents/rules/wormswmd-maintenance.md" 120
    check_line_cap ".github/copilot-instructions.md" 80
    check_line_cap "docs/style/agent-harness.md" 260
    check_line_cap "docs/runbooks/agent-session.md" 220
    check_line_cap "docs/design/runtime-contracts.md" 260
    check_line_cap "docs/exec-plans/TEMPLATE.md" 120
    check_line_cap "docs/exec-plans/README.md" 160
    check_line_cap "tools/validate_harness.sh" 680
    check_line_cap ".github/workflows/ci.yml" 180
    check_line_cap ".github/workflows/github-security.yml" 120
    check_line_cap ".github/workflows/release.yml" 140
}

check_ci_and_ownership_gates() {
    local ci_file="$ROOT_DIR/.github/workflows/ci.yml"
    local release_file="$ROOT_DIR/.github/workflows/release.yml"
    local codeowners="$ROOT_DIR/.github/CODEOWNERS"
    local required_ci_check
    local required_owner
    local workflow
    local line
    local line_number
    local action_ref
    local ref_part

    for required_ci_check in \
        "./tools/validate_harness.sh" \
        "./tools/test_harness_security.sh" \
        "./tools/test_sensitive_change_report.sh" \
        "./tools/test_github_security.sh" \
        "./tools/test_ci_changed_paths.sh" \
        "./tools/test_ci_change_classification.sh" \
        "python3 tools/test_generate_sbom.py" \
        "./tools/test_git_hooks.sh" \
        "./tools/test_bootstrap_installer_safety.sh" \
        "./tools/test_issue_10_regression.sh" \
        "./tools/test_issue_11_game_detection.sh" \
        "./tools/test_issue_12_agl_install_failure.sh" \
        "./tools/test_installer_rollback_regression.sh" \
        "./tools/test_mutation_safety.sh" \
        "./tools/test_support_bundle_sanitization.sh" \
        "./tools/test_backup_saves_regression.sh" \
        "./tools/test_launcher_friction.sh" \
        "./tools/test_preflight_regression.sh" \
        "./tools/test_manifest_regression.sh" \
        "./tools/test_qt_version_pinning.sh" \
        "./tools/build_release_bundle.sh --version ci --skip-zip"; do
        if [[ -f "$ci_file" ]] && ! grep -Fq "$required_ci_check" "$ci_file"; then
            fail ".github/workflows/ci.yml does not run required check: $required_ci_check"
        fi
    done

    if [[ -f "$release_file" ]] && ! grep -Fq "./tools/validate_harness.sh" "$release_file"; then
        fail ".github/workflows/release.yml does not validate the harness"
    fi

    for required_owner in \
        "/.agents/** @cboyd0319" \
        "/.githooks/** @cboyd0319" \
        "/.github/** @cboyd0319" \
        "/AGENTS.md @cboyd0319" \
        "/docs/exec-plans/** @cboyd0319" \
        "/docs/style/agent-harness.md @cboyd0319" \
        "/docs/runbooks/agent-session.md @cboyd0319" \
        "/docs/design/runtime-contracts.md @cboyd0319"; do
        if [[ -f "$codeowners" ]] && ! grep -Fxq "$required_owner" "$codeowners"; then
            fail ".github/CODEOWNERS is missing protected surface: $required_owner"
        fi
    done

    for workflow in "$ROOT_DIR"/.github/workflows/*.yml "$ROOT_DIR"/.github/workflows/*.yaml; do
        [[ -f "$workflow" ]] || continue
        while IFS= read -r line; do
            line_number=${line%%:*}
            runner_label=${line#*:}
            runner_label=${runner_label#*runs-on:}
            runner_label=${runner_label%%#*}
            runner_label=${runner_label//[[:space:]\"\']/}
            [[ -n "$runner_label" ]] || continue

            if [[ "$runner_label" == *-latest ]]; then
                fail "${workflow#"$ROOT_DIR"/}:$line_number uses a mutable runner label: $runner_label"
            fi
        done < <(grep -nE '^[[:space:]]*runs-on:' "$workflow" || true)

        while IFS= read -r line; do
            line_number=${line%%:*}
            action_ref=${line#*:}
            action_ref=${action_ref#*uses:}
            action_ref=${action_ref%%#*}
            action_ref=${action_ref//[[:space:]\"\']/}
            [[ -n "$action_ref" ]] || continue

            case "$action_ref" in
                ./*|../*|docker://*)
                    continue
                    ;;
            esac

            if [[ "$action_ref" != *@* ]]; then
                fail "${workflow#"$ROOT_DIR"/}:$line_number uses an action without an explicit ref: $action_ref"
                continue
            fi
            ref_part=${action_ref##*@}
            if [[ ! "$ref_part" =~ ^[0-9a-f]{40}$ ]]; then
                fail "${workflow#"$ROOT_DIR"/}:$line_number uses an action ref that is not a full commit SHA: $action_ref"
            fi
        done < <(grep -nE '^[[:space:]]*uses:' "$workflow" || true)
    done

    if [[ -f "$ci_file" ]] && grep -Fq "ludeeus/action-shellcheck@" "$ci_file"; then
        if ! grep -Eq '^[[:space:]]+version:[[:space:]]+v[0-9]+[.][0-9]+[.][0-9]+[[:space:]]*$' "$ci_file"; then
            fail ".github/workflows/ci.yml runs action-shellcheck without a pinned ShellCheck binary version"
        fi
    fi
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-harness.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

SAFE_REPO_FILES="$tmp_dir/safe-repo-files.txt"
collect_safe_repo_files > "$SAFE_REPO_FILES"
sort -u -o "$SAFE_REPO_FILES" "$SAFE_REPO_FILES"

require_file "AGENTS.md"
require_file ".agents/README.md"
require_file ".agents/CLAUDE.md"
require_file ".agents/rules/wormswmd-maintenance.md"
require_file ".githooks/pre-commit"
require_file ".github/CODEOWNERS"
require_file ".github/copilot-instructions.md"
require_file ".github/workflows/ci.yml"
require_file ".github/workflows/github-security.yml"
require_file ".github/workflows/release.yml"
require_file "docs/README.md"
require_file "docs/design/runtime-contracts.md"
require_file "docs/runbooks/agent-session.md"
require_file "docs/style/agent-harness.md"
require_file "docs/exec-plans/README.md"
require_file "docs/exec-plans/TEMPLATE.md"
require_file "tools/extract_release_notes.sh"
require_file "tools/ci_changed_paths.sh"
require_file "tools/ci_requires_macos.sh"
require_file "tools/generate_sbom.py"
require_file "tools/install_git_hooks.sh"
require_file "tools/report_sensitive_changes.sh"
require_file "tools/test_ci_changed_paths.sh"
require_file "tools/test_ci_change_classification.sh"
require_file "tools/test_generate_sbom.py"
require_file "tools/test_git_hooks.sh"
require_file "tools/test_harness_security.sh"
require_file "tools/test_sensitive_change_report.sh"
require_file "tools/test_github_security.sh"

check_harness_markers
check_harness_line_caps
check_ci_and_ownership_gates

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

markdown_files="$tmp_dir/markdown-files.txt"
index_targets="$tmp_dir/index-targets.txt"
repo_text_files="$tmp_dir/repo-text-files.txt"

: > "$markdown_files"
while IFS= read -r source; do
    case "$source" in
        *.md)
            source_size=$(repo_file_size "$ROOT_DIR/$source")
            if [[ "$source_size" =~ ^[0-9]+$ ]] && (( source_size > 1048576 )); then
                fail "Unsafe repository source: $source (Markdown read exceeds 1 MiB)"
            else
                printf '%s\n' "$source" >> "$markdown_files"
            fi
            ;;
    esac
done < "$SAFE_REPO_FILES"
sort -u -o "$markdown_files" "$markdown_files"

collect_repo_text_files > "$repo_text_files"

while IFS= read -r source; do
    check_no_local_machine_paths "$source"
done < "$repo_text_files"

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
check_general_doc_plan_statuses

if (( failures > 0 )); then
    printf 'Harness validation failed with %d issue(s).\n' "$failures" >&2
    exit 1
fi

printf 'Harness validation passed.\n'
