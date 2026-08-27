#!/bin/bash
# Return success when changed paths require Qt SBOM vulnerability scanning.

set -euo pipefail

SAW_PATH=false

while IFS= read -r -d '' path; do
    [[ -n "$path" ]] || continue
    SAW_PATH=true
    case "$path" in
        dist/*|packaging/*)
            exit 0
            ;;
        tools/generate_sbom.py|tools/scan_qt_sbom.sh)
            exit 0
            ;;
        tools/test_generate_sbom.py|tools/test_qt_vulnerability_policy.py)
            exit 0
            ;;
        .github/workflows/github-security.yml|.github/workflows/rebuild-qt.yml)
            exit 0
            ;;
    esac
done

# Empty or unreadable diffs fail safe and require the scan.
$SAW_PATH || exit 0
exit 1
