#!/bin/bash
# Regression checks for the fail-safe macOS CI change classifier.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFIER="$SCRIPT_DIR/ci_requires_macos.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

require_macos() {
    local description="$1"
    shift

    if ! printf '%s\0' "$@" | "$CLASSIFIER"; then
        fail "$description should require macOS validation"
    fi
}

skip_macos() {
    local description="$1"
    shift

    if printf '%s\0' "$@" | "$CLASSIFIER"; then
        fail "$description should use the cheap CI path"
    fi
}

[[ -x "$CLASSIFIER" ]] || fail "tools/ci_requires_macos.sh is required and must be executable"

require_macos "empty or unreadable diff" ""
require_macos "main installer" "fix_worms_wmd.sh"
require_macos "friendly launcher" "Worms W.M.D Fix.command"
require_macos "runtime script" "scripts/05_verify_installation.sh"
require_macos "tooling" "tools/build_release_bundle.sh"
require_macos "native source" "src/agl_stub.c"
require_macos "runtime payload" "dist/qt-frameworks-x86_64-5.15.19.tar.gz"
require_macos "CI workflow" ".github/workflows/ci.yml"
require_macos "release workflow" ".github/workflows/release.yml"
require_macos "unknown root artifact" "unexpected.bin"

skip_macos "documentation" "README.md" "docs/TRUST.md" "CHANGELOG.md"
skip_macos "community metadata" ".github/ISSUE_TEMPLATE/config.yml" ".github/pull_request_template.md"
skip_macos "dependency automation" ".github/dependabot.yml"
skip_macos "agent guidance" "AGENTS.md" ".agents/rules/wormswmd-maintenance.md"

printf '%s\n' "CI change classification check passed."
