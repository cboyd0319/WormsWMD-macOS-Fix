#!/bin/bash
# Regression checks for repository-local GitHub security policy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FAILURES=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
}

check_workflow() {
    local workflow="$1"
    local name="${workflow#"$ROOT_DIR"/}"
    local jobs
    local job_permissions
    local checkouts
    local non_persistent_checkouts
    local runners
    local timeouts
    local line
    local action_ref
    local ref_part

    if ! grep -Eq '^permissions:[[:space:]]*\{\}[[:space:]]*$' "$workflow"; then
        fail "$name must deny workflow permissions by default"
    fi
    if ! grep -Eq '^concurrency:[[:space:]]*$' "$workflow"; then
        fail "$name must define workflow concurrency"
    fi
    if ! grep -Eq '^[[:space:]]+cancel-in-progress:[[:space:]]+(true|false)[[:space:]]*$' "$workflow"; then
        fail "$name must state whether superseded runs are cancelled"
    fi
    if grep -Eq '^[[:space:]]{2}(pull_request_target|workflow_run|issue_comment):' "$workflow"; then
        fail "$name uses a privileged or comment-driven trigger"
    fi
    if grep -Eq '^[[:space:]]+run:.*\$\{\{' "$workflow"; then
        fail "$name expands a GitHub expression directly in a run command"
    fi

    jobs=$(grep -Ec '^[[:space:]]+runs-on:' "$workflow" || true)
    job_permissions=$(grep -Ec '^[[:space:]]+permissions:' "$workflow" || true)
    timeouts=$(grep -Ec '^[[:space:]]+timeout-minutes:' "$workflow" || true)
    if [[ "$jobs" -eq 0 ]]; then
        fail "$name does not define a job"
    fi
    if [[ "$job_permissions" -ne "$jobs" ]]; then
        fail "$name must grant permissions separately for every job"
    fi
    if [[ "$timeouts" -ne "$jobs" ]]; then
        fail "$name must bound every job with timeout-minutes"
    fi

    checkouts=$(grep -Ec '^[[:space:]]+uses:[[:space:]]+actions/checkout@' "$workflow" || true)
    non_persistent_checkouts=$(grep -Ec '^[[:space:]]+persist-credentials:[[:space:]]+false[[:space:]]*$' "$workflow" || true)
    if [[ "$checkouts" -ne "$non_persistent_checkouts" ]]; then
        fail "$name must disable credential persistence for every checkout"
    fi

    runners=$(grep -E '^[[:space:]]+runs-on:' "$workflow" || true)
    if grep -q -- '-latest' <<< "$runners"; then
        fail "$name uses a mutable runner label"
    fi

    while IFS= read -r line; do
        action_ref=${line#*uses:}
        action_ref=${action_ref%%#*}
        action_ref=${action_ref//[[:space:]\"\']/}
        [[ -n "$action_ref" ]] || continue
        case "$action_ref" in
            ./*|../*|docker://*)
                continue
                ;;
        esac
        ref_part=${action_ref##*@}
        if [[ "$action_ref" != *@* ]] || [[ ! "$ref_part" =~ ^[0-9a-f]{40}$ ]]; then
            fail "$name uses a remote action without an immutable full SHA: $action_ref"
        fi
    done < <(grep -E '^[[:space:]]+uses:' "$workflow" || true)
}

for workflow in "$ROOT_DIR"/.github/workflows/*.yml "$ROOT_DIR"/.github/workflows/*.yaml; do
    [[ -f "$workflow" ]] || continue
    check_workflow "$workflow"
done

if grep -R -Eq '\$\{\{[[:space:]]*secrets[.]|secrets:[[:space:]]*inherit' \
    "$ROOT_DIR/.github/workflows"; then
    fail "workflows must not consume static repository secrets or inherit secret sets"
fi

if [[ ! -f "$ROOT_DIR/.github/workflows/github-security.yml" ]]; then
    fail ".github/workflows/github-security.yml is required"
else
    if ! grep -Fq 'zizmorcore/zizmor-action@3dc1ecc9bcb9e94e9b2c709687979e1298497054' \
        "$ROOT_DIR/.github/workflows/github-security.yml"; then
        fail "GitHub security workflow must pin zizmor-action v0.6.2"
    fi
    if ! grep -Eq '^[[:space:]]+version:[[:space:]]+[v]?[0-9]+[.][0-9]+[.][0-9]+[[:space:]]*$' \
        "$ROOT_DIR/.github/workflows/github-security.yml"; then
        fail "GitHub security workflow must pin the zizmor binary version"
    fi
    for marker in \
        'KINGFISHER_VERSION: 2.0.0' \
        'KINGFISHER_SHA256: d30d71f82e25e8c024f98cce3258c90e17b5be31d0fdb6f30b438d2fac1f130b' \
        '--git-history none' \
        "--exclude '**/.git/**'" \
        '--no-validate' \
        '--redact'; do
        if ! grep -Fq -- "$marker" "$ROOT_DIR/.github/workflows/github-security.yml"; then
            fail "GitHub security workflow is missing Kingfisher marker: $marker"
        fi
    done
fi

if ! grep -Eq '^[[:space:]]+default-days:[[:space:]]+7[[:space:]]*$' \
    "$ROOT_DIR/.github/dependabot.yml"; then
    fail "Dependabot GitHub Actions updates require a seven-day cooldown"
fi

if [[ ! -f "$ROOT_DIR/.github/pull_request_template.md" ]]; then
    fail ".github/pull_request_template.md is required"
fi

for required_file in \
    "$ROOT_DIR/.githooks/pre-commit" \
    "$ROOT_DIR/tools/ci_changed_paths.sh" \
    "$ROOT_DIR/tools/ci_requires_macos.sh" \
    "$ROOT_DIR/tools/generate_sbom.py" \
    "$ROOT_DIR/tools/install_git_hooks.sh" \
    "$ROOT_DIR/tools/report_sensitive_changes.sh" \
    "$ROOT_DIR/tools/test_ci_changed_paths.sh" \
    "$ROOT_DIR/tools/test_ci_change_classification.sh" \
    "$ROOT_DIR/tools/test_generate_sbom.py" \
    "$ROOT_DIR/tools/test_git_hooks.sh" \
    "$ROOT_DIR/tools/test_harness_security.sh" \
    "$ROOT_DIR/tools/test_sensitive_change_report.sh"; do
    if [[ ! -f "$required_file" ]]; then
        fail "required GitHub security file is missing: ${required_file#"$ROOT_DIR"/}"
    fi
done

ci_workflow="$ROOT_DIR/.github/workflows/ci.yml"
# These are literal workflow source markers, not shell expressions.
# shellcheck disable=SC2016
for marker in \
    'needs: shellcheck' \
    "if: needs.shellcheck.outputs.macos-required == 'true'" \
    './tools/ci_changed_paths.sh' \
    './tools/ci_requires_macos.sh' \
    './tools/report_sensitive_changes.sh' \
    './tools/test_harness_security.sh' \
    './tools/test_sensitive_change_report.sh' \
    'name: Compile AGL stub'; do
    if ! grep -Fq "$marker" "$ci_workflow"; then
        fail "CI workflow is missing cost-control marker: $marker"
    fi
done
if grep -Fq 'name: Validate C Code' "$ci_workflow"; then
    fail "CI workflow must not start a separate macOS C validation job"
fi
if ! grep -Fq '/security/advisories/new' "$ROOT_DIR/.github/ISSUE_TEMPLATE/config.yml"; then
    fail "issue chooser must route vulnerability reports to private advisories"
fi

release_workflow="$ROOT_DIR/.github/workflows/release.yml"
# These are literal workflow source markers, not shell expressions.
# shellcheck disable=SC2016
for marker in \
    'retention-days: 14' \
    'python3 tools/generate_sbom.py' \
    '--archive "dist/qt-frameworks-x86_64-5.15.19.tar.gz"' \
    '--release-archive "build/release/WormsWMD-macOS-Fix-${RELEASE_VERSION}.zip"' \
    '--release-checksum "build/release/WormsWMD-macOS-Fix-${RELEASE_VERSION}.zip.sha256"' \
    'sbom-path: build/release/WormsWMD-macOS-Fix-*.cdx.json' \
    'build/release/*.cdx.json' \
    'gh release create "$GITHUB_REF_NAME" --draft' \
    'gh release edit "$GITHUB_REF_NAME" --draft=false' \
    'Refusing to overwrite published release'; do
    if ! grep -Fq -- "$marker" "$release_workflow"; then
        fail "release workflow is missing safe publication marker: $marker"
    fi
done

if [[ ! -x "$ROOT_DIR/tools/extract_release_notes.sh" ]]; then
    fail "tools/extract_release_notes.sh is required and must be executable"
else
    release_notes=$("$ROOT_DIR/tools/extract_release_notes.sh" 1.7.6 2>/dev/null || true)
    if [[ "$release_notes" != '## 1.7.6 '* ]]; then
        fail "release notes helper did not extract the v1.7.6 changelog section"
    fi
    if grep -Fq '## Mainline maintenance after 1.7.5' <<< "$release_notes"; then
        fail "release notes helper included the next changelog section"
    fi
    if "$ROOT_DIR/tools/extract_release_notes.sh" '../1.7.6' >/dev/null 2>&1; then
        fail "release notes helper accepted an unsafe version"
    fi
    if "$ROOT_DIR/tools/extract_release_notes.sh" '0.0.0' >/dev/null 2>&1; then
        fail "release notes helper accepted a missing version"
    fi
fi

if [[ "$FAILURES" -ne 0 ]]; then
    printf '%s\n' "GitHub security regression check failed with $FAILURES finding(s)." >&2
    exit 1
fi

printf '%s\n' "GitHub security regression check passed."
