#!/bin/bash
# Compare Qt archives across structural, manifest, provenance, and Mach-O evidence.

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

ALLOW_VERSION_CHANGE=false
REPORT_PATH=""
WORK_DIR=""

# shellcheck disable=SC2329
cleanup() {
    if [[ -n "$WORK_DIR" ]] && [[ -d "$WORK_DIR" ]] && [[ ! -L "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage: ./tools/compare_qt_artifacts.sh LEFT.tar.gz RIGHT.tar.gz [OPTIONS]

Options:
  --allow-version-change  Permit content/hash/version drift but not structural,
                          Mach-O, mode, symlink, or provenance-name drift
  --report FILE           Atomically write JSON comparison evidence
  --help, -h              Show this help
EOF
}

[[ $# -ge 2 ]] || { usage >&2; exit 2; }
LEFT_ARCHIVE="$1"
RIGHT_ARCHIVE="$2"
shift 2
while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-version-change)
            ALLOW_VERSION_CHANGE=true
            shift
            ;;
        --report)
            [[ -n "${2:-}" ]] && [[ "$2" != -* ]] || {
                echo "ERROR: --report requires a file path" >&2
                exit 2
            }
            REPORT_PATH="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

for archive in "$LEFT_ARCHIVE" "$RIGHT_ARCHIVE"; do
    worms_reject_control_chars "$archive" "Qt archive path"
    [[ -f "$archive" ]] && [[ ! -L "$archive" ]] \
        && [[ "$(worms_file_link_count "$archive")" == "1" ]] || {
        echo "ERROR: Qt archive must be a regular non-linked file: $archive" >&2
        exit 2
    }
done
[[ -x /usr/bin/python3 ]] || { echo "ERROR: /usr/bin/python3 is required" >&2; exit 2; }

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-qt-compare.XXXXXX")
mkdir -p "$WORK_DIR/left" "$WORK_DIR/right"
worms_copy_and_inspect_archive \
    "$LEFT_ARCHIVE" "$WORK_DIR/left.tar.gz" qt "" --quiet
worms_copy_and_inspect_archive \
    "$RIGHT_ARCHIVE" "$WORK_DIR/right.tar.gz" qt "" --quiet
tar -xzf "$WORK_DIR/left.tar.gz" -C "$WORK_DIR/left"
tar -xzf "$WORK_DIR/right.tar.gz" -C "$WORK_DIR/right"

/usr/bin/python3 "$ROOT_DIR/tools/qt_artifact_evidence.py" collect \
    "$WORK_DIR/left" --output "$WORK_DIR/left.json"
/usr/bin/python3 "$ROOT_DIR/tools/qt_artifact_evidence.py" collect \
    "$WORK_DIR/right" --output "$WORK_DIR/right.json"

left_sha=$(worms_file_sha256 "$LEFT_ARCHIVE")
right_sha=$(worms_file_sha256 "$RIGHT_ARCHIVE")
compare_args=(
    compare "$WORK_DIR/left.json" "$WORK_DIR/right.json"
    --left-sha256 "$left_sha"
    --right-sha256 "$right_sha"
    --output "$WORK_DIR/report.json"
)
$ALLOW_VERSION_CHANGE && compare_args+=(--allow-version-change)
set +e
/usr/bin/python3 "$ROOT_DIR/tools/qt_artifact_evidence.py" "${compare_args[@]}"
compare_status=$?
set -e

if [[ -n "$REPORT_PATH" ]]; then
    worms_reject_control_chars "$REPORT_PATH" "comparison report path"
    mkdir -p "$(dirname "$REPORT_PATH")"
    worms_validate_replaceable_regular_file "$REPORT_PATH" || {
        echo "ERROR: Refusing unsafe comparison report target" >&2
        exit 2
    }
    chmod 0600 "$WORK_DIR/report.json"
    mv -f -- "$WORK_DIR/report.json" "$REPORT_PATH"
    echo "Comparison report: $REPORT_PATH"
else
    cat "$WORK_DIR/report.json"
fi
exit "$compare_status"
