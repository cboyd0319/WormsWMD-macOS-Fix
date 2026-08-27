#!/bin/bash
# Regression checks for harness source-file and plan-status safety.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VALIDATOR="$ROOT_DIR/tools/validate_harness.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -x "$VALIDATOR" ]] || fail "tools/validate_harness.sh is required and must be executable"

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-harness-security.XXXXXX")
validator_pid=""
cleanup() {
    if [[ -n "$validator_pid" ]] && kill -0 "$validator_pid" 2>/dev/null; then
        kill "$validator_pid" 2>/dev/null || true
        wait "$validator_pid" 2>/dev/null || true
    fi
    rm -rf "$test_dir"
}
trap cleanup EXIT

new_fixture() {
    local fixture="$1"
    local rel

    git clone -q --no-hardlinks "$ROOT_DIR" "$fixture"
    rm -rf "$fixture/.git"

    for rel in \
        AGENTS.md \
        .agents/rules/wormswmd-maintenance.md \
        .github/copilot-instructions.md \
        .github/CODEOWNERS \
        .github/pull_request_template.md \
        .github/workflows/ci.yml \
        docs/README.md \
        docs/exec-plans/README.md \
        docs/exec-plans/2026-08-27-security-remediation-pr1-harness-hooks.md \
        docs/exec-plans/2026-08-27-security-remediation-pr2-archive-bottle-safety.md \
        docs/runbooks/agent-session.md \
        docs/style/agent-harness.md \
        packaging/qt-homebrew-lock.tsv \
        .githooks/pre-commit \
        tools/install_git_hooks.sh \
        tools/inspect_archive.py \
        tools/report_sensitive_changes.sh \
        tools/test_archive_inspector.py \
        tools/test_fetch_qt_homebrew_bottles.rb \
        tools/test_github_security.sh \
        tools/test_harness_security.sh \
        tools/test_sensitive_change_report.sh \
        tools/validate_harness.sh; do
        if [[ -e "$ROOT_DIR/$rel" ]]; then
            mkdir -p "$fixture/$(dirname "$rel")"
            cp -p "$ROOT_DIR/$rel" "$fixture/$rel"
        fi
    done

    git -C "$fixture" init -q -b main
    git -C "$fixture" config user.name "Harness security test"
    git -C "$fixture" config user.email "harness-security@example.invalid"
    git -C "$fixture" add .
    git -C "$fixture" commit -qm "fixture"
}

run_validator_bounded() {
    local fixture="$1"
    local output="$2"
    local path_prefix="${3:-}"
    local waited=0

    (
        cd "$fixture"
        if [[ -n "$path_prefix" ]]; then
            PATH="$path_prefix:$PATH" ./tools/validate_harness.sh
        else
            ./tools/validate_harness.sh
        fi
    ) >"$output" 2>&1 &
    validator_pid=$!

    while kill -0 "$validator_pid" 2>/dev/null; do
        if (( waited >= 100 )); then
            kill "$validator_pid" 2>/dev/null || true
            wait "$validator_pid" 2>/dev/null || true
            validator_pid=""
            return 124
        fi
        sleep 0.1
        waited=$((waited + 1))
    done

    if wait "$validator_pid"; then
        status=0
    else
        status=$?
    fi
    validator_pid=""
    return "$status"
}

external_file="$test_dir/external.md"
printf '%s\n' '[outside](EXTERNAL_LINK_MARKER.md)' > "$external_file"

fixture="$test_dir/baseline"
new_fixture "$fixture"
set +e
run_validator_bounded "$fixture" "$test_dir/baseline.out"
status=$?
set -e
if [[ "$status" -ne 0 ]]; then
    cat "$test_dir/baseline.out" >&2
    fail "baseline harness fixture did not validate"
fi

gnu_stat_bin="$test_dir/gnu-stat-bin"
mkdir -p "$gnu_stat_bin"
cat > "$gnu_stat_bin/stat" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-f" ]]; then
    printf '%s\n' "simulated GNU filesystem stat output"
    exit 0
fi
if [[ "$(/usr/bin/uname -s)" == "Darwin" && "${1:-}" == "-c" ]]; then
    case "${2:-}" in
        %h) exec /usr/bin/stat -f %l "$3" ;;
        %s) exec /usr/bin/stat -f %z "$3" ;;
    esac
fi
exec /usr/bin/stat "$@"
STUB
chmod +x "$gnu_stat_bin/stat"
set +e
run_validator_bounded "$fixture" "$test_dir/gnu-stat.out" "$gnu_stat_bin"
status=$?
set -e
if [[ "$status" -ne 0 ]]; then
    cat "$test_dir/gnu-stat.out" >&2
    fail "harness validator rejected GNU stat output fallback"
fi

fixture="$test_dir/unsafe-sources"
new_fixture "$fixture"
ln -s "$external_file" "$fixture/untracked-leak.md"
ln -s "$external_file" "$fixture/tracked-leak.md"
git -C "$fixture" add tracked-leak.md
ln -s "$test_dir/missing.md" "$fixture/dangling.md"
ln "$external_file" "$fixture/hardlinked.md"
mkfifo "$fixture/fifo.md"
unsafe_name=$'unsafe\nINJECTED_FILENAME.md'
printf '%s\n' 'safe text' > "$fixture/$unsafe_name"
printf '%s\n' $'[unsafe](bad\tINJECTED_LINK_TARGET.md)' > "$fixture/injected-link.md"
set +e
run_validator_bounded "$fixture" "$test_dir/unsafe-sources.out"
status=$?
set -e
[[ "$status" -ne 124 ]] || fail "harness validator hung while inspecting an unsafe source"
[[ "$status" -ne 0 ]] || fail "harness validator accepted unsafe repository sources"
for marker in EXTERNAL_LINK_MARKER INJECTED_FILENAME INJECTED_LINK_TARGET; do
    if grep -Fq "$marker" "$test_dir/unsafe-sources.out"; then
        fail "harness validator disclosed unsafe source content: $marker"
    fi
done
unsafe_count=$(grep -c 'Unsafe repository source' "$test_dir/unsafe-sources.out" || true)
[[ "$unsafe_count" -ge 6 ]] \
    || fail "harness validator did not report every unsafe source class"
grep -Fq 'Markdown link target containing a control character' "$test_dir/unsafe-sources.out" \
    || fail "harness validator did not reject a control-character link target"

fixture="$test_dir/status-duplication"
new_fixture "$fixture"
python3 - "$fixture/docs/README.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    "- [Security remediation PR 1 plan](exec-plans/2026-08-27-security-remediation-pr1-harness-hooks.md)\n"
    "  - harness and hook trust implementation record.",
    "- [Security remediation PR 1 plan](exec-plans/2026-08-27-security-remediation-pr1-harness-hooks.md)\n"
    "  - active harness and hook trust implementation record.",
)
path.write_text(text, encoding="utf-8")
PY
set +e
run_validator_bounded "$fixture" "$test_dir/status-duplication.out"
status=$?
set -e
[[ "$status" -ne 0 && "$status" -ne 124 ]] \
    || fail "harness validator accepted duplicated execution-plan status prose"
grep -Fq 'must not duplicate execution plan status' "$test_dir/status-duplication.out" \
    || fail "harness validator did not explain duplicated plan status"

printf '%s\n' "Harness security regression check passed."
