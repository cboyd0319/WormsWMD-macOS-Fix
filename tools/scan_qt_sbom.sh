#!/bin/bash
# Generate and scan the scoped Qt runtime SBOM with pinned Grype.

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

GRYPE_VERSION="0.117.0"
OUTPUT_DIR="$ROOT_DIR/build/security"
WORK_DIR=""

cleanup() {
    if [[ -n "$WORK_DIR" ]] && [[ -d "$WORK_DIR" ]] && [[ ! -L "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage: ./tools/scan_qt_sbom.sh --local-report [--output-dir DIR]

Generates the scoped Qt runtime/build SBOM, runs pinned Grype in report-only
mode, and writes deterministic JSON evidence. Findings do not fail the command;
tool failure, invalid policy/VEX, or zero runtime inventory does.
EOF
}

LOCAL_REPORT=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --local-report)
            LOCAL_REPORT=true
            shift
            ;;
        --output-dir)
            [[ -n "${2:-}" ]] && [[ "$2" != -* ]] || {
                echo "ERROR: --output-dir requires a directory" >&2
                exit 1
            }
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done
$LOCAL_REPORT || { usage >&2; exit 1; }

for command_name in date git grype mktemp mv shasum; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "ERROR: Missing required command: $command_name" >&2
        exit 1
    }
done
[[ -x /usr/bin/python3 ]] || { echo "ERROR: /usr/bin/python3 is required" >&2; exit 1; }
worms_reject_control_chars "$OUTPUT_DIR" "scan output directory"

installed_grype_version=$(grype version 2>/dev/null \
    | awk -F': *' '$1 == "Version" {print $2; exit}')
[[ "$installed_grype_version" == "$GRYPE_VERSION" ]] || {
    echo "ERROR: Grype $GRYPE_VERSION is required; found ${installed_grype_version:-unknown}" >&2
    exit 1
}

mkdir -p "$OUTPUT_DIR"
[[ -d "$OUTPUT_DIR" ]] && [[ ! -L "$OUTPUT_DIR" ]] || {
    echo "ERROR: Scan output must be a non-linked directory: $OUTPUT_DIR" >&2
    exit 1
}
WORK_DIR=$(mktemp -d "$OUTPUT_DIR/.wormswmd-scan.XXXXXX")
chmod 0700 "$WORK_DIR"

source_version="v$(awk -F= '/^VERSION=/{gsub(/"/, "", $2); print $2; exit}' \
    "$ROOT_DIR/fix_worms_wmd.sh")"
source_timestamp=$(git -C "$ROOT_DIR" show -s --format=%cI HEAD)
scan_date=$(date -u +%F)
sbom_staged="$WORK_DIR/qt-runtime.cdx.json"
raw_staged="$WORK_DIR/grype-raw.json"
report_staged="$WORK_DIR/qt-vulnerability-report.json"
sbom_output="$OUTPUT_DIR/qt-runtime.cdx.json"
report_output="$OUTPUT_DIR/qt-vulnerability-report.json"
vex_path=""
[[ ! -f "$ROOT_DIR/packaging/qt-vex.tsv" ]] \
    || vex_path="$ROOT_DIR/packaging/qt-vex.tsv"

/usr/bin/python3 "$ROOT_DIR/tools/generate_sbom.py" \
    --inventory-only \
    --version "$source_version" \
    --timestamp "$source_timestamp" \
    --output "$sbom_staged"

GRYPE_CHECK_FOR_APP_UPDATE=false grype \
    "sbom:$sbom_staged" \
    --by-cve \
    --output json > "$raw_staged"

PYTHONPATH="$ROOT_DIR/tools" /usr/bin/python3 - \
    "$sbom_staged" "$raw_staged" "$report_staged" "$scan_date" "$vex_path" <<'PY'
from datetime import date
from pathlib import Path
import sys

from generate_sbom import atomic_write_json
from qt_component_policy import normalize_grype_report

sbom, raw, output, scan_date, vex = sys.argv[1:]
document = normalize_grype_report(
    Path(sbom),
    Path(raw),
    date.fromisoformat(scan_date),
    Path(vex) if vex else None,
)
atomic_write_json(Path(output), document)
PY

chmod 0600 "$sbom_staged" "$report_staged"
if ! worms_validate_replaceable_regular_file "$sbom_output" \
    || ! worms_validate_replaceable_regular_file "$report_output"; then
    echo "ERROR: Refusing unsafe existing scan output" >&2
    exit 1
fi
mv -f -- "$sbom_staged" "$sbom_output"
mv -f -- "$report_staged" "$report_output"

/usr/bin/python3 - "$report_output" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    report = json.load(handle)
metadata = report["wormswmd"]
print(f"Runtime inventory: {metadata['runtimeInventoryCount']}")
unmapped = metadata["unmappedRuntimeComponents"]
print("Unmapped runtime: " + (", ".join(unmapped) if unmapped else "none"))
print(f"Report-only findings: {len(report['matches'])}")
PY
printf 'SBOM_SHA256=%s\n' "$(shasum -a 256 "$sbom_output" | awk '{print $1}')"
printf 'REPORT_SHA256=%s\n' "$(shasum -a 256 "$report_output" | awk '{print $1}')"
printf 'SBOM=%s\nREPORT=%s\n' "$sbom_output" "$report_output"
