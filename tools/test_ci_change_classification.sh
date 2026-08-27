#!/bin/bash
# Regression checks for the fail-safe macOS CI change classifier.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFIER="$SCRIPT_DIR/ci_requires_macos.sh"
QT_SCAN_CLASSIFIER="$SCRIPT_DIR/ci_requires_qt_scan.sh"

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

require_qt_scan() {
    local description="$1"
    shift

    if ! printf '%s\0' "$@" | "$QT_SCAN_CLASSIFIER"; then
        fail "$description should require Qt vulnerability scanning"
    fi
}

skip_qt_scan() {
    local description="$1"
    shift

    if printf '%s\0' "$@" | "$QT_SCAN_CLASSIFIER"; then
        fail "$description should skip Qt vulnerability scanning"
    fi
}

[[ -x "$CLASSIFIER" ]] || fail "tools/ci_requires_macos.sh is required and must be executable"
[[ -x "$QT_SCAN_CLASSIFIER" ]] \
    || fail "tools/ci_requires_qt_scan.sh is required and must be executable"

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

require_qt_scan "empty or unreadable diff" ""
require_qt_scan "Qt dist" "dist/qt-frameworks-x86_64-5.15.19.tar.gz"
require_qt_scan "component policy" "packaging/qt-component-policy.tsv"
require_qt_scan "VEX policy" "packaging/qt-vex.tsv"
require_qt_scan "SBOM generator" "tools/generate_sbom.py"
require_qt_scan "scanner" "tools/scan_qt_sbom.sh"
require_qt_scan "security workflow" ".github/workflows/github-security.yml"
skip_qt_scan "unrelated docs" "README.md" "docs/INSTALL.md"
skip_qt_scan "runtime source" "fix_worms_wmd.sh" "scripts/05_verify_installation.sh"

printf '%s\n' "CI change classification check passed."
